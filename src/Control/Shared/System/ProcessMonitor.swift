// Control - macOS Power User Interaction Manager
// Process Monitor
//
// Monitor process lifecycle and resource usage.

import AppKit
import Foundation
@preconcurrency import Darwin

// MARK: - Mach Task Helper

/// Helper to get mach_task_self_ in a concurrency-safe manner
/// The mach_task_self_ global is thread-safe at the Mach level, but Swift 6's
/// strict concurrency checking flags it as unsafe. This wrapper provides safe access.
@inline(__always)
private func currentTask() -> mach_port_t {
    return mach_task_self_
}
// MARK: - Control Process Info

/// Information about a running process
public struct ControlProcessInfo: Sendable {
    public let pid: pid_t
    public let name: String
    public let bundleId: String?
    public let path: String?
    public let memoryUsage: UInt64  // bytes
    public let cpuUsage: Double     // percentage
    public let launchDate: Date?
    
    public init(
        pid: pid_t,
        name: String,
        bundleId: String? = nil,
        path: String? = nil,
        memoryUsage: UInt64 = 0,
        cpuUsage: Double = 0,
        launchDate: Date? = nil
    ) {
        self.pid = pid
        self.name = name
        self.bundleId = bundleId
        self.path = path
        self.memoryUsage = memoryUsage
        self.cpuUsage = cpuUsage
        self.launchDate = launchDate
    }
}

// MARK: - Process Event

/// Process lifecycle events
public enum ProcessEvent: Sendable {
    case launched(ControlProcessInfo)
    case terminated(pid: pid_t, bundleId: String?)
    case activated(ControlProcessInfo)
}

// MARK: - Process Observer

/// Observer protocol for process events
public protocol ProcessObserver: AnyObject {
    func processMonitor(_ monitor: ProcessMonitor, didReceive event: ProcessEvent)
}

// MARK: - Process Monitor

/// Monitors process lifecycle and resource usage
///
/// Features:
/// - App launch/quit detection
/// - Memory and CPU monitoring
/// - Foreground app tracking
public final class ProcessMonitor: @unchecked Sendable {
    
    // MARK: - Singleton
    
    public static let shared = ProcessMonitor()
    
    // MARK: - Properties
    
    /// Observers
    private var observers: [ObjectIdentifier: WeakObserver] = [:]
    private let observersLock = NSLock()
    
    /// Workspace notifications
    private var notificationObservers: [Any] = []
    
    /// Currently active app
    public private(set) var activeApp: ControlProcessInfo?
    
    /// Resource monitoring timer
    private var resourceTimer: Timer?
    public private(set) var isMonitoringResources: Bool = false
    
    /// Resource monitoring interval
    public var resourceCheckInterval: TimeInterval = 5.0
    
    // MARK: - Weak Observer Wrapper
    
    private class WeakObserver {
        weak var observer: ProcessObserver?
        init(_ observer: ProcessObserver) {
            self.observer = observer
        }
    }
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Start monitoring
    @MainActor
    public func start() {
        setupNotifications()
        log.info("ProcessMonitor started")
    }
    
    /// Stop monitoring
    @MainActor
    public func stop() {
        for observer in notificationObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        notificationObservers.removeAll()
        stopResourceMonitoring()
        log.info("ProcessMonitor stopped")
    }
    
    /// Add observer
    public func addObserver(_ observer: ProcessObserver) {
        let id = ObjectIdentifier(observer)
        observersLock.lock()
        observers[id] = WeakObserver(observer)
        observersLock.unlock()
    }
    
    /// Remove observer
    public func removeObserver(_ observer: ProcessObserver) {
        let id = ObjectIdentifier(observer)
        observersLock.lock()
        observers.removeValue(forKey: id)
        observersLock.unlock()
    }
    
    /// Get running applications
    public func getRunningApps() -> [ControlProcessInfo] {
        return NSWorkspace.shared.runningApplications.map { app in
            ControlProcessInfo(
                pid: app.processIdentifier,
                name: app.localizedName ?? "Unknown",
                bundleId: app.bundleIdentifier,
                path: app.bundleURL?.path,
                launchDate: app.launchDate
            )
        }
    }
    
