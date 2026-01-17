// Control - macOS Power User Interaction Manager
// CGEvent Handler
//
// Optimized event tap management.

import CoreGraphics
import Foundation

// MARK: - Event Type Filter

/// Event types to monitor
public struct EventTypeFilter: OptionSet, Sendable {
    public let rawValue: UInt64
    
    public static let mouseMove = EventTypeFilter(rawValue: 1 << CGEventType.mouseMoved.rawValue)
    public static let leftMouseDown = EventTypeFilter(rawValue: 1 << CGEventType.leftMouseDown.rawValue)
    public static let leftMouseUp = EventTypeFilter(rawValue: 1 << CGEventType.leftMouseUp.rawValue)
    public static let rightMouseDown = EventTypeFilter(rawValue: 1 << CGEventType.rightMouseDown.rawValue)
    public static let rightMouseUp = EventTypeFilter(rawValue: 1 << CGEventType.rightMouseUp.rawValue)
    public static let leftMouseDragged = EventTypeFilter(rawValue: 1 << CGEventType.leftMouseDragged.rawValue)
    public static let rightMouseDragged = EventTypeFilter(rawValue: 1 << CGEventType.rightMouseDragged.rawValue)
    public static let scrollWheel = EventTypeFilter(rawValue: 1 << CGEventType.scrollWheel.rawValue)
    public static let keyDown = EventTypeFilter(rawValue: 1 << CGEventType.keyDown.rawValue)
    public static let keyUp = EventTypeFilter(rawValue: 1 << CGEventType.keyUp.rawValue)
    
    public static let allMouse: EventTypeFilter = [.mouseMove, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .leftMouseDragged, .rightMouseDragged]
    public static let allKeyboard: EventTypeFilter = [.keyDown, .keyUp]
    
    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }
}

// MARK: - Event Handler

/// Event handler closure type
public typealias CGEventCallback = (CGEvent) -> CGEvent?

// MARK: - Event Tap Handle

/// Handle to a created event tap
public class EventTapHandle: @unchecked Sendable {
    fileprivate let tap: CFMachPort
    fileprivate let runLoopSource: CFRunLoopSource
    fileprivate var isEnabled: Bool = true
    
    fileprivate init(tap: CFMachPort, source: CFRunLoopSource) {
        self.tap = tap
        self.runLoopSource = source
    }
    
    deinit {
        disable()
        CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    }
    
    /// Enable the event tap
    public func enable() {
        CGEvent.tapEnable(tap: tap, enable: true)
        isEnabled = true
    }
    
    /// Disable the event tap
    public func disable() {
        CGEvent.tapEnable(tap: tap, enable: false)
        isEnabled = false
    }
}

// MARK: - CGEvent Handler

/// Optimized CGEvent tap manager
///
/// Features:
/// - Multiple concurrent taps
/// - Per-tap callbacks
/// - Automatic tap re-enabling
public final class CGEventHandler: @unchecked Sendable {
    
    // MARK: - Singleton
    
    public static let shared = CGEventHandler()
    
    // MARK: - Properties
    
    /// Active taps
    private var activeTaps: [UUID: (handle: EventTapHandle, callback: CGEventCallback)] = [:]
    private let tapsLock = NSLock()
    
    /// Tap re-enable timer
    private var reenableTimer: Timer?
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Create an event tap
    public func createTap(
        location: CGEventTapLocation = .cghidEventTap,
        placement: CGEventTapPlacement = .headInsertEventTap,
        options: CGEventTapOptions = .defaultTap,
        filter: EventTypeFilter,
        callback: @escaping CGEventCallback
    ) throws -> UUID {
        let tapId = UUID()
        
        // Store callback for the tap
        tapsLock.lock()
        
        // Create context for callback
        let context = TapContext(id: tapId, handler: self)
        let contextPtr = Unmanaged.passRetained(context).toOpaque()
        
        guard let tap = CGEvent.tapCreate(
            tap: location,
            place: placement,
            options: options,
            eventsOfInterest: CGEventMask(filter.rawValue),
            callback: { proxy, type, event, userInfo in
                guard let userInfo = userInfo else {
                    return Unmanaged.passRetained(event)
                }
                
                let context = Unmanaged<TapContext>.fromOpaque(userInfo).takeUnretainedValue()
                
                // Handle tap disabled event
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    context.handler.handleTapDisabled(context.id)
                    return Unmanaged.passRetained(event)
                }
                
                // Get callback and process
                if let callback = context.handler.getCallback(for: context.id) {
                    if let result = callback(event) {
                        return Unmanaged.passRetained(result)
                    }
                    return nil
                }
                
                return Unmanaged.passRetained(event)
            },
            userInfo: contextPtr
        ) else {
            tapsLock.unlock()
            _ = Unmanaged<TapContext>.fromOpaque(contextPtr).takeRetainedValue()
            throw CGEventHandlerError.failedToCreateTap
        }
        
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)!
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        
        let handle = EventTapHandle(tap: tap, source: runLoopSource)
        activeTaps[tapId] = (handle, callback)
        
        tapsLock.unlock()
        
        log.debug("Created event tap: \(tapId)")
        return tapId
    }
    
    /// Remove an event tap
    public func removeTap(_ id: UUID) {
        tapsLock.lock()
        if let entry = activeTaps.removeValue(forKey: id) {
            entry.handle.disable()
        }
        tapsLock.unlock()
        
        log.debug("Removed event tap: \(id)")
    }
    
    /// Get tap handle
    public func getTapHandle(_ id: UUID) -> EventTapHandle? {
        tapsLock.lock()
        defer { tapsLock.unlock() }
        return activeTaps[id]?.handle
    }
    
    /// Remove all taps
    public func removeAllTaps() {
        tapsLock.lock()
        for (_, entry) in activeTaps {
            entry.handle.disable()
        }
        activeTaps.removeAll()
        tapsLock.unlock()
        
        log.info("Removed all event taps")
    }
    
    /// Get active tap count
    public var activeTapCount: Int {
        tapsLock.lock()
        defer { tapsLock.unlock() }
        return activeTaps.count
    }
    
    // MARK: - Private Methods
    
    fileprivate func getCallback(for id: UUID) -> CGEventCallback? {
        tapsLock.lock()
        defer { tapsLock.unlock() }
        return activeTaps[id]?.callback
    }
    
    fileprivate func handleTapDisabled(_ id: UUID) {
        // Re-enable the tap
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.tapsLock.lock()
            self?.activeTaps[id]?.handle.enable()
            self?.tapsLock.unlock()
            
            log.debug("Re-enabled event tap: \(id)")
        }
    }
}

// MARK: - Tap Context

private class TapContext {
    let id: UUID
    let handler: CGEventHandler
    
    init(id: UUID, handler: CGEventHandler) {
        self.id = id
        self.handler = handler
    }
}

// MARK: - Errors

public enum CGEventHandlerError: Error, LocalizedError {
    case failedToCreateTap
    case tapNotFound
    
    public var errorDescription: String? {
        switch self {
        case .failedToCreateTap:
            return "Failed to create CGEvent tap. Ensure accessibility permission is granted."
        case .tapNotFound:
            return "Event tap not found"
        }
    }
}
