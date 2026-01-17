// Control - macOS Power User Interaction Manager
// Gesture Mapper
//
// Maps trackpad gestures to custom actions.
// Integrates with Shortcuts.app for extensibility.

import AppKit
import CoreGraphics
import Foundation

// MARK: - Gesture Type

/// Types of trackpad gestures
public enum GestureType: String, CaseIterable, Sendable {
    case threeFingerSwipeUp = "three_finger_swipe_up"
    case threeFingerSwipeDown = "three_finger_swipe_down"
    case threeFingerSwipeLeft = "three_finger_swipe_left"
    case threeFingerSwipeRight = "three_finger_swipe_right"
    case fourFingerSwipeUp = "four_finger_swipe_up"
    case fourFingerSwipeDown = "four_finger_swipe_down"
    case fourFingerSwipeLeft = "four_finger_swipe_left"
    case fourFingerSwipeRight = "four_finger_swipe_right"
    case pinchIn = "pinch_in"
    case pinchOut = "pinch_out"
    case rotate = "rotate"
    
    public var displayName: String {
        switch self {
        case .threeFingerSwipeUp: return "3-Finger Swipe Up"
        case .threeFingerSwipeDown: return "3-Finger Swipe Down"
        case .threeFingerSwipeLeft: return "3-Finger Swipe Left"
        case .threeFingerSwipeRight: return "3-Finger Swipe Right"
        case .fourFingerSwipeUp: return "4-Finger Swipe Up"
        case .fourFingerSwipeDown: return "4-Finger Swipe Down"
        case .fourFingerSwipeLeft: return "4-Finger Swipe Left"
        case .fourFingerSwipeRight: return "4-Finger Swipe Right"
        case .pinchIn: return "Pinch In"
        case .pinchOut: return "Pinch Out"
        case .rotate: return "Rotate"
        }
    }
}

// MARK: - Gesture Action

/// Action to perform when gesture is triggered
public enum GestureAction: Sendable {
    case controlCommand(String)      // e.g., "window maximize"
    case shortcut(String)            // Shortcuts.app shortcut name
    case keystroke(String)           // e.g., "cmd+shift+f"
    case shell(String)               // Shell command
    case none
    
    public var description: String {
        switch self {
        case .controlCommand(let cmd): return "control \(cmd)"
        case .shortcut(let name): return "shortcut: \(name)"
        case .keystroke(let keys): return "keystroke: \(keys)"
        case .shell(let cmd): return "shell: \(cmd)"
        case .none: return "none"
        }
    }
}

// MARK: - Gesture Mapping

/// A gesture to action mapping
public struct GestureMapping: Sendable {
    public let gesture: GestureType
    public let action: GestureAction
    public let enabled: Bool
    
    public init(gesture: GestureType, action: GestureAction, enabled: Bool = true) {
        self.gesture = gesture
        self.action = action
        self.enabled = enabled
    }
}

// MARK: - Gesture Mapper

/// Maps trackpad gestures to custom actions
///
/// Features:
/// - Multi-finger swipe detection
/// - Control command integration
/// - Shortcuts.app support
/// - Keystroke simulation
public final class GestureMapper: @unchecked Sendable {
    
    // MARK: - Singleton
    
    public static let shared = GestureMapper()
    
    // MARK: - Properties
    
    /// Active gesture mappings
    private var mappings: [GestureType: GestureMapping] = [:]
    private let mappingsLock = NSLock()
    
    /// Gesture recognition state
    private var recognitionState: GestureRecognitionState = .idle
    private var touchCount: Int = 0
    private var accumulatedDelta: CGPoint = .zero
    
    /// Thresholds
    public var swipeThreshold: CGFloat = 50.0  // pixels
    public var swipeVelocityThreshold: CGFloat = 200.0  // pixels/second
    
    /// Event monitor
    private var localMonitor: Any?
    private var globalMonitor: Any?
    public private(set) var isActive: Bool = false
    
    // MARK: - Recognition State
    
    private enum GestureRecognitionState {
        case idle
        case tracking(startTime: Date, startPosition: CGPoint)
        case recognized(GestureType)
    }
    
    // MARK: - Initialization
    
    private init() {
        setupDefaultMappings()
    }
    
    // MARK: - Public Methods
    
