import CoreGraphics
import Foundation

struct RectData: Codable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(_ rect: CGRect) {
        self.x = Double(rect.origin.x)
        self.y = Double(rect.origin.y)
        self.width = Double(rect.width)
        self.height = Double(rect.height)
    }

    var cgRect: CGRect {
        CGRect(
            x: x,
            y: y,
            width: width,
            height: height
        )
    }
}

struct WindowIdentity: Codable, Hashable {
    var bundleId: String
    var title: String
    var windowNumber: Int?
}

struct WindowInfo: Codable {
    static let unknownBundleId = "unknown.bundle"

    var bundleId: String
    var appName: String
    var pid: Int32
    var windowNumber: Int
    var title: String
    var frame: RectData
    var isOnScreen: Bool

    var isControllable: Bool {
        !bundleId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && bundleId != Self.unknownBundleId
            && windowNumber >= 0
    }
}
