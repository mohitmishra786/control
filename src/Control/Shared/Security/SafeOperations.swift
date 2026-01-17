// Control - macOS Power User Interaction Manager
// Safe Operations
//
// Protected path validation and safe file operations.

import Foundation

// MARK: - Safe Operation Error

public enum SafeOperationError: Error, LocalizedError {
    case protectedPath(path: String)
    case sipProtected(path: String)
    case insufficientPermissions(path: String)
    case operationDenied(reason: String)
    
    public var errorDescription: String? {
        switch self {
        case .protectedPath(let path):
            return "Operation denied: \(path) is a protected path"
        case .sipProtected(let path):
            return "Operation denied: \(path) is protected by SIP"
        case .insufficientPermissions(let path):
            return "Insufficient permissions to access: \(path)"
        case .operationDenied(let reason):
            return "Operation denied: \(reason)"
        }
    }
}

// MARK: - Safe Operations

/// Safe file operations that respect SIP and protected paths
public final class SafeOperations {
    
    // MARK: - Protected Paths
    
    /// System-protected paths (SIP and root-owned)
    public static let protectedPaths: Set<String> = [
        "/System",
        "/Library",
        "/usr",
        "/bin",
        "/sbin",
        "/private/var",
        "/private/etc"
    ]
    
    /// User-writable but sensitive paths
    public static let sensitivePaths: Set<String> = [
        "~/Library/Keychains",
        "~/Library/Preferences",
        "~/Library/Application Support/com.apple.TCC"
    ]
    
    // MARK: - Validation
    
    /// Check if path is protected
    public static func isProtected(_ path: String) -> Bool {
        let expandedPath = (path as NSString).expandingTildeInPath
        let resolvedPath = (expandedPath as NSString).resolvingSymlinksInPath
        
        for protected in protectedPaths {
            if resolvedPath.hasPrefix(protected) {
                return true
            }
        }
        
        return false
    }
    
    /// Check if path is sensitive
    public static func isSensitive(_ path: String) -> Bool {
        let expandedPath = (path as NSString).expandingTildeInPath
        
        for sensitive in sensitivePaths {
            let expandedSensitive = (sensitive as NSString).expandingTildeInPath
            if expandedPath.hasPrefix(expandedSensitive) {
                return true
            }
        }
        
        return false
    }
    
    /// Validate path is safe to write to
    public static func validateWritePath(_ path: String) throws {
        if isProtected(path) {
            throw SafeOperationError.protectedPath(path: path)
        }
        
        // Check SIP status for certain paths
        let sipDetector = SIPDetector.shared
        if sipDetector.isEnabled && path.hasPrefix("/System") {
            throw SafeOperationError.sipProtected(path: path)
        }
        
        // Check write permission
        let expandedPath = (path as NSString).expandingTildeInPath
        let parentDir = (expandedPath as NSString).deletingLastPathComponent
        
        if !FileManager.default.isWritableFile(atPath: parentDir) {
            throw SafeOperationError.insufficientPermissions(path: path)
        }
    }
    
    /// Validate path is safe to read from
    public static func validateReadPath(_ path: String) throws {
        let expandedPath = (path as NSString).expandingTildeInPath
        
        if !FileManager.default.isReadableFile(atPath: expandedPath) {
            throw SafeOperationError.insufficientPermissions(path: path)
        }
    }
    
    // MARK: - Safe File Operations
    
    /// Safely write data to file
    public static func safeWrite(data: Data, to path: String) throws {
        try validateWritePath(path)
        
        let expandedPath = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)
        
        // Create parent directory if needed
        let parentDir = (expandedPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: parentDir,
            withIntermediateDirectories: true
        )
        
        try data.write(to: url)
        log.debug("Safely wrote to: \(path)")
    }
    
    /// Safely write string to file
    public static func safeWrite(string: String, to path: String, encoding: String.Encoding = .utf8) throws {
        guard let data = string.data(using: encoding) else {
            throw SafeOperationError.operationDenied(reason: "Failed to encode string")
        }
        try safeWrite(data: data, to: path)
    }
    
    /// Safely read data from file
    public static func safeRead(from path: String) throws -> Data {
        try validateReadPath(path)
        
        let expandedPath = (path as NSString).expandingTildeInPath
        return try Data(contentsOf: URL(fileURLWithPath: expandedPath))
    }
    
    /// Safely read string from file
    public static func safeReadString(from path: String, encoding: String.Encoding = .utf8) throws -> String {
        let data = try safeRead(from: path)
        guard let string = String(data: data, encoding: encoding) else {
            throw SafeOperationError.operationDenied(reason: "Failed to decode string")
        }
        return string
    }
    
    /// Safely delete file
    public static func safeDelete(_ path: String) throws {
        try validateWritePath(path)
        
        // Extra check for sensitive files
        if isSensitive(path) {
            throw SafeOperationError.operationDenied(reason: "Cannot delete sensitive file")
        }
        
        let expandedPath = (path as NSString).expandingTildeInPath
        try FileManager.default.removeItem(atPath: expandedPath)
        log.debug("Safely deleted: \(path)")
    }
    
    /// Safely move file
    public static func safeMove(from source: String, to destination: String) throws {
        try validateReadPath(source)
        try validateWritePath(destination)
        
        let expandedSource = (source as NSString).expandingTildeInPath
        let expandedDest = (destination as NSString).expandingTildeInPath
        
        try FileManager.default.moveItem(atPath: expandedSource, toPath: expandedDest)
        log.debug("Safely moved: \(source) -> \(destination)")
    }
    
    /// Safely copy file
    public static func safeCopy(from source: String, to destination: String) throws {
        try validateReadPath(source)
        try validateWritePath(destination)
        
        let expandedSource = (source as NSString).expandingTildeInPath
        let expandedDest = (destination as NSString).expandingTildeInPath
        
        try FileManager.default.copyItem(atPath: expandedSource, toPath: expandedDest)
        log.debug("Safely copied: \(source) -> \(destination)")
    }
}
