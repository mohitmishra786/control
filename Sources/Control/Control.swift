// Control - macOS Power User Interaction Manager
// Copyright (c) 2026. MIT License.
//
// Entry point for the Control CLI application.
// Routes commands to appropriate module handlers.

import Foundation
import ArgumentParser

/// Root command for the Control CLI
@main
struct Control: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "control",
        abstract: "Linux-like power for macOS - One binary to rule your Mac",
        discussion: """
            Control consolidates fragmented macOS interaction and workflow management
            tools into a single, efficient, open-source binary.
            
            Modules:
              - window:      Window management, tiling, and corner grab fixes
              - input:       Mouse acceleration, scroll direction, gestures
              - permission:  Permission management and automation (SIP-safe)
              - consistency: UI harmonization and icon normalization
              - daemon:      Background service management
              - config:      Configuration management
              - status:      System and permission status
            """,
        version: "0.1.0",
        subcommands: [
            WindowCommand.self,
            InputCommand.self,
            PermissionCommand.self,
            ConsistencyCommand.self,
            DaemonCommand.self,
            ConfigCommand.self,
            StatusCommand.self
        ],
        defaultSubcommand: StatusCommand.self
    )
}
