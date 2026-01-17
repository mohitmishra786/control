// Control - macOS Power User Interaction Manager
// Error Handler
//
// Centralized error handling with recovery strategies and user-friendly messages.

import Foundation

// MARK: - Control Error Protocol

/// Base protocol for all Control errors
public protocol ControlErrorProtocol: Error, LocalizedError, Sendable {
    /// Error code for tracking
    var code: String { get }
    
    /// Severity level
    var severity: ErrorSeverity { get }
    
    /// Suggested recovery action
    var recoverySuggestion: String? { get }
    
    /// Whether this error is recoverable
    var isRecoverable: Bool { get }
}

// MARK: - Error Severity

/// Error severity levels
public enum ErrorSeverity: String, Sendable {
    case info = "info"
    case warning = "warning"
    case error = "error"
    case critical = "critical"
}

// MARK: - Core Errors

/// Core system errors
public enum CoreError: ControlErrorProtocol {
    case configurationError(reason: String)
    case fileNotFound(path: String)
    case fileAccessDenied(path: String)
    case invalidData(reason: String)
    case timeout(operation: String, seconds: Int)
    case unexpected(reason: String)
    
    public var code: String {
        switch self {
        case .configurationError: return "CORE_CONFIG"
        case .fileNotFound: return "CORE_FILE_NOT_FOUND"
        case .fileAccessDenied: return "CORE_ACCESS_DENIED"
        case .invalidData: return "CORE_INVALID_DATA"
        case .timeout: return "CORE_TIMEOUT"
        case .unexpected: return "CORE_UNEXPECTED"
        }
    }
    
    public var severity: ErrorSeverity {
        switch self {
        case .unexpected: return .critical
        case .configurationError, .fileNotFound, .fileAccessDenied: return .error
        case .invalidData, .timeout: return .warning
        }
    }
    
    public var errorDescription: String? {
        switch self {
        case .configurationError(let reason):
            return "Configuration error: \(reason)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .fileAccessDenied(let path):
            return "Access denied to file: \(path)"
        case .invalidData(let reason):
            return "Invalid data: \(reason)"
        case .timeout(let operation, let seconds):
            return "Operation '\(operation)' timed out after \(seconds) seconds"
        case .unexpected(let reason):
            return "Unexpected error: \(reason)"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .configurationError:
            return "Check the configuration file syntax and try again."
        case .fileNotFound:
            return "Verify the file path exists and is accessible."
        case .fileAccessDenied:
            return "Check file permissions or run with elevated privileges."
        case .invalidData:
            return "The data format may be corrupted. Try resetting to defaults."
        case .timeout:
            return "The operation took too long. Try again or check system resources."
        case .unexpected:
            return "Please report this issue with the error details."
        }
    }
    
    public var isRecoverable: Bool {
        switch self {
        case .unexpected, .fileAccessDenied: return false
        default: return true
        }
    }
}

// MARK: - Permission Errors

/// Permission-related errors
public enum PermissionError: ControlErrorProtocol {
    case accessibilityDenied
    case screenRecordingDenied
    case inputMonitoringDenied
    case automationDenied(app: String)
    case sipEnabled
    case tccDatabaseLocked
    
    public var code: String {
        switch self {
        case .accessibilityDenied: return "PERM_ACCESSIBILITY"
        case .screenRecordingDenied: return "PERM_SCREEN_RECORDING"
        case .inputMonitoringDenied: return "PERM_INPUT_MONITORING"
        case .automationDenied: return "PERM_AUTOMATION"
        case .sipEnabled: return "PERM_SIP"
        case .tccDatabaseLocked: return "PERM_TCC_LOCKED"
        }
    }
    
    public var severity: ErrorSeverity {
        return .error
    }
    
