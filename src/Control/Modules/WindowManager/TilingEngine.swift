// Control - macOS Power User Interaction Manager
// Tiling Engine
//
// Keyboard-driven tiling layouts for window management.
// Skill Reference: window-mason
// - Action: Use AXUIElement actions for movement
// - Target: 1px precision for resizing

import AppKit
import Foundation

// MARK: - Layout Type

/// Predefined layout types
public enum LayoutType: String, CaseIterable, Sendable {
    case leftHalf = "left_half"
    case rightHalf = "right_half"
    case topHalf = "top_half"
    case bottomHalf = "bottom_half"
    case leftThird = "left_third"
    case centerThird = "center_third"
    case rightThird = "right_third"
    case leftTwoThirds = "left_two_thirds"
    case rightTwoThirds = "right_two_thirds"
    case topLeft = "top_left"
    case topRight = "top_right"
    case bottomLeft = "bottom_left"
    case bottomRight = "bottom_right"
    case maximized = "maximized"
    case centered = "centered"
    
    public var displayName: String {
        switch self {
        case .leftHalf: return "Left Half"
        case .rightHalf: return "Right Half"
        case .topHalf: return "Top Half"
        case .bottomHalf: return "Bottom Half"
        case .leftThird: return "Left Third"
        case .centerThird: return "Center Third"
        case .rightThird: return "Right Third"
        case .leftTwoThirds: return "Left Two Thirds"
        case .rightTwoThirds: return "Right Two Thirds"
        case .topLeft: return "Top Left Quarter"
        case .topRight: return "Top Right Quarter"
        case .bottomLeft: return "Bottom Left Quarter"
        case .bottomRight: return "Bottom Right Quarter"
        case .maximized: return "Maximized"
        case .centered: return "Centered"
        }
    }
    
    /// Calculate frame for this layout type
    public func calculateFrame(in screenFrame: CGRect) -> CGRect {
        let x = screenFrame.origin.x
        let y = screenFrame.origin.y
        let w = screenFrame.width
        let h = screenFrame.height
        
        switch self {
        case .leftHalf:
            return CGRect(x: x, y: y, width: w / 2, height: h)
        case .rightHalf:
            return CGRect(x: x + w / 2, y: y, width: w / 2, height: h)
        case .topHalf:
            return CGRect(x: x, y: y, width: w, height: h / 2)
        case .bottomHalf:
            return CGRect(x: x, y: y + h / 2, width: w, height: h / 2)
        case .leftThird:
            return CGRect(x: x, y: y, width: w / 3, height: h)
        case .centerThird:
            return CGRect(x: x + w / 3, y: y, width: w / 3, height: h)
        case .rightThird:
            return CGRect(x: x + 2 * w / 3, y: y, width: w / 3, height: h)
        case .leftTwoThirds:
            return CGRect(x: x, y: y, width: 2 * w / 3, height: h)
        case .rightTwoThirds:
            return CGRect(x: x + w / 3, y: y, width: 2 * w / 3, height: h)
        case .topLeft:
            return CGRect(x: x, y: y, width: w / 2, height: h / 2)
        case .topRight:
            return CGRect(x: x + w / 2, y: y, width: w / 2, height: h / 2)
        case .bottomLeft:
            return CGRect(x: x, y: y + h / 2, width: w / 2, height: h / 2)
        case .bottomRight:
            return CGRect(x: x + w / 2, y: y + h / 2, width: w / 2, height: h / 2)
        case .maximized:
            return screenFrame
        case .centered:
            let centeredWidth = w * 0.7
            let centeredHeight = h * 0.7
            return CGRect(
                x: x + (w - centeredWidth) / 2,
                y: y + (h - centeredHeight) / 2,
                width: centeredWidth,
                height: centeredHeight
            )
        }
    }
}

// MARK: - Tiling Engine

/// Keyboard-driven tiling engine for window management
///
/// Provides:
/// - Predefined layouts (halves, thirds, quarters)
/// - Custom zone support
/// - Multi-display awareness
/// - 1px precision positioning
public final class TilingEngine: @unchecked Sendable {
    
    // MARK: - Singleton
    
    public static let shared = TilingEngine()
    
    // MARK: - Properties
    
    /// Custom zones by name
    private var customZones: [String: CGRect] = [:]
    private let zonesLock = NSLock()
    
    /// Gap/margin between windows (pixels)
    public var windowGap: CGFloat = 0
    
    /// Reference to WindowManager
    private var windowManager: WindowManager?
    
    // MARK: - Initialization
    
    private init() {
        windowManager = WindowManager.shared
    }
    
    // MARK: - Public Methods
    
