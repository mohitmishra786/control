// Control - macOS Power User Interaction Manager
// Icon Normalizer
//
// Normalizes app icons using shape masks and caching.

import AppKit
import Foundation

// MARK: - Icon Shape

/// Icon shape masks for normalization
public enum IconShape: String, Sendable {
    case roundedSquare = "rounded_square"
    case circle = "circle"
    case squircle = "squircle"
    case square = "square"
}

// MARK: - Icon Cache Entry

/// Cached normalized icon
private struct IconCacheEntry {
    let originalHash: Int
    let normalizedIcon: NSImage
    let timestamp: Date
}

// MARK: - Icon Normalizer

/// Normalizes app icons with consistent shapes
///
/// Features:
/// - Shape mask application (rounded rect, circle, squircle)
/// - Icon caching for performance
/// - Batch processing for Dock icons
public final class IconNormalizer: @unchecked Sendable {
    
    // MARK: - Singleton
    
    public static let shared = IconNormalizer()
    
    // MARK: - Properties
    
    /// Default shape for normalization
    public var defaultShape: IconShape = .roundedSquare
    
    /// Corner radius ratio (0-1, relative to icon size)
    public var cornerRadiusRatio: CGFloat = 0.22
    
    /// Icon cache
    private var cache: [String: IconCacheEntry] = [:]
    private let cacheLock = NSLock()
    
    /// Cache TTL (seconds)
    private let cacheTTL: TimeInterval = 3600  // 1 hour
    
    /// Maximum cache size
    private let maxCacheSize = 100
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Normalize an icon to the default shape
    public func normalize(_ icon: NSImage, bundleId: String? = nil) -> NSImage {
        return normalize(icon, to: defaultShape, bundleId: bundleId)
    }
    
    /// Normalize an icon to a specific shape
    public func normalize(_ icon: NSImage, to shape: IconShape, bundleId: String? = nil) -> NSImage {
        // Check cache
        if let bundleId = bundleId {
            cacheLock.lock()
            if let cached = cache[bundleId],
               Date().timeIntervalSince(cached.timestamp) < cacheTTL {
                cacheLock.unlock()
                return cached.normalizedIcon
            }
            cacheLock.unlock()
        }
        
        // Normalize
        let normalized: NSImage
        
        switch shape {
        case .roundedSquare:
            normalized = applyRoundedSquareMask(to: icon)
        case .circle:
            normalized = applyCircleMask(to: icon)
        case .squircle:
            normalized = applySquircleMask(to: icon)
        case .square:
            normalized = icon  // No mask
        }
        
        // Cache result
        if let bundleId = bundleId {
            cacheLock.lock()
            
            // Evict old entries if cache is full
            if cache.count >= maxCacheSize {
                evictOldestEntry()
            }
            
            cache[bundleId] = IconCacheEntry(
                originalHash: icon.hashValue,
                normalizedIcon: normalized,
                timestamp: Date()
            )
            cacheLock.unlock()
        }
        
        return normalized
    }
    
    /// Get normalized icon for an app
    public func normalizedIcon(forApp bundleId: String) -> NSImage? {
        guard let icon = iconForApp(bundleId) else { return nil }
        return normalize(icon, bundleId: bundleId)
    }
    
    /// Clear the icon cache
    public func clearCache() {
        cacheLock.lock()
        cache.removeAll()
        cacheLock.unlock()
        
        log.info("Icon cache cleared")
    }
    
    /// Preload icons for running applications
    public func preloadRunningApps() {
        Task.detached { [weak self] in
            let apps = NSWorkspace.shared.runningApplications
            
            for app in apps {
                guard let bundleId = app.bundleIdentifier,
                      let icon = app.icon else { continue }
                
                _ = self?.normalize(icon, bundleId: bundleId)
            }
            
            await MainActor.run {
                log.info("Preloaded icons for \(apps.count) running apps")
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// Get icon for an app by bundle ID
    private func iconForApp(_ bundleId: String) -> NSImage? {
        guard let path = NSWorkspace.shared.absolutePathForApplication(
            withBundleIdentifier: bundleId
        ) else {
            return nil
        }
        
        return NSWorkspace.shared.icon(forFile: path)
    }
    
    /// Apply rounded square mask
    private func applyRoundedSquareMask(to icon: NSImage) -> NSImage {
        let size = icon.size
        let cornerRadius = min(size.width, size.height) * cornerRadiusRatio
        
        let result = NSImage(size: size)
        result.lockFocus()
        
        let path = NSBezierPath(
            roundedRect: NSRect(origin: .zero, size: size),
            xRadius: cornerRadius,
            yRadius: cornerRadius
        )
        path.addClip()
        
        icon.draw(in: NSRect(origin: .zero, size: size))
        
        result.unlockFocus()
        return result
    }
    
    /// Apply circle mask
    private func applyCircleMask(to icon: NSImage) -> NSImage {
        let size = icon.size
        let diameter = min(size.width, size.height)
        
        let result = NSImage(size: size)
        result.lockFocus()
        
        let path = NSBezierPath(ovalIn: NSRect(
            x: (size.width - diameter) / 2,
            y: (size.height - diameter) / 2,
            width: diameter,
            height: diameter
        ))
        path.addClip()
        
        icon.draw(in: NSRect(origin: .zero, size: size))
        
        result.unlockFocus()
        return result
    }
    
    /// Apply squircle (superellipse) mask
    private func applySquircleMask(to icon: NSImage) -> NSImage {
        let size = icon.size
        
        let result = NSImage(size: size)
        result.lockFocus()
        
        // Approximate squircle using bezier curve
        let path = createSquirclePath(in: NSRect(origin: .zero, size: size))
        path.addClip()
        
        icon.draw(in: NSRect(origin: .zero, size: size))
        
        result.unlockFocus()
        return result
    }
    
    /// Create a squircle (superellipse) path
    private func createSquirclePath(in rect: NSRect) -> NSBezierPath {
        let path = NSBezierPath()
        let w = rect.width
        let h = rect.height
        let c = min(w, h) * 0.18  // Control point offset
        
        // Start from top-left
        path.move(to: NSPoint(x: 0, y: h * 0.5))
        
        // Top-left corner
        path.curve(to: NSPoint(x: w * 0.5, y: h),
                   controlPoint1: NSPoint(x: 0, y: h - c),
                   controlPoint2: NSPoint(x: c, y: h))
        
        // Top-right corner
        path.curve(to: NSPoint(x: w, y: h * 0.5),
                   controlPoint1: NSPoint(x: w - c, y: h),
                   controlPoint2: NSPoint(x: w, y: h - c))
        
        // Bottom-right corner
        path.curve(to: NSPoint(x: w * 0.5, y: 0),
                   controlPoint1: NSPoint(x: w, y: c),
                   controlPoint2: NSPoint(x: w - c, y: 0))
        
        // Bottom-left corner
        path.curve(to: NSPoint(x: 0, y: h * 0.5),
                   controlPoint1: NSPoint(x: c, y: 0),
                   controlPoint2: NSPoint(x: 0, y: c))
        
        path.close()
        return path
    }
    
    /// Evict oldest cache entry
    private func evictOldestEntry() {
        guard let oldest = cache.min(by: { $0.value.timestamp < $1.value.timestamp }) else {
            return
        }
        cache.removeValue(forKey: oldest.key)
    }
}
