// Control - macOS Power User Interaction Manager
// Scroll Controller
//
// Per-device scroll direction control for mice and trackpads.
// Skill Reference: input-flow
// - Logic: Use IOHIDManager to identify device types (Mouse vs Trackpad) before applying scroll inversion

import CoreGraphics
import Foundation

// MARK: - Scroll Direction

/// Scroll direction setting
public enum ScrollDirection: String, Sendable {
    case natural = "natural"       // Content follows finger direction
    case traditional = "traditional"  // Scroll bars follow wheel direction
}

// MARK: - Scroll Settings

/// Per-device scroll settings
public struct ScrollSettings: Sendable {
    public let deviceId: String
    public var direction: ScrollDirection
    public var speedMultiplier: CGFloat
    public var smoothScrolling: Bool
    
    public init(
        deviceId: String,
        direction: ScrollDirection = .natural,
        speedMultiplier: CGFloat = 1.0,
        smoothScrolling: Bool = true
    ) {
        self.deviceId = deviceId
        self.direction = direction
        self.speedMultiplier = speedMultiplier
        self.smoothScrolling = smoothScrolling
    }
}

// MARK: - Device Scroll Preference

/// Default scroll preferences by device type
public struct DeviceScrollPreference: Sendable {
    public static let defaultMouse = ScrollSettings(
        deviceId: "default_mouse",
        direction: .traditional,  // Traditional for mice
        speedMultiplier: 1.0,
        smoothScrolling: false
    )
    
    public static let defaultTrackpad = ScrollSettings(
        deviceId: "default_trackpad",
        direction: .natural,  // Natural for trackpads
        speedMultiplier: 1.0,
        smoothScrolling: true
    )
}

// MARK: - Scroll Controller

/// Controls scroll direction per device
///
/// Solves the macOS limitation of forcing same scroll direction
/// for all devices. Trackpad uses natural, mouse uses traditional.
public final class ScrollController: @unchecked Sendable {
    
    // MARK: - Singleton
    
    public static let shared = ScrollController()
    
    // MARK: - Properties
    
    /// Per-device scroll settings
    private var deviceSettings: [String: ScrollSettings] = [:]
    private let settingsLock = NSLock()
    
    /// Default settings by device type
    private var defaultMouseDirection: ScrollDirection = .traditional
    private var defaultTrackpadDirection: ScrollDirection = .natural
    
    /// Event tap for scroll event interception
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    public private(set) var isActive: Bool = false
    
    /// Reference to input manager for device lookup
    private let inputManager = InputManager.shared
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Start scroll event interception
    public func start() throws {
        guard !isActive else { return }
        
        // Register for device events
        inputManager.addObserver(self)
        
        // Start event tap
        try startEventTap()
        
        log.info("ScrollController started - per-device scroll direction enabled")
    }
    
    /// Stop scroll event interception
    public func stop() {
        inputManager.removeObserver(self)
        stopEventTap()
        
        log.info("ScrollController stopped")
    }
    
    /// Set default scroll direction for mice
    public func setDefaultMouseDirection(_ direction: ScrollDirection) {
        defaultMouseDirection = direction
        log.info("Default mouse scroll direction set to: \(direction.rawValue)")
    }
    
    /// Set default scroll direction for trackpads
    public func setDefaultTrackpadDirection(_ direction: ScrollDirection) {
        defaultTrackpadDirection = direction
        log.info("Default trackpad scroll direction set to: \(direction.rawValue)")
    }
    
    /// Set scroll direction for a specific device
    public func setScrollDirection(_ direction: ScrollDirection, forDevice deviceId: String) {
        settingsLock.lock()
        defer { settingsLock.unlock() }
        
        if var settings = deviceSettings[deviceId] {
            settings.direction = direction
            deviceSettings[deviceId] = settings
        } else {
            deviceSettings[deviceId] = ScrollSettings(deviceId: deviceId, direction: direction)
        }
        
        log.info("Scroll direction set for device", metadata: [
            "device": deviceId,
            "direction": direction.rawValue
        ])
    }
    
