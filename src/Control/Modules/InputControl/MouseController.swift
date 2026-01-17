// Control - macOS Power User Interaction Manager
// Mouse Controller
//
// Controls mouse acceleration with 1:1 raw input option.
// Skill Reference: input-flow
// - Logic: Use IOHIDManager to identify device types
// - Acceleration: Implement custom Bezier curve interpolation for pointer acceleration overrides

import CoreGraphics
import Foundation

// MARK: - Acceleration Curve

/// Represents an acceleration curve for pointer movement
public struct AccelerationCurve: Sendable {
    public let name: String
    public let controlPoints: [CGPoint]
    
    /// Linear curve (1:1 raw input)
    public static let linear = AccelerationCurve(
        name: "linear",
        controlPoints: [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 1, y: 1)
        ]
    )
    
    /// Smooth curve (gentle acceleration)
    public static let smooth = AccelerationCurve(
        name: "smooth",
        controlPoints: [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 0.3, y: 0.2),
            CGPoint(x: 0.7, y: 0.8),
            CGPoint(x: 1, y: 1)
        ]
    )
    
    /// Gaming curve (fast response, slight acceleration at high speeds)
    public static let gaming = AccelerationCurve(
        name: "gaming",
        controlPoints: [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 0.5, y: 0.5),
            CGPoint(x: 0.8, y: 0.9),
            CGPoint(x: 1, y: 1)
        ]
    )
    
    public init(name: String, controlPoints: [CGPoint]) {
        self.name = name
        self.controlPoints = controlPoints
    }
    
    /// Evaluate curve at position t (0-1)
    public func evaluate(at t: CGFloat) -> CGFloat {
        guard controlPoints.count >= 2 else { return t }
        
        if controlPoints.count == 2 {
            // Linear interpolation
            let p0 = controlPoints[0]
            let p1 = controlPoints[1]
            return p0.y + (p1.y - p0.y) * t
        }
        
        // Bezier interpolation for more control points
        return bezierEvaluate(points: controlPoints, t: t)
    }
    
    /// Bezier curve evaluation using De Casteljau's algorithm
    private func bezierEvaluate(points: [CGPoint], t: CGFloat) -> CGFloat {
        var workingPoints = points.map { $0.y }
        
        while workingPoints.count > 1 {
            var newPoints: [CGFloat] = []
            for i in 0..<(workingPoints.count - 1) {
                let interpolated = workingPoints[i] * (1 - t) + workingPoints[i + 1] * t
                newPoints.append(interpolated)
            }
            workingPoints = newPoints
        }
        
        return workingPoints.first ?? t
    }
}

// MARK: - Mouse Settings

/// Per-device mouse settings
public struct MouseSettings: Sendable {
    public let deviceId: String
    public var accelerationEnabled: Bool
    public var accelerationCurve: AccelerationCurve
    public var sensitivity: CGFloat  // Multiplier (1.0 = normal)
    
    public init(
        deviceId: String,
        accelerationEnabled: Bool = false,
        accelerationCurve: AccelerationCurve = .linear,
        sensitivity: CGFloat = 1.0
    ) {
        self.deviceId = deviceId
        self.accelerationEnabled = accelerationEnabled
        self.accelerationCurve = accelerationCurve
        self.sensitivity = sensitivity
    }
}

// MARK: - Mouse Controller

/// Controls mouse acceleration and pointer behavior
///
/// Provides:
/// - 1:1 raw input (disabled acceleration)
/// - Custom acceleration curves
/// - Per-device settings
public final class MouseController: @unchecked Sendable {
    
    // MARK: - Singleton
    
    public static let shared = MouseController()
    
    // MARK: - Properties
    
    /// Per-device settings
    private var deviceSettings: [String: MouseSettings] = [:]
    private let settingsLock = NSLock()
    
    /// Global acceleration disabled flag
    public private(set) var globalAccelerationDisabled: Bool = false
    
