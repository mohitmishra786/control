// Control Unit Tests
// CornerGrabFixer Tests

import XCTest
@testable import Control

final class CornerGrabFixerTests: XCTestCase {
    
    func testDefaultConfiguration() {
        let config = CornerGrabConfig()
        
        XCTAssertEqual(config.precisionPixels, 1, "Default precision should be 1px")
        XCTAssertEqual(config.hitBoxExtension, 5, "Default hit-box extension should be 5px")
        XCTAssertEqual(config.systemCornerRadius, 20, "Default corner radius should be 20px")
        XCTAssertTrue(config.isEnabled, "Should be enabled by default")
    }
    
    func testHitBoxVerification() {
        // Verification check as per verification.md
        // "Ensure WindowManager includes the logic for the 5px invisible hit-box"
        let fixer = CornerGrabFixer()
        XCTAssertTrue(fixer.verifyHitBoxConfiguration(), "Hit-box should be 5px")
    }
    
    func testWindowEdgeCornerDetection() {
        XCTAssertTrue(WindowEdge.topLeft.isCorner, "topLeft should be corner")
        XCTAssertTrue(WindowEdge.topRight.isCorner, "topRight should be corner")
        XCTAssertTrue(WindowEdge.bottomLeft.isCorner, "bottomLeft should be corner")
        XCTAssertTrue(WindowEdge.bottomRight.isCorner, "bottomRight should be corner")
        
        XCTAssertFalse(WindowEdge.top.isCorner, "top should not be corner")
        XCTAssertFalse(WindowEdge.bottom.isCorner, "bottom should not be corner")
        XCTAssertFalse(WindowEdge.left.isCorner, "left should not be corner")
        XCTAssertFalse(WindowEdge.right.isCorner, "right should not be corner")
        XCTAssertFalse(WindowEdge.none.isCorner, "none should not be corner")
    }
    
    func testFixerInitialState() {
        let fixer = CornerGrabFixer()
        XCTAssertFalse(fixer.isActive, "Fixer should not be active initially")
    }
}
