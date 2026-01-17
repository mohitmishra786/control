// Control - macOS Power User Interaction Manager
// Window Manager
//
// Core window management functionality using macOS Accessibility API.
// Provides window enumeration, manipulation, and layout management.

import AppKit
import Foundation

// MARK: - Window Model

/// Represents a window with its properties
public struct Window: Identifiable, Equatable {
    public let id: CGWindowID
    public let title: String
    public let bundleIdentifier: String
    public let ownerName: String
    public let frame: CGRect
    public let isMinimized: Bool
    public let isFullscreen: Bool
    public let axElement: AXUIElement?
    
    public init(
        id: CGWindowID,
        title: String,
        bundleIdentifier: String,
        ownerName: String,
        frame: CGRect,
        isMinimized: Bool = false,
        isFullscreen: Bool = false,
        axElement: AXUIElement? = nil
    ) {
        self.id = id
        self.title = title
        self.bundleIdentifier = bundleIdentifier
        self.ownerName = ownerName
        self.frame = frame
        self.isMinimized = isMinimized
        self.isFullscreen = isFullscreen
        self.axElement = axElement
    }
    
    public static func == (lhs: Window, rhs: Window) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Window Zone

/// Represents a zone for window tiling
public struct Zone: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let xRatio: CGFloat
    public let yRatio: CGFloat
    public let widthRatio: CGFloat
    public let heightRatio: CGFloat
    
    public init(
        id: String,
        name: String,
        xRatio: CGFloat,
        yRatio: CGFloat,
        widthRatio: CGFloat,
        heightRatio: CGFloat
    ) {
        self.id = id
        self.name = name
        self.xRatio = xRatio
        self.yRatio = yRatio
        self.widthRatio = widthRatio
        self.heightRatio = heightRatio
    }
    
    /// Calculate absolute frame from zone ratios and screen bounds
    public func frame(for screen: NSScreen) -> CGRect {
        let visibleFrame = screen.visibleFrame
        return CGRect(
            x: visibleFrame.origin.x + visibleFrame.width * xRatio,
            y: visibleFrame.origin.y + visibleFrame.height * yRatio,
            width: visibleFrame.width * widthRatio,
            height: visibleFrame.height * heightRatio
        )
    }
}

// MARK: - Window Error

/// Errors that can occur during window operations
public enum WindowError: Error, LocalizedError {
    case accessibilityPermissionDenied
    case windowNotFound(id: CGWindowID)
    case invalidGeometry(reason: String)
    case axElementError(code: AXError)
    case operationFailed(reason: String)
    
    public var errorDescription: String? {
        switch self {
        case .accessibilityPermissionDenied:
            return "Accessibility permission is required. Grant permission in System Settings > Privacy & Security > Accessibility"
        case .windowNotFound(let id):
            return "Window with ID \(id) not found"
        case .invalidGeometry(let reason):
            return "Invalid window geometry: \(reason)"
        case .axElementError(let code):
            return "Accessibility API error: \(code.rawValue)"
        case .operationFailed(let reason):
            return "Window operation failed: \(reason)"
        }
    }
}

// MARK: - Window Manager

/// Manages window operations using macOS Accessibility API
///
/// WindowManager provides high-level window manipulation operations
/// built on top of the Accessibility API (AXUIElement).
///
/// - Important: Requires Accessibility permission to function.
/// - Note: Window geometries are cached for performance.
public final class WindowManager: @unchecked Sendable {
    
    // MARK: - Singleton
    
    public static let shared = WindowManager()
    
    // MARK: - Properties
    
    /// Cache for window geometries (window ID -> frame)
    /// TTL: 100ms for performance
    private var geometryCache: [CGWindowID: (frame: CGRect, timestamp: Date)] = [:]
    private let cacheTTL: TimeInterval = 0.1  // 100ms
    
    /// Lock for thread-safe cache access
    private let cacheLock = NSLock()
    
