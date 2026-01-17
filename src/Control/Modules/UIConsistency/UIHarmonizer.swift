// Control - macOS Power User Interaction Manager
// UI Harmonizer
//
// Standardizes UI element sizes and positions across apps.

import AppKit
import Foundation

// MARK: - Button Style

/// Standard button styles
public enum ButtonStyle: String, Sendable {
    case trafficLight = "traffic_light"
    case toolbar = "toolbar"
    case custom = "custom"
}

// MARK: - Traffic Light Position

/// Traffic light button positioning modes
public enum TrafficLightPosition: String, Sendable {
    case systemDefault = "system_default"
    case centered = "centered"
    case compact = "compact"
    case hidden = "hidden"
}

// MARK: - UI Harmonizer

/// Standardizes UI elements across applications
///
/// Features:
/// - Traffic light button normalization
/// - Window controller behavior standardization
/// - Cross-app UI consistency
public final class UIHarmonizer: @unchecked Sendable {
    
    // MARK: - Singleton
    public static let shared = UIHarmonizer()
    
    // MARK: - Properties
    /// Traffic light position mode
    public var trafficLightPosition: TrafficLightPosition = .systemDefault
    
    /// Standard button spacing
    public var buttonSpacing: CGFloat = 6.0
    
    /// Standard button size
    public var buttonDiameter: CGFloat = 12.0
    
    /// Vertical offset from top of window
    public var verticalOffset: CGFloat = 16.0
    
    /// Horizontal offset from left edge
    public var horizontalOffset: CGFloat = 8.0
    
    /// Observer for window creation
    private var windowObserver: Any?
    public private(set) var isActive: Bool = false
    
    // MARK: - Initialization
    private init() {}
    
    // MARK: - Public Methods
    /// Start UI harmonization
    @MainActor
    public func start() {
        guard !isActive else { return }
        
        // Observe window creation
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            Task { @MainActor in
                self?.harmonizeWindow(window)
            }
        }
        
        // Harmonize existing windows
        for window in NSApplication.shared.windows {
            harmonizeWindow(window)
        }
        
        isActive = true
        log.info("UIHarmonizer started")
    }
    
    /// Stop UI harmonization
    @MainActor
    public func stop() {
        guard isActive else { return }
        
        if let observer = windowObserver {
            NotificationCenter.default.removeObserver(observer)
            windowObserver = nil
        }
        
        isActive = false
        log.info("UIHarmonizer stopped")
    }
    
    /// Harmonize a specific window
    @MainActor
    public func harmonizeWindow(_ window: NSWindow) {
        // Only process windows with standard controls
        guard window.styleMask.contains(.closable) else { return }
        
        switch trafficLightPosition {
        case .systemDefault:
            // Don't modify
            break
            
        case .centered:
            centerTrafficLights(in: window)
            
        case .compact:
            compactTrafficLights(in: window)
            
        case .hidden:
            hideTrafficLights(in: window)
        }
    }
    
    /// Normalize all traffic lights to standard position
    @MainActor
    public func normalizeTrafficLights(position: TrafficLightPosition) {
        trafficLightPosition = position
        
        for window in NSApplication.shared.windows {
            harmonizeWindow(window)
        }
        
        log.info("Traffic lights normalized to: \(position.rawValue)")
    }
    
    // MARK: - Private Methods
    
    /// Center traffic lights vertically in title bar
    @MainActor
    private func centerTrafficLights(in window: NSWindow) {
        guard let titleBarView = findTitleBarView(in: window) else { return }
        
        let buttons = [
            window.standardWindowButton(.closeButton),
            window.standardWindowButton(.miniaturizeButton),
            window.standardWindowButton(.zoomButton)
        ].compactMap { $0 }
        
        guard !buttons.isEmpty else { return }
        
        let titleBarHeight = titleBarView.frame.height
        let buttonY = (titleBarHeight - buttonDiameter) / 2
        
        var currentX = horizontalOffset
        
        for button in buttons {
            button.frame.origin = CGPoint(x: currentX, y: buttonY)
            currentX += buttonDiameter + buttonSpacing
        }
    }
    
    /// Compact traffic lights with minimal spacing
    @MainActor
    private func compactTrafficLights(in window: NSWindow) {
        let buttons = [
            window.standardWindowButton(.closeButton),
            window.standardWindowButton(.miniaturizeButton),
            window.standardWindowButton(.zoomButton)
        ].compactMap { $0 }
        
        var currentX = horizontalOffset
        let compactSpacing: CGFloat = 4.0
        
        for button in buttons {
            button.frame.origin.x = currentX
            currentX += buttonDiameter + compactSpacing
        }
    }
    
    /// Hide traffic light buttons
    @MainActor
    private func hideTrafficLights(in window: NSWindow) {
        let buttons = [
            window.standardWindowButton(.closeButton),
            window.standardWindowButton(.miniaturizeButton),
            window.standardWindowButton(.zoomButton)
        ].compactMap { $0 }
        
        for button in buttons {
            button.isHidden = true
        }
    }
    
    /// Find title bar view in window
    @MainActor
    private func findTitleBarView(in window: NSWindow) -> NSView? {
        guard let contentView = window.contentView,
              let superview = contentView.superview else {
            return nil
        }
        
        // The title bar is typically at the top of the window's theme frame
        for subview in superview.subviews {
            if String(describing: type(of: subview)).contains("TitleBar") {
                return subview
            }
        }
        
        return nil
    }
}
