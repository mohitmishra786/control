// Control - macOS Power User Interaction Manager
// Theme Engine
//
// System-wide color scheme management.

import AppKit
import Foundation

// MARK: - Theme Mode

/// Theme mode for the system
public enum ThemeMode: String, Sendable {
    case light = "light"
    case dark = "dark"
    case auto = "auto"
}

// MARK: - Accent Color

/// System accent colors
public enum AccentColor: Int, Sendable, CaseIterable {
    case blue = 4
    case purple = 5
    case pink = 6
    case red = 0
    case orange = 1
    case yellow = 2
    case green = 3
    case graphite = -1
    case multicolor = -2  // App-specific
    
    public var displayName: String {
        switch self {
        case .blue: return "Blue"
        case .purple: return "Purple"
        case .pink: return "Pink"
        case .red: return "Red"
        case .orange: return "Orange"
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .graphite: return "Graphite"
        case .multicolor: return "Multicolor"
        }
    }
    
    public var nsColor: NSColor {
        switch self {
        case .blue: return .systemBlue
        case .purple: return .systemPurple
        case .pink: return .systemPink
        case .red: return .systemRed
        case .orange: return .systemOrange
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        case .graphite: return .systemGray
        case .multicolor: return .controlAccentColor
        }
    }
}

// MARK: - Theme Settings

/// Complete theme settings
public struct ThemeSettings: Sendable {
    public var mode: ThemeMode
    public var accentColor: AccentColor
    public var highlightColor: AccentColor
    public var reduceTransparency: Bool
    public var increaseContrast: Bool
    
    public static let `default` = ThemeSettings(
        mode: .auto,
        accentColor: .multicolor,
        highlightColor: .multicolor,
        reduceTransparency: false,
        increaseContrast: false
    )
    
    public init(
        mode: ThemeMode = .auto,
        accentColor: AccentColor = .multicolor,
        highlightColor: AccentColor = .multicolor,
        reduceTransparency: Bool = false,
        increaseContrast: Bool = false
    ) {
        self.mode = mode
        self.accentColor = accentColor
        self.highlightColor = highlightColor
        self.reduceTransparency = reduceTransparency
        self.increaseContrast = increaseContrast
    }
}

// MARK: - Theme Engine

/// Manages system-wide color schemes and appearance
///
/// Features:
/// - Dark/Light mode switching
/// - Accent color management
/// - Enhanced dark mode
/// - Theme presets
public final class ThemeEngine: @unchecked Sendable {
    
    // MARK: - Singleton
    
    public static let shared = ThemeEngine()
    
    // MARK: - Properties
    
    /// Current theme settings
    public private(set) var currentSettings = ThemeSettings.default
    
    /// Appearance observer
    private var appearanceObserver: NSKeyValueObservation?
    
    /// Change handlers
    private var changeHandlers: [(ThemeSettings) -> Void] = []
    private let handlersLock = NSLock()
    
    // MARK: - Initialization
    
    private init() {
        Task { @MainActor in
            self.observeAppearanceChanges()
        }
    }
    
    // MARK: - Public Methods
    
    /// Get current system appearance
    @MainActor
    public func getCurrentMode() -> ThemeMode {
        if #available(macOS 12.0, *) {
            let appearance = NSApp.effectiveAppearance.name
            
            if appearance == .darkAqua || appearance == .vibrantDark {
                return .dark
            } else {
                return .light
            }
        }
        
        return .light
    }
    
    /// Set theme mode
    public func setMode(_ mode: ThemeMode) {
        currentSettings.mode = mode
        
        switch mode {
        case .light:
            setDarkMode(false)
        case .dark:
            setDarkMode(true)
        case .auto:
            enableAutoMode()
        }
        
        notifyChangeHandlers()
        log.info("Theme mode set to: \(mode.rawValue)")
    }
    
    /// Set accent color
    public func setAccentColor(_ color: AccentColor) {
        currentSettings.accentColor = color
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["write", "-g", "AppleAccentColor", "-int", String(color.rawValue)]
        
        do {
            try process.run()
            process.waitUntilExit()
            
            notifyChangeHandlers()
            log.info("Accent color set to: \(color.displayName)")
        } catch {
            log.error("Failed to set accent color: \(error)")
        }
    }
    
    /// Set highlight color
    public func setHighlightColor(_ color: AccentColor) {
        currentSettings.highlightColor = color
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["write", "-g", "AppleHighlightColor", "-string", highlightColorString(color)]
        
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            log.error("Failed to set highlight color: \(error)")
        }
    }
    
    /// Toggle reduce transparency
    public func setReduceTransparency(_ enabled: Bool) {
        currentSettings.reduceTransparency = enabled
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["write", "com.apple.universalaccess", "reduceTransparency", "-bool", enabled ? "true" : "false"]
        
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            log.error("Failed to set reduce transparency: \(error)")
        }
    }
    
    /// Apply complete theme settings
    public func applySettings(_ settings: ThemeSettings) {
        currentSettings = settings
        
        setMode(settings.mode)
        setAccentColor(settings.accentColor)
        setHighlightColor(settings.highlightColor)
        setReduceTransparency(settings.reduceTransparency)
        
        // Increase contrast requires Accessibility API
        if settings.increaseContrast {
            enableIncreaseContrast()
        }
        
        notifyChangeHandlers()
    }
    
    /// Add handler for theme changes
    public func onThemeChange(_ handler: @escaping (ThemeSettings) -> Void) {
        handlersLock.lock()
        changeHandlers.append(handler)
        handlersLock.unlock()
    }
    
    /// Get preset themes
    public func getPresets() -> [String: ThemeSettings] {
        return [
            "default": .default,
            "dark_blue": ThemeSettings(mode: .dark, accentColor: .blue),
            "dark_purple": ThemeSettings(mode: .dark, accentColor: .purple),
            "light_orange": ThemeSettings(mode: .light, accentColor: .orange),
            "minimal": ThemeSettings(mode: .dark, accentColor: .graphite, reduceTransparency: true)
        ]
    }
    
    // MARK: - Private Methods
    
    private func setDarkMode(_ enabled: Bool) {
        // Use AppleScript as it's the most reliable method
        let script = """
        tell application "System Events"
            tell appearance preferences
                set dark mode to \(enabled ? "true" : "false")
            end tell
        end tell
        """
        
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            scriptObject.executeAndReturnError(&error)
            
            if let error = error {
                log.warning("AppleScript error: \(error)")
            }
        }
    }
    
    private func enableAutoMode() {
        // Remove the manual dark mode setting to let system decide
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["delete", "-g", "AppleInterfaceStyle"]
        
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // Ignore - key might not exist
        }
    }
    
    private func enableIncreaseContrast() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["write", "com.apple.universalaccess", "increaseContrast", "-bool", "true"]
        
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            log.error("Failed to enable increase contrast: \(error)")
        }
    }
    
    private func highlightColorString(_ color: AccentColor) -> String {
        // Format: "R G B" normalized values
        let nsColor = color.nsColor.usingColorSpace(.deviceRGB) ?? color.nsColor
        return "\(nsColor.redComponent) \(nsColor.greenComponent) \(nsColor.blueComponent)"
    }
    
    @MainActor
    private func observeAppearanceChanges() {
        if #available(macOS 12.0, *) {
            appearanceObserver = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
                self?.notifyChangeHandlers()
            }
        }
    }
    
    private func notifyChangeHandlers() {
        handlersLock.lock()
        let handlers = changeHandlers
        handlersLock.unlock()
        
        for handler in handlers {
            handler(currentSettings)
        }
    }
}
