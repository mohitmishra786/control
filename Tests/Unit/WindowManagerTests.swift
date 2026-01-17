// Control Unit Tests
// WindowManager Tests

import XCTest
@testable import Control

final class WindowManagerTests: XCTestCase {
    
    func testWindowManagerSingleton() {
        let manager1 = WindowManager.shared
        let manager2 = WindowManager.shared
        XCTAssertTrue(manager1 === manager2, "WindowManager should be singleton")
    }
    
    func testDefaultZonesExist() {
        let manager = WindowManager.shared
        XCTAssertFalse(manager.defaultZones.isEmpty, "Default zones should exist")
        
        // Check for essential zones
        let zoneIds = manager.defaultZones.map { $0.id }
        XCTAssertTrue(zoneIds.contains("left_half"), "Should have left_half zone")
        XCTAssertTrue(zoneIds.contains("right_half"), "Should have right_half zone")
        XCTAssertTrue(zoneIds.contains("maximize"), "Should have maximize zone")
    }
    
    func testZoneFrameCalculation() {
        let zone = Zone(
            id: "test",
            name: "Test Zone",
            xRatio: 0,
            yRatio: 0,
            widthRatio: 0.5,
            heightRatio: 1.0
        )
        
        // Note: This test would require a mock NSScreen
        // Placeholder for actual implementation
        XCTAssertEqual(zone.widthRatio, 0.5)
        XCTAssertEqual(zone.heightRatio, 1.0)
    }
}
