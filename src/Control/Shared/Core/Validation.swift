// Control - macOS Power User Interaction Manager
// Validation
//
// Input validation utilities for safe operations.

import Foundation

// MARK: - Validation Result

/// Result of a validation check
public enum ValidationResult {
    case valid
    case invalid(reason: String)
    
    public var isValid: Bool {
        if case .valid = self { return true }
        return false
    }
    
    public var reason: String? {
        if case .invalid(let reason) = self { return reason }
        return nil
    }
}

// MARK: - Validator

/// Protocol for validators
public protocol Validator {
    associatedtype Input
    func validate(_ input: Input) -> ValidationResult
}

// MARK: - Built-in Validators

/// Path validator
public struct PathValidator: Validator {
    public let mustExist: Bool
    public let mustBeWritable: Bool
    public let allowedExtensions: [String]?
    
    public init(
        mustExist: Bool = false,
        mustBeWritable: Bool = false,
        allowedExtensions: [String]? = nil
    ) {
        self.mustExist = mustExist
        self.mustBeWritable = mustBeWritable
        self.allowedExtensions = allowedExtensions
    }
    
    public func validate(_ path: String) -> ValidationResult {
        let fm = FileManager.default
        
        // Normalize the path: expand tilde and resolve symlinks
        let expandedPath = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)
        let normalizedPath = url.standardized.resolvingSymlinksInPath().path
        
        // Check existence
        if mustExist && !fm.fileExists(atPath: normalizedPath) {
            return .invalid(reason: "Path does not exist: \(path)")
        }
        
        // Check writability
        if mustBeWritable && !fm.isWritableFile(atPath: normalizedPath) {
            return .invalid(reason: "Path is not writable: \(path)")
        }
        
        // Check extension
        if let allowed = allowedExtensions {
            // Normalize allowed extensions: lowercase and strip leading dots
            let normalizedAllowed = allowed.map { ext in
                ext.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            }
            let ext = (normalizedPath as NSString).pathExtension.lowercased()
            if !normalizedAllowed.contains(ext) {
                return .invalid(reason: "Invalid extension: \(ext). Allowed: \(normalizedAllowed.joined(separator: ", "))")
            }
        }
        
        return .valid
    }
}

/// Bundle ID validator
public struct BundleIDValidator: Validator {
    public init() {}
    
    public func validate(_ bundleId: String) -> ValidationResult {
        // Bundle ID format: com.company.app
        let pattern = "^[a-zA-Z][a-zA-Z0-9-]*(\\.[a-zA-Z][a-zA-Z0-9-]*)+$"
        
        if bundleId.range(of: pattern, options: .regularExpression) == nil {
            return .invalid(reason: "Invalid bundle ID format")
        }
        
        return .valid
    }
}

/// Range validator for numbers
public struct RangeValidator<T: Comparable & Numeric>: Validator {
    public let min: T?
    public let max: T?
    
    public init(min: T? = nil, max: T? = nil) {
        self.min = min
        self.max = max
    }
    
    public func validate(_ value: T) -> ValidationResult {
        if let min = min, value < min {
            return .invalid(reason: "Value \(value) is below minimum \(min)")
        }
        if let max = max, value > max {
            return .invalid(reason: "Value \(value) is above maximum \(max)")
        }
        return .valid
    }
}

// MARK: - Validation Utilities

/// Static validation utilities
public enum Validation {
    
    /// Validate a path is safe (not protected)
    /// This implementation resolves symlinks and normalizes paths to prevent bypass attacks
    public static func isSafePath(_ path: String) -> Bool {
        let protectedPaths = [
            "/System",
            "/Library",
            "/private",
            "/usr",
            "/bin",
            "/sbin"
        ]
        
        // Expand tilde and normalize the path
        let expandedPath = (path as NSString).expandingTildeInPath
        
        // Get normalized, symlink-resolved absolute path
        let url = URL(fileURLWithPath: expandedPath)
        let resolvedPath = url.standardized.resolvingSymlinksInPath().path
        
        for protected in protectedPaths {
            // Check exact match or directory prefix with component boundary
            if resolvedPath == protected || resolvedPath.hasPrefix(protected + "/") {
                return false
            }
        }
        
        return true
    }
    
    /// Validate bundle ID format
    public static func isValidBundleID(_ bundleId: String) -> Bool {
        return BundleIDValidator().validate(bundleId).isValid
    }
    
    /// Validate positive integer
    public static func isPositiveInt(_ value: Int) -> Bool {
        return value > 0
    }
    
    /// Validate percentage (0-100)
    public static func isPercentage(_ value: Int) -> Bool {
        return value >= 0 && value <= 100
    }
    
    /// Validate normalized value (0.0-1.0)
    public static func isNormalized(_ value: Double) -> Bool {
        return value >= 0.0 && value <= 1.0
    }
    
    /// Validate color hex string
    public static func isValidHexColor(_ hex: String) -> Bool {
        let pattern = "^#?([A-Fa-f0-9]{6}|[A-Fa-f0-9]{8})$"
        return hex.range(of: pattern, options: .regularExpression) != nil
    }
    
    /// Validate keyboard shortcut format
    public static func isValidShortcut(_ shortcut: String) -> Bool {
        // Format: modifier+modifier+key (e.g., cmd+shift+a)
        let parts = shortcut.lowercased().components(separatedBy: "+")
        guard parts.count >= 2 else { return false }
        
        let validModifiers = ["cmd", "command", "ctrl", "control", "alt", "option", "shift"]
        let modifiers = parts.dropLast()
        
        // Validate all modifiers
        for mod in modifiers {
            if !validModifiers.contains(mod) {
                return false
            }
        }
        
        // Validate final key: must be non-empty and not a modifier
        guard let key = parts.last else { return false }
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedKey.isEmpty || validModifiers.contains(trimmedKey) {
            return false
        }
        
        return true
    }
}
