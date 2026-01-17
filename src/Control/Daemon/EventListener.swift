// Control - macOS Power User Interaction Manager
// Event Listener
//
// Monitors system events for the daemon.

import AppKit
import CoreGraphics
import Foundation

// MARK: - Event Type

/// Types of events the listener monitors
public enum MonitoredEventType: String, Sendable {
    case applicationLaunch = "app_launch"
    case applicationQuit = "app_quit"
    case applicationActivate = "app_activate"
    case windowCreated = "window_created"
    case windowClosed = "window_closed"
    case displayChange = "display_change"
    case sleepWake = "sleep_wake"
}

// MARK: - Event

/// A system event captured by the listener
public struct SystemEvent: Sendable {
    public let type: MonitoredEventType
    public let timestamp: Date
    public let data: [String: String]
    
    public init(type: MonitoredEventType, data: [String: String] = [:]) {
        self.type = type
        self.timestamp = Date()
        self.data = data
    }
}

// MARK: - Event Handler

/// Protocol for handling system events
public protocol EventHandler: AnyObject {
    func handleEvent(_ event: SystemEvent)
}

// MARK: - Event Listener

/// Monitors CGEvent streams and system notifications
public final class EventListener: @unchecked Sendable {
    
    // MARK: - Singleton
    
    public static let shared = EventListener()
    
    // MARK: - Properties
    
    /// Whether the listener is active
    public private(set) var isActive: Bool = false
    
    /// Event handlers
    private var handlers: [WeakHandler] = []
    private let handlersLock = NSLock()
    
    /// Notification observers
    private var notificationObservers: [NSObjectProtocol] = []
    
    /// Recent events (ring buffer)
    private var recentEvents: [SystemEvent] = []
    private let maxRecentEvents = 100
    private let eventsLock = NSLock()
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Start listening for events
    public func start() throws {
        guard !isActive else { return }
        
        // Register for workspace notifications
        registerWorkspaceNotifications()
        
        // Register for display notifications
        registerDisplayNotifications()
        
        isActive = true
        log.info("EventListener started")
    }
    
    /// Stop listening for events
    public func stop() {
        guard isActive else { return }
        
        // Remove observers
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        notificationObservers.removeAll()
        
        isActive = false
        log.info("EventListener stopped")
    }
    
    /// Add event handler
    public func addHandler(_ handler: EventHandler) {
        handlersLock.lock()
        defer { handlersLock.unlock() }
        
        handlers = handlers.filter { $0.handler != nil }
        handlers.append(WeakHandler(handler))
    }
    
    /// Remove event handler
    public func removeHandler(_ handler: EventHandler) {
        handlersLock.lock()
        defer { handlersLock.unlock() }
        
        handlers = handlers.filter { $0.handler !== handler }
    }
    
    /// Get recent events
    public func getRecentEvents() -> [SystemEvent] {
        eventsLock.lock()
        defer { eventsLock.unlock() }
        return recentEvents
    }
    
    // MARK: - Private Methods
    
    private func registerWorkspaceNotifications() {
        let workspace = NSWorkspace.shared
        let nc = workspace.notificationCenter
        
        // Application launched
        let launchObserver = nc.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                let event = SystemEvent(
                    type: .applicationLaunch,
                    data: [
                        "bundleId": app.bundleIdentifier ?? "unknown",
                        "name": app.localizedName ?? "unknown"
                    ]
                )
                self?.recordEvent(event)
            }
        }
        notificationObservers.append(launchObserver)
        
        // Application quit
        let quitObserver = nc.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                let event = SystemEvent(
                    type: .applicationQuit,
                    data: [
                        "bundleId": app.bundleIdentifier ?? "unknown",
                        "name": app.localizedName ?? "unknown"
                    ]
                )
                self?.recordEvent(event)
            }
        }
        notificationObservers.append(quitObserver)
        
        // Application activated
        let activateObserver = nc.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                let event = SystemEvent(
                    type: .applicationActivate,
                    data: [
                        "bundleId": app.bundleIdentifier ?? "unknown",
                        "name": app.localizedName ?? "unknown"
                    ]
                )
                self?.recordEvent(event)
            }
        }
        notificationObservers.append(activateObserver)
        
        // Sleep notification
        let sleepObserver = nc.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            let event = SystemEvent(type: .sleepWake, data: ["action": "sleep"])
            self?.recordEvent(event)
        }
        notificationObservers.append(sleepObserver)
        
        // Wake notification
        let wakeObserver = nc.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            let event = SystemEvent(type: .sleepWake, data: ["action": "wake"])
            self?.recordEvent(event)
        }
        notificationObservers.append(wakeObserver)
    }
    
    private func registerDisplayNotifications() {
        let nc = NotificationCenter.default
        
        // Screen configuration change
        let screenObserver = nc.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            let event = SystemEvent(
                type: .displayChange,
                data: ["screens": String(NSScreen.screens.count)]
            )
            self?.recordEvent(event)
        }
        notificationObservers.append(screenObserver)
    }
    
    private func recordEvent(_ event: SystemEvent) {
        // Add to recent events
        eventsLock.lock()
        recentEvents.append(event)
        if recentEvents.count > maxRecentEvents {
            recentEvents.removeFirst()
        }
        eventsLock.unlock()
        
        // Notify handlers
        handlersLock.lock()
        let currentHandlers = handlers.compactMap { $0.handler }
        handlersLock.unlock()
        
        for handler in currentHandlers {
            handler.handleEvent(event)
        }
        
        log.debug("Event recorded: \(event.type.rawValue)")
    }
}

// MARK: - Weak Handler

private class WeakHandler {
    weak var handler: EventHandler?
    
    init(_ handler: EventHandler) {
        self.handler = handler
    }
}