    /// Predefined zones for window tiling
    public let defaultZones: [Zone] = [
        Zone(id: "left_half", name: "Left Half", xRatio: 0, yRatio: 0, widthRatio: 0.5, heightRatio: 1),
        Zone(id: "right_half", name: "Right Half", xRatio: 0.5, yRatio: 0, widthRatio: 0.5, heightRatio: 1),
        Zone(id: "top_half", name: "Top Half", xRatio: 0, yRatio: 0.5, widthRatio: 1, heightRatio: 0.5),
        Zone(id: "bottom_half", name: "Bottom Half", xRatio: 0, yRatio: 0, widthRatio: 1, heightRatio: 0.5),
        Zone(id: "top_left", name: "Top Left Quarter", xRatio: 0, yRatio: 0.5, widthRatio: 0.5, heightRatio: 0.5),
        Zone(id: "top_right", name: "Top Right Quarter", xRatio: 0.5, yRatio: 0.5, widthRatio: 0.5, heightRatio: 0.5),
        Zone(id: "bottom_left", name: "Bottom Left Quarter", xRatio: 0, yRatio: 0, widthRatio: 0.5, heightRatio: 0.5),
        Zone(id: "bottom_right", name: "Bottom Right Quarter", xRatio: 0.5, yRatio: 0, widthRatio: 0.5, heightRatio: 0.5),
        Zone(id: "left_third", name: "Left Third", xRatio: 0, yRatio: 0, widthRatio: 0.333, heightRatio: 1),
        Zone(id: "center_third", name: "Center Third", xRatio: 0.333, yRatio: 0, widthRatio: 0.334, heightRatio: 1),
        Zone(id: "right_third", name: "Right Third", xRatio: 0.667, yRatio: 0, widthRatio: 0.333, heightRatio: 1),
        Zone(id: "maximize", name: "Maximize", xRatio: 0, yRatio: 0, widthRatio: 1, heightRatio: 1)
    ]
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Permission Check
    
    /// Check if accessibility permission is granted
    /// - Returns: true if accessibility is enabled
    public func hasAccessibilityPermission() -> Bool {
        return AXIsProcessTrusted()
    }
    
    /// Request accessibility permission by showing system prompt
    @MainActor
    public func requestAccessibilityPermission() {
        // Use the known string value directly to avoid Swift 6 concurrency issues with global vars
        let options: NSDictionary = ["AXTrustedCheckOptionPrompt": true]
        AXIsProcessTrustedWithOptions(options)
    }
    
    // MARK: - Window Enumeration
    
