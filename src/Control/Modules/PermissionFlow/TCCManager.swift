// Control - macOS Power User Interaction Manager
// TCC Manager
//
// SIP-compliant permission automation strategies.
// Skill Reference: permission-manager
// - CRITICAL: Never write directly to TCC.db
// - Strategy 1: UI Automation (Accessibility API to click Allow buttons)
// - Strategy 2: Plist modification (Amnesia method for screen recording)
// - Strategy 3: Guided setup (open System Settings to correct pane)

import AppKit
import Foundation

// MARK: - Automation Strategy

/// Available SIP-compliant automation strategies
public enum AutomationStrategy: String, Sendable {
    case uiAutomation = "ui_automation"    // Click Allow buttons
    case plistModification = "plist"       // Amnesia method
    case guidedSetup = "guided"            // Open System Settings
}

// MARK: - Automation Result

/// Result of an automation attempt
public enum AutomationResult: Sendable {
    case success
    case needsAccessibilityPermission
    case dialogNotFound
    case timeout
    case failed(reason: String)
}

// MARK: - TCC Manager

/// SIP-compliant permission automation
///
/// CRITICAL: This manager NEVER writes to TCC.db directly.
/// Uses three SIP-safe strategies:
/// 1. UI Automation - Click Allow buttons using Accessibility API
/// 2. Plist Modification - Amnesia method for screen recording
/// 3. Guided Setup - Open System Settings to correct pane
public final class TCCManager: @unchecked Sendable {
    
    // MARK: - Singleton
    
    public static let shared = TCCManager()
    
    // MARK: - Properties
    
    /// Reference to permission manager
    private let permissionManager = PermissionManager.shared
    
    /// Dialog detection timeout (seconds)
    public var dialogTimeout: TimeInterval = 5.0
    
    /// Delay before clicking Allow (avoid false positives)
    public var clickDelay: TimeInterval = 0.5
    
    // MARK: - Screen Recording Plist Paths
    
    private var screenRecordingPlistPattern: String {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        return homeDir.appendingPathComponent(
            "Library/Preferences/ByHost/com.apple.replayd.*.plist"
        ).path
    }
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Automate permission granting using best available strategy
    @MainActor
    public func automatePermission(
        _ type: PermissionType,
        forApp bundleId: String
    ) async -> AutomationResult {
        
        // Check if we have accessibility permission (needed for UI automation)
        guard permissionManager.checkAccessibilityPermission() else {
            log.warning("Cannot use UI automation without Accessibility permission")
            
            // Fall back to guided setup
            return await guidedSetup(for: type)
        }
        
        // Try UI automation first
        let uiResult = await uiAutomation(for: type, app: bundleId)
        
        if case .success = uiResult {
            return uiResult
        }
        
        // For screen recording, try Amnesia method
        if type == .screenRecording {
            let plistResult = amnesiaMethod(forApp: bundleId)
            if case .success = plistResult {
                return plistResult
            }
        }
        
        // Fall back to guided setup
        return await guidedSetup(for: type)
    }
    
    /// Strategy 1: UI Automation
    @MainActor
    public func uiAutomation(
        for type: PermissionType,
        app bundleId: String
    ) async -> AutomationResult {
        
        log.info("Attempting UI automation for: \(type.displayName)", metadata: [
            "app": bundleId
        ])
        
        // Wait for permission dialog to appear
        let startTime = Date()
        
        while Date().timeIntervalSince(startTime) < dialogTimeout {
            if let dialog = findPermissionDialog(for: type) {
                // Wait before clicking
                try? await Task.sleep(nanoseconds: UInt64(clickDelay * 1_000_000_000))
                
                // Click Allow button
                if clickAllowButton(in: dialog) {
                    log.info("Successfully clicked Allow button")
                    return .success
                }
            }
            
            // Small delay before retry
            try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        }
        
        log.warning("Permission dialog not found within timeout")
        return .dialogNotFound
    }
    
    /// Strategy 2: Plist Modification (Amnesia Method)
    public func amnesiaMethod(forApp bundleId: String) -> AutomationResult {
        log.info("Attempting Amnesia method for screen recording", metadata: [
            "app": bundleId
        ])
        
        // Find screen recording plist files
        let plistFiles = findScreenRecordingPlists()
        
        guard !plistFiles.isEmpty else {
            log.warning("No screen recording plist files found")
            return .failed(reason: "No plist files found")
        }
        
        for plistPath in plistFiles {
            // Create backup before modification
            backupPlist(at: plistPath)
            
            // Modify the plist
            if modifyScreenRecordingPlist(at: plistPath, addApp: bundleId) {
                log.info("Modified screen recording plist", metadata: [
                    "path": plistPath
                ])
                return .success
            }
        }
        
        return .failed(reason: "Failed to modify plists")
    }
    