    /// Set scroll speed multiplier for a device
    public func setSpeedMultiplier(_ multiplier: CGFloat, forDevice deviceId: String) {
        settingsLock.lock()
        defer { settingsLock.unlock() }
        
        if var settings = deviceSettings[deviceId] {
            settings.speedMultiplier = multiplier
            deviceSettings[deviceId] = settings
        } else {
            deviceSettings[deviceId] = ScrollSettings(
                deviceId: deviceId,
                speedMultiplier: multiplier
            )
        }
        
        log.info("Scroll speed set for device", metadata: [
            "device": deviceId,
            "multiplier": String(format: "%.2f", multiplier)
        ])
    }
    
    /// Get settings for a device
    public func getSettings(forDevice deviceId: String) -> ScrollSettings? {
        settingsLock.lock()
        defer { settingsLock.unlock() }
        return deviceSettings[deviceId]
    }
    
    /// Get scroll direction for a device type
    public func getDirection(forDeviceType type: InputDeviceType) -> ScrollDirection {
        switch type {
        case .trackpad:
            return defaultTrackpadDirection
        case .mouse, .magicMouse:
            return defaultMouseDirection
        default:
            return .natural
        }
    }
    
    // MARK: - Event Tap
    
    private func startEventTap() throws {
        let eventMask: CGEventMask = (1 << CGEventType.scrollWheel.rawValue)
        
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, userInfo in
                guard let userInfo = userInfo else { return Unmanaged.passRetained(event) }
                let controller = Unmanaged<ScrollController>.fromOpaque(userInfo).takeUnretainedValue()
                return controller.handleScrollEvent(event: event)
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
    }
    
    private func stopEventTap() {
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
    }
    
    // MARK: - Event Handling
    
    private func handleScrollEvent(event: CGEvent) -> Unmanaged<CGEvent>? {
        // Get scroll deltas
        var deltaY = event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
        var deltaX = event.getDoubleValueField(.scrollWheelEventDeltaAxis2)
        
        // Determine device type from event
        // Note: This is a simplified approach; in production, you'd correlate
        // with IOHIDManager device events
        let isMomentumPhase = event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0
        let isPixelDeltas = event.getIntegerValueField(.scrollWheelEventIsContinuous) == 1
        
        // Continuous events (pixel deltas) typically come from trackpads
        // Discrete events (line deltas) typically come from mice
        let deviceType: InputDeviceType = isPixelDeltas ? .trackpad : .mouse
        
        // Get direction for device type
        let direction = getDirection(forDeviceType: deviceType)
        
        // Check system natural scroll setting
        // If system is set to natural and we want traditional for mice, invert
        let systemNatural = isSystemNaturalScrollEnabled()
        let shouldInvert = (direction == .traditional && systemNatural) ||
                          (direction == .natural && !systemNatural)
        
        if shouldInvert && !isMomentumPhase {
            // Invert scroll direction
            deltaY = -deltaY
            deltaX = -deltaX
            
            event.setDoubleValueField(.scrollWheelEventDeltaAxis1, value: deltaY)
            event.setDoubleValueField(.scrollWheelEventDeltaAxis2, value: deltaX)
            
            // Also invert pixel deltas if present
            if isPixelDeltas {
                let pixelDeltaY = -event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
                let pixelDeltaX = -event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
                event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: pixelDeltaY)
                event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: pixelDeltaX)
            }
        }
        
        return Unmanaged.passRetained(event)
    }
    
    /// Check if system natural scrolling is enabled
    private func isSystemNaturalScrollEnabled() -> Bool {
        // Read from user defaults
        if let natural = UserDefaults.standard.object(forKey: "com.apple.swipescrolldirection") as? Bool {
            return natural
        }
        // Default to true (natural scrolling is default on modern macOS)
        return true
    }
}

// MARK: - InputDeviceObserver

extension ScrollController: InputDeviceObserver {
    public func deviceConnected(_ device: InputDevice) {
        log.debug("Device connected, applying scroll settings", metadata: [
            "device": device.productName,
            "type": device.type.rawValue
        ])
        
        // Apply default settings for this device type
        let direction = getDirection(forDeviceType: device.type)
        setScrollDirection(direction, forDevice: device.id)
    }
    
    public func deviceDisconnected(_ device: InputDevice) {
        log.debug("Device disconnected", metadata: [
            "device": device.productName
        ])
        
        // Optionally remove settings for disconnected device
        // We keep them to remember preferences for when device reconnects
    }
}
