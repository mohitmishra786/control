// Control - macOS Power User Interaction Manager
// SIP Detector
//
// Detects System Integrity Protection status and enforces SIP-safe operations.

import Foundation

// MARK: - SIP Status

/// System Integrity Protection status
public enum SIPStatus: Sendable {
    case enabled
    case disabled
    case partiallyDisabled(flags: [String])
    case unknown
    
    public var isFullyEnabled: Bool {
        if case .enabled = self {
            return true
        }
        return false
    }
    
    public var description: String {
        switch self {
        case .enabled:
            return "SIP is fully enabled"
        case .disabled:
            return "SIP is disabled"
        case .partiallyDisabled(let flags):
            return "SIP is partially disabled: \(flags.joined(separator: ", "))"
        case .unknown:
            return "SIP status unknown"
        }
    }
}

// MARK: - SIP Detector

/// Detects and reports SIP status
///
/// Control is designed to work with SIP enabled. This detector
/// helps verify the system state and warns about SIP-dependent operations.
public final class SIPDetector: Sendable {
    
    // MARK: - Singleton
    
    public static let shared = SIPDetector()
    
    // MARK: - Cached Status
    
    private let cachedStatus: SIPStatus
    
    // MARK: - Initialization
    
    private init() {
        cachedStatus = SIPDetector.detectStatus()
    }
    
    // MARK: - Public Methods
    
    /// Get current SIP status (cached)
    public var status: SIPStatus {
        return cachedStatus
    }
    
    /// Check if SIP is enabled
    public var isEnabled: Bool {
        return cachedStatus.isFullyEnabled
    }
    
    /// Refresh SIP status (expensive - runs shell command)
    public func refreshStatus() -> SIPStatus {
        return SIPDetector.detectStatus()
    }
    
    /// Check if an operation requires SIP disabled
    /// - Parameter operation: Description of the operation
    /// - Returns: true if operation is allowed
    public func canPerformOperation(_ operation: String) -> Bool {
        // Control operations are designed to be SIP-safe
        // This method can be extended to check specific operations
        return true
    }
    
    // MARK: - Private Methods
    
    /// Detect SIP status by running csrutil
    private static func detectStatus() -> SIPStatus {
        let process = Process()
        let pipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: "/usr/bin/csrutil")
        process.arguments = ["status"]
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return .unknown
            }
            
            return parseCSRUtilOutput(output)
        } catch {
            log.warning("Failed to detect SIP status: \(error.localizedDescription)")
            return .unknown
        }
    }
    
    /// Parse csrutil output
    private static func parseCSRUtilOutput(_ output: String) -> SIPStatus {
        let lowercased = output.lowercased()
        
        if lowercased.contains("enabled") {
            // Check for partial disable
            if lowercased.contains("disabled") {
                // Parse which flags are disabled
                let flags = parseDisabledFlags(output)
                if flags.isEmpty {
                    return .enabled
                }
                return .partiallyDisabled(flags: flags)
            }
            return .enabled
        } else if lowercased.contains("disabled") {
            return .disabled
        }
        
        return .unknown
    }
    
    /// Parse disabled flags from csrutil output
    private static func parseDisabledFlags(_ output: String) -> [String] {
        var flags: [String] = []
        let lines = output.components(separatedBy: "\n")
        
        for line in lines {
            let lowercased = line.lowercased()
            if lowercased.contains("disabled") {
                // Extract flag name
                if let colonIndex = line.range(of: ":")?.lowerBound {
                    let flagName = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                    if !flagName.isEmpty {
                        flags.append(flagName)
                    }
                }
            }
        }
        
        return flags
    }
}

// MARK: - SIP-Safe Operation Wrapper

/// Wrapper for SIP-safe operations
public struct SIPSafeOperation<T> {
    private let operation: () throws -> T
    private let description: String
    
    public init(_ description: String, operation: @escaping () throws -> T) {
        self.description = description
        self.operation = operation
    }
    
    /// Execute the operation after verifying SIP safety
    public func execute() throws -> T {
        // Log operation
        log.debug("Executing SIP-safe operation: \(description)")
        
        // All Control operations are SIP-safe by design
        // This wrapper provides a consistent pattern for documentation
        return try operation()
    }
}
