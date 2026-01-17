// Control - macOS Power User Interaction Manager
// Menu Bar Manager
//
// Manages menu bar items visibility and ordering.

import AppKit
import Foundation

// MARK: - Menu Bar Item

/// Represents a menu bar item
public struct MenuBarItem: Sendable {
    public let bundleId: String
    public let displayName: String
    public var isVisible: Bool
    public var position: Int
    
    public init(bundleId: String, displayName: String, isVisible: Bool = true, position: Int = 0) {
        self.bundleId = bundleId
        self.displayName = displayName
        self.isVisible = isVisible
        self.position = position
    }
}

// MARK: - Menu Bar Manager

/// Manages menu bar item visibility and ordering
///
/// Features:
/// - Hide/show menu bar items
/// - Reorder items
/// - Per-app menu bar configurations
public final class MenuBarManager: @unchecked Sendable {
    
    // MARK: - Singleton
    
    public static let shared = MenuBarManager()
    
    // MARK: - Properties
    
    /// Hidden bundle IDs
    private var hiddenItems: Set<String> = []
    private let itemsLock = NSLock()
    
    /// Configuration file path
    private let configPath: String
    
    // MARK: - Known System Items
    
    /// Common menu bar extra bundle IDs
    public static let knownItems: [String: String] = [
        "com.apple.controlcenter.wifi": "Wi-Fi",
        "com.apple.controlcenter.bluetooth": "Bluetooth",
        "com.apple.controlcenter.battery": "Battery",
        "com.apple.controlcenter.sound": "Sound",
        "com.apple.controlcenter.nowplaying": "Now Playing",
        "com.apple.controlcenter.focus": "Focus",
        "com.apple.controlcenter.display": "Display",
        "com.apple.Spotlight": "Spotlight",
        "com.apple.notificationcenterui": "Notification Center",
        "com.apple.systemuiserver.clock": "Clock"
    ]
    
    // MARK: - Initialization
    
    private init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        configPath = homeDir.appendingPathComponent(
            ".config/control/menubar.json"
        ).path
        
        loadConfiguration()
    }
    
    // MARK: - Public Methods
    
    /// Get all menu bar items
    public func getAllItems() -> [MenuBarItem] {
        var items: [MenuBarItem] = []
        
        itemsLock.lock()
        let currentHidden = hiddenItems
        itemsLock.unlock()
        
        for (bundleId, name) in Self.knownItems {
            let item = MenuBarItem(
                bundleId: bundleId,
                displayName: name,
                isVisible: !currentHidden.contains(bundleId)
            )
            items.append(item)
        }
        
        return items.sorted { $0.displayName < $1.displayName }
    }
    
    /// Hide a menu bar item
    public func hideItem(_ bundleId: String) {
        itemsLock.lock()
        hiddenItems.insert(bundleId)
        itemsLock.unlock()
        
        saveConfiguration()
        log.info("Hidden menu bar item: \(bundleId)")
    }
    
    /// Show a menu bar item
    public func showItem(_ bundleId: String) {
        itemsLock.lock()
        hiddenItems.remove(bundleId)
        itemsLock.unlock()
        
        saveConfiguration()
        log.info("Shown menu bar item: \(bundleId)")
    }
    
    /// Toggle item visibility
    public func toggleItem(_ bundleId: String) {
        itemsLock.lock()
        if hiddenItems.contains(bundleId) {
            hiddenItems.remove(bundleId)
        } else {
            hiddenItems.insert(bundleId)
        }
        itemsLock.unlock()
        
        saveConfiguration()
    }
    
    /// Check if item is visible
    public func isItemVisible(_ bundleId: String) -> Bool {
        itemsLock.lock()
        defer { itemsLock.unlock() }
        return !hiddenItems.contains(bundleId)
    }
    
    /// Apply visibility changes
    /// Note: This uses defaults commands as direct manipulation requires SIP bypass
    @MainActor
    public func applyChanges() {
        itemsLock.lock()
        let currentHidden = hiddenItems
        itemsLock.unlock()
        
        // Use defaults to configure menu bar extras
        // This method modifies user preferences which is SIP-safe
        
        for bundleId in currentHidden {
            // Different approaches for different items
            if bundleId.contains("controlcenter") {
                modifyControlCenterItem(bundleId, visible: false)
            }
        }
        
        // Restart menu bar to apply changes
        restartSystemUIServer()
        
        log.info("Applied menu bar changes")
    }
    
    /// Reset to system defaults
    public func resetToDefaults() {
        itemsLock.lock()
        hiddenItems.removeAll()
        itemsLock.unlock()
        
        saveConfiguration()
        log.info("Menu bar reset to defaults")
    }
    
    // MARK: - Private Methods
    
    /// Load configuration from disk
    private func loadConfiguration() {
        guard FileManager.default.fileExists(atPath: configPath) else { return }
        
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
            let hidden = try JSONDecoder().decode([String].self, from: data)
            
            itemsLock.lock()
            hiddenItems = Set(hidden)
            itemsLock.unlock()
            
            log.debug("Loaded menu bar configuration")
        } catch {
            log.warning("Failed to load menu bar config: \(error)")
        }
    }
    
    /// Save configuration to disk
    private func saveConfiguration() {
        do {
            let directory = (configPath as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(
                atPath: directory,
                withIntermediateDirectories: true
            )
            
            itemsLock.lock()
            let hidden = Array(hiddenItems)
            itemsLock.unlock()
            
            let data = try JSONEncoder().encode(hidden)
            try data.write(to: URL(fileURLWithPath: configPath))
        } catch {
            log.error("Failed to save menu bar config: \(error)")
        }
    }
    
    /// Modify Control Center item visibility
    private func modifyControlCenterItem(_ bundleId: String, visible: Bool) {
        // Extract the item name from bundle ID
        guard let itemName = bundleId.components(separatedBy: ".").last else { return }
        
        let value = visible ? "1" : "0"
        let domain = "com.apple.controlcenter"
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["write", domain, "NSStatusItem Visible \(itemName)", "-bool", value]
        
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            log.warning("Failed to modify control center item: \(error)")
        }
    }
    
    /// Restart SystemUIServer to apply changes
    private func restartSystemUIServer() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["SystemUIServer"]
        
        do {
            try process.run()
        } catch {
            log.warning("Failed to restart SystemUIServer: \(error)")
        }
    }
}