    /// Start gesture monitoring
    @MainActor
    public func start() {
        guard !isActive else { return }
        
        // Monitor for gesture events
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.gesture, .swipe, .magnify, .rotate]
        ) { [weak self] event in
            self?.handleEvent(event)
            return event
        }
        
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.gesture, .swipe, .magnify, .rotate]
        ) { [weak self] event in
            self?.handleEvent(event)
        }
        
        isActive = true
        log.info("GestureMapper started")
    }
    
    /// Stop gesture monitoring
    @MainActor
    public func stop() {
        guard isActive else { return }
        
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        
        isActive = false
        log.info("GestureMapper stopped")
    }
    
    /// Set mapping for a gesture
    public func setMapping(_ mapping: GestureMapping) {
        mappingsLock.lock()
        defer { mappingsLock.unlock() }
        
        mappings[mapping.gesture] = mapping
        log.info("Gesture mapping set: \(mapping.gesture.rawValue) -> \(mapping.action.description)")
    }
    
    /// Remove mapping for a gesture
    public func removeMapping(for gesture: GestureType) {
        mappingsLock.lock()
        defer { mappingsLock.unlock() }
        
        mappings.removeValue(forKey: gesture)
    }
    
    /// Get mapping for a gesture
    public func getMapping(for gesture: GestureType) -> GestureMapping? {
        mappingsLock.lock()
        defer { mappingsLock.unlock() }
        
        return mappings[gesture]
    }
    
    /// Get all mappings
    public func getAllMappings() -> [GestureMapping] {
        mappingsLock.lock()
        defer { mappingsLock.unlock() }
        
        return Array(mappings.values)
    }
    
    // MARK: - Private Methods
    
    private func setupDefaultMappings() {
        // Default mappings for window management
        setMapping(GestureMapping(
            gesture: .threeFingerSwipeUp,
            action: .controlCommand("window maximize"),
            enabled: false  // Disabled by default
        ))
        
        setMapping(GestureMapping(
            gesture: .threeFingerSwipeDown,
            action: .controlCommand("window restore"),
            enabled: false
        ))
    }
    
    private func handleEvent(_ event: NSEvent) {
        switch event.type {
        case .swipe:
            handleSwipeEvent(event)
        case .magnify:
            handleMagnifyEvent(event)
        case .rotate:
            handleRotateEvent(event)
        default:
            break
        }
    }
    
    private func handleSwipeEvent(_ event: NSEvent) {
        let deltaX = event.deltaX
        let deltaY = event.deltaY
        
        // Determine swipe direction
        let gesture: GestureType?
        
        if abs(deltaX) > abs(deltaY) {
            // Horizontal swipe
            gesture = deltaX > 0 ? .threeFingerSwipeRight : .threeFingerSwipeLeft
        } else {
            // Vertical swipe
            gesture = deltaY > 0 ? .threeFingerSwipeDown : .threeFingerSwipeUp
        }
        
        if let gesture = gesture {
            triggerGesture(gesture)
        }
    }
    
    private func handleMagnifyEvent(_ event: NSEvent) {
        let magnification = event.magnification
        
        // Only trigger at end of gesture
        if event.phase == .ended {
            let gesture: GestureType = magnification > 0 ? .pinchOut : .pinchIn
            triggerGesture(gesture)
        }
    }
    
    private func handleRotateEvent(_ event: NSEvent) {
        if event.phase == .ended {
            triggerGesture(.rotate)
        }
    }
    
    private func triggerGesture(_ gesture: GestureType) {
        mappingsLock.lock()
        let mapping = mappings[gesture]
        mappingsLock.unlock()
        
        guard let mapping = mapping, mapping.enabled else {
            return
        }
        
        log.debug("Gesture triggered: \(gesture.rawValue)")
        
        // Execute action
        Task {
            await executeAction(mapping.action)
        }
    }
    
    @MainActor
    private func executeAction(_ action: GestureAction) async {
        switch action {
        case .controlCommand(let command):
            executeControlCommand(command)
            
        case .shortcut(let name):
            executeShortcut(name)
            
        case .keystroke(let keys):
            simulateKeystroke(keys)
            
        case .shell(let command):
            executeShellCommand(command)
            
        case .none:
            break
        }
    }
    
    private func executeControlCommand(_ command: String) {
        // Execute control command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/local/bin/control")
        process.arguments = command.components(separatedBy: " ")
        
        do {
            try process.run()
        } catch {
            log.error("Failed to execute control command: \(error)")
        }
    }
    
    private func executeShortcut(_ name: String) {
        // Run Shortcuts.app shortcut
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name]
        
        do {
            try process.run()
        } catch {
            log.error("Failed to run shortcut '\(name)': \(error)")
        }
    }
    
    private func simulateKeystroke(_ keys: String) {
        // Parse keystroke (e.g., "cmd+shift+f")
        let components = keys.lowercased().components(separatedBy: "+")
        
        var flags: CGEventFlags = []
        var keyCode: CGKeyCode = 0
        
        for component in components {
            switch component {
            case "cmd", "command": flags.insert(.maskCommand)
            case "ctrl", "control": flags.insert(.maskControl)
            case "alt", "option": flags.insert(.maskAlternate)
            case "shift": flags.insert(.maskShift)
            default:
                // Assume it's the key
                keyCode = keyCodeForCharacter(component)
            }
        }
        
        // Create and post keyboard events
        if let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
           let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) {
            keyDown.flags = flags
            keyUp.flags = flags
            
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }
    
    private func executeShellCommand(_ command: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        
        do {
            try process.run()
        } catch {
            log.error("Failed to execute shell command: \(error)")
        }
    }
    
    private func keyCodeForCharacter(_ char: String) -> CGKeyCode {
        // Common key codes (simplified)
        let keyCodes: [String: CGKeyCode] = [
            "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5,
            "h": 4, "i": 34, "j": 38, "k": 40, "l": 37, "m": 46, "n": 45,
            "o": 31, "p": 35, "q": 12, "r": 15, "s": 1, "t": 17, "u": 32,
            "v": 9, "w": 13, "x": 7, "y": 16, "z": 6,
            "space": 49, "return": 36, "tab": 48, "escape": 53
        ]
        
        return keyCodes[char] ?? 0
    }
}
