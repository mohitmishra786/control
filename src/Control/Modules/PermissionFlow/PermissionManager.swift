// Control - macOS Power User Interaction Manager
// Permission Manager
//
// SIP-safe permission scanning and management.
// Skill Reference: permission-manager
// - CRITICAL: Never write directly to TCC.db (SIP-protected)
// - Use READ-ONLY TCC database access for permission scanning

import Foundation
import SQLite3

// MARK: - Permission Type

/// Types of permissions in macOS TCC database
public enum PermissionType: String, CaseIterable, Sendable {
    case accessibility = "kTCCServiceAccessibility"
    case screenRecording = "kTCCServiceScreenCapture"
    case inputMonitoring = "kTCCServiceListenEvent"
    case fullDiskAccess = "kTCCServiceSystemPolicyAllFiles"
    case camera = "kTCCServiceCamera"
    case microphone = "kTCCServiceMicrophone"
    case location = "kTCCServiceLocation"
    case contacts = "kTCCServiceAddressBook"
    case calendar = "kTCCServiceCalendar"
    case reminders = "kTCCServiceReminders"
    case photos = "kTCCServicePhotos"
    case automation = "kTCCServiceAppleEvents"
    
    public var displayName: String {
        switch self {
        case .accessibility: return "Accessibility"
        case .screenRecording: return "Screen Recording"
        case .inputMonitoring: return "Input Monitoring"
        case .fullDiskAccess: return "Full Disk Access"
        case .camera: return "Camera"
        case .microphone: return "Microphone"
        case .location: return "Location Services"
        case .contacts: return "Contacts"
        case .calendar: return "Calendar"
        case .reminders: return "Reminders"
        case .photos: return "Photos"
        case .automation: return "Automation"
        }
    }
    
    public var systemSettingsPath: String {
        return "x-apple.systempreferences:com.apple.preference.security?Privacy_\(displayName.replacingOccurrences(of: " ", with: ""))"
    }
}

// MARK: - Permission Status

/// Status of a permission
public enum PermissionStatus: String, Sendable {
    case granted = "granted"
    case denied = "denied"
    case notDetermined = "not_determined"
    case limited = "limited"
    case unknown = "unknown"
    
    public var displayName: String {
        switch self {
        case .granted: return "Granted"
        case .denied: return "Denied"
        case .notDetermined: return "Not Determined"
        case .limited: return "Limited"
        case .unknown: return "Unknown"
        }
    }
}

// MARK: - Permission Entry

/// Represents a permission entry from TCC database
public struct PermissionEntry: Sendable {
    public let service: PermissionType
    public let client: String  // Bundle ID
    public let status: PermissionStatus
    public let lastModified: Date?
    
    public init(
        service: PermissionType,
        client: String,
        status: PermissionStatus,
        lastModified: Date? = nil
    ) {
        self.service = service
        self.client = client
        self.status = status
        self.lastModified = lastModified
    }
}

// MARK: - Permission Manager

/// SIP-safe permission management
///
/// CRITICAL: This manager NEVER writes to TCC.db directly.
/// All operations use Apple-approved mechanisms:
/// - READ-ONLY TCC database access for scanning
/// - UI Automation for granting (via TCCManager)
/// - Plist modification for screen recording (Amnesia method)
public final class PermissionManager: @unchecked Sendable {
    
    // MARK: - Singleton
    
    public static let shared = PermissionManager()
    
    // MARK: - Properties
    
    /// TCC database paths
    private let userTCCPath: String
    private let systemTCCPath = "/Library/Application Support/com.apple.TCC/TCC.db"
    
    /// Cached permissions
    private var cachedPermissions: [PermissionEntry] = []
    private let cacheLock = NSLock()
    private var cacheTimestamp: Date?
    private let cacheTTL: TimeInterval = 60  // 1 minute cache
    
    // MARK: - Initialization
    
