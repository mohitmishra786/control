// Control - macOS Power User Interaction Manager
// Display Persistence
//
// Multi-display window position persistence.
// Prevents "window jumble" on display wake.

import AppKit
import Foundation
import SQLite3

// MARK: - Saved Window Position

/// Saved window position data
public struct SavedWindowPosition: Codable {
    public let bundleId: String
    public let windowTitle: String
    public let frame: CodableRect
    public let displayId: UInt32
    public let timestamp: Date
    
    public init(
        bundleId: String,
        windowTitle: String,
        frame: CGRect,
        displayId: UInt32
    ) {
        self.bundleId = bundleId
        self.windowTitle = windowTitle
        self.frame = CodableRect(frame)
        self.displayId = displayId
        self.timestamp = Date()
    }
}

// MARK: - Codable Rect

/// Codable wrapper for CGRect
public struct CodableRect: Codable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    
    public init(_ rect: CGRect) {
        self.x = Double(rect.origin.x)
        self.y = Double(rect.origin.y)
        self.width = Double(rect.size.width)
        self.height = Double(rect.size.height)
    }
    
    public var cgRect: CGRect {
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

// MARK: - Display Persistence

/// Manages window position persistence across display changes
///
/// Features:
/// - SQLite position cache
/// - Display configuration observer
/// - Automatic position restoration
public final class DisplayPersistence: @unchecked Sendable {
    
    // MARK: - Singleton
    
    public static let shared = DisplayPersistence()
    
    // MARK: - Properties
    
    /// Database path
    private let dbPath: String
    
    /// SQLite database handle
    private var db: OpaquePointer?
    
    /// Display change observer
    private var displayObserver: Any?
    
    /// Window manager reference
    private var windowManager: WindowManager?
    
    /// Is active
    public private(set) var isActive: Bool = false
    
    /// Restore delay (seconds after display change)
    public var restoreDelay: TimeInterval = 1.0
    
    // MARK: - Initialization
    
    private init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        dbPath = homeDir.appendingPathComponent(
            ".config/control/positions.sqlite"
        ).path
        
        windowManager = WindowManager.shared
    }
    
    // MARK: - Public Methods
    
    /// Start display persistence
    @MainActor
    public func start() throws {
        guard !isActive else { return }
        
        // Open database
        try openDatabase()
        
        // Setup display change observer
        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleDisplayChange()
        }
        
        isActive = true
        log.info("DisplayPersistence started")
    }
    
    /// Stop display persistence
    public func stop() {
        guard isActive else { return }
        
        if let observer = displayObserver {
            NotificationCenter.default.removeObserver(observer)
            displayObserver = nil
        }
        
        closeDatabase()
        isActive = false
        log.info("DisplayPersistence stopped")
    }
    
    /// Save current window positions
    public func saveCurrentPositions() {
        guard let manager = windowManager else { return }
        
        let windows = manager.getAllWindows()
        var savedCount = 0
        
        for window in windows {
            let displayId = getDisplayId(for: window.frame)
            
            let position = SavedWindowPosition(
                bundleId: window.bundleIdentifier,
                windowTitle: window.title,
                frame: window.frame,
                displayId: displayId
            )
            
            savePosition(position)
            savedCount += 1
        }
        
        log.info("Saved \(savedCount) window positions")
    }
    
    /// Restore window positions
    @MainActor
    public func restorePositions() {
        guard let manager = windowManager else { return }
        
        let windows = manager.getAllWindows()
        var restoredCount = 0
        
        for window in windows {
            if let saved = getPosition(bundleId: window.bundleIdentifier, title: window.title) {
                // Check if display still exists
                guard displayExists(saved.displayId) else { continue }
                
                // Restore position
                let success = manager.moveWindow(window: window, to: saved.frame.cgRect)
                if success {
                    restoredCount += 1
                }
            }
        }
        
        log.info("Restored \(restoredCount) window positions")
    }
    
    /// Clear saved positions
    public func clearPositions() {
        guard let db = db else { return }
        
        let sql = "DELETE FROM positions"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_step(statement)
        }
        
        sqlite3_finalize(statement)
        log.info("Cleared saved positions")
    }
    
    /// Get saved position count
    public func getPositionCount() -> Int {
        guard let db = db else { return 0 }
        
        let sql = "SELECT COUNT(*) FROM positions"
        var statement: OpaquePointer?
        var count = 0
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                count = Int(sqlite3_column_int(statement, 0))
            }
        }
        
        sqlite3_finalize(statement)
        return count
    }
    
    // MARK: - Private Methods
    
    private func openDatabase() throws {
        // Create directory
        let directory = (dbPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true
        )
        
        // Open database
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            throw NSError(domain: "DisplayPersistence", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to open database"
            ])
        }
        
        // Create table
        let createSQL = """
            CREATE TABLE IF NOT EXISTS positions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                bundle_id TEXT NOT NULL,
                window_title TEXT,
                x REAL NOT NULL,
                y REAL NOT NULL,
                width REAL NOT NULL,
                height REAL NOT NULL,
                display_id INTEGER NOT NULL,
                timestamp INTEGER NOT NULL,
                UNIQUE(bundle_id, window_title)
            )
        """
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, createSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }
    
    private func closeDatabase() {
        if let db = db {
            sqlite3_close(db)
            self.db = nil
        }
    }
    
    private func savePosition(_ position: SavedWindowPosition) {
        guard let db = db else { return }
        
        let sql = """
            INSERT OR REPLACE INTO positions 
            (bundle_id, window_title, x, y, width, height, display_id, timestamp)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """
        
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, position.bundleId, -1, nil)
            sqlite3_bind_text(statement, 2, position.windowTitle, -1, nil)
            sqlite3_bind_double(statement, 3, Double(position.frame.x))
            sqlite3_bind_double(statement, 4, Double(position.frame.y))
            sqlite3_bind_double(statement, 5, Double(position.frame.width))
            sqlite3_bind_double(statement, 6, Double(position.frame.height))
            sqlite3_bind_int(statement, 7, Int32(position.displayId))
            sqlite3_bind_int64(statement, 8, Int64(position.timestamp.timeIntervalSince1970))
            
            sqlite3_step(statement)
        }
        
        sqlite3_finalize(statement)
    }
    
    private func getPosition(bundleId: String, title: String) -> SavedWindowPosition? {
        guard let db = db else { return nil }
        
        let sql = """
            SELECT x, y, width, height, display_id, timestamp
            FROM positions
            WHERE bundle_id = ? AND window_title = ?
        """
        
        var statement: OpaquePointer?
        var result: SavedWindowPosition?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, bundleId, -1, nil)
            sqlite3_bind_text(statement, 2, title, -1, nil)
            
            if sqlite3_step(statement) == SQLITE_ROW {
                let x = CGFloat(sqlite3_column_double(statement, 0))
                let y = CGFloat(sqlite3_column_double(statement, 1))
                let width = CGFloat(sqlite3_column_double(statement, 2))
                let height = CGFloat(sqlite3_column_double(statement, 3))
                let displayId = UInt32(sqlite3_column_int(statement, 4))
                let _ = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 5)))
                
                result = SavedWindowPosition(
                    bundleId: bundleId,
                    windowTitle: title,
                    frame: CGRect(x: x, y: y, width: width, height: height),
                    displayId: displayId
                )
            }
        }
        
        sqlite3_finalize(statement)
        return result
    }
    
    private func handleDisplayChange() {
        log.info("Display configuration changed")
        
        // Save current positions first
        saveCurrentPositions()
        
        // Restore after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) { [weak self] in
            Task { @MainActor in
                self?.restorePositions()
            }
        }
    }
    
    private func getDisplayId(for frame: CGRect) -> UInt32 {
        // Find which screen contains the window center
        let center = CGPoint(x: frame.midX, y: frame.midY)
        
        for screen in NSScreen.screens {
            if screen.frame.contains(center) {
                if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                    return screenNumber.uint32Value
                }
            }
        }
        
        // Default to main display
        if let main = NSScreen.main,
           let screenNumber = main.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return screenNumber.uint32Value
        }
        
        return 0
    }
    
    private func displayExists(_ displayId: UInt32) -> Bool {
        for screen in NSScreen.screens {
            if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                if screenNumber.uint32Value == displayId {
                    return true
                }
            }
        }
        return false
    }
}
