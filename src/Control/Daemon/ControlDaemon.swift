// Control - macOS Power User Interaction Manager
// Control Daemon
//
// Background service for real-time event monitoring.

import Foundation

// MARK: - Daemon State

/// Current state of the daemon
public enum DaemonState: String, Sendable {
    case stopped = "stopped"
    case starting = "starting"
    case running = "running"
    case stopping = "stopping"
    case error = "error"
}

// MARK: - Daemon Configuration

/// Configuration for the daemon
public struct DaemonConfiguration: Sendable {
    public var heartbeatInterval: TimeInterval = 30
    public var autoRestart: Bool = true
    public var logPath: String
    public var ipcSocketPath: String = "/tmp/control.sock"
    
    public init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        logPath = homeDir.appendingPathComponent(".config/control/daemon.log").path
    }
}

// MARK: - Control Daemon

/// Background service for Control
///
/// Provides:
/// - Real-time event monitoring
/// - IPC with CLI commands
/// - State persistence
/// - Health monitoring
public final class ControlDaemon: @unchecked Sendable {
    
    // MARK: - Singleton
    
    public static let shared = ControlDaemon()
    
    // MARK: - Properties
    
    /// Current daemon state
    public private(set) var state: DaemonState = .stopped
    
    /// Configuration
    public var configuration = DaemonConfiguration()
    
    /// Event listener
    private let eventListener = EventListener.shared
    
    /// State manager
    private let stateManager = StateManager.shared
    
    /// Last heartbeat time
    private var lastHeartbeat: Date?
    
    /// Heartbeat timer
    private var heartbeatTimer: Timer?
    
    /// Start time
    private var startTime: Date?
    
    // MARK: - LaunchAgent Paths
    
    private var launchAgentPath: String {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        return homeDir.appendingPathComponent(
            "Library/LaunchAgents/com.control.daemon.plist"
        ).path
    }
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Start the daemon
    @MainActor
    public func start() async throws {
        guard state == .stopped else {
            log.warning("Daemon already running or in transition")
            return
        }
        
        state = .starting
        log.info("Starting Control daemon...")
        
        do {
            // Start event listener
            try eventListener.start()
            
            // Start state manager
            stateManager.start()
            
            // Start heartbeat
            startHeartbeat()
            
            state = .running
            startTime = Date()
            log.info("Control daemon started successfully")
            
        } catch {
            state = .error
            log.error("Failed to start daemon: \(error)")
            throw error
        }
    }
    
    /// Stop the daemon
    @MainActor
    public func stop() async {
        guard state == .running else { return }
        
        state = .stopping
        log.info("Stopping Control daemon...")
        
        // Stop heartbeat
        stopHeartbeat()
        
        // Stop event listener
        eventListener.stop()
        
        // Save state
        stateManager.save()
        
        state = .stopped
        startTime = nil
        log.info("Control daemon stopped")
    }
    
    /// Restart the daemon
    @MainActor
    public func restart() async throws {
        await stop()
        try await start()
    }
    
    /// Get daemon status
    public func getStatus() -> DaemonStatus {
        return DaemonStatus(
            state: state,
            uptime: startTime.map { Date().timeIntervalSince($0) },
            lastHeartbeat: lastHeartbeat,
            eventListenerActive: eventListener.isActive,
            processId: ProcessInfo.processInfo.processIdentifier
        )
    }
    
    /// Install LaunchAgent
    public func installLaunchAgent() throws {
        let plist = generateLaunchAgentPlist()
        
        // Ensure directory exists
        let directory = (launchAgentPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true
        )
        
        // Write plist
        try plist.write(toFile: launchAgentPath, atomically: true, encoding: .utf8)
        
        // Load the agent
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["load", launchAgentPath]
        try process.run()
        process.waitUntilExit()
        
        log.info("Installed LaunchAgent at: \(launchAgentPath)")
    }
    
    /// Uninstall LaunchAgent
    public func uninstallLaunchAgent() throws {
        guard FileManager.default.fileExists(atPath: launchAgentPath) else {
            log.warning("LaunchAgent not installed")
            return
        }
        
        // Unload the agent
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["unload", launchAgentPath]
        try process.run()
        process.waitUntilExit()
        
        // Remove plist
        try FileManager.default.removeItem(atPath: launchAgentPath)
        
        log.info("Uninstalled LaunchAgent")
    }
    
    /// Check if LaunchAgent is installed
    public func isLaunchAgentInstalled() -> Bool {
        return FileManager.default.fileExists(atPath: launchAgentPath)
    }
    
    // MARK: - Private Methods
    
    private func startHeartbeat() {
        heartbeatTimer = Timer.scheduledTimer(
            withTimeInterval: configuration.heartbeatInterval,
            repeats: true
        ) { [weak self] _ in
            self?.heartbeat()
        }
    }
    
    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }
    
    private func heartbeat() {
        lastHeartbeat = Date()
        log.debug("Daemon heartbeat")
    }
    
    private func generateLaunchAgentPlist() -> String {
        // Get path to control binary
        let controlPath = "/usr/local/bin/control"
        
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.control.daemon</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(controlPath)</string>
                <string>daemon</string>
                <string>run</string>
            </array>
            <key>KeepAlive</key>
            <\(configuration.autoRestart ? "true" : "false")/>
            <key>RunAtLoad</key>
            <true/>
            <key>StandardOutPath</key>
            <string>\(configuration.logPath)</string>
            <key>StandardErrorPath</key>
            <string>\(configuration.logPath)</string>
        </dict>
        </plist>
        """
    }
}

// MARK: - Daemon Status

/// Status information for the daemon
public struct DaemonStatus: Sendable {
    public let state: DaemonState
    public let uptime: TimeInterval?
    public let lastHeartbeat: Date?
    public let eventListenerActive: Bool
    public let processId: Int32
    
    public var formattedUptime: String {
        guard let uptime = uptime else { return "N/A" }
        
        let hours = Int(uptime) / 3600
        let minutes = Int(uptime) % 3600 / 60
        let seconds = Int(uptime) % 60
        
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
