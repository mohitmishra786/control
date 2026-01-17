// Control - macOS Power User Interaction Manager
// Entitlements
//
// Runtime entitlement checking.

import Foundation
import Security

// MARK: - Entitlement

/// Known entitlements for Control
public enum Entitlement: String, CaseIterable {
    case automationAppleEvents = "com.apple.security.automation.apple-events"
    case appSandbox = "com.apple.security.app-sandbox"
    case filesUserSelected = "com.apple.security.files.user-selected.read-write"
    case filesDownloads = "com.apple.security.files.downloads.read-write"
    case unsignedExecutableMemory = "com.apple.security.cs.allow-unsigned-executable-memory"
    case disableLibraryValidation = "com.apple.security.cs.disable-library-validation"
    case debugger = "com.apple.security.cs.debugger"
    case allowJIT = "com.apple.security.cs.allow-jit"
    
    public var displayName: String {
        switch self {
        case .automationAppleEvents: return "Automation (Apple Events)"
        case .appSandbox: return "App Sandbox"
        case .filesUserSelected: return "User-Selected Files"
        case .filesDownloads: return "Downloads Access"
        case .unsignedExecutableMemory: return "Unsigned Executable Memory"
        case .disableLibraryValidation: return "Disable Library Validation"
        case .debugger: return "Debugger"
        case .allowJIT: return "Allow JIT"
        }
    }
}

// MARK: - Entitlements Checker

/// Checks runtime entitlements for the current process
public final class EntitlementsChecker: @unchecked Sendable {
    
    // MARK: - Singleton
    
    public static let shared = EntitlementsChecker()
    
    // MARK: - Properties
    
    /// Cached entitlements
    private var cachedEntitlements: [String: Any]?
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Check if an entitlement is granted
    public func hasEntitlement(_ entitlement: Entitlement) -> Bool {
        return hasEntitlement(entitlement.rawValue)
    }
    
    /// Check if an entitlement is granted by key
    public func hasEntitlement(_ key: String) -> Bool {
        guard let entitlements = getEntitlements() else {
            return false
        }
        
        if let value = entitlements[key] as? Bool {
            return value
        }
        
        return entitlements[key] != nil
    }
    
    /// Get all entitlements
    public func getEntitlements() -> [String: Any]? {
        if let cached = cachedEntitlements {
            return cached
        }
        
        // Get code signature info
        var code: SecCode?
        let status = SecCodeCopySelf([], &code)
        
        guard status == errSecSuccess, let code = code else {
            log.warning("Failed to get SecCode: \(status)")
            return nil
        }
        
        // Convert to static code for signing info
        var staticCode: SecStaticCode?
        let staticStatus = SecCodeCopyStaticCode(code, [], &staticCode)
        
        guard staticStatus == errSecSuccess, let staticCode = staticCode else {
            log.warning("Failed to get SecStaticCode: \(staticStatus)")
            return nil
        }
        
        // Get signing info
        var info: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &info
        )
        
        guard infoStatus == errSecSuccess,
              let infoDict = info as? [String: Any] else {
            log.warning("Failed to get signing info: \(infoStatus)")
            return nil
        }
        
        // Extract entitlements
        if let entitlements = infoDict[kSecCodeInfoEntitlementsDict as String] as? [String: Any] {
            cachedEntitlements = entitlements
            return entitlements
        }
        
        return nil
    }
    
    /// Get missing required entitlements
    public func getMissingEntitlements(_ required: [Entitlement]) -> [Entitlement] {
        return required.filter { !hasEntitlement($0) }
    }
    
    /// Check if running with hardened runtime
    public func isHardenedRuntime() -> Bool {
        guard getSecCode() != nil else { return false }
        
        // SecCodeGetTypeID returns a non-zero type ID if Security.framework is loaded
        let status = SecCodeGetTypeID()
        
        return status != 0
    }
    
    /// Check if app is sandboxed
    public func isSandboxed() -> Bool {
        return hasEntitlement(.appSandbox)
    }
    
    /// Get code signature status
    public func getSignatureStatus() -> String {
        guard let code = getSecCode() else {
            return "unsigned"
        }
        
        let status = SecCodeCheckValidity(code, [], nil)
        
        switch status {
        case errSecSuccess:
            return "valid"
        case errSecCSUnsigned:
            return "unsigned"
        case errSecCSSignatureFailed:
            return "invalid"
        default:
            return "unknown (\(status))"
        }
    }
    
    // MARK: - Private Methods
    
    private func getSecCode() -> SecCode? {
        var code: SecCode?
        let status = SecCodeCopySelf([], &code)
        return status == errSecSuccess ? code : nil
    }
}
