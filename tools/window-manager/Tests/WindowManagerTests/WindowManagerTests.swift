import CoreGraphics
import XCTest
@testable import WindowManager

final class WindowManagerTests: XCTestCase {
    func testTilePositionParse() {
        XCTAssertEqual(TilePosition.parse("left"), .left)
        XCTAssertEqual(TilePosition.parse("top_left"), .topLeft)
        XCTAssertEqual(TilePosition.parse("bottom-right"), .bottomRight)
        XCTAssertNil(TilePosition.parse("unknown"))
    }

    func testLayoutEngineLeftAndRight() {
        let engine = LayoutEngine()
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let left = engine.frame(for: .left, in: screen)
        let right = engine.frame(for: .right, in: screen)

        XCTAssertEqual(left, CGRect(x: 0, y: 0, width: 960, height: 1080))
        XCTAssertEqual(right, CGRect(x: 960, y: 0, width: 960, height: 1080))
    }
}