    /// Tile the frontmost window to a layout
    @MainActor
    public func tileToLayout(_ layout: LayoutType) -> Bool {
        guard let manager = windowManager else {
            log.error("WindowManager not available")
            return false
        }
        
        // Get frontmost window
        guard let window = manager.getFrontmostWindow() else {
            log.warning("No frontmost window found")
            return false
        }
        
        // Get screen frame (visible area)
        guard let screen = NSScreen.main else {
            log.warning("No main screen found")
            return false
        }
        
        let visibleFrame = screen.visibleFrame
        
        // Calculate target frame
        var targetFrame = layout.calculateFrame(in: visibleFrame)
        
        // Apply window gap if set
        if windowGap > 0 {
            targetFrame = targetFrame.insetBy(dx: windowGap / 2, dy: windowGap / 2)
        }
        
        // Move window to target frame with 1px precision
        let success = manager.moveWindow(window: window, to: targetFrame)
        
        if success {
            log.info("Tiled window to \(layout.displayName)", metadata: [
                "frame": "\(targetFrame)"
            ])
        }
        
        return success
    }
    
    /// Tile window to a custom zone by name
    @MainActor
    public func tileToZone(_ zoneName: String) -> Bool {
        guard let zone = getCustomZone(zoneName) else {
            log.warning("Zone not found: \(zoneName)")
            return false
        }
        
        guard let manager = windowManager,
              let window = manager.getFrontmostWindow() else {
            return false
        }
        
        // Get screen frame
        guard let screen = NSScreen.main else { return false }
        
        // Convert zone (0-1 normalized) to screen coordinates
        let screenFrame = screen.visibleFrame
        let targetFrame = CGRect(
            x: screenFrame.origin.x + zone.origin.x * screenFrame.width,
            y: screenFrame.origin.y + zone.origin.y * screenFrame.height,
            width: zone.width * screenFrame.width,
            height: zone.height * screenFrame.height
        )
        
        return manager.moveWindow(window: window, to: targetFrame)
    }
    
    /// Add a custom zone (normalized 0-1 coordinates)
    public func addCustomZone(name: String, rect: CGRect) {
        zonesLock.lock()
        defer { zonesLock.unlock() }
        
        customZones[name] = rect
        log.info("Added custom zone: \(name)")
    }
    
    /// Remove a custom zone
    public func removeCustomZone(name: String) {
        zonesLock.lock()
        defer { zonesLock.unlock() }
        
        customZones.removeValue(forKey: name)
    }
    
    /// Get a custom zone
    public func getCustomZone(_ name: String) -> CGRect? {
        zonesLock.lock()
        defer { zonesLock.unlock() }
        
        return customZones[name]
    }
    
    /// Get all custom zones
    public func getAllCustomZones() -> [String: CGRect] {
        zonesLock.lock()
        defer { zonesLock.unlock() }
        
        return customZones
    }
    
    /// Cycle through halves (left -> right -> left)
    @MainActor
    public func cycleHalves() -> Bool {
        guard let manager = windowManager,
              let window = manager.getFrontmostWindow(),
              let screen = NSScreen.main else {
            return false
        }
        
        let currentFrame = window.frame
        let screenFrame = screen.visibleFrame
        let leftHalf = LayoutType.leftHalf.calculateFrame(in: screenFrame)
        
        // Check if currently in left half (with some tolerance)
        let isInLeftHalf = abs(currentFrame.origin.x - leftHalf.origin.x) < 10 &&
                          abs(currentFrame.width - leftHalf.width) < 10
        
        // Toggle to opposite half
        let targetLayout: LayoutType = isInLeftHalf ? .rightHalf : .leftHalf
        return tileToLayout(targetLayout)
    }
    
    /// Cycle through thirds (left -> center -> right -> left)
    @MainActor
    public func cycleThirds() -> Bool {
        guard let manager = windowManager,
              let window = manager.getFrontmostWindow(),
              let screen = NSScreen.main else {
            return false
        }
        
        let currentFrame = window.frame
        let screenFrame = screen.visibleFrame
        
        // Determine current position
        let thirdWidth = screenFrame.width / 3
        let relativeX = currentFrame.origin.x - screenFrame.origin.x
        
        let targetLayout: LayoutType
        if relativeX < thirdWidth * 0.5 {
            targetLayout = .centerThird
        } else if relativeX < thirdWidth * 1.5 {
            targetLayout = .rightThird
        } else {
            targetLayout = .leftThird
        }
        
        return tileToLayout(targetLayout)
    }
    
    /// Apply layout to specific window
    public func applyLayout(_ layout: LayoutType, to windowElement: AXUIElement, on screen: NSScreen) -> Bool {
        let targetFrame = layout.calculateFrame(in: screen.visibleFrame)
        return windowElement.setFrame(targetFrame)
    }
}
