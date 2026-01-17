// Control - macOS Power User Interaction Manager
// Config Manager
//
// TOML configuration loading with hot-reload support.

import Foundation
import TOMLKit

// MARK: - Configuration

/// Main configuration structure
public struct ControlConfiguration: Sendable {
    public var core: CoreConfig
    public var window: WindowConfig
    public var input: InputConfig
    public var permission: PermissionConfig
    public var consistency: ConsistencyConfig
    public var daemon: DaemonConfig
    public var security: SecurityConfig
    
    public init() {
        self.core = CoreConfig()
        self.window = WindowConfig()
        self.input = InputConfig()
        self.permission = PermissionConfig()
        self.consistency = ConsistencyConfig()
        self.daemon = DaemonConfig()
        self.security = SecurityConfig()
    }
}

// MARK: - Section Configs

public struct CoreConfig: Sendable {
    public var logLevel: String = "info"
    public var daemonEnabled: Bool = false
    public var telemetryEnabled: Bool = false
    public var healthCheckInterval: Int = 30
}

public struct WindowConfig: Sendable {
    public var cornerFixEnabled: Bool = true
    public var cornerHitBoxPx: Int = 5
    public var snapEnabled: Bool = true
    public var snapThresholdPx: Int = 20
    public var tilingEnabled: Bool = true
    public var defaultLayout: String = "developer"
    public var windowGapPx: Int = 0
    public var preservePositionsOnWake: Bool = true
}

public struct InputConfig: Sendable {
    public var mouseAccelerationEnabled: Bool = false
    public var accelerationCurve: String = "linear"
    public var trackpadNaturalScroll: Bool = true
    public var mouseNaturalScroll: Bool = false
    public var scrollSpeed: Double = 1.0
}

public struct PermissionConfig: Sendable {
    public var developerMode: Bool = false
    public var uiAutomationEnabled: Bool = true
    public var amnesiaMethodEnabled: Bool = false
    public var trustProfile: String = "minimal"
}

public struct ConsistencyConfig: Sendable {
    public var trafficLightNormalize: Bool = true
    public var iconNormalize: Bool = false
    public var menuBarEnabled: Bool = false
}

public struct DaemonConfig: Sendable {
    public var runAtLoad: Bool = false
    public var autoRestart: Bool = true
    public var heartbeatInterval: Int = 30
    public var maxMemoryMB: Int = 150
}

public struct SecurityConfig: Sendable {
    public var requireBiometric: Bool = true
    public var auditLogEnabled: Bool = true
}

// MARK: - Config Manager

/// Manages configuration loading and hot-reload
///
/// Features:
/// - TOML parsing with TOMLKit
/// - Hot-reload on file change
/// - Schema validation
/// - Preset support
public final class ConfigManager: @unchecked Sendable {
    
    // MARK: - Singleton
    
    public static let shared = ConfigManager()
    
    // MARK: - Properties
    
    /// Current configuration
    public private(set) var config = ControlConfiguration()
    
    /// Configuration file path
    public let configPath: String
    
    /// File monitor for hot-reload
    private var fileMonitor: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    
    /// Change handlers
    private var changeHandlers: [(ControlConfiguration) -> Void] = []
    private let handlersLock = NSLock()
    
    /// Last load time
    private var lastLoadTime: Date?
    
    // MARK: - Initialization
    
    private init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        configPath = homeDir.appendingPathComponent(
            ".config/control/control.toml"
        ).path
        