    private init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        userTCCPath = homeDir.appendingPathComponent(
            "Library/Application Support/com.apple.TCC/TCC.db"
        ).path
    }
    
    // MARK: - Public Methods
    
    /// Scan all permissions (READ-ONLY)
    public func scanPermissions() -> [PermissionEntry] {
        // Check cache
        if let cached = getCachedPermissions() {
            return cached
        }
        
        var entries: [PermissionEntry] = []
        
        // Read from user TCC database
        if let userEntries = readTCCDatabase(at: userTCCPath) {
            entries.append(contentsOf: userEntries)
        }
        
        // Cache results
        setCachedPermissions(entries)
        
        log.info("Scanned \(entries.count) permission entries")
        return entries
    }
    
    /// Get permissions for a specific app
    public func getPermissions(forApp bundleId: String) -> [PermissionEntry] {
        return scanPermissions().filter { $0.client == bundleId }
    }
    
    /// Get apps with a specific permission
    public func getApps(withPermission type: PermissionType) -> [PermissionEntry] {
        return scanPermissions().filter { $0.service == type }
    }
    
    /// Check if app has permission
    public func hasPermission(_ type: PermissionType, app bundleId: String) -> Bool {
        let entries = getPermissions(forApp: bundleId)
        return entries.contains { $0.service == type && $0.status == .granted }
    }
    
    /// Check Control's own accessibility permission
    public func checkAccessibilityPermission() -> Bool {
        return AXIsProcessTrusted()
    }
    
    /// Check if SIP is enabled
    public func checkSIPStatus() -> SIPStatus {
        return SIPDetector.shared.status
    }
    
    /// Get grouped permissions by service type
    public func getGroupedPermissions() -> [PermissionType: [PermissionEntry]] {
        let entries = scanPermissions()
        return Dictionary(grouping: entries) { $0.service }
    }
    
    /// Refresh permission cache
    public func refreshCache() {
        cacheLock.lock()
        cacheTimestamp = nil
        cacheLock.unlock()
        
        _ = scanPermissions()
    }
    
    /// Open System Settings to specific permission section
    public func openSystemSettings(for type: PermissionType) {
        let urlString = type.systemSettingsPath
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
            log.info("Opened System Settings for: \(type.displayName)")
        }
    }
    
    // MARK: - Private Methods
    
    /// Read TCC database (READ-ONLY)
    private func readTCCDatabase(at path: String) -> [PermissionEntry]? {
        var db: OpaquePointer?
        
        // Open database in READ-ONLY mode
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK else {
            log.warning("Cannot open TCC database: \(path)")
            return nil
        }
        
        defer { sqlite3_close(db) }
        
        // Query permissions
        let query = """
            SELECT service, client, auth_value, last_modified
            FROM access
        """
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            log.warning("Failed to prepare TCC query: \(errorMsg)")
            return nil
        }
        
        defer { sqlite3_finalize(statement) }
        
        var entries: [PermissionEntry] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            // Get service name
            guard let servicePtr = sqlite3_column_text(statement, 0) else { continue }
            let serviceName = String(cString: servicePtr)
            
            // Get client bundle ID
            guard let clientPtr = sqlite3_column_text(statement, 1) else { continue }
            let client = String(cString: clientPtr)
            
            // Get auth value
            let authValue = sqlite3_column_int(statement, 2)
            
            // Get last modified timestamp
            let lastModifiedInt = sqlite3_column_int64(statement, 3)
            let lastModified = Date(timeIntervalSince1970: Double(lastModifiedInt))
            
            // Map service to PermissionType
            guard let permType = PermissionType.allCases.first(where: { $0.rawValue == serviceName }) else {
                continue
            }
            
            // Map auth value to status
            let status: PermissionStatus
            switch authValue {
            case 0: status = .denied
            case 1: status = .notDetermined
            case 2: status = .granted
            case 3: status = .limited
            default: status = .unknown
            }
            
            let entry = PermissionEntry(
                service: permType,
                client: client,
                status: status,
                lastModified: lastModified
            )
            entries.append(entry)
        }
        
        return entries
    }
    
    /// Get cached permissions if valid
    private func getCachedPermissions() -> [PermissionEntry]? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        
        guard let timestamp = cacheTimestamp,
              Date().timeIntervalSince(timestamp) < cacheTTL else {
            return nil
        }
        
        return cachedPermissions
    }
    
    /// Set cached permissions
    private func setCachedPermissions(_ entries: [PermissionEntry]) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        
        cachedPermissions = entries
        cacheTimestamp = Date()
    }
}

import AppKit
