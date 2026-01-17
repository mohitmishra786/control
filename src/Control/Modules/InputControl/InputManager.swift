// Control - macOS Power User Interaction Manager
// Input Manager
//
// Central coordinator for input device management using IOHIDManager.
// Skill Reference: input-flow
// - Target: Raw 1:1 mouse input and per-device scroll direction
// - Logic: Use IOHIDManager to identify device types before applying scroll inversion

import Foundation
import IOKit
import IOKit.hid

// MARK: - Input Device Types

/// Represents the type of input device
public enum InputDeviceType: String, Sendable {
    case mouse = "mouse"
    case trackpad = "trackpad"
    case magicMouse = "magic_mouse"
    case keyboard = "keyboard"
    case unknown = "unknown"
}

// MARK: - Input Device

/// Represents a connected input device
public struct InputDevice: Identifiable, Sendable {
    public let id: String  // UUID
    public let type: InputDeviceType
    public let vendorID: Int
    public let productID: Int
    public let productName: String
    public let manufacturer: String
    public let isBuiltin: Bool
    
    public init(
        id: String,
        type: InputDeviceType,
        vendorID: Int,
        productID: Int,
        productName: String,
        manufacturer: String,
        isBuiltin: Bool = false
    ) {
        self.id = id
        self.type = type
        self.vendorID = vendorID
        self.productID = productID
        self.productName = productName
        self.manufacturer = manufacturer
        self.isBuiltin = isBuiltin
    }
}

// MARK: - Input Device Observer

/// Protocol for observing input device changes
public protocol InputDeviceObserver: AnyObject {
    func deviceConnected(_ device: InputDevice)
    func deviceDisconnected(_ device: InputDevice)
}

// MARK: - Input Manager

/// Central manager for input devices using IOHIDManager
///
/// Provides device enumeration, monitoring, and per-device configuration
/// for mice, trackpads, and other HID devices.
public final class InputManager: @unchecked Sendable {
    
    // MARK: - Singleton
    
    public static let shared = InputManager()
    
    // MARK: - Properties
    
    /// Currently connected devices
    private var devices: [String: InputDevice] = [:]
    private let devicesLock = NSLock()
    
    /// Observers
    private var observers: [WeakObserver] = []
    private let observersLock = NSLock()
    
    /// HID Manager
    private var hidManager: IOHIDManager?
    
    /// Run loop for HID events
    private var hidRunLoop: CFRunLoop?
    
    /// Whether manager is active
    public private(set) var isActive: Bool = false
    
    // MARK: - Constants
    
    /// Apple vendor ID
    private let appleVendorID = 0x05AC
    
