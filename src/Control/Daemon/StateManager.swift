// Control - macOS Power User Interaction Manager
// State Manager
//
// Persistent state management for the daemon.

import Foundation

// MARK: - Persisted State

/// State that persists across daemon restarts
public struct PersistedState: Codable, Sendable {
    public var windowPositions: [String: WindowPosition] = [:]
    public var lastActiveLayout: String?
    public var deviceSettings: [String: DeviceSettings] = [:]
    public var lastSyncTime: Date?
    
    public init() {}
}

// MARK: - Window Position

/// Saved window position
public struct WindowPosition: Codable, Sendable {
    public let bundleId: String
    public let windowTitle: String
    public let frame: CodableRect
    public let savedAt: Date
    
    public init(bundleId: String, windowTitle: String, frame: CGRect) {
        self.bundleId = bundleId
        self.windowTitle = windowTitle
        self.frame = CodableRect(frame)
        self.savedAt = Date()
    }
}

// MARK: - Device Settings

/// Per-device settings
public struct DeviceSettings: Codable, Sendable {
    public let deviceId: String
    public var scrollDirection: String = "natural"
    public var accelerationEnabled: Bool = true
    public var sensitivity: Double = 1.0
}

// MARK: - Codable CGRect

/// CGRect wrapper for Codable
public struct CodableRect: Codable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    
    public init(_ rect: CGRect) {
        self.x = rect.origin.x
        self.y = rect.origin.y
        self.width = rect.width
        self.height = rect.height
    }
    
    public var cgRect: CGRect {
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

// MARK: - State Manager

/// Manages persistent daemon state
public final class StateManager: @unchecked Sendable {
    
    // MARK: - Singleton
    
    public static let shared = StateManager()
    
    // MARK: - Properties
    
    /// Current state
    private var state: PersistedState
    private let stateLock = NSLock()
    
    /// State file path
    private let statePath: String
    
    /// Auto-save timer
    private var autoSaveTimer: Timer?
    
    /// Auto-save interval (seconds)
    public var autoSaveInterval: TimeInterval = 60
    
    /// Dirty flag for pending changes
    private var isDirty: Bool = false
    
    // MARK: - Initialization
    
    private init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        statePath = homeDir.appendingPathComponent(
            ".config/control/state.json"
        ).path
        
        // Load existing state or create new
        state = StateManager.loadState(from: statePath) ?? PersistedState()
    }
    
    // MARK: - Public Methods
    
    /// Start auto-save
    public func start() {
        autoSaveTimer = Timer.scheduledTimer(
            withTimeInterval: autoSaveInterval,
            repeats: true
        ) { [weak self] _ in
            self?.saveIfDirty()
        }
        log.info("StateManager started with auto-save interval: \(autoSaveInterval)s")
    }
    
    /// Stop auto-save
    public func stop() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil
        save()
    }
    
    /// Save state to disk
    public func save() {
        stateLock.lock()
        let currentState = state
        isDirty = false
        stateLock.unlock()
        
        do {
            let directory = (statePath as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(
                atPath: directory,
                withIntermediateDirectories: true
            )
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            encoder.dateEncodingStrategy = .iso8601
            
            let data = try encoder.encode(currentState)
            try data.write(to: URL(fileURLWithPath: statePath))
            
            log.debug("State saved to disk")
        } catch {
            log.error("Failed to save state: \(error)")
        }
    }
    
    /// Save window position
    public func saveWindowPosition(bundleId: String, title: String, frame: CGRect) {
        let position = WindowPosition(bundleId: bundleId, windowTitle: title, frame: frame)
        let key = "\(bundleId):\(title)"
        
        stateLock.lock()
        state.windowPositions[key] = position
        isDirty = true
        stateLock.unlock()
    }
    
    /// Get saved window position
    public func getWindowPosition(bundleId: String, title: String) -> CGRect? {
        let key = "\(bundleId):\(title)"
        
        stateLock.lock()
        let position = state.windowPositions[key]
        stateLock.unlock()
        
        return position?.frame.cgRect
    }
    
    /// Set active layout
    public func setActiveLayout(_ layoutName: String) {
        stateLock.lock()
        state.lastActiveLayout = layoutName
        isDirty = true
        stateLock.unlock()
    }
    
    /// Get active layout
    public func getActiveLayout() -> String? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return state.lastActiveLayout
    }
    
    /// Save device settings
    public func saveDeviceSettings(_ settings: DeviceSettings) {
        stateLock.lock()
        state.deviceSettings[settings.deviceId] = settings
        isDirty = true
        stateLock.unlock()
    }
    
    /// Get device settings
    public func getDeviceSettings(for deviceId: String) -> DeviceSettings? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return state.deviceSettings[deviceId]
    }
    
    /// Clear all state
    public func clearState() {
        stateLock.lock()
        state = PersistedState()
        isDirty = true
        stateLock.unlock()
        
        save()
        log.info("State cleared")
    }
    
    // MARK: - Private Methods
    
    private func saveIfDirty() {
        stateLock.lock()
        let shouldSave = isDirty
        stateLock.unlock()
        
        if shouldSave {
            save()
        }
    }
    
    private static func loadState(from path: String) -> PersistedState? {
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            let state = try decoder.decode(PersistedState.self, from: data)
            log.info("Loaded persisted state")
            return state
        } catch {
            log.warning("Failed to load state: \(error)")
            return nil
        }
    }
}