    public var errorDescription: String? {
        switch self {
        case .accessibilityDenied:
            return "Accessibility permission is required"
        case .screenRecordingDenied:
            return "Screen Recording permission is required"
        case .inputMonitoringDenied:
            return "Input Monitoring permission is required"
        case .automationDenied(let app):
            return "Automation permission denied for \(app)"
        case .sipEnabled:
            return "System Integrity Protection is enabled"
        case .tccDatabaseLocked:
            return "TCC database is locked by the system"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .accessibilityDenied:
            return "Grant permission in System Settings > Privacy & Security > Accessibility"
        case .screenRecordingDenied:
            return "Grant permission in System Settings > Privacy & Security > Screen Recording"
        case .inputMonitoringDenied:
            return "Grant permission in System Settings > Privacy & Security > Input Monitoring"
        case .automationDenied:
            return "Grant automation permission when prompted by the system"
        case .sipEnabled:
            return "Control is designed to work with SIP enabled. No action needed."
        case .tccDatabaseLocked:
            return "Wait a moment and try again. The system may be updating permissions."
        }
    }
    
    public var isRecoverable: Bool {
        switch self {
        case .sipEnabled: return false
        default: return true
        }
    }
}

// MARK: - Error Handler

/// Centralized error handler with recovery strategies
public final class ErrorHandler: @unchecked Sendable {
    
    // MARK: - Singleton
    
    public static let shared = ErrorHandler()
    
    // MARK: - Properties
    
    /// Recent errors for debugging
    private var recentErrors: [ErrorRecord] = []
    private let maxRecentErrors = 100
    private let lock = NSLock()
    
    // MARK: - Error Record
    
    public struct ErrorRecord: Sendable {
        public let timestamp: Date
        public let error: any Error
        public let context: String?
        
        init(error: any Error, context: String?) {
            self.timestamp = Date()
            self.error = error
            self.context = context
        }
    }
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Handle an error with logging and optional recovery
    public func handle(
        _ error: any Error,
        context: String? = nil,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        // Record the error
        recordError(error, context: context)
        
        // Log the error
        let contextString = context.map { " [\($0)]" } ?? ""
        
        if let controlError = error as? any ControlErrorProtocol {
            log.error(
                "\(controlError.errorDescription ?? "Unknown error")\(contextString)",
                metadata: [
                    "code": controlError.code,
                    "severity": controlError.severity.rawValue,
                    "recoverable": String(controlError.isRecoverable)
                ],
                file: file,
                function: function,
                line: line
            )
            
            // Log recovery suggestion if available
            if let suggestion = controlError.recoverySuggestion {
                log.info("Recovery suggestion: \(suggestion)")
            }
        } else {
            log.error(
                "\(error.localizedDescription)\(contextString)",
                file: file,
                function: function,
                line: line
            )
        }
    }
    
    /// Attempt to recover from an error
    public func attemptRecovery<T>(
        from error: any Error,
        fallback: T
    ) -> T {
        // Log recovery attempt
        log.info("Attempting recovery with fallback value")
        return fallback
    }
    
    /// Get recent errors for debugging
    public func getRecentErrors() -> [ErrorRecord] {
        lock.lock()
        defer { lock.unlock() }
        return recentErrors
    }
    
    /// Clear error history
    public func clearHistory() {
        lock.lock()
        defer { lock.unlock() }
        recentErrors.removeAll()
    }
    
    // MARK: - Private Methods
    
    private func recordError(_ error: any Error, context: String?) {
        lock.lock()
        defer { lock.unlock() }
        
        let record = ErrorRecord(error: error, context: context)
        recentErrors.append(record)
        
        // Trim if needed
        if recentErrors.count > maxRecentErrors {
            recentErrors.removeFirst(recentErrors.count - maxRecentErrors)
        }
    }
}

// MARK: - Result Extension

extension Result {
    /// Handle failure with ErrorHandler
    @discardableResult
    public func handleError(context: String? = nil) -> Result {
        if case .failure(let error) = self {
            ErrorHandler.shared.handle(error, context: context)
        }
        return self
    }
}
