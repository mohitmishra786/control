// Control - macOS Power User Interaction Manager
// Snap Handler
//
// Drag-to-edge snapping with visual overlay feedback.
// Skill Reference: window-mason
// - Target: 1px precision for resizing

import AppKit
import CoreGraphics
import Foundation

// MARK: - Snap Edge

/// Edges that can trigger snapping
public enum SnapEdge: String, Sendable {
    case left = "left"
    case right = "right"
    case top = "top"
    case bottom = "bottom"
    case topLeft = "top_left"
    case topRight = "top_right"
    case bottomLeft = "bottom_left"
    case bottomRight = "bottom_right"
}

// MARK: - Snap Zone

/// A zone that windows can snap to
public struct SnapZone: Sendable {
    public let edge: SnapEdge
    public let triggerRect: CGRect  // Area that triggers snapping
    public let targetRect: CGRect   // Final window position
    
    public init(edge: SnapEdge, triggerRect: CGRect, targetRect: CGRect) {
        self.edge = edge
        self.triggerRect = triggerRect
        self.targetRect = targetRect
    }
}

// MARK: - Snap Handler

/// Handles drag-to-edge window snapping
///
/// Features:
/// - Mouse position monitoring during drag
/// - Visual overlay for snap zones
/// - Configurable snap threshold
/// - 1px precision positioning
public final class SnapHandler: @unchecked Sendable {
    
    // MARK: - Singleton
    
    public static let shared = SnapHandler()
    
    // MARK: - Properties
    
    /// Whether snapping is enabled
    public var isEnabled: Bool = true
    
    /// Snap threshold (distance from edge to trigger)
    public var snapThreshold: CGFloat = 20
    
    /// Animation duration (milliseconds)
    public var animationDuration: Int = 150
    
    /// Show visual overlay when hovering snap zone
    public var showOverlay: Bool = true
    
    /// Current snap zones for active screen
    private var snapZones: [SnapZone] = []
    
    /// Overlay window for visual feedback
    private var overlayWindow: NSWindow?
    
    /// Currently highlighted zone
    private var highlightedZone: SnapZone?
    
    /// Event monitor for drag detection
    private var eventMonitor: Any?
    
    /// Whether we're currently tracking a drag
    private var isDragging: Bool = false
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Start monitoring for window drags
    @MainActor
    public func start() {
        guard eventMonitor == nil else { return }
        
        // Monitor mouse events
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            Task { @MainActor in
                self?.handleMouseEvent(event)
            }
        }
        
        // Build snap zones for current screen
        updateSnapZones()
        
