// Control - macOS Power User Interaction Manager
// Logger
//
// Structured logging with os_log integration and multiple output targets.

import Foundation
import Logging
import os.log

// MARK: - Log Level

/// Log levels matching Swift Log and os_log
public enum LogLevel: String, CaseIterable, Sendable {
    case debug = "debug"
    case info = "info"
    case warning = "warning"
    case error = "error"
    case critical = "critical"
    
    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        case .critical: return .fault
        }
    }
    
    var swiftLogLevel: Logging.Logger.Level {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .warning
        case .error: return .error
        case .critical: return .critical
        }
    }
}

// MARK: - Log Entry

/// Represents a single log entry
public struct LogEntry: Sendable {
    public let timestamp: Date
    public let level: LogLevel
    public let message: String
    public let metadata: [String: String]
    public let file: String
    public let function: String
    public let line: UInt
    
    public init(
        timestamp: Date = Date(),
        level: LogLevel,
        message: String,
        metadata: [String: String] = [:],
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        self.timestamp = timestamp
        self.level = level
        self.message = message
        self.metadata = metadata
        self.file = file
        self.function = function
        self.line = line
    }
    
    /// Format entry for file output
    public func formatted() -> String {
        let dateFormatter = ISO8601DateFormatter()
        let timestamp = dateFormatter.string(from: self.timestamp)
        let filename = URL(fileURLWithPath: file).lastPathComponent
        
        var result = "[\(timestamp)] [\(level.rawValue.uppercased())] \(message)"
        
        if !metadata.isEmpty {
            let metaString = metadata.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            result += " {\(metaString)}"
        }
        
        result += " [\(filename):\(line)]"
        return result
    }
}

// MARK: - Control Logger

/// Central logging service for Control
///
/// Provides structured logging with multiple output targets:
/// - Console (stderr)
/// - File (~/.config/control/control.log)
/// - System log (os_log)
public final class ControlLogger: @unchecked Sendable {
    
    // MARK: - Singleton
    
    public static let shared = ControlLogger()
    
    // MARK: - Properties
    
    /// Minimum log level to output
    public var minLevel: LogLevel = .info
    
    /// Enable console output
    public var consoleEnabled: Bool = true
    
    /// Enable file output
    public var fileEnabled: Bool = true
    
    /// Enable os_log output
    public var osLogEnabled: Bool = true
    
    /// Log file path
    public var logFilePath: String
    
    /// Maximum log file size before rotation (100MB default)
    public var maxFileSize: UInt64 = 100 * 1024 * 1024
    
    /// os_log logger
    private let osLog: OSLog
    
    /// Swift Log logger
    private var swiftLogger: Logging.Logger
    
    /// File handle for log file
    private var fileHandle: FileHandle?
    
    /// Lock for thread-safe file writes
    private let fileLock = NSLock()
    
    // MARK: - Initialization
    
    private init() {
        // Set default log path
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        logFilePath = homeDir.appendingPathComponent(".config/control/control.log").path
        
        // Initialize os_log
        osLog = OSLog(subsystem: "com.control", category: "Control")
        
        // Initialize Swift Log
        swiftLogger = Logging.Logger(label: "com.control")
        
        // Create log directory if needed
        createLogDirectory()
    }
    
    // MARK: - Public Logging Methods
    
    /// Log a debug message
    public func debug(
        _ message: String,
        metadata: [String: String] = [:],
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        log(level: .debug, message: message, metadata: metadata, file: file, function: function, line: line)
    }
    
    /// Log an info message
    public func info(
        _ message: String,
        metadata: [String: String] = [:],
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        log(level: .info, message: message, metadata: metadata, file: file, function: function, line: line)
    }
    
    /// Log a warning message
    public func warning(
        _ message: String,
        metadata: [String: String] = [:],
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        log(level: .warning, message: message, metadata: metadata, file: file, function: function, line: line)
    }
    
    /// Log an error message
    public func error(
        _ message: String,
        metadata: [String: String] = [:],
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        log(level: .error, message: message, metadata: metadata, file: file, function: function, line: line)
    }
    
    /// Log a critical message
    public func critical(
        _ message: String,
        metadata: [String: String] = [:],
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        log(level: .critical, message: message, metadata: metadata, file: file, function: function, line: line)
    }
    
    // MARK: - Core Logging
    
    /// Core logging method
    private func log(
        level: LogLevel,
        message: String,
        metadata: [String: String],
        file: String,
        function: String,
        line: UInt
    ) {
        // Check minimum level
        guard shouldLog(level: level) else { return }
        
        let entry = LogEntry(
            level: level,
            message: message,
            metadata: metadata,
            file: file,
            function: function,
            line: line
        )
        
        // Output to console
        if consoleEnabled {
            writeToConsole(entry)
        }
        
        // Output to file
        if fileEnabled {
            writeToFile(entry)
        }
        
        // Output to os_log
        if osLogEnabled {
            writeToOSLog(entry)
        }
    }
    
    /// Check if level should be logged
    private func shouldLog(level: LogLevel) -> Bool {
        let levels = LogLevel.allCases
        guard let minIndex = levels.firstIndex(of: minLevel),
              let levelIndex = levels.firstIndex(of: level) else {
            return true
        }
        return levelIndex >= minIndex
    }
    
    // MARK: - Output Targets
    
    /// Write to console (stderr)
    private func writeToConsole(_ entry: LogEntry) {
        let output = entry.formatted()
        FileHandle.standardError.write(Data((output + "\n").utf8))
    }
    
    /// Write to log file
    private func writeToFile(_ entry: LogEntry) {
        fileLock.lock()
        defer { fileLock.unlock() }
        
        // Open file handle if needed
        if fileHandle == nil {
            openLogFile()
        }
        
        guard let handle = fileHandle else { return }
        
        let output = entry.formatted() + "\n"
        if let data = output.data(using: .utf8) {
            handle.write(data)
        }
        
        // Check for rotation
        checkLogRotation()
    }
    
    /// Write to os_log
    private func writeToOSLog(_ entry: LogEntry) {
        os_log("%{public}@", log: osLog, type: entry.level.osLogType, entry.message)
    }
    
    // MARK: - File Management
    
    /// Create log directory if it doesn't exist
    private func createLogDirectory() {
        let directory = (logFilePath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true
        )
    }
    
    /// Open or create log file
    private func openLogFile() {
        let fm = FileManager.default
        
        if !fm.fileExists(atPath: logFilePath) {
            fm.createFile(atPath: logFilePath, contents: nil)
        }
        
        fileHandle = FileHandle(forWritingAtPath: logFilePath)
        fileHandle?.seekToEndOfFile()
    }
    
    /// Check if log rotation is needed
    private func checkLogRotation() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logFilePath),
              let fileSize = attrs[.size] as? UInt64 else {
            return
        }
        
        if fileSize > maxFileSize {
            rotateLog()
        }
    }
    
    /// Rotate log file
    private func rotateLog() {
        fileHandle?.closeFile()
        fileHandle = nil
        
        let fm = FileManager.default
        let rotatedPath = logFilePath + ".1"
        
        // Remove old rotated log
        try? fm.removeItem(atPath: rotatedPath)
        
        // Rotate current log
        try? fm.moveItem(atPath: logFilePath, toPath: rotatedPath)
        
        // Open fresh log file
        openLogFile()
    }
    
    /// Close log file
    public func close() {
        fileLock.lock()
        defer { fileLock.unlock() }
        
        fileHandle?.closeFile()
        fileHandle = nil
    }
}

// MARK: - Global Convenience

/// Global logger instance
public let log = ControlLogger.shared
