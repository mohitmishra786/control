// Control - macOS Power User Interaction Manager
// Accessibility API Helpers
//
// Common patterns and utilities for working with the Accessibility API.

import AppKit
import Foundation

// MARK: - Accessibility Permission

/// Accessibility permission utilities
public struct AccessibilityPermission {
    
    /// Check if accessibility permission is granted
    public static var isGranted: Bool {
        return AXIsProcessTrusted()
    }
    
    /// Request accessibility permission with system prompt
    @MainActor
    public static func request() {
        // Use string literal to avoid Swift 6 concurrency issues with global var
        let options: NSDictionary = ["AXTrustedCheckOptionPrompt": true]
        AXIsProcessTrustedWithOptions(options)
    }
    
    /// Open System Settings to Accessibility pane
    public static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}

// MARK: - AXUIElement Extensions

extension AXUIElement {
    
    /// Get attribute value with type casting
    public func attribute<T>(_ attribute: String) -> T? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(self, attribute as CFString, &value)
        
        guard result == .success else {
            return nil
        }
        
        return value as? T
    }
    
    /// Set attribute value
    @discardableResult
    public func setAttribute(_ attribute: String, value: Any) -> AXError {
        return AXUIElementSetAttributeValue(self, attribute as CFString, value as CFTypeRef)
    }
    
    /// Get CGPoint attribute (position)
    public var position: CGPoint? {
        guard let value: AXValue = attribute(kAXPositionAttribute) else {
            return nil
        }
        var point = CGPoint.zero
        AXValueGetValue(value, .cgPoint, &point)
        return point
    }
    
    /// Set CGPoint attribute (position)
    @discardableResult
    public func setPosition(_ point: CGPoint) -> AXError {
        var mutablePoint = point
        guard let value = AXValueCreate(.cgPoint, &mutablePoint) else {
            return .failure
        }
        return setAttribute(kAXPositionAttribute, value: value)
    }
    
    /// Get CGSize attribute (size)
    public var size: CGSize? {
        guard let value: AXValue = attribute(kAXSizeAttribute) else {
            return nil
        }
        var size = CGSize.zero
        AXValueGetValue(value, .cgSize, &size)
        return size
    }
    
    /// Set CGSize attribute (size)
    @discardableResult
    public func setSize(_ size: CGSize) -> AXError {
        var mutableSize = size
        guard let value = AXValueCreate(.cgSize, &mutableSize) else {
            return .failure
        }
        return setAttribute(kAXSizeAttribute, value: value)
    }
    
    /// Get frame (position + size)
    public var frame: CGRect? {
        guard let position = position, let size = size else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }
    
    /// Set frame (position + size)
    @discardableResult
    public func setFrame(_ frame: CGRect) -> Bool {
        let posResult = setPosition(frame.origin)
        let sizeResult = setSize(frame.size)
        return posResult == .success && sizeResult == .success
    }
    
    /// Get title
    public var title: String? {
        return attribute(kAXTitleAttribute)
    }
    
    /// Get role
    public var role: String? {
        return attribute(kAXRoleAttribute)
    }
    
    /// Get subrole
    public var subrole: String? {
        return attribute(kAXSubroleAttribute)
    }
    
    /// Get children elements
    public var children: [AXUIElement]? {
        return attribute(kAXChildrenAttribute)
    }
    
    /// Get parent element
    public var parent: AXUIElement? {
        return attribute(kAXParentAttribute)
    }
    
    /// Get windows (for application elements)
    public var windows: [AXUIElement]? {
        return attribute(kAXWindowsAttribute)
    }
    
    /// Get focused window (for application elements)
    public var focusedWindow: AXUIElement? {
        return attribute(kAXFocusedWindowAttribute)
    }
    
    /// Check if element is minimized
    public var isMinimized: Bool {
        return attribute(kAXMinimizedAttribute) ?? false
    }
    
    /// Check if element is fullscreen
    public var isFullscreen: Bool {
        return attribute("AXFullScreen") ?? false
    }
    
    /// Perform action on element
    @discardableResult
    public func performAction(_ action: String) -> AXError {
        return AXUIElementPerformAction(self, action as CFString)
    }
    
    /// Get process ID
    public var pid: pid_t? {
        var pid: pid_t = 0
        let result = AXUIElementGetPid(self, &pid)
        return result == .success ? pid : nil
    }
}

// MARK: - System-Wide Element

/// Get system-wide accessibility element
public func systemWideElement() -> AXUIElement {
    return AXUIElementCreateSystemWide()
}

/// Get focused application
public func focusedApplication() -> AXUIElement? {
    let systemWide = systemWideElement()
    return systemWide.attribute(kAXFocusedApplicationAttribute)
}

/// Get application element for PID
public func applicationElement(for pid: pid_t) -> AXUIElement {
    return AXUIElementCreateApplication(pid)
}

// MARK: - Window Utilities

/// Get all windows for an application
public func windows(for app: NSRunningApplication) -> [AXUIElement] {
    let appElement = applicationElement(for: app.processIdentifier)
    return appElement.windows ?? []
}

/// Find window by title
public func findWindow(title: String, in app: NSRunningApplication) -> AXUIElement? {
    let appWindows = windows(for: app)
    return appWindows.first { $0.title == title }
}

// MARK: - AXError Extension

extension AXError {
    
    /// Human-readable description
    public var description: String {
        switch self {
        case .success: return "Success"
        case .failure: return "Failure"
        case .illegalArgument: return "Illegal argument"
        case .invalidUIElement: return "Invalid UI element"
        case .invalidUIElementObserver: return "Invalid UI element observer"
        case .cannotComplete: return "Cannot complete"
        case .attributeUnsupported: return "Attribute unsupported"
        case .actionUnsupported: return "Action unsupported"
        case .notificationUnsupported: return "Notification unsupported"
        case .notImplemented: return "Not implemented"
        case .notificationAlreadyRegistered: return "Notification already registered"
        case .notificationNotRegistered: return "Notification not registered"
        case .apiDisabled: return "API disabled"
        case .noValue: return "No value"
        case .parameterizedAttributeUnsupported: return "Parameterized attribute unsupported"
        case .notEnoughPrecision: return "Not enough precision"
        @unknown default: return "Unknown error (\(self.rawValue))"
        }
    }
}