    /// Get process by PID
    public func getProcess(pid: pid_t) -> ControlProcessInfo? {
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            return nil
        }
        
        return ControlProcessInfo(
            pid: app.processIdentifier,
            name: app.localizedName ?? "Unknown",
            bundleId: app.bundleIdentifier,
            path: app.bundleURL?.path,
            memoryUsage: getMemoryUsage(pid: pid),
            launchDate: app.launchDate
        )
    }
    
    /// Get process by bundle ID
    public func getProcess(bundleId: String) -> [ControlProcessInfo] {
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            .map { app in
                ControlProcessInfo(
                    pid: app.processIdentifier,
                    name: app.localizedName ?? "Unknown",
                    bundleId: app.bundleIdentifier,
                    path: app.bundleURL?.path,
                    launchDate: app.launchDate
                )
            }
    }
    
    /// Start resource usage monitoring
    @MainActor
    public func startResourceMonitoring() {
        guard !isMonitoringResources else { return }
        
        resourceTimer = Timer.scheduledTimer(withTimeInterval: resourceCheckInterval, repeats: true) { [weak self] _ in
            self?.checkResources()
        }
        
        isMonitoringResources = true
        log.debug("Resource monitoring started")
    }
    
    /// Stop resource usage monitoring
    public func stopResourceMonitoring() {
        resourceTimer?.invalidate()
        resourceTimer = nil
        isMonitoringResources = false
    }
    
    /// Get Control's own resource usage
    public func getOwnResourceUsage() -> (memory: UInt64, cpu: Double) {
        let pid = Foundation.ProcessInfo.processInfo.processIdentifier
        return (
            memory: getMemoryUsage(pid: pid),
            cpu: 0  // CPU usage requires additional implementation
        )
    }
    
    // MARK: - Private Methods
    
    @MainActor
    private func setupNotifications() {
        let nc = NSWorkspace.shared.notificationCenter
        
        // App launched
        notificationObservers.append(nc.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleAppLaunched(notification)
        })
        
        // App terminated
        notificationObservers.append(nc.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleAppTerminated(notification)
        })
        
        // App activated
        notificationObservers.append(nc.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleAppActivated(notification)
        })
    }
    
    private func handleAppLaunched(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        
        let info = ControlProcessInfo(
            pid: app.processIdentifier,
            name: app.localizedName ?? "Unknown",
            bundleId: app.bundleIdentifier,
            path: app.bundleURL?.path,
            launchDate: app.launchDate
        )
        
        notifyObservers(.launched(info))
    }
    
    private func handleAppTerminated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        
        notifyObservers(.terminated(pid: app.processIdentifier, bundleId: app.bundleIdentifier))
    }
    
    private func handleAppActivated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        
        let info = ControlProcessInfo(
            pid: app.processIdentifier,
            name: app.localizedName ?? "Unknown",
            bundleId: app.bundleIdentifier,
            path: app.bundleURL?.path,
            launchDate: app.launchDate
        )
        
        activeApp = info
        notifyObservers(.activated(info))
    }
    
    private func notifyObservers(_ event: ProcessEvent) {
        observersLock.lock()
        let currentObservers = observers.values.compactMap { $0.observer }
        observersLock.unlock()
        
        for observer in currentObservers {
            observer.processMonitor(self, didReceive: event)
        }
    }
    
    private func checkResources() {
        // Check own memory usage
        let (memory, _) = getOwnResourceUsage()
        
        // Log if memory is high
        let memoryMB = memory / (1024 * 1024)
        if memoryMB > 100 {
            log.warning("Control memory usage: \(memoryMB) MB")
        }
    }
    
    private func getMemoryUsage(pid: pid_t) -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        var task: mach_port_t = 0
        let result = task_for_pid(currentTask(), pid, &task)
        
        if result != KERN_SUCCESS {
            return 0
        }
        
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(task, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        mach_port_deallocate(currentTask(), task)
        
        if status == KERN_SUCCESS {
            return UInt64(info.resident_size)
        }
        
        return 0
    }
}
