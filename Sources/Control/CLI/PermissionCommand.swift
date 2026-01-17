// Control - macOS Power User Interaction Manager
// Permission Management CLI Command
//
// Handles permission status, automation, and trust list management.
// IMPORTANT: This module is SIP-safe and never writes directly to TCC.db

import ArgumentParser
import Foundation

/// Permission management command group
struct PermissionCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "permission",
        abstract: "Permission management and automation (SIP-safe)",
        discussion: """
            Provides SIP-compliant permission management:
              - View current permission status
              - Automate permission granting via UI automation
              - Manage trust lists for quick permission workflows
              - Fix screen recording reauthorization (Amnesia method)
            
            IMPORTANT: This module never writes directly to TCC.db.
            All automation uses approved Apple mechanisms.
            """,
        subcommands: [
            Status.self,
            Grant.self,
            TrustList.self,
            ScreenFix.self
        ],
        defaultSubcommand: Status.self
    )
}

// MARK: - Subcommands

extension PermissionCommand {
    /// Permission status overview
    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "View current permission status"
        )
        
        @Flag(name: .shortAndLong, help: "Show all permissions including denied")
        var all: Bool = false
        
        @Option(name: .shortAndLong, help: "Filter by app bundle ID")
        var app: String?
        
        func run() throws {
            print("Permission Status (SIP-safe read-only)")
            print("======================================")
            
            if let bundleId = app {
                print("Permissions for: \(bundleId)")
            } else {
                print("Control App Permissions:")
                print("  Accessibility: checking...")
                print("  Screen Recording: checking...")
                print("  Input Monitoring: checking...")
            }
            // TODO: Read TCC database (read-only) via PermissionManager
        }
    }
    
    /// Guide user through granting permissions
    struct Grant: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Guide permission granting (SIP-safe automation)"
        )
        
        @Argument(help: "Permission type (accessibility, screen_recording, input_monitoring)")
        var permission: String
        
        @Option(name: .shortAndLong, help: "Bundle ID of app to grant permission to")
        var app: String?
        
        @Flag(name: .long, help: "Use UI automation to click Allow button")
        var automate: Bool = false
        
        func run() throws {
            let targetApp = app ?? "com.control.Control"
            
            print("Granting \(permission) permission to \(targetApp)")
            print("Strategy: \(automate ? "UI Automation" : "Guided Setup")")
            
            if automate {
                print("Attempting UI automation (requires Accessibility permission)...")
                // TODO: Use TCCManager UI automation strategy
            } else {
                print("Opening System Settings to the correct pane...")
                // TODO: Use TCCManager guided setup strategy
            }
        }
    }
    
    /// Manage trust list
    struct TrustList: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Manage trusted application list"
        )
        
        @Flag(name: .shortAndLong, help: "List trusted applications")
        var list: Bool = false
        
        @Option(name: .long, help: "Add bundle ID to trust list")
        var add: String?
        
        @Option(name: .long, help: "Remove bundle ID from trust list")
        var remove: String?
        
        func run() throws {
            if list {
                print("Trusted Applications:")
                print("  com.jetbrains.* -> [accessibility, screen_recording]")
                print("  com.microsoft.VSCode -> [accessibility]")
                // TODO: List from config
                return
            }
            
            if let bundleId = add {
                print("Adding to trust list: \(bundleId)...")
                // TODO: Add to trust list
            } else if let bundleId = remove {
                print("Removing from trust list: \(bundleId)...")
                // TODO: Remove from trust list
            } else {
                print("Use --list, --add, or --remove")
            }
        }
    }
    
    /// Fix screen recording reauthorization (Amnesia method)
    struct ScreenFix: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Fix screen recording reauthorization (Amnesia method)"
        )
        
        @Flag(name: .long, help: "Apply fix to extend screen recording permissions")
        var apply: Bool = false
        
        @Flag(name: .long, help: "Check current status")
        var status: Bool = false
        
        @Flag(name: .long, help: "Create backup before applying fix")
        var backup: Bool = true
        
        func run() throws {
            if status {
                print("Screen Recording Reauth Fix Status:")
                print("  Checking replayd plist files...")
                // TODO: Check plist status
                return
            }
            
            if apply {
                if backup {
                    print("Creating backup of plist files...")
                    // TODO: Backup plists
                }
                
                print("Applying Amnesia method fix...")
                print("  Modifying: ~/Library/Preferences/ByHost/com.apple.replayd.*.plist")
                // TODO: Apply Amnesia method via TCCManager
            } else {
                print("Use --apply to fix or --status to check")
            }
        }
    }
}
