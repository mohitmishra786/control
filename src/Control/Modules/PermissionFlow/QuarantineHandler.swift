// Control - macOS Power User Interaction Manager
// Quarantine Handler
//
// Removes quarantine attributes from downloaded apps with biometric confirmation.
// Skill Reference: permission-manager
// - Use xattr system calls to remove com.apple.quarantine
// - Verify code signature before removal
// - Require biometric/password confirmation

import Foundation
import LocalAuthentication
import AppKit

// MARK: - Quarantine Status

/// Quarantine status of a file
public enum QuarantineStatus: Sendable {
    case quarantined(origin: String?, date: Date?)
    case notQuarantined
    case checkFailed(reason: String)
}

// MARK: - Quarantine Removal Result

/// Result of quarantine removal
public enum QuarantineRemovalResult: Sendable {
    case success
    case authenticationFailed
    case signatureInvalid
    case attributeNotFound
    case removeFailed(reason: String)
}

// MARK: - Quarantine Handler

/// Handles quarantine attribute removal for downloaded apps
///
/// Security measures:
/// - Verifies code signature before removal
/// - Requires biometric/password confirmation
/// - Logs all removal operations
public final class QuarantineHandler: @unchecked Sendable {
    
    // MARK: - Singleton
    
    public static let shared = QuarantineHandler()
    
    // MARK: - Properties
    
    /// Quarantine attribute name
    private let quarantineAttribute = "com.apple.quarantine"
    
    /// Audit log path
    private let auditLogPath: String
    
    // MARK: - Initialization
    
    private init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        auditLogPath = homeDir.appendingPathComponent(
            ".config/control/quarantine_audit.log"
        ).path
    }
    
    // MARK: - Public Methods
    
    /// Check quarantine status of a file
    public func checkStatus(at path: String) -> QuarantineStatus {
        guard FileManager.default.fileExists(atPath: path) else {
            return .checkFailed(reason: "File not found")
        }
        
        // Read quarantine attribute
        let bufferSize = 1024
        var buffer = [CChar](repeating: 0, count: bufferSize)
        
        let result = getxattr(path, quarantineAttribute, &buffer, bufferSize, 0, XATTR_NOFOLLOW)
        
        if result < 0 {
            if errno == ENOATTR {
                return .notQuarantined
            }
            return .checkFailed(reason: String(cString: strerror(errno)))
        }
        
        // Parse quarantine data
        let quarantineData = String(cString: buffer)
        let (origin, date) = parseQuarantineData(quarantineData)
        
        return .quarantined(origin: origin, date: date)
    }
    
    /// Remove quarantine attribute with biometric confirmation
    public func removeQuarantine(
        at path: String,
        requireAuthentication: Bool = true
    ) async -> QuarantineRemovalResult {
        
        // Check if quarantined
        guard case .quarantined = checkStatus(at: path) else {
            log.info("File not quarantined: \(path)")
            return .attributeNotFound
        }
        
        // Verify code signature
        if !verifyCodeSignature(at: path) {
            log.warning("Code signature invalid, refusing to remove quarantine: \(path)")
            return .signatureInvalid
        }
        
        // Require authentication
        if requireAuthentication {
            let authenticated = await authenticate(reason: "Remove quarantine from downloaded app")
            if !authenticated {
                log.warning("Authentication failed for quarantine removal")
                return .authenticationFailed
            }
        }
        
        // Remove the attribute
        let result = removexattr(path, quarantineAttribute, XATTR_NOFOLLOW)
        
        if result != 0 {
            let error = String(cString: strerror(errno))
            log.error("Failed to remove quarantine: \(error)")
            return .removeFailed(reason: error)
        }
        
        // Log the removal
        logRemoval(path: path)
        
        log.info("Quarantine removed: \(path)")
        return .success
    }
    
    /// Remove quarantine from an app bundle and its contents
    public func removeQuarantineRecursive(
        at appPath: String,
        requireAuthentication: Bool = true
    ) async -> QuarantineRemovalResult {
        
        // Verify it's an app bundle
        guard appPath.hasSuffix(".app") else {
            return .removeFailed(reason: "Not an app bundle")
        }
        
        // Verify code signature
        if !verifyCodeSignature(at: appPath) {
            log.warning("Code signature invalid: \(appPath)")
            return .signatureInvalid
        }
        
        // Require authentication
        if requireAuthentication {
            let authenticated = await authenticate(
                reason: "Remove quarantine from \(URL(fileURLWithPath: appPath).lastPathComponent)"
            )
            if !authenticated {
                return .authenticationFailed
            }
        }
        
        // Remove from main bundle
        _ = removexattr(appPath, quarantineAttribute, XATTR_NOFOLLOW)
        
        // Recursively remove from contents
        if let enumerator = FileManager.default.enumerator(atPath: appPath) {
            while let relativePath = enumerator.nextObject() as? String {
                let fullPath = (appPath as NSString).appendingPathComponent(relativePath)
                removexattr(fullPath, quarantineAttribute, XATTR_NOFOLLOW)
            }
        }
        
        // Log the removal
        logRemoval(path: appPath)
        
        log.info("Quarantine removed recursively: \(appPath)")
        return .success
    }
    
    /// Get audit log entries
    public func getAuditLog() -> [String] {
        guard let contents = try? String(contentsOfFile: auditLogPath, encoding: .utf8) else {
            return []
        }
        return contents.components(separatedBy: "\n").filter { !$0.isEmpty }
    }
    
    // MARK: - Private Methods
    
    /// Parse quarantine data string
    private func parseQuarantineData(_ data: String) -> (origin: String?, date: Date?) {
        // Quarantine format: flags;timestamp;origin
        let components = data.components(separatedBy: ";")
        
        var origin: String? = nil
        var date: Date? = nil
        
        if components.count > 2 {
            origin = components[2]
        }
        
        if components.count > 1 {
            if let timestampInt = UInt64(components[1], radix: 16) {
                date = Date(timeIntervalSinceReferenceDate: Double(timestampInt))
            }
        }
        
        return (origin, date)
    }
    
    /// Verify code signature of file
    private func verifyCodeSignature(at path: String) -> Bool {
        let process = Process()
        let pipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-v", "--strict", path]
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            // Exit code 0 means valid signature
            return process.terminationStatus == 0
        } catch {
            log.warning("Failed to verify code signature: \(error)")
            return false
        }
    }
    
    /// Authenticate with biometrics or password
    private func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        
        // Check if biometrics available
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            log.warning("Authentication not available: \(error?.localizedDescription ?? "unknown")")
            return false
        }
        
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            ) { success, error in
                if let error = error {
                    log.warning("Authentication error: \(error.localizedDescription)")
                }
                continuation.resume(returning: success)
            }
        }
    }
    
    /// Log quarantine removal to audit file
    private func logRemoval(path: String) {
        let dateFormatter = ISO8601DateFormatter()
        let timestamp = dateFormatter.string(from: Date())
        let userName = NSUserName()
        
        let logEntry = "[\(timestamp)] user=\(userName) action=remove_quarantine path=\(path)\n"
        
        // Ensure directory exists
        let directory = (auditLogPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true
        )
        
        // Append to log file
        if let handle = FileHandle(forWritingAtPath: auditLogPath) {
            handle.seekToEndOfFile()
            handle.write(logEntry.data(using: .utf8) ?? Data())
            handle.closeFile()
        } else {
            FileManager.default.createFile(
                atPath: auditLogPath,
                contents: logEntry.data(using: .utf8)
            )
        }
    }
}