        log.info("SnapHandler started")
    }
    
    /// Stop monitoring
    @MainActor
    public func stop() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        
        hideOverlay()
        isDragging = false
        
        log.info("SnapHandler stopped")
    }
    
    /// Update snap zones for current screen configuration
    @MainActor
    public func updateSnapZones() {
        snapZones = []
        
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let threshold = snapThreshold
        
        // Left edge -> Left half
        snapZones.append(SnapZone(
            edge: .left,
            triggerRect: CGRect(x: frame.minX, y: frame.minY, width: threshold, height: frame.height),
            targetRect: CGRect(x: frame.minX, y: frame.minY, width: frame.width / 2, height: frame.height)
        ))
        
        // Right edge -> Right half
        snapZones.append(SnapZone(
            edge: .right,
            triggerRect: CGRect(x: frame.maxX - threshold, y: frame.minY, width: threshold, height: frame.height),
            targetRect: CGRect(x: frame.midX, y: frame.minY, width: frame.width / 2, height: frame.height)
        ))
        
        // Top edge -> Maximized
        snapZones.append(SnapZone(
            edge: .top,
            triggerRect: CGRect(x: frame.minX + threshold, y: frame.maxY - threshold, width: frame.width - 2 * threshold, height: threshold),
            targetRect: frame
        ))
        
        // Top-left corner -> Top-left quarter
        snapZones.append(SnapZone(
            edge: .topLeft,
            triggerRect: CGRect(x: frame.minX, y: frame.maxY - threshold, width: threshold, height: threshold),
            targetRect: CGRect(x: frame.minX, y: frame.midY, width: frame.width / 2, height: frame.height / 2)
        ))
        
        // Top-right corner -> Top-right quarter
        snapZones.append(SnapZone(
            edge: .topRight,
            triggerRect: CGRect(x: frame.maxX - threshold, y: frame.maxY - threshold, width: threshold, height: threshold),
            targetRect: CGRect(x: frame.midX, y: frame.midY, width: frame.width / 2, height: frame.height / 2)
        ))
        
        // Bottom-left corner -> Bottom-left quarter
        snapZones.append(SnapZone(
            edge: .bottomLeft,
            triggerRect: CGRect(x: frame.minX, y: frame.minY, width: threshold, height: threshold),
            targetRect: CGRect(x: frame.minX, y: frame.minY, width: frame.width / 2, height: frame.height / 2)
        ))
        
        // Bottom-right corner -> Bottom-right quarter
        snapZones.append(SnapZone(
            edge: .bottomRight,
            triggerRect: CGRect(x: frame.maxX - threshold, y: frame.minY, width: threshold, height: threshold),
            targetRect: CGRect(x: frame.midX, y: frame.minY, width: frame.width / 2, height: frame.height / 2)
        ))
    }
    
    /// Check if point is in a snap zone
    public func checkSnapZone(at point: CGPoint) -> SnapZone? {
        // Check corners first (higher priority)
        for zone in snapZones where [.topLeft, .topRight, .bottomLeft, .bottomRight].contains(zone.edge) {
            if zone.triggerRect.contains(point) {
                return zone
            }
        }
        
        // Then check edges
        for zone in snapZones where [.left, .right, .top, .bottom].contains(zone.edge) {
            if zone.triggerRect.contains(point) {
                return zone
            }
        }
        
        return nil
    }
    
    /// Snap window to zone
    @MainActor
    public func snapWindow(_ window: AXUIElement, to zone: SnapZone) -> Bool {
        let success = window.setFrame(zone.targetRect)
        
        if success {
            log.info("Snapped window to \(zone.edge.rawValue)")
        }
        
        return success
    }
    
    // MARK: - Private Methods
    
    /// Handle mouse events during drag
    @MainActor
    private func handleMouseEvent(_ event: NSEvent) {
        guard isEnabled else { return }
        
        switch event.type {
        case .leftMouseDragged:
            handleDrag(at: NSEvent.mouseLocation)
            
        case .leftMouseUp:
            handleDragEnd(at: NSEvent.mouseLocation)
            
        default:
            break
        }
    }
    
    /// Handle drag movement
    @MainActor
    private func handleDrag(at point: CGPoint) {
        isDragging = true
        
        // Check if we're in a snap zone
        if let zone = checkSnapZone(at: point) {
            if highlightedZone?.edge != zone.edge {
                highlightedZone = zone
                if showOverlay {
                    showSnapOverlay(for: zone)
                }
            }
        } else {
            highlightedZone = nil
            hideOverlay()
        }
    }
    
    /// Handle drag end
    @MainActor
    private func handleDragEnd(at point: CGPoint) {
        guard isDragging else { return }
        isDragging = false
        
        // If we ended in a snap zone, snap the window
        if let zone = highlightedZone {
            // Get the frontmost window
            if let window = WindowManager.shared.getFrontmostWindow(),
               let axElement = window.axElement {
                _ = snapWindow(axElement, to: zone)
            }
        }
        
        highlightedZone = nil
        hideOverlay()
    }
    
    /// Show visual overlay for snap zone
    @MainActor
    private func showSnapOverlay(for zone: SnapZone) {
        hideOverlay()
        
        // Create overlay window
        let overlay = NSWindow(
            contentRect: zone.targetRect,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        
        overlay.level = .floating
        overlay.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.2)
        overlay.isOpaque = false
        overlay.hasShadow = false
        overlay.ignoresMouseEvents = true
        
        // Add border
        if let contentView = overlay.contentView {
            contentView.wantsLayer = true
            contentView.layer?.borderColor = NSColor.systemBlue.withAlphaComponent(0.5).cgColor
            contentView.layer?.borderWidth = 2
            contentView.layer?.cornerRadius = 8
        }
        
        overlay.orderFront(nil)
        overlayWindow = overlay
    }
    
    /// Hide overlay
    @MainActor
    private func hideOverlay() {
        overlayWindow?.close()
        overlayWindow = nil
    }
}
