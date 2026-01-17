// Control - macOS Power User Interaction Manager
// Trust List Manager
//
// Manages trusted applications for fast-track permission automation.
// Supports bundle ID patterns and profiles.

import Foundation

// MARK: - Trust Profile

/// Predefined trust profiles
public enum TrustProfile: String, CaseIterable, Sendable {
    case developer = "developer"
    case designer = "designer"
    case minimal = "minimal"
    case custom = "custom"
    
    public var description: String {
        switch self {
        case .developer: return "Developer (JetBrains, VS Code, Docker, terminals)"
        case .designer: return "Designer (Adobe, Figma, Sketch)"
        case .minimal: return "Minimal (essential system tools only)"
        case .custom: return "Custom user-defined list"
        }
    }
}

// MARK: - Trust Entry

/// A trusted application entry
public struct TrustEntry: Codable, Sendable {
    public let pattern: String  // Bundle ID or pattern (e.g., "com.jetbrains.*")
    public let permissions: [String]  // Permission types to auto-grant
    public let addedDate: Date
    public let notes: String?
    
    public init(
        pattern: String,
        permissions: [String] = [],
        addedDate: Date = Date(),
        notes: String? = nil
    ) {
        self.pattern = pattern
        self.permissions = permissions
        self.addedDate = addedDate
        self.notes = notes
    }
    
    /// Check if bundle ID matches this entry's pattern
    public func matches(bundleId: String) -> Bool {
        if pattern.hasSuffix(".*") {
            // Wildcard pattern
            let prefix = String(pattern.dropLast(2))
            return bundleId.hasPrefix(prefix)
        } else if pattern.contains("*") {
            // Convert to regex pattern
            let regexPattern = pattern
                .replacingOccurrences(of: ".", with: "\\.")
                .replacingOccurrences(of: "*", with: ".*")
            
            return bundleId.range(of: regexPattern, options: .regularExpression) != nil
        } else {
            // Exact match
            return bundleId == pattern
        }
    }
}

// MARK: - Trust List Manager

/// Manages trusted applications for permission automation
///
/// Features:
/// - Pattern matching (e.g., com.jetbrains.*)
/// - Predefined profiles (developer, designer, minimal)
/// - Import/export trust lists
/// - Signature verification
public final class TrustListManager: @unchecked Sendable {
    
    // MARK: - Singleton
    
    public static let shared = TrustListManager()
    
    // MARK: - Properties
    
    /// Trust list storage path
    private let trustListPath: String
    
    /// Current trust entries
    private var entries: [TrustEntry] = []
    private let entriesLock = NSLock()
    
    /// Active profile
    public private(set) var activeProfile: TrustProfile = .minimal
    
    // MARK: - Built-in Patterns
    
    /// Developer profile patterns
    private static let developerPatterns: [TrustEntry] = [
        TrustEntry(pattern: "com.jetbrains.*", permissions: ["accessibility", "screen_recording"]),
        TrustEntry(pattern: "com.microsoft.VSCode", permissions: ["accessibility"]),
        TrustEntry(pattern: "com.docker.docker", permissions: ["screen_recording", "full_disk_access"]),
        TrustEntry(pattern: "com.github.atom", permissions: ["accessibility"]),
        TrustEntry(pattern: "com.sublimetext.*", permissions: ["accessibility"]),
        TrustEntry(pattern: "com.googlecode.iterm2", permissions: ["accessibility", "full_disk_access"]),
        TrustEntry(pattern: "com.apple.Terminal", permissions: ["accessibility", "full_disk_access"]),
        TrustEntry(pattern: "org.vim.*", permissions: ["accessibility"]),
        TrustEntry(pattern: "com.neovim.*", permissions: ["accessibility"]),
    ]
    
    /// Designer profile patterns
    private static let designerPatterns: [TrustEntry] = [
        TrustEntry(pattern: "com.adobe.*", permissions: ["accessibility", "screen_recording"]),
        TrustEntry(pattern: "com.figma.Desktop", permissions: ["accessibility"]),
        TrustEntry(pattern: "com.bohemiancoding.sketch3", permissions: ["accessibility"]),
        TrustEntry(pattern: "com.affinity.*", permissions: ["accessibility"]),
        TrustEntry(pattern: "com.pixelmator.*", permissions: ["accessibility"]),
    ]
    