    /// Known Apple product IDs
    private let appleTrackpadProductIDs = [0x0265, 0x0266, 0x0272, 0x0273, 0x8302]
    private let appleMagicMouseProductIDs = [0x030D, 0x030E]
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Start monitoring input devices
    public func start() throws {
        guard !isActive else { return }
        
        // Create HID Manager
        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        
        guard let manager = hidManager else {
            throw CoreError.unexpected(reason: "Failed to create HID Manager")
        }
        
        // Set device matching for mice and trackpads
        let matchingDicts = createMatchingDictionaries()
        IOHIDManagerSetDeviceMatchingMultiple(manager, matchingDicts as CFArray)
        
        // Set callbacks
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, result, sender, device in
            guard let context = context else { return }
            let manager = Unmanaged<InputManager>.fromOpaque(context).takeUnretainedValue()
            manager.handleDeviceConnected(device)
        }, selfPointer)
        
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, result, sender, device in
            guard let context = context else { return }
            let manager = Unmanaged<InputManager>.fromOpaque(context).takeUnretainedValue()
            manager.handleDeviceDisconnected(device)
        }, selfPointer)
        
        // Schedule with run loop
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        
        // Open manager
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            throw CoreError.unexpected(reason: "Failed to open HID Manager")
        }
        
        isActive = true
        log.info("InputManager started - monitoring HID devices")
        
        // Enumerate existing devices
        enumerateExistingDevices()
    }
    
    /// Stop monitoring input devices
    public func stop() {
        guard isActive, let manager = hidManager else { return }
        
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        
        hidManager = nil
        isActive = false
        
        log.info("InputManager stopped")
    }
    
    /// Get all connected devices
    public func getAllDevices() -> [InputDevice] {
        devicesLock.lock()
        defer { devicesLock.unlock() }
        return Array(devices.values)
    }
    
    /// Get devices of a specific type
    public func getDevices(ofType type: InputDeviceType) -> [InputDevice] {
        return getAllDevices().filter { $0.type == type }
    }
    
    /// Get device by ID
    public func getDevice(id: String) -> InputDevice? {
        devicesLock.lock()
        defer { devicesLock.unlock() }
        return devices[id]
    }
    
    /// Add observer for device changes
    public func addObserver(_ observer: InputDeviceObserver) {
        observersLock.lock()
        defer { observersLock.unlock() }
        
        // Clean up dead references
        observers = observers.filter { $0.observer != nil }
        
        observers.append(WeakObserver(observer))
    }
    
    /// Remove observer
    public func removeObserver(_ observer: InputDeviceObserver) {
        observersLock.lock()
        defer { observersLock.unlock() }
        
        observers = observers.filter { $0.observer !== observer }
    }
    
    // MARK: - Private Methods
    
    /// Create matching dictionaries for HID devices
    private func createMatchingDictionaries() -> [[String: Any]] {
        // Match mice
        let mouseDict: [String: Any] = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse
        ]
        
        // Match pointers (trackpads)
        let pointerDict: [String: Any] = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Pointer
        ]
        
        return [mouseDict, pointerDict]
    }
    
    /// Enumerate existing connected devices
    private func enumerateExistingDevices() {
        guard let manager = hidManager else { return }
        
        if let deviceSet = IOHIDManagerCopyDevices(manager) {
            let devices = deviceSet as! Set<IOHIDDevice>
            for device in devices {
                handleDeviceConnected(device)
            }
        }
    }
    
    /// Handle device connection
    private func handleDeviceConnected(_ deviceRef: IOHIDDevice) {
        guard let device = createInputDevice(from: deviceRef) else { return }
        
        devicesLock.lock()
        devices[device.id] = device
        devicesLock.unlock()
        
        log.info("Device connected: \(device.productName)", metadata: [
            "type": device.type.rawValue,
            "id": device.id
        ])
        
        // Notify observers
        notifyObservers { $0.deviceConnected(device) }
    }
    
    /// Handle device disconnection
    private func handleDeviceDisconnected(_ deviceRef: IOHIDDevice) {
        guard let deviceId = getDeviceID(from: deviceRef) else { return }
        
        devicesLock.lock()
        let device = devices.removeValue(forKey: deviceId)
        devicesLock.unlock()
        
        guard let removedDevice = device else { return }
        
        log.info("Device disconnected: \(removedDevice.productName)")
        
        // Notify observers
        notifyObservers { $0.deviceDisconnected(removedDevice) }
    }
    
    /// Create InputDevice from IOHIDDevice
    private func createInputDevice(from deviceRef: IOHIDDevice) -> InputDevice? {
        guard let deviceId = getDeviceID(from: deviceRef) else { return nil }
        
        let vendorID = getIntProperty(deviceRef, key: kIOHIDVendorIDKey) ?? 0
        let productID = getIntProperty(deviceRef, key: kIOHIDProductIDKey) ?? 0
        let productName = getStringProperty(deviceRef, key: kIOHIDProductKey) ?? "Unknown Device"
        let manufacturer = getStringProperty(deviceRef, key: kIOHIDManufacturerKey) ?? "Unknown"
        let isBuiltin = getIntProperty(deviceRef, key: kIOHIDBuiltInKey) == 1
        
        // Determine device type
        let deviceType = determineDeviceType(
            vendorID: vendorID,
            productID: productID,
            productName: productName,
            isBuiltin: isBuiltin
        )
        
        return InputDevice(
            id: deviceId,
            type: deviceType,
            vendorID: vendorID,
            productID: productID,
            productName: productName,
            manufacturer: manufacturer,
            isBuiltin: isBuiltin
        )
    }
    
    /// Get unique device ID
    private func getDeviceID(from deviceRef: IOHIDDevice) -> String? {
        let vendorID = getIntProperty(deviceRef, key: kIOHIDVendorIDKey) ?? 0
        let productID = getIntProperty(deviceRef, key: kIOHIDProductIDKey) ?? 0
        let locationID = getIntProperty(deviceRef, key: kIOHIDLocationIDKey) ?? 0
        
        return "\(vendorID)-\(productID)-\(locationID)"
    }
    
    /// Determine device type from properties
    private func determineDeviceType(
        vendorID: Int,
        productID: Int,
        productName: String,
        isBuiltin: Bool
    ) -> InputDeviceType {
        let lowercaseName = productName.lowercased()
        
        // Apple devices
        if vendorID == appleVendorID {
            if appleTrackpadProductIDs.contains(productID) || lowercaseName.contains("trackpad") {
                return .trackpad
            }
            if appleMagicMouseProductIDs.contains(productID) || lowercaseName.contains("magic mouse") {
                return .magicMouse
            }
        }
        
        // Check name for clues
        if lowercaseName.contains("trackpad") || lowercaseName.contains("touchpad") {
            return .trackpad
        }
        
        if lowercaseName.contains("mouse") {
            if lowercaseName.contains("magic") {
                return .magicMouse
            }
            return .mouse
        }
        
        // Built-in pointing devices are likely trackpads
        if isBuiltin {
            return .trackpad
        }
        
        return .mouse  // Default to mouse
    }
    
    /// Get integer property from HID device
    private func getIntProperty(_ device: IOHIDDevice, key: String) -> Int? {
        guard let value = IOHIDDeviceGetProperty(device, key as CFString) else {
            return nil
        }
        return (value as? NSNumber)?.intValue
    }
    
    /// Get string property from HID device
    private func getStringProperty(_ device: IOHIDDevice, key: String) -> String? {
        guard let value = IOHIDDeviceGetProperty(device, key as CFString) else {
            return nil
        }
        return value as? String
    }
    
    /// Notify all observers
    private func notifyObservers(_ action: (InputDeviceObserver) -> Void) {
        observersLock.lock()
        let currentObservers = observers.compactMap { $0.observer }
        observersLock.unlock()
        
        for observer in currentObservers {
            action(observer)
        }
    }
}

// MARK: - Weak Observer Wrapper

private class WeakObserver {
    weak var observer: InputDeviceObserver?
    
    init(_ observer: InputDeviceObserver) {
        self.observer = observer
    }
}
