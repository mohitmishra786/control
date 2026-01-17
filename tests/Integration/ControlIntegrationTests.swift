// Control Integration Tests
// Placeholder for integration tests

import XCTest
@testable import Control
@testable import ControlKit

final class ControlIntegrationTests: XCTestCase {
    
    func testControlKitVersion() {
        XCTAssertEqual(ControlKit.version, "0.1.0")
    }
    
    func testBuildInfo() {
        let buildInfo = ControlKit.buildInfo
        XCTAssertEqual(buildInfo.platform, "macOS")
        XCTAssertTrue(["arm64", "x86_64"].contains(buildInfo.architecture))
    }
}