        // Load initial configuration
        _ = load()
    }
    
    // MARK: - Public Methods
    
    /// Load configuration from file
    @discardableResult
    public func load() -> Bool {
        guard FileManager.default.fileExists(atPath: configPath) else {
            log.info("Config file not found, using defaults: \(configPath)")
            return false
        }
        
        do {
            let contents = try String(contentsOfFile: configPath, encoding: .utf8)
            let toml = try TOMLTable(string: contents)
            
            // Parse sections
            if let core = toml["core"] as? TOMLTable {
                parseCore(core)
            }
            if let window = toml["window"] as? TOMLTable {
                parseWindow(window)
            }
            if let input = toml["input"] as? TOMLTable {
                parseInput(input)
            }
            if let permission = toml["permission"] as? TOMLTable {
                parsePermission(permission)
            }
            if let consistency = toml["consistency"] as? TOMLTable {
                parseConsistency(consistency)
            }
            if let daemon = toml["daemon"] as? TOMLTable {
                parseDaemon(daemon)
            }
            if let security = toml["security"] as? TOMLTable {
                parseSecurity(security)
            }
            
            lastLoadTime = Date()
            notifyChangeHandlers()
            
            log.info("Configuration loaded from: \(configPath)")
            return true
            
        } catch {
            log.error("Failed to load config: \(error)")
            return false
        }
    }
    
    /// Reload configuration
    public func reload() {
        _ = load()
    }
    
    /// Enable hot-reload file monitoring
    public func enableHotReload() {
        guard fileMonitor == nil else { return }
        
        fileDescriptor = open(configPath, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            log.warning("Cannot monitor config file")
            return
        }
        
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename],
            queue: .global()
        )
        
        source.setEventHandler { [weak self] in
            self?.reload()
        }
        
        source.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                close(fd)
            }
        }
        
        source.resume()
        fileMonitor = source
        
        log.info("Hot-reload enabled for config")
    }
    
    /// Disable hot-reload
    public func disableHotReload() {
        fileMonitor?.cancel()
        fileMonitor = nil
        
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
    }
    
    /// Add change handler
    public func onChange(_ handler: @escaping (ControlConfiguration) -> Void) {
        handlersLock.lock()
        changeHandlers.append(handler)
        handlersLock.unlock()
    }
    
    /// Get config value by key path
    public func getValue<T>(_ keyPath: KeyPath<ControlConfiguration, T>) -> T {
        return config[keyPath: keyPath]
    }
    
    /// Validate configuration
    public func validate() -> [String] {
        var errors: [String] = []
        
        // Validate window settings
        if config.window.cornerHitBoxPx < 1 || config.window.cornerHitBoxPx > 20 {
            errors.append("window.corner_hit_box_px must be between 1 and 20")
        }
        
        // Validate daemon settings
        if config.daemon.maxMemoryMB < 50 {
            errors.append("daemon.max_memory_mb must be at least 50")
        }
        
        return errors
    }
    
    // MARK: - Private Parsing Methods
    
    private func parseCore(_ table: TOMLTable) {
        if let logLevel = table["log_level"] as? String {
            config.core.logLevel = logLevel
        }
        if let daemonEnabled = table["daemon_enabled"] as? Bool {
            config.core.daemonEnabled = daemonEnabled
        }
        if let telemetryEnabled = table["telemetry_enabled"] as? Bool {
            config.core.telemetryEnabled = telemetryEnabled
        }
        if let interval = table["health_check_interval"] as? Int {
            config.core.healthCheckInterval = interval
        }
    }
    
    private func parseWindow(_ table: TOMLTable) {
        if let cornerFix = table["corner_fix_enabled"] as? Bool {
            config.window.cornerFixEnabled = cornerFix
        }
        if let hitBox = table["corner_hit_box_px"] as? Int {
            config.window.cornerHitBoxPx = hitBox
        }
        if let snap = table["snap_enabled"] as? Bool {
            config.window.snapEnabled = snap
        }
        if let threshold = table["snap_threshold_px"] as? Int {
            config.window.snapThresholdPx = threshold
        }
        if let tiling = table["tiling_enabled"] as? Bool {
            config.window.tilingEnabled = tiling
        }
        if let layout = table["default_layout"] as? String {
            config.window.defaultLayout = layout
        }
        if let gap = table["window_gap_px"] as? Int {
            config.window.windowGapPx = gap
        }
        if let preserve = table["preserve_positions_on_wake"] as? Bool {
            config.window.preservePositionsOnWake = preserve
        }
    }
    
    private func parseInput(_ table: TOMLTable) {
        if let accel = table["mouse_acceleration_enabled"] as? Bool {
            config.input.mouseAccelerationEnabled = accel
        }
        if let curve = table["acceleration_curve"] as? String {
            config.input.accelerationCurve = curve
        }
        if let trackpad = table["trackpad_natural_scroll"] as? Bool {
            config.input.trackpadNaturalScroll = trackpad
        }
        if let mouse = table["mouse_natural_scroll"] as? Bool {
            config.input.mouseNaturalScroll = mouse
        }
        if let speed = table["scroll_speed"] as? Double {
            config.input.scrollSpeed = speed
        }
    }
    
    private func parsePermission(_ table: TOMLTable) {
        if let devMode = table["developer_mode"] as? Bool {
            config.permission.developerMode = devMode
        }
        if let uiAuto = table["ui_automation_enabled"] as? Bool {
            config.permission.uiAutomationEnabled = uiAuto
        }
        if let amnesia = table["amnesia_method_enabled"] as? Bool {
            config.permission.amnesiaMethodEnabled = amnesia
        }
        if let trust = table["trust_profile"]?["active"] as? String {
            config.permission.trustProfile = trust
        }
    }
    
    private func parseConsistency(_ table: TOMLTable) {
        if let traffic = table["traffic_light_normalize"] as? Bool {
            config.consistency.trafficLightNormalize = traffic
        }
        if let icon = table["icon_normalize"] as? Bool {
            config.consistency.iconNormalize = icon
        }
        if let menuBar = table["menu_bar_enabled"] as? Bool {
            config.consistency.menuBarEnabled = menuBar
        }
    }
    
    private func parseDaemon(_ table: TOMLTable) {
        if let runAt = table["run_at_load"] as? Bool {
            config.daemon.runAtLoad = runAt
        }
        if let restart = table["auto_restart"] as? Bool {
            config.daemon.autoRestart = restart
        }
        if let heartbeat = table["heartbeat_interval"] as? Int {
            config.daemon.heartbeatInterval = heartbeat
        }
        if let maxMem = table["max_memory_mb"] as? Int {
            config.daemon.maxMemoryMB = maxMem
        }
    }
    
    private func parseSecurity(_ table: TOMLTable) {
        if let bio = table["require_biometric"] as? Bool {
            config.security.requireBiometric = bio
        }
        if let audit = table["audit_log_enabled"] as? Bool {
            config.security.auditLogEnabled = audit
        }
    }
    
    private func notifyChangeHandlers() {
        handlersLock.lock()
        let handlers = changeHandlers
        handlersLock.unlock()
        
        for handler in handlers {
            handler(config)
        }
    }
}
