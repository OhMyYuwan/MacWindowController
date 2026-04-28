import CoreGraphics
import Foundation
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

    func testCurrentProcessWindowIsNotControllable() {
        let window = WindowInfo(
            bundleId: "com.ohmyyuwan.WinCtlManager",
            appName: "WinCtlManager",
            pid: ProcessInfo.processInfo.processIdentifier,
            windowNumber: 42,
            title: "Workbench",
            frame: RectData(x: 0, y: 0, width: 640, height: 480),
            isOnScreen: true
        )

        XCTAssertTrue(window.isCurrentProcess)
        XCTAssertFalse(window.isControllable)
    }

    func testWindowIdentityTabTitleUsesWindowTitleAndAppName() {
        let identity = WindowIdentity(
            bundleId: "com.google.Chrome",
            title: "A very long project planning document",
            windowNumber: 10,
            appName: "Google Chrome"
        )

        XCTAssertEqual(
            identity.tabDisplayTitle(maxWindowTitleLength: 12, maxAppNameLength: 14),
            "A very long... - Google Chrome"
        )
        XCTAssertEqual(
            identity.fullDisplayTitle,
            "A very long project planning document - Google Chrome"
        )
    }

    func testWindowIdentityTabTitleFallsBackToAppName() {
        let identity = WindowIdentity(
            bundleId: "com.apple.finder",
            title: "",
            windowNumber: 2,
            appName: "Finder"
        )

        XCTAssertEqual(identity.tabDisplayTitle(), "Finder")
        XCTAssertEqual(identity.fullDisplayTitle, "Finder")
    }

    func testWindowIdentityDecodesLegacyStacksWithoutAppName() throws {
        let data = """
        {
          "bundleId": "com.google.Chrome",
          "title": "Docs",
          "windowNumber": 7
        }
        """.data(using: .utf8)!

        let identity = try JSONDecoder().decode(WindowIdentity.self, from: data)

        XCTAssertNil(identity.appName)
        XCTAssertEqual(identity.displayAppName, "com.google.Chrome")
        XCTAssertEqual(identity.fullDisplayTitle, "Docs - com.google.Chrome")
    }
}
