// Control - macOS Power User Interaction Manager
// Zone Presets
//
// Predefined window layout presets for different workflows.

import Foundation

// MARK: - Preset

/// A named collection of zones for a workflow
public struct ZonePreset: Codable, Sendable {
    public let name: String
    public let description: String
    public let zones: [String: NormalizedRect]
    public let rules: [AppLayoutRule]
    
    public init(
        name: String,
        description: String,
        zones: [String: NormalizedRect] = [:],
        rules: [AppLayoutRule] = []
    ) {
        self.name = name
        self.description = description
        self.zones = zones
        self.rules = rules
    }
}

// MARK: - Normalized Rectangle

/// Rectangle with normalized coordinates (0-1 range)
public struct NormalizedRect: Codable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
    
    /// Convert to CGRect using screen dimensions
    public func toCGRect(in screenFrame: CGRect) -> CGRect {
        return CGRect(
            x: screenFrame.origin.x + x * screenFrame.width,
            y: screenFrame.origin.y + y * screenFrame.height,
            width: width * screenFrame.width,
            height: height * screenFrame.height
        )
    }
}

// MARK: - App Layout Rule

/// Rule for automatically positioning an app
public struct AppLayoutRule: Codable, Sendable {
    public let bundleIdPattern: String  // Bundle ID or pattern
    public let zone: String             // Zone name to place the app
    public let alwaysOnTop: Bool
    
    public init(bundleIdPattern: String, zone: String, alwaysOnTop: Bool = false) {
        self.bundleIdPattern = bundleIdPattern
        self.zone = zone
        self.alwaysOnTop = alwaysOnTop
    }
    
    /// Check if this rule matches a bundle ID
    public func matches(bundleId: String) -> Bool {
        if bundleIdPattern.hasSuffix(".*") {
            let prefix = String(bundleIdPattern.dropLast(2))
            return bundleId.hasPrefix(prefix)
        }
        return bundleId == bundleIdPattern
    }
}

// MARK: - Built-in Presets

/// Built-in preset definitions
public enum BuiltInPreset: String, CaseIterable {
    case developer = "developer"
    case designer = "designer"
    case writer = "writer"
    case minimal = "minimal"
    
    public var preset: ZonePreset {
        switch self {
        case .developer:
            return ZonePreset(
                name: "Developer",
                description: "Terminal + Editor + Browser layout for development",
                zones: [
                    "terminal": NormalizedRect(x: 0, y: 0, width: 0.33, height: 1),
                    "editor": NormalizedRect(x: 0.33, y: 0, width: 0.34, height: 1),
                    "browser": NormalizedRect(x: 0.67, y: 0, width: 0.33, height: 1)
                ],
                rules: [
                    AppLayoutRule(bundleIdPattern: "com.apple.Terminal", zone: "terminal"),
                    AppLayoutRule(bundleIdPattern: "com.googlecode.iterm2", zone: "terminal"),
                    AppLayoutRule(bundleIdPattern: "com.microsoft.VSCode", zone: "editor"),
                    AppLayoutRule(bundleIdPattern: "com.jetbrains.*", zone: "editor"),
                    AppLayoutRule(bundleIdPattern: "com.apple.Safari", zone: "browser"),
                    AppLayoutRule(bundleIdPattern: "com.google.Chrome", zone: "browser"),
                ]
            )
            
        case .designer:
            return ZonePreset(
                name: "Designer",
                description: "Canvas + Tools layout for design work",
                zones: [
                    "canvas": NormalizedRect(x: 0, y: 0, width: 0.75, height: 1),
                    "tools": NormalizedRect(x: 0.75, y: 0, width: 0.25, height: 1)
                ],
                rules: [
                    AppLayoutRule(bundleIdPattern: "com.figma.Desktop", zone: "canvas"),
                    AppLayoutRule(bundleIdPattern: "com.bohemiancoding.sketch3", zone: "canvas"),
                    AppLayoutRule(bundleIdPattern: "com.adobe.Photoshop", zone: "canvas"),
                    AppLayoutRule(bundleIdPattern: "com.apple.finder", zone: "tools"),
                ]
            )
            
        case .writer:
            return ZonePreset(
                name: "Writer",
                description: "Focused writing layout",
                zones: [
                    "main": NormalizedRect(x: 0.15, y: 0, width: 0.7, height: 1),
                    "reference": NormalizedRect(x: 0, y: 0, width: 0.15, height: 1)
                ],
                rules: [
                    AppLayoutRule(bundleIdPattern: "com.apple.iWork.Pages", zone: "main"),
                    AppLayoutRule(bundleIdPattern: "com.microsoft.Word", zone: "main"),
                    AppLayoutRule(bundleIdPattern: "md.obsidian", zone: "main"),
                    AppLayoutRule(bundleIdPattern: "com.apple.Notes", zone: "reference"),
                ]
            )
            
        case .minimal:
            return ZonePreset(
                name: "Minimal",
                description: "Simple halves layout",
                zones: [
                    "left": NormalizedRect(x: 0, y: 0, width: 0.5, height: 1),
                    "right": NormalizedRect(x: 0.5, y: 0, width: 0.5, height: 1)
                ],
                rules: []
            )
        }
    }
}

