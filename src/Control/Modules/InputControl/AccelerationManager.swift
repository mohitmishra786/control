// Control - macOS Power User Interaction Manager
// Acceleration Manager
//
// Custom Bezier curve interpolation for pointer acceleration.
// Skill Reference: input-flow
// - Implement custom Bezier curve interpolation for pointer acceleration overrides
// - Bypass system "Enhance Pointer Precision" lag

import CoreGraphics
import Foundation

// MARK: - Bezier Curve

/// Cubic Bezier curve for acceleration mapping
public struct BezierAccelerationCurve: Sendable {
    /// Control points (4 points for cubic Bezier)
    public let p0: CGPoint
    public let p1: CGPoint
    public let p2: CGPoint
    public let p3: CGPoint
    
    /// Curve name for identification
    public let name: String
    
    /// Presets
    public static let linear = BezierAccelerationCurve(
        name: "linear",
        p0: CGPoint(x: 0, y: 0),
        p1: CGPoint(x: 0.333, y: 0.333),
        p2: CGPoint(x: 0.666, y: 0.666),
        p3: CGPoint(x: 1, y: 1)
    )
    
    public static let smooth = BezierAccelerationCurve(
        name: "smooth",
        p0: CGPoint(x: 0, y: 0),
        p1: CGPoint(x: 0.25, y: 0.1),
        p2: CGPoint(x: 0.25, y: 1),
        p3: CGPoint(x: 1, y: 1)
    )
    
    public static let gaming = BezierAccelerationCurve(
        name: "gaming",
        p0: CGPoint(x: 0, y: 0),
        p1: CGPoint(x: 0.5, y: 0.1),
        p2: CGPoint(x: 0.5, y: 0.5),
        p3: CGPoint(x: 1, y: 1)
    )
    
    public static let precision = BezierAccelerationCurve(
        name: "precision",
        p0: CGPoint(x: 0, y: 0),
        p1: CGPoint(x: 0.1, y: 0.4),
        p2: CGPoint(x: 0.4, y: 0.9),
        p3: CGPoint(x: 1, y: 1)
    )
    
    public init(name: String, p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint) {
        self.name = name
        self.p0 = p0
        self.p1 = p1
        self.p2 = p2
        self.p3 = p3
    }
    
    /// Create from control point array
    public init?(name: String, controlPoints: [[Double]]) {
        guard controlPoints.count >= 4 else { return nil }
        
        self.name = name
        self.p0 = CGPoint(x: controlPoints[0][0], y: controlPoints[0][1])
        self.p1 = CGPoint(x: controlPoints[1][0], y: controlPoints[1][1])
        self.p2 = CGPoint(x: controlPoints[2][0], y: controlPoints[2][1])
        self.p3 = CGPoint(x: controlPoints[3][0], y: controlPoints[3][1])
    }
    
    /// Evaluate curve at parameter t (0-1)
    /// Returns output value (0-1) for input velocity
    public func evaluate(at t: CGFloat) -> CGFloat {
        let t2 = t * t
        let t3 = t2 * t
        let mt = 1 - t
        let mt2 = mt * mt
        let mt3 = mt2 * mt
        
        // Cubic Bezier formula: B(t) = (1-t)^3*P0 + 3*(1-t)^2*t*P1 + 3*(1-t)*t^2*P2 + t^3*P3
        let y = mt3 * p0.y + 3 * mt2 * t * p1.y + 3 * mt * t2 * p2.y + t3 * p3.y
        
        return max(0, min(1, y))
    }
    
    /// Find t for given x value using Newton-Raphson
    public func solveForX(_ x: CGFloat, iterations: Int = 8) -> CGFloat {
        var t = x  // Initial guess
        
        for _ in 0..<iterations {
            let currentX = evaluateX(at: t)
            let derivative = evaluateXDerivative(at: t)
            
            if abs(derivative) < 0.0001 {
                break
            }
            
            t = t - (currentX - x) / derivative
            t = max(0, min(1, t))
        }
        
        return t
    }
    
    /// Evaluate X coordinate at parameter t
    private func evaluateX(at t: CGFloat) -> CGFloat {
        let t2 = t * t
        let t3 = t2 * t
        let mt = 1 - t
        let mt2 = mt * mt
        let mt3 = mt2 * mt
        
        return mt3 * p0.x + 3 * mt2 * t * p1.x + 3 * mt * t2 * p2.x + t3 * p3.x
    }
    
    /// Derivative of X at parameter t
    private func evaluateXDerivative(at t: CGFloat) -> CGFloat {
        let t2 = t * t
        let mt = 1 - t
        let mt2 = mt * mt
        
        return 3 * mt2 * (p1.x - p0.x) + 6 * mt * t * (p2.x - p1.x) + 3 * t2 * (p3.x - p2.x)
    }
    
    /// Get Y value for X value (the main acceleration function)
    public func accelerate(normalizedVelocity x: CGFloat) -> CGFloat {
        let t = solveForX(x)
        return evaluate(at: t)
    }
}

