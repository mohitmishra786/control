// Control - macOS Power User Interaction Manager
// ControlKit - Reusable Framework
//
// This framework contains shared components and exportable APIs
// for the Control application.

import Foundation

/// ControlKit version information
public struct ControlKit {
    /// Current version
    public static let version = "0.1.0"
    
    /// Build info
    public static let buildInfo = BuildInfo()
    
    public struct BuildInfo: Sendable {
        public let platform: String
        public let architecture: String
        
        public init() {
            #if os(macOS)
            self.platform = "macOS"
            #else
            self.platform = "Unknown"
            #endif
            
            #if arch(arm64)
            self.architecture = "arm64"
            #elseif arch(x86_64)
            self.architecture = "x86_64"
            #else
            self.architecture = "unknown"
            #endif
        }
    }
}
