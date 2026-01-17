// Control - macOS Power User Interaction Manager
// Status CLI Command
//
// Displays overall system and Control status.

import ArgumentParser
import Foundation

/// Status command - default when no subcommand specified
struct StatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "System and permission status overview"
    )
    
    @Flag(name: .shortAndLong, help: "Show detailed status")
    var verbose: Bool = false
    
    @Flag(name: .long, help: "Output in JSON format")
    var json: Bool = false
    
    func run() throws {
        if json {
            printJSONStatus()
        } else {
            printStatus()
        }
    }
    
    private func printStatus() {
        print("""
        Control v0.1.0 - macOS Power User Interaction Manager
        =====================================================
        
        System Information:
          macOS Version: \(ProcessInfo.processInfo.operatingSystemVersionString)
          Architecture: \(getArchitecture())
          SIP Status: checking...
        
        Control Status:
          Daemon: checking...
          Config: ~/.config/control/control.toml
        
        Permissions:
          Accessibility: checking...
          Screen Recording: checking...
          Input Monitoring: checking...
        
        Modules:
          Window Management: enabled
          Input Control: enabled
          Permission Manager: enabled (SIP-safe)
          UI Consistency: enabled
        
        Run 'control --help' for available commands.
        """)
        
        if verbose {
            print("\nDetailed Module Status:")
            print("  Window > Corner Fix: enabled")
            print("  Window > Tiling: enabled")
            print("  Input > Acceleration: disabled (raw input)")
            print("  Input > Scroll Direction: per-device")
        }
    }
    
    private func printJSONStatus() {
        // TODO: Output proper JSON via Codable
        print("""
        {
            "version": "0.1.0",
            "daemon_running": false,
            "permissions": {
                "accessibility": "unknown",
                "screen_recording": "unknown",
                "input_monitoring": "unknown"
            }
        }
        """)
    }
    
    private func getArchitecture() -> String {
        #if arch(arm64)
        return "arm64 (Apple Silicon)"
        #elseif arch(x86_64)
        return "x86_64 (Intel)"
        #else
        return "unknown"
        #endif
    }
}