    /// Get all windows using CGWindowListCopyWindowInfo
    /// - Parameter onScreen: If true, only return on-screen windows
    /// - Returns: Array of Window objects
    public func getAllWindows(onScreen: Bool = true) -> [Window] {
        let options: CGWindowListOption = onScreen 
            ? [.optionOnScreenOnly, .excludeDesktopElements]
            : [.excludeDesktopElements]
        
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        
        return windowList.compactMap { windowInfo -> Window? in
            guard let windowId = windowInfo[kCGWindowNumber as String] as? CGWindowID,
                  let ownerName = windowInfo[kCGWindowOwnerName as String] as? String,
                  let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: Any],
                  let x = boundsDict["X"] as? CGFloat,
                  let y = boundsDict["Y"] as? CGFloat,
                  let width = boundsDict["Width"] as? CGFloat,
                  let height = boundsDict["Height"] as? CGFloat,
                  let layer = windowInfo[kCGWindowLayer as String] as? Int,
                  layer == 0  // Normal window layer
            else {
                return nil
            }
            
            let title = windowInfo[kCGWindowName as String] as? String ?? ""
            let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? Int32 ?? 0
            
            // Get bundle identifier from PID
            let bundleId = getBundleIdentifier(fromPID: ownerPID) ?? ""
            
            let frame = CGRect(x: x, y: y, width: width, height: height)
            
            return Window(
                id: windowId,
                title: title,
                bundleIdentifier: bundleId,
                ownerName: ownerName,
                frame: frame
            )
        }
    }
    
    /// Get the currently focused window
    /// - Returns: The focused Window, or nil if none
    /// - Throws: WindowError if accessibility permission denied
    public func getFocusedWindow() throws -> Window? {
        guard hasAccessibilityPermission() else {
            throw WindowError.accessibilityPermissionDenied
        }
        
        // Get the system-wide accessibility element
        let systemWide = AXUIElementCreateSystemWide()
        
        // Get the focused application
        var focusedApp: AnyObject?
        let appResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedApp
        )
        
        guard appResult == .success, let app = focusedApp else {
            return nil
        }
        
        // Get the focused window of the application
        var focusedWindow: AnyObject?
        let windowResult = AXUIElementCopyAttributeValue(
            app as! AXUIElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        )
        
        guard windowResult == .success, let windowElement = focusedWindow else {
            return nil
        }
        
        return try createWindow(from: windowElement as! AXUIElement)
    }
    
    // MARK: - Window Manipulation
    
    /// Move a window to a specific position
    /// - Parameters:
    ///   - window: The window to move
    ///   - position: Target position
    /// - Throws: WindowError if operation fails
    public func move(window: Window, to position: CGPoint) throws {
        guard hasAccessibilityPermission() else {
            throw WindowError.accessibilityPermissionDenied
        }
        
        guard let axElement = window.axElement ?? getAXElement(for: window) else {
            throw WindowError.windowNotFound(id: window.id)
        }
        
        var point = position
        let value = AXValueCreate(.cgPoint, &point)!
        
        let result = AXUIElementSetAttributeValue(
            axElement,
            kAXPositionAttribute as CFString,
            value
        )
        
        if result != .success {
            throw WindowError.axElementError(code: result)
        }
        
        // Invalidate cache
        invalidateCache(for: window.id)
    }
    
    /// Resize a window to specific dimensions
    /// - Parameters:
    ///   - window: The window to resize
    ///   - size: Target size
    /// - Throws: WindowError if operation fails
    public func resize(window: Window, to size: CGSize) throws {
        guard hasAccessibilityPermission() else {
            throw WindowError.accessibilityPermissionDenied
        }
        
        guard let axElement = window.axElement ?? getAXElement(for: window) else {
            throw WindowError.windowNotFound(id: window.id)
        }
        
        var sizeValue = size
        let value = AXValueCreate(.cgSize, &sizeValue)!
        
        let result = AXUIElementSetAttributeValue(
            axElement,
            kAXSizeAttribute as CFString,
            value
        )
        
        if result != .success {
            throw WindowError.axElementError(code: result)
        }
        
        // Invalidate cache
        invalidateCache(for: window.id)
    }
    
    /// Snap a window to a zone
    /// - Parameters:
    ///   - window: The window to snap
    ///   - zone: Target zone
    ///   - screen: Target screen (defaults to main screen)
    /// - Throws: WindowError if operation fails
    public func snap(window: Window, to zone: Zone, on screen: NSScreen? = nil) throws {
        let targetScreen = screen ?? NSScreen.main ?? NSScreen.screens.first!
        let targetFrame = zone.frame(for: targetScreen)
        
        // Move and resize in sequence
        try move(window: window, to: targetFrame.origin)
        try resize(window: window, to: targetFrame.size)
    }
    
    // MARK: - Private Helpers
    
    /// Get bundle identifier from process ID
    private func getBundleIdentifier(fromPID pid: Int32) -> String? {
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            return nil
        }
        return app.bundleIdentifier
    }
    
    /// Get AXUIElement for a window (requires accessibility permission)
    private func getAXElement(for window: Window) -> AXUIElement? {
        // Get PID from bundle identifier
        let apps = NSRunningApplication.runningApplications(
            withBundleIdentifier: window.bundleIdentifier
        )
        
        guard let app = apps.first else {
            return nil
        }
        
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        
        // Get all windows of the application
        var windowsValue: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsValue
        )
        
        guard result == .success, let windows = windowsValue as? [AXUIElement] else {
            return nil
        }
        
        // Find window matching title
        for windowElement in windows {
            var titleValue: AnyObject?
            AXUIElementCopyAttributeValue(
                windowElement,
                kAXTitleAttribute as CFString,
                &titleValue
            )
            
            if let title = titleValue as? String, title == window.title {
                return windowElement
            }
        }
        
        // If no title match, return first window
        return windows.first
    }
    
    /// Create Window object from AXUIElement
    private func createWindow(from element: AXUIElement) throws -> Window {
        // Get window title
        var titleValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue)
        let title = titleValue as? String ?? ""
        
        // Get position
        var positionValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue)
        var position = CGPoint.zero
        if let value = positionValue {
            AXValueGetValue(value as! AXValue, .cgPoint, &position)
        }
        
        // Get size
        var sizeValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)
        var size = CGSize.zero
        if let value = sizeValue {
            AXValueGetValue(value as! AXValue, .cgSize, &size)
        }
        
        // Get PID
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        
        let bundleId = getBundleIdentifier(fromPID: pid) ?? ""
        let app = NSRunningApplication(processIdentifier: pid)
        let ownerName = app?.localizedName ?? ""
        
        let frame = CGRect(origin: position, size: size)
        
        return Window(
            id: 0,  // Window ID not directly available from AXUIElement
            title: title,
            bundleIdentifier: bundleId,
            ownerName: ownerName,
            frame: frame,
            axElement: element
        )
    }
    
    /// Get cached geometry or fetch fresh
    private func getCachedGeometry(for windowId: CGWindowID) -> CGRect? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        
        guard let cached = geometryCache[windowId] else {
            return nil
        }
        
        // Check TTL
        if Date().timeIntervalSince(cached.timestamp) > cacheTTL {
            geometryCache.removeValue(forKey: windowId)
            return nil
        }
        
        return cached.frame
    }
    
    /// Invalidate cache for a specific window
    private func invalidateCache(for windowId: CGWindowID) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        geometryCache.removeValue(forKey: windowId)
    }
    
    /// Clear entire geometry cache
    public func clearCache() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        geometryCache.removeAll()
    }
}