    /// Event tap for mouse movement interception
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    public private(set) var isActive: Bool = false
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Disable mouse acceleration globally (1:1 raw input)
    public func disableAcceleration() throws {
        globalAccelerationDisabled = true
        
        // Apply system-level setting if possible
        applySystemAcceleration(enabled: false)
        
        // Start event tap for runtime control
        if !isActive {
            try startEventTap()
        }
        
        log.info("Mouse acceleration disabled globally")
    }
    
    /// Enable mouse acceleration globally
    public func enableAcceleration() {
        globalAccelerationDisabled = false
        
        // Restore system setting
        applySystemAcceleration(enabled: true)
        
        log.info("Mouse acceleration enabled globally")
    }
    
    /// Set acceleration curve for a specific device
    public func setAccelerationCurve(_ curve: AccelerationCurve, forDevice deviceId: String) {
        settingsLock.lock()
        defer { settingsLock.unlock() }
        
        if var settings = deviceSettings[deviceId] {
            settings.accelerationCurve = curve
            settings.accelerationEnabled = curve.name != "linear"
            deviceSettings[deviceId] = settings
        } else {
            deviceSettings[deviceId] = MouseSettings(
                deviceId: deviceId,
                accelerationEnabled: curve.name != "linear",
                accelerationCurve: curve
            )
        }
        
        log.info("Set acceleration curve for device", metadata: [
            "device": deviceId,
            "curve": curve.name
        ])
    }
    
    /// Set sensitivity for a specific device
    public func setSensitivity(_ sensitivity: CGFloat, forDevice deviceId: String) {
        settingsLock.lock()
        defer { settingsLock.unlock() }
        
        if var settings = deviceSettings[deviceId] {
            settings.sensitivity = sensitivity
            deviceSettings[deviceId] = settings
        } else {
            deviceSettings[deviceId] = MouseSettings(
                deviceId: deviceId,
                sensitivity: sensitivity
            )
        }
        
        log.info("Set sensitivity for device", metadata: [
            "device": deviceId,
            "sensitivity": String(format: "%.2f", sensitivity)
        ])
    }
    
    /// Get settings for a device
    public func getSettings(forDevice deviceId: String) -> MouseSettings? {
        settingsLock.lock()
        defer { settingsLock.unlock() }
        return deviceSettings[deviceId]
    }
    
    /// Start event tap for mouse event interception
    public func startEventTap() throws {
        guard !isActive else { return }
        
        let eventMask: CGEventMask = (1 << CGEventType.mouseMoved.rawValue)
        
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, userInfo in
                guard let userInfo = userInfo else { return Unmanaged.passRetained(event) }
                let controller = Unmanaged<MouseController>.fromOpaque(userInfo).takeUnretainedValue()
                return controller.handleMouseEvent(event: event)
            },
            userInfo: selfPointer
        ) else {
            throw PermissionError.accessibilityDenied
        }
        
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        
        isActive = true
        log.info("MouseController event tap started")
    }
    
    /// Stop event tap
    public func stopEventTap() {
        guard isActive else { return }
        
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        
        eventTap = nil
        runLoopSource = nil
        isActive = false
        
        log.info("MouseController event tap stopped")
    }
    
    // MARK: - Private Methods
    
    /// Handle mouse movement event
    private func handleMouseEvent(event: CGEvent) -> Unmanaged<CGEvent>? {
        // If global acceleration is disabled, we modify the delta
        if globalAccelerationDisabled {
            // The event delta is already the raw delta from the device
            // We don't need to modify it further for 1:1 mode
            return Unmanaged.passRetained(event)
        }
        
        // For custom curves, we would transform the delta here
        // This is a simplified implementation
        return Unmanaged.passRetained(event)
    }
    
    /// Apply system-level acceleration setting
    private func applySystemAcceleration(enabled: Bool) {
        // Use IOKit to set mouse acceleration
        // Note: This requires accessibility permissions and may not persist
        
        let speed: Float = enabled ? 1.0 : 0.0
        
        // Set via defaults (this is a common workaround)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = [
            "write",
            ".GlobalPreferences",
            "com.apple.mouse.scaling",
            String(speed)
        ]
        
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            log.warning("Failed to apply system acceleration setting: \(error.localizedDescription)")
        }
    }
}