    /// Strategy 3: Guided Setup
    @MainActor
    public func guidedSetup(for type: PermissionType) async -> AutomationResult {
        log.info("Opening System Settings for guided setup: \(type.displayName)")
        
        permissionManager.openSystemSettings(for: type)
        
        // Show notification to user
        showGuidanceNotification(for: type)
        
        return .success
    }
    
    /// Request Control's own accessibility permission
    @MainActor
    public func requestAccessibilityForSelf() {
        log.info("Requesting Accessibility permission for Control")
        AccessibilityPermission.request()
    }
    
    // MARK: - Private Methods: UI Automation
    
    /// Find permission dialog in System UI
    private func findPermissionDialog(for type: PermissionType) -> AXUIElement? {
        // Look for dialogs from common system processes
        let systemUIProcesses = ["SecurityAgent", "UserNotificationCenter", "System Preferences"]
        
        for processName in systemUIProcesses {
            if let app = NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.apple.\(processName)"
            ).first {
                let appElement = applicationElement(for: app.processIdentifier)
                
                // Look for windows that might be permission dialogs
                if let windows = appElement.windows {
                    for window in windows {
                        if isPermissionDialog(window, type: type) {
                            return window
                        }
                    }
                }
            }
        }
        
        // Also check focused window
        if let focusedApp = focusedApplication(),
           let focusedWindow = focusedApp.focusedWindow,
           isPermissionDialog(focusedWindow, type: type) {
            return focusedWindow
        }
        
        return nil
    }
    
    /// Check if window is a permission dialog
    private func isPermissionDialog(_ window: AXUIElement, type: PermissionType) -> Bool {
        guard let title: String = window.attribute(kAXTitleAttribute) else {
            return false
        }
        
        let keywords = ["permission", "access", "allow", type.displayName.lowercased()]
        let lowercasedTitle = title.lowercased()
        
        return keywords.contains { lowercasedTitle.contains($0) }
    }
    
    /// Click Allow button in dialog
    private func clickAllowButton(in dialog: AXUIElement) -> Bool {
        guard let children = dialog.children else {
            return false
        }
        
        // Recursively search for Allow button
        return findAndClickButton(in: children, labels: ["Allow", "OK", "Grant"])
    }
    
    /// Find and click button with matching label
    private func findAndClickButton(in elements: [AXUIElement], labels: [String]) -> Bool {
        for element in elements {
            if let role: String = element.attribute(kAXRoleAttribute),
               role == kAXButtonRole {
                if let title: String = element.attribute(kAXTitleAttribute),
                   labels.contains(where: { title.contains($0) }) {
                    let result = element.performAction(kAXPressAction)
                    return result == .success
                }
            }
            
            // Recurse into children
            if let children = element.children {
                if findAndClickButton(in: children, labels: labels) {
                    return true
                }
            }
        }
        
        return false
    }
    
    // MARK: - Private Methods: Plist Modification
    
    /// Find screen recording plist files
    private func findScreenRecordingPlists() -> [String] {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let byHostPath = homeDir.appendingPathComponent("Library/Preferences/ByHost")
        
        do {
            let files = try FileManager.default.contentsOfDirectory(atPath: byHostPath.path)
            return files
                .filter { $0.hasPrefix("com.apple.replayd.") && $0.hasSuffix(".plist") }
                .map { byHostPath.appendingPathComponent($0).path }
        } catch {
            log.warning("Failed to list ByHost directory: \(error)")
            return []
        }
    }
    
    /// Backup plist before modification
    private func backupPlist(at path: String) {
        let backupPath = path + ".backup"
        try? FileManager.default.copyItem(atPath: path, toPath: backupPath)
    }
    
    /// Modify screen recording plist (Amnesia method)
    private func modifyScreenRecordingPlist(at path: String, addApp bundleId: String) -> Bool {
        guard var plist = NSDictionary(contentsOfFile: path) as? [String: Any] else {
            return false
        }
        
        // Get or create allowed processes array
        var allowedProcesses = plist["ReplayKitRemoteScreenAllowedProcesses"] as? [String] ?? []
        
        // Add app if not already present
        if !allowedProcesses.contains(bundleId) {
            allowedProcesses.append(bundleId)
        }
        
        plist["ReplayKitRemoteScreenAllowedProcesses"] = allowedProcesses
        
        // Set expiry date far in future (Amnesia method)
        // Year 3024 - 1000 years in the future
        let futureDate = Date().addingTimeInterval(1000 * 365 * 24 * 60 * 60)
        plist["LastUsedDate"] = futureDate
        
        // Write back
        let nsDict = plist as NSDictionary
        return nsDict.write(toFile: path, atomically: true)
    }
    
    // MARK: - Private Methods: Notifications
    
    /// Show guidance notification
    private func showGuidanceNotification(for type: PermissionType) {
        // Use user notification center
        let notification = NSUserNotification()
        notification.title = "Grant Permission Required"
        notification.informativeText = "Please grant \(type.displayName) permission in the opened System Settings window."
        notification.soundName = NSUserNotificationDefaultSoundName
        
        NSUserNotificationCenter.default.deliver(notification)
    }
}
