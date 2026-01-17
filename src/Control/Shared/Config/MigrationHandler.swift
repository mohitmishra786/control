// Control - macOS Power User Interaction Manager
// Migration Handler
//
// Handles configuration version migrations.

import Foundation

// MARK: - Config Version

/// Configuration version
public struct ConfigVersion: Comparable, CustomStringConvertible, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    
    public static let current = ConfigVersion(major: 1, minor: 0, patch: 0)
    
    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }
    
    public init?(string: String) {
        let parts = string.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        
        self.major = parts[0]
        self.minor = parts[1]
        self.patch = parts.count > 2 ? parts[2] : 0
    }
    
    public var description: String {
        return "\(major).\(minor).\(patch)"
    }
    
    public static func < (lhs: ConfigVersion, rhs: ConfigVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

// MARK: - Migration

/// A single migration step
public protocol ConfigMigration {
    var fromVersion: ConfigVersion { get }
    var toVersion: ConfigVersion { get }
    
    func migrate(config: inout [String: Any]) throws
}

// MARK: - Migration Handler

/// Handles configuration migrations between versions
///
/// Features:
/// - Version detection
/// - Sequential migration application
/// - Backup before migration
public final class MigrationHandler: @unchecked Sendable {
    
    // MARK: - Singleton
    
    public static let shared = MigrationHandler()
    
    // MARK: - Properties
    
    /// Registered migrations
    private var migrations: [ConfigMigration] = []
    
    /// Backup directory
    private let backupDir: String
    
    // MARK: - Initialization
    
    private init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        backupDir = homeDir.appendingPathComponent(
            ".config/control/backups"
        ).path
        
        // Register migrations
        registerMigrations()
    }
    
    // MARK: - Public Methods
    
    /// Check if migration is needed
    public func needsMigration(configPath: String) -> Bool {
        guard let version = detectVersion(at: configPath) else {
            return false
        }
        
        return version < ConfigVersion.current
    }
    
    /// Migrate configuration file
    public func migrate(configPath: String) throws -> Bool {
        guard let version = detectVersion(at: configPath) else {
            log.info("No version detected, assuming current")
            return false
        }
        
        if version >= ConfigVersion.current {
            log.info("Config already at current version")
            return false
        }
        
        // Create backup
        try createBackup(of: configPath)
        
        // Load config
        var config = try loadConfig(at: configPath)
        
        // Apply migrations sequentially
        var currentVersion = version
        
        for migration in migrations.sorted(by: { $0.fromVersion < $1.fromVersion }) {
            if migration.fromVersion == currentVersion {
                log.info("Applying migration: \(migration.fromVersion) -> \(migration.toVersion)")
                
                try migration.migrate(config: &config)
                currentVersion = migration.toVersion
            }
        }
        
        // Update version in config
        config["version"] = ConfigVersion.current.description
        
        // Save migrated config
        try saveConfig(config, to: configPath)
        
        log.info("Migration complete: \(version) -> \(ConfigVersion.current)")
        return true
    }
    
    /// Get backup files
    public func listBackups() -> [String] {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: backupDir) else {
            return []
        }
        
        return files.filter { $0.hasSuffix(".toml") }.sorted().reversed()
    }
    
    /// Restore from backup
    public func restoreBackup(_ backupName: String, to configPath: String) throws {
        let backupPath = (backupDir as NSString).appendingPathComponent(backupName)
        
        guard FileManager.default.fileExists(atPath: backupPath) else {
            throw NSError(domain: "MigrationHandler", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Backup not found: \(backupName)"
            ])
        }
        
        try FileManager.default.copyItem(atPath: backupPath, toPath: configPath)
        log.info("Restored backup: \(backupName)")
    }
    
    // MARK: - Private Methods
    
    private func registerMigrations() {
        // Register future migrations here
        // migrations.append(V0_9_to_V1_0_Migration())
    }
    
    private func detectVersion(at path: String) -> ConfigVersion? {
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        
        do {
            let contents = try String(contentsOfFile: path, encoding: .utf8)
            
            // Look for version key
            if let range = contents.range(of: #"version\s*=\s*"([^"]+)""#, options: .regularExpression) {
                let match = contents[range]
                if let versionRange = match.range(of: #""([^"]+)""#, options: .regularExpression) {
                    let versionString = match[versionRange].dropFirst().dropLast()
                    return ConfigVersion(string: String(versionString))
                }
            }
            
            // No version key = v0.9 (pre-versioning)
            return ConfigVersion(major: 0, minor: 9, patch: 0)
            
        } catch {
            return nil
        }
    }
    
    private func createBackup(of path: String) throws {
        try FileManager.default.createDirectory(
            atPath: backupDir,
            withIntermediateDirectories: true
        )
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        
        let backupPath = (backupDir as NSString).appendingPathComponent(
            "control_\(timestamp).toml"
        )
        
        try FileManager.default.copyItem(atPath: path, toPath: backupPath)
        log.info("Created backup: \(backupPath)")
    }
    
    private func loadConfig(at path: String) throws -> [String: Any] {
        let contents = try String(contentsOfFile: path, encoding: .utf8)
        
        // Simple TOML to dictionary (basic implementation)
        var config: [String: Any] = [:]
        var currentSection = ""
        
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip comments and empty lines
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            
            // Section header
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                currentSection = String(trimmed.dropFirst().dropLast())
                if config[currentSection] == nil {
                    config[currentSection] = [String: Any]()
                }
                continue
            }
            
            // Key-value pair
            if let equalsIndex = trimmed.firstIndex(of: "=") {
                let key = String(trimmed[..<equalsIndex]).trimmingCharacters(in: .whitespaces)
                var value = String(trimmed[trimmed.index(after: equalsIndex)...])
                    .trimmingCharacters(in: .whitespaces)
                
                // Parse value
                let parsedValue: Any
                if value == "true" {
                    parsedValue = true
                } else if value == "false" {
                    parsedValue = false
                } else if let intVal = Int(value) {
                    parsedValue = intVal
                } else if let doubleVal = Double(value) {
                    parsedValue = doubleVal
                } else {
                    // String (remove quotes)
                    if value.hasPrefix("\"") && value.hasSuffix("\"") {
                        value = String(value.dropFirst().dropLast())
                    }
                    parsedValue = value
                }
                
                if currentSection.isEmpty {
                    config[key] = parsedValue
                } else if var section = config[currentSection] as? [String: Any] {
                    section[key] = parsedValue
                    config[currentSection] = section
                }
            }
        }
        
        return config
    }
    
    private func saveConfig(_ config: [String: Any], to path: String) throws {
        var lines: [String] = []
        
        // Add version
        lines.append("# Control Configuration")
        lines.append("# Migrated to version \(ConfigVersion.current)")
        lines.append("")
        
        // Write top-level keys first
        for (key, value) in config where !(value is [String: Any]) {
            lines.append(formatKeyValue(key: key, value: value))
        }
        
        // Write sections
        for (key, value) in config {
            if let section = value as? [String: Any] {
                lines.append("")
                lines.append("[\(key)]")
                for (subKey, subValue) in section {
                    lines.append(formatKeyValue(key: subKey, value: subValue))
                }
            }
        }
        
        let contents = lines.joined(separator: "\n")
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
    }
    
    private func formatKeyValue(key: String, value: Any) -> String {
        switch value {
        case let bool as Bool:
            return "\(key) = \(bool)"
        case let int as Int:
            return "\(key) = \(int)"
        case let double as Double:
            return "\(key) = \(double)"
        case let string as String:
            return "\(key) = \"\(string)\""
        default:
            return "\(key) = \"\(value)\""
        }
    }
}
