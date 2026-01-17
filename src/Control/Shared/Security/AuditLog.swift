// Control - macOS Power User Interaction Manager
// Audit Log
//
// Security audit trail for sensitive operations.

import Foundation

// MARK: - Audit Event

/// Types of auditable events
public enum AuditEventType: String, Codable {
    case permissionChange = "permission_change"
    case fileModification = "file_modification"
    case configChange = "config_change"
    case daemonAction = "daemon_action"
    case quarantineRemoval = "quarantine_removal"
    case trustListChange = "trust_list_change"
    case securityEvent = "security_event"
}

/// An auditable event
public struct AuditEvent: Codable {
    public let id: UUID
    public let timestamp: Date
    public let type: AuditEventType
    public let action: String
    public let user: String
    public let details: [String: String]
    public let success: Bool
    
    public init(
        type: AuditEventType,
        action: String,
        details: [String: String] = [:],
        success: Bool = true
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.type = type
        self.action = action
        self.user = NSUserName()
        self.details = details
        self.success = success
    }
    
    /// Internal initializer that preserves original id, timestamp, and user
    internal init(
        id: UUID,
        timestamp: Date,
        user: String,
        type: AuditEventType,
        action: String,
        details: [String: String],
        success: Bool
    ) {
        self.id = id
        self.timestamp = timestamp
        self.user = user
        self.type = type
        self.action = action
        self.details = details
        self.success = success
    }
}

// MARK: - Audit Log

/// Security audit logging
///
/// Features:
/// - Append-only log file
/// - Structured events
/// - Log rotation
public final class AuditLog: @unchecked Sendable {
    
    // MARK: - Singleton
    
    public static let shared = AuditLog()
    
    // MARK: - Properties
    
    /// Log file path
    private let logPath: String
    
    /// Maximum log file size (10MB)
    private let maxLogSize: UInt64 = 10 * 1024 * 1024
    
    /// Maximum number of rotated logs
    private let maxRotatedLogs = 5
    
    /// Lock for thread-safe writes
    private let writeLock = NSLock()
    
    /// Enabled state
    public var isEnabled: Bool = true
    
    // MARK: - Initialization
    
    private init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        logPath = homeDir.appendingPathComponent(
            ".config/control/audit.log"
        ).path
        
