// Control - macOS Power User Interaction Manager
// System Info
//
// macOS version, hardware info, and capability detection.

import AppKit
import Foundation
import IOKit

// MARK: - System Info

/// macOS system information
public final class SystemInfo: @unchecked Sendable {
    
    // MARK: - Singleton
    
    nonisolated public static let shared = SystemInfo()
    
    // MARK: - Properties
    
    /// macOS version
    public let osVersion: OperatingSystemVersion
    
    /// macOS version string
    public let osVersionString: String
    
    /// macOS code name
    public var osCodeName: String {
        switch osVersion.majorVersion {
        case 15: return "Tahoe"
        case 14: return "Sonoma"
        case 13: return "Ventura"
        case 12: return "Monterey"
        case 11: return "Big Sur"
        case 10:
            switch osVersion.minorVersion {
            case 15: return "Catalina"
            case 14: return "Mojave"
            default: return "macOS 10.\(osVersion.minorVersion)"
            }
        default: return "macOS \(osVersion.majorVersion)"
        }
    }
    
    /// Hardware model
    public let hardwareModel: String
    
    /// CPU architecture
    public let cpuArchitecture: String
    
    /// Is Apple Silicon
    public var isAppleSilicon: Bool {
        return cpuArchitecture == "arm64"
    }
    
    /// Total RAM in bytes
    public let totalMemory: UInt64
    
    /// Number of CPU cores
    public let cpuCoreCount: Int
    
    /// Display count
    public var displayCount: Int {
        return NSScreen.screens.count
    }
    
    /// Host name
    public let hostName: String
    
    /// Computer name
    public let computerName: String
    
    /// User name
    public let userName: String
    
    // MARK: - Initialization
    
    private init() {
        // OS Version
        osVersion = ProcessInfo.processInfo.operatingSystemVersion
        osVersionString = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"
        
        // Hardware model
        hardwareModel = SystemInfo.getHardwareModel()
        
        // CPU architecture
        #if arch(arm64)
        cpuArchitecture = "arm64"
        #else
        cpuArchitecture = "x86_64"
        #endif
        
        // Memory
        totalMemory = ProcessInfo.processInfo.physicalMemory
        
        // CPU cores
        cpuCoreCount = ProcessInfo.processInfo.processorCount
        
        // Names
        hostName = ProcessInfo.processInfo.hostName
        computerName = Host.current().localizedName ?? "Mac"
        userName = NSUserName()
    }
    
    // MARK: - Public Methods
    
    /// Check if running on macOS version or later
    public func isAtLeast(majorVersion major: Int, minorVersion minor: Int = 0) -> Bool {
        if osVersion.majorVersion > major { return true }
        if osVersion.majorVersion < major { return false }
        return osVersion.minorVersion >= minor
    }
    
    /// Get available disk space
    public func getAvailableDiskSpace() -> UInt64 {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(
            forPath: NSHomeDirectory()
        ) else {
            return 0
        }
        
        return attrs[.systemFreeSize] as? UInt64 ?? 0
    }
    
    /// Get screen info
    public func getScreenInfo() -> [(name: String, resolution: CGSize, isMain: Bool)] {
        return NSScreen.screens.map { screen in
            let isMain = screen == NSScreen.main
            return (
                name: screen.localizedName,
                resolution: screen.frame.size,
                isMain: isMain
            )
        }
    }
    
    /// Get serial number (requires admin privileges)
    public func getSerialNumber() -> String? {
        let platformExpert = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        
        guard platformExpert != 0 else { return nil }
        defer { IOObjectRelease(platformExpert) }
        
        guard let serialNumber = IORegistryEntryCreateCFProperty(
            platformExpert,
            kIOPlatformSerialNumberKey as CFString,
            kCFAllocatorDefault,
            0
        ) else { return nil }
        
        return serialNumber.takeUnretainedValue() as? String
    }
    
    /// Get boot time
    public func getBootTime() -> Date? {
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.size
        
        guard sysctl(&mib, 2, &bootTime, &size, nil, 0) == 0 else {
            return nil
        }
        
        return Date(timeIntervalSince1970: TimeInterval(bootTime.tv_sec))
    }
    
    /// Get uptime
    public func getUptime() -> TimeInterval {
        guard let bootTime = getBootTime() else {
            return 0
        }
        return Date().timeIntervalSince(bootTime)
    }
    
    /// Get formatted uptime string
    public func getUptimeString() -> String {
        let uptime = Int(getUptime())
        let days = uptime / 86400
        let hours = (uptime % 86400) / 3600
        let minutes = (uptime % 3600) / 60
        
        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    /// Get formatted memory string
    public func getTotalMemoryString() -> String {
        let gb = Double(totalMemory) / (1024 * 1024 * 1024)
        return String(format: "%.1f GB", gb)
    }
    
    /// Print system summary
    public func printSummary() {
        print("macOS \(osVersionString) (\(osCodeName))")
        print("Hardware: \(hardwareModel)")
        print("CPU: \(cpuArchitecture), \(cpuCoreCount) cores")
        print("Memory: \(getTotalMemoryString())")
        print("Displays: \(displayCount)")
        print("Uptime: \(getUptimeString())")
    }
    
    // MARK: - Private Methods
    
    private static func getHardwareModel() -> String {
        var size: Int = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        
        return String(cString: model)
    }
}

// MARK: - Capability Detection

extension SystemInfo {
    
    /// Check if Accessibility API is available
    public var hasAccessibilityAPI: Bool {
        return AXIsProcessTrusted()
    }
    
    /// Check if can create CGEvent taps
    public var canCreateEventTaps: Bool {
        return hasAccessibilityAPI
    }
    
    /// Check if running in sandbox
    public var isSandboxed: Bool {
        return ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }
    
    /// Check if SIP is enabled
    public var isSIPEnabled: Bool {
        return SIPDetector.shared.isEnabled
    }
}