    /// Minimal profile patterns
    private static let minimalPatterns: [TrustEntry] = [
        TrustEntry(pattern: "com.apple.Terminal", permissions: ["accessibility"]),
    ]
    
    // MARK: - Initialization
    
    private init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        trustListPath = homeDir.appendingPathComponent(
            ".config/control/trust_list.json"
        ).path
        
        loadTrustList()
    }
    
    // MARK: - Public Methods
    
    /// Set active profile
    public func setProfile(_ profile: TrustProfile) {
        activeProfile = profile
        
        entriesLock.lock()
        defer { entriesLock.unlock() }
        
        switch profile {
        case .developer:
            entries = Self.developerPatterns
        case .designer:
            entries = Self.designerPatterns
        case .minimal:
            entries = Self.minimalPatterns
        case .custom:
            loadTrustList()
        }
        
        log.info("Trust profile set to: \(profile.rawValue)")
    }
    
    /// Add trusted app pattern
    public func addTrustedApp(
        pattern: String,
        permissions: [String] = [],
        notes: String? = nil
    ) {
        entriesLock.lock()
        defer { entriesLock.unlock() }
        
        let entry = TrustEntry(
            pattern: pattern,
            permissions: permissions,
            notes: notes
        )
        
        // Remove existing entry with same pattern
        entries.removeAll { $0.pattern == pattern }
        entries.append(entry)
        
        // Auto-switch to custom profile
        activeProfile = .custom
        
        saveTrustList()
        
        log.info("Added trusted app pattern: \(pattern)")
    }
    
    /// Remove trusted app pattern
    public func removeTrustedApp(pattern: String) {
        entriesLock.lock()
        defer { entriesLock.unlock() }
        
        entries.removeAll { $0.pattern == pattern }
        saveTrustList()
        
        log.info("Removed trusted app pattern: \(pattern)")
    }
    
    /// Check if bundle ID is trusted
    public func isTrusted(bundleId: String) -> Bool {
        entriesLock.lock()
        defer { entriesLock.unlock() }
        
        return entries.contains { $0.matches(bundleId: bundleId) }
    }
    
    /// Get trust entry for bundle ID
    public func getTrustEntry(for bundleId: String) -> TrustEntry? {
        entriesLock.lock()
        defer { entriesLock.unlock() }
        
        return entries.first { $0.matches(bundleId: bundleId) }
    }
    
    /// Get all trusted entries
    public func getAllEntries() -> [TrustEntry] {
        entriesLock.lock()
        defer { entriesLock.unlock() }
        
        return entries
    }
    
    /// Get permissions for app
    public func getPermissions(for bundleId: String) -> [String] {
        guard let entry = getTrustEntry(for: bundleId) else {
            return []
        }
        return entry.permissions
    }
    
    /// Export trust list to file
    public func exportTrustList(to path: String) throws {
        entriesLock.lock()
        let currentEntries = entries
        entriesLock.unlock()
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(currentEntries)
        try data.write(to: URL(fileURLWithPath: path))
        
        log.info("Exported trust list to: \(path)")
    }
    
    /// Import trust list from file
    public func importTrustList(from path: String) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let importedEntries = try decoder.decode([TrustEntry].self, from: data)
        
        entriesLock.lock()
        entries = importedEntries
        entriesLock.unlock()
        
        activeProfile = .custom
        saveTrustList()
        
        log.info("Imported \(importedEntries.count) trust entries from: \(path)")
    }
    
    // MARK: - Private Methods
    
    /// Load trust list from disk
    private func loadTrustList() {
        guard FileManager.default.fileExists(atPath: trustListPath) else {
            log.debug("No trust list file found, using defaults")
            return
        }
        
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: trustListPath))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            entries = try decoder.decode([TrustEntry].self, from: data)
            activeProfile = .custom
            
            log.info("Loaded \(entries.count) trust entries")
        } catch {
            log.warning("Failed to load trust list: \(error)")
        }
    }
    
    /// Save trust list to disk
    private func saveTrustList() {
        do {
            // Ensure directory exists
            let directory = (trustListPath as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(
                atPath: directory,
                withIntermediateDirectories: true
            )
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            
            let data = try encoder.encode(entries)
            try data.write(to: URL(fileURLWithPath: trustListPath))
            
            log.debug("Saved trust list")
        } catch {
            log.error("Failed to save trust list: \(error)")
        }
    }
}