// MARK: - Zone Presets Manager

/// Manages zone presets
public final class ZonePresets: @unchecked Sendable {
    
    // MARK: - Singleton
    
    public static let shared = ZonePresets()
    
    // MARK: - Properties
    
    /// Custom presets
    private var customPresets: [String: ZonePreset] = [:]
    private let lock = NSLock()
    
    /// Active preset name
    public private(set) var activePresetName: String = "minimal"
    
    /// Presets storage path
    private let presetsPath: String
    
    // MARK: - Initialization
    
    private init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        presetsPath = homeDir.appendingPathComponent(
            ".config/control/presets.json"
        ).path
        
        loadCustomPresets()
    }
    
    // MARK: - Public Methods
    
    /// Get all available presets (built-in + custom)
    public func getAllPresets() -> [ZonePreset] {
        lock.lock()
        defer { lock.unlock() }
        
        var presets = BuiltInPreset.allCases.map { $0.preset }
        presets.append(contentsOf: customPresets.values)
        return presets
    }
    
    /// Get preset by name
    public func getPreset(named name: String) -> ZonePreset? {
        // Check built-in first
        if let builtIn = BuiltInPreset(rawValue: name) {
            return builtIn.preset
        }
        
        // Check custom
        lock.lock()
        defer { lock.unlock() }
        return customPresets[name]
    }
    
    /// Get active preset
    public func getActivePreset() -> ZonePreset? {
        return getPreset(named: activePresetName)
    }
    
    /// Set active preset
    public func setActivePreset(_ name: String) -> Bool {
        guard getPreset(named: name) != nil else {
            log.warning("Preset not found: \(name)")
            return false
        }
        
        activePresetName = name
        log.info("Active preset set to: \(name)")
        return true
    }
    
    /// Add custom preset
    public func addPreset(_ preset: ZonePreset) {
        lock.lock()
        customPresets[preset.name] = preset
        lock.unlock()
        
        saveCustomPresets()
        log.info("Added custom preset: \(preset.name)")
    }
    
    /// Remove custom preset
    public func removePreset(named name: String) {
        lock.lock()
        customPresets.removeValue(forKey: name)
        lock.unlock()
        
        saveCustomPresets()
        log.info("Removed preset: \(name)")
    }
    
    /// Get zone for an app from active preset
    public func getZone(forApp bundleId: String) -> String? {
        guard let preset = getActivePreset() else { return nil }
        
        for rule in preset.rules {
            if rule.matches(bundleId: bundleId) {
                return rule.zone
            }
        }
        
        return nil
    }
    
    /// Get zone rect for an app
    public func getZoneRect(forApp bundleId: String, in screenFrame: CGRect) -> CGRect? {
        guard let preset = getActivePreset(),
              let zoneName = getZone(forApp: bundleId),
              let normalizedRect = preset.zones[zoneName] else {
            return nil
        }
        
        return normalizedRect.toCGRect(in: screenFrame)
    }
    
    // MARK: - Private Methods
    
    private func loadCustomPresets() {
        guard FileManager.default.fileExists(atPath: presetsPath) else { return }
        
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: presetsPath))
            let presets = try JSONDecoder().decode([ZonePreset].self, from: data)
            
            lock.lock()
            for preset in presets {
                customPresets[preset.name] = preset
            }
            lock.unlock()
            
            log.info("Loaded \(presets.count) custom presets")
        } catch {
            log.warning("Failed to load custom presets: \(error)")
        }
    }
    
    private func saveCustomPresets() {
        lock.lock()
        let presets = Array(customPresets.values)
        lock.unlock()
        
        do {
            let directory = (presetsPath as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(
                atPath: directory,
                withIntermediateDirectories: true
            )
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(presets)
            try data.write(to: URL(fileURLWithPath: presetsPath))
        } catch {
            log.error("Failed to save presets: \(error)")
        }
    }
}