// MARK: - Acceleration Manager

/// Manages pointer acceleration with custom curves
///
/// Features:
/// - Custom Bezier curve acceleration
/// - Per-device curve profiles
/// - Bypass system "Enhance Pointer Precision"
public final class AccelerationManager: @unchecked Sendable {
    
    // MARK: - Singleton
    
    public static let shared = AccelerationManager()
    
    // MARK: - Properties
    
    /// Active curve for all devices
    private var activeCurve: BezierAccelerationCurve = .linear
    
    /// Per-device curves
    private var deviceCurves: [String: BezierAccelerationCurve] = [:]
    private let curvesLock = NSLock()
    
    /// Maximum velocity for normalization (pixels/second)
    public var maxVelocity: CGFloat = 3000.0
    
    /// Minimum velocity threshold (below this, linear 1:1)
    public var minVelocityThreshold: CGFloat = 50.0
    
    /// Event tap for velocity-based acceleration
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    public private(set) var isActive: Bool = false
    
    /// Last event time for velocity calculation
    private var lastEventTime: CFTimeInterval = 0
    private var lastPosition: CGPoint = .zero
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Set the active acceleration curve
    public func setCurve(_ curve: BezierAccelerationCurve) {
        curvesLock.lock()
        activeCurve = curve
        curvesLock.unlock()
        
        log.info("Acceleration curve set to: \(curve.name)")
    }
    
    /// Set curve by preset name
    public func setCurveByName(_ name: String) {
        let curve: BezierAccelerationCurve
        
        switch name.lowercased() {
        case "linear": curve = .linear
        case "smooth": curve = .smooth
        case "gaming": curve = .gaming
        case "precision": curve = .precision
        default:
            log.warning("Unknown curve preset: \(name), using linear")
            curve = .linear
        }
        
        setCurve(curve)
    }
    
    /// Set curve for specific device
    public func setCurve(_ curve: BezierAccelerationCurve, forDevice deviceId: String) {
        curvesLock.lock()
        deviceCurves[deviceId] = curve
        curvesLock.unlock()
        
        log.info("Acceleration curve for device \(deviceId): \(curve.name)")
    }
    
    /// Get curve for device (falls back to active curve)
    public func getCurve(forDevice deviceId: String) -> BezierAccelerationCurve {
        curvesLock.lock()
        defer { curvesLock.unlock() }
        
        return deviceCurves[deviceId] ?? activeCurve
    }
    
    /// Start acceleration event tap
    public func start() throws {
        guard !isActive else { return }
        
        let eventMask: CGEventMask = (1 << CGEventType.mouseMoved.rawValue) |
                                      (1 << CGEventType.leftMouseDragged.rawValue) |
                                      (1 << CGEventType.rightMouseDragged.rawValue)
        
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, userInfo in
                guard let userInfo = userInfo else {
                    return Unmanaged.passRetained(event)
                }
                let manager = Unmanaged<AccelerationManager>.fromOpaque(userInfo).takeUnretainedValue()
                return manager.processMouseEvent(event)
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
        log.info("AccelerationManager started")
    }
    
    /// Stop acceleration event tap
    public func stop() {
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
        
        log.info("AccelerationManager stopped")
    }
    
    /// Apply acceleration curve to delta
    public func applyAcceleration(dx: CGFloat, dy: CGFloat, curve: BezierAccelerationCurve) -> (CGFloat, CGFloat) {
        // Calculate velocity magnitude
        let velocity = sqrt(dx * dx + dy * dy)
        
        // Below threshold: linear 1:1
        if velocity < minVelocityThreshold {
            return (dx, dy)
        }
        
        // Normalize velocity to 0-1
        let normalizedVelocity = min(velocity / maxVelocity, 1.0)
        
        // Apply curve
        let acceleratedVelocity = curve.accelerate(normalizedVelocity: normalizedVelocity)
        
        // Calculate multiplier
        let multiplier = (acceleratedVelocity * maxVelocity) / velocity
        
        return (dx * multiplier, dy * multiplier)
    }
    
    // MARK: - Private Methods
    
    private func processMouseEvent(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        curvesLock.lock()
        let curve = activeCurve
        curvesLock.unlock()
        
        // For linear curve, pass through unchanged
        if curve.name == "linear" {
            return Unmanaged.passRetained(event)
        }
        
        // Get delta from event
        let dx = event.getDoubleValueField(.mouseEventDeltaX)
        let dy = event.getDoubleValueField(.mouseEventDeltaY)
        
        // Apply acceleration
        let (newDx, newDy) = applyAcceleration(dx: dx, dy: dy, curve: curve)
        
        // Set new delta
        event.setDoubleValueField(.mouseEventDeltaX, value: newDx)
        event.setDoubleValueField(.mouseEventDeltaY, value: newDy)
        
        return Unmanaged.passRetained(event)
    }
}
