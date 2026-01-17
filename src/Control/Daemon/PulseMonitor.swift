// Control - macOS Power User Interaction Manager
// Pulse Monitor
//
// Health monitoring and watchdog for daemon.
// Restarts daemon if memory exceeds threshold.

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

// MARK: - Pulse Status

/// Health status of the daemon
public struct PulseStatus: Sendable {
    public let timestamp: Date
    public let memoryUsage: UInt64      // bytes
    public let cpuUsage: Double         // percentage
    public let uptimeSeconds: TimeInterval
    public let eventTapCount: Int
    public let isHealthy: Bool
    public let warnings: [String]
    
    public init(
        memoryUsage: UInt64,
        cpuUsage: Double,
        uptimeSeconds: TimeInterval,
        eventTapCount: Int,
        isHealthy: Bool,
        warnings: [String]
    ) {
        self.timestamp = Date()
        self.memoryUsage = memoryUsage
        self.cpuUsage = cpuUsage
        self.uptimeSeconds = uptimeSeconds
        self.eventTapCount = eventTapCount
        self.isHealthy = isHealthy
        self.warnings = warnings
    }
    
    public var memoryMB: Double {
        return Double(memoryUsage) / (1024 * 1024)
    }
}

// MARK: - Pulse Config

/// Pulse monitoring configuration
public struct PulseConfig: Sendable {
    public var maxMemoryMB: Int = 150
    public var checkIntervalSeconds: TimeInterval = 30
    public var autoRestartEnabled: Bool = true
    public var logHealthStatus: Bool = true
    
    public static let `default` = PulseConfig()
    
    public init(
        maxMemoryMB: Int = 150,
        checkIntervalSeconds: TimeInterval = 30,
        autoRestartEnabled: Bool = true,
        logHealthStatus: Bool = true
    ) {
        self.maxMemoryMB = maxMemoryMB
        self.checkIntervalSeconds = checkIntervalSeconds
        self.autoRestartEnabled = autoRestartEnabled
        self.logHealthStatus = logHealthStatus
    }
}

// MARK: - Pulse Monitor

/// Health monitoring and watchdog
///
/// Features:
/// - Memory usage monitoring
/// - Automatic daemon restart
/// - Health status reporting
public final class PulseMonitor: @unchecked Sendable {
    
    // MARK: - Singleton
    
    public static let shared = PulseMonitor()
    
    // MARK: - Properties
    
    /// Configuration
    public var config = PulseConfig.default
    
    /// Monitoring timer
    private var timer: Timer?
    
    /// Daemon start time
    private var startTime: Date?
    
    /// Is monitoring active
    public private(set) var isActive: Bool = false
    
    /// Last status
    public private(set) var lastStatus: PulseStatus?
    
    /// Status change handler
    public var onStatusChange: ((PulseStatus) -> Void)?
    
    /// Memory warning handler
    public var onMemoryWarning: ((UInt64, Int) -> Void)?
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Start monitoring
    @MainActor
    public func start() {
        guard !isActive else { return }
        
        startTime = Date()
        
        timer = Timer.scheduledTimer(
            withTimeInterval: config.checkIntervalSeconds,
            repeats: true
        ) { [weak self] _ in
            self?.performHealthCheck()
        }
        
        // Initial check
        performHealthCheck()
        
        isActive = true
        log.info("PulseMonitor started (max memory: \(config.maxMemoryMB)MB)")
    }
    
    /// Stop monitoring
    public func stop() {
        guard isActive else { return }
        
        timer?.invalidate()
        timer = nil
        isActive = false
        
        log.info("PulseMonitor stopped")
    }
    
    /// Get current health status
    public func getCurrentStatus() -> PulseStatus {
        let memoryUsage = getMemoryUsage()
        let uptime = startTime.map { Date().timeIntervalSince($0) } ?? 0
        let eventTapCount = CGEventHandler.shared.activeTapCount
        
        var warnings: [String] = []
        var isHealthy = true
        
        let memoryMB = Double(memoryUsage) / (1024 * 1024)
        
        // Check memory
        if memoryMB > Double(config.maxMemoryMB) {
            warnings.append("Memory usage exceeds limit: \(Int(memoryMB))MB > \(config.maxMemoryMB)MB")
            isHealthy = false
        } else if memoryMB > Double(config.maxMemoryMB) * 0.8 {
            warnings.append("Memory usage high: \(Int(memoryMB))MB")
        }
        
        // Check event taps
        if eventTapCount == 0 {
            warnings.append("No active event taps")
        }
        
        return PulseStatus(
            memoryUsage: memoryUsage,
            cpuUsage: 0,  // TODO: Implement CPU monitoring
            uptimeSeconds: uptime,
            eventTapCount: eventTapCount,
            isHealthy: isHealthy,
            warnings: warnings
        )
    }
    
    /// Force a restart of the daemon
    public func triggerRestart(reason: String) {
        log.warning("Daemon restart triggered: \(reason)")
        
        // Log audit event
        AuditLog.shared.log(AuditEvent(
            type: .daemonAction,
            action: "restart",
            details: ["reason": reason]
        ))
        
        // Restart via launchctl
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["kickstart", "-k", "gui/\(getuid())/com.control.daemon"]
        
        do {
            try process.run()
        } catch {
            log.error("Failed to restart daemon: \(error)")
            
            // Fallback: exit and let launchd restart us
            exit(1)
        }
    }
    
    // MARK: - Private Methods
    
    private func performHealthCheck() {
        let status = getCurrentStatus()
        lastStatus = status
        
        // Log if enabled
        if config.logHealthStatus {
            log.debug("Pulse: memory=\(Int(status.memoryMB))MB, uptime=\(Int(status.uptimeSeconds))s, taps=\(status.eventTapCount)")
        }
        
        // Notify handler
        onStatusChange?(status)
        
        // Handle unhealthy state
        if !status.isHealthy {
            for warning in status.warnings {
                log.warning("Health check: \(warning)")
            }
            
            // Check memory threshold
            let memoryMB = Int(status.memoryMB)
            if memoryMB > config.maxMemoryMB {
                onMemoryWarning?(status.memoryUsage, config.maxMemoryMB)
                
                if config.autoRestartEnabled {
                    triggerRestart(reason: "Memory exceeded \(config.maxMemoryMB)MB limit")
                }
            }
        }
    }
    
    private func getMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(currentTask(), task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            return UInt64(info.resident_size)
        }
        
        return 0
    }
}