        ensureLogDirectory()
    }
    
    // MARK: - Public Methods
    
    /// Log an audit event
    public func log(_ event: AuditEvent) {
        guard isEnabled else { return }
        
        writeLock.lock()
        defer { writeLock.unlock() }
        
        rotateIfNeeded()
        
        let entry = formatEvent(event)
        appendToLog(entry)
    }
    
    /// Log a permission change
    public func logPermissionChange(
        permission: String,
        app: String,
        granted: Bool
    ) {
        log(AuditEvent(
            type: .permissionChange,
            action: granted ? "grant" : "revoke",
            details: [
                "permission": permission,
                "app": app
            ],
            success: true
        ))
    }
    
    /// Log a file modification
    public func logFileModification(
        path: String,
        action: String,
        success: Bool
    ) {
        log(AuditEvent(
            type: .fileModification,
            action: action,
            details: ["path": path],
            success: success
        ))
    }
    
    /// Log a config change
    public func logConfigChange(
        key: String,
        oldValue: String,
        newValue: String
    ) {
        log(AuditEvent(
            type: .configChange,
            action: "update",
            details: [
                "key": key,
                "old_value": oldValue,
                "new_value": newValue
            ]
        ))
    }
    
    /// Log a security event
    public func logSecurityEvent(
        event: String,
        details: [String: String] = [:]
    ) {
        log(AuditEvent(
            type: .securityEvent,
            action: event,
            details: details
        ))
    }
    
    /// Get recent audit events
    public func getRecentEvents(count: Int = 100) -> [AuditEvent] {
        writeLock.lock()
        defer { writeLock.unlock() }
        
        guard let contents = try? String(contentsOfFile: logPath, encoding: .utf8) else {
            return []
        }
        
        let lines = contents.components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .suffix(count)
        
        return lines.compactMap { parseEvent($0) }
    }
    
    /// Search audit events
    public func search(
        type: AuditEventType? = nil,
        action: String? = nil,
        since: Date? = nil
    ) -> [AuditEvent] {
        let events = getRecentEvents(count: 1000)
        
        return events.filter { event in
            if let type = type, event.type != type { return false }
            if let action = action, !event.action.contains(action) { return false }
            if let since = since, event.timestamp < since { return false }
            return true
        }
    }
    
    /// Export audit log
    public func export(to path: String) throws {
        try FileManager.default.copyItem(atPath: logPath, toPath: path)
    }
    
    // MARK: - Private Methods
    
    private func ensureLogDirectory() {
        let directory = (logPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true
        )
    }
    
    /// Format event as JSON Line
    private func formatEvent(_ event: AuditEvent) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        do {
            let data = try encoder.encode(event)
            if let jsonString = String(data: data, encoding: .utf8) {
                return jsonString
            }
        } catch {
            // Fallback to legacy format if encoding fails
            return formatEventLegacy(event)
        }
        
        return formatEventLegacy(event)
    }
    
    /// Legacy format for backwards compatibility
    private func formatEventLegacy(_ event: AuditEvent) -> String {
        let dateFormatter = ISO8601DateFormatter()
        let timestamp = dateFormatter.string(from: event.timestamp)
        
        var parts = [
            event.id.uuidString,
            timestamp,
            event.type.rawValue,
            event.action,
            "user=\(event.user)",
            "success=\(event.success)"
        ]
        
        for (key, value) in event.details {
            parts.append("\(key)=\(value)")
        }
        
        return parts.joined(separator: " ")
    }
    
    /// Parse event from line (JSON or legacy format)
    private func parseEvent(_ line: String) -> AuditEvent? {
        // Detect JSON format (starts with '{')
        if line.hasPrefix("{") {
            return parseEventJSON(line)
        }
        
        // Fall back to legacy space-delimited format
        return parseEventLegacy(line)
    }
    
    /// Parse JSON-formatted event
    private func parseEventJSON(_ line: String) -> AuditEvent? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        guard let data = line.data(using: .utf8) else { return nil }
        
        do {
            return try decoder.decode(AuditEvent.self, from: data)
        } catch {
            return nil
        }
    }
    
    /// Parse legacy space-delimited event format
    private func parseEventLegacy(_ line: String) -> AuditEvent? {
        let parts = line.components(separatedBy: " ")
        // Format: id timestamp type action user=X success=X [details...]
        guard parts.count >= 6 else { return nil }
        
        guard let id = UUID(uuidString: parts[0]) else { return nil }
        
        let dateFormatter = ISO8601DateFormatter()
        guard let timestamp = dateFormatter.date(from: parts[1]),
              let type = AuditEventType(rawValue: parts[2]) else {
            return nil
        }
        
        let action = parts[3]
        var details: [String: String] = [:]
        var user = ""
        var success = true
        
        for part in parts.dropFirst(4) {
            if let equalsIndex = part.firstIndex(of: "=") {
                let key = String(part[..<equalsIndex])
                let value = String(part[part.index(after: equalsIndex)...])
                
                if key == "user" {
                    user = value
                } else if key == "success" {
                    success = value == "true"
                } else {
                    details[key] = value
                }
            }
        }
        
        return AuditEvent(
            id: id,
            timestamp: timestamp,
            user: user,
            type: type,
            action: action,
            details: details,
            success: success
        )
    }
    
    private func appendToLog(_ entry: String) {
        do {
            let data = (entry + "\n").data(using: .utf8)!
            
            if FileManager.default.fileExists(atPath: logPath) {
                let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: logPath))
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                try data.write(to: URL(fileURLWithPath: logPath))
            }
        } catch {
            // Silent failure - don't want audit log to break functionality
        }
    }
    
    private func rotateIfNeeded() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logPath),
              let size = attrs[.size] as? UInt64,
              size > maxLogSize else {
            return
        }
        
        // Rotate logs
        for i in (1..<maxRotatedLogs).reversed() {
            let current = "\(logPath).\(i)"
            let next = "\(logPath).\(i + 1)"
            
            try? FileManager.default.removeItem(atPath: next)
            try? FileManager.default.moveItem(atPath: current, toPath: next)
        }
        
        try? FileManager.default.moveItem(atPath: logPath, toPath: "\(logPath).1")
    }
}
