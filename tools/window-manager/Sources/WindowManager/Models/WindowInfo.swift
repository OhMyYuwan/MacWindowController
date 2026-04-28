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
    var appName: String? = nil

    var displayAppName: String {
        let trimmed = (appName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return bundleId
    }

    var fullDisplayTitle: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty {
            return displayAppName
        }
        return "\(trimmedTitle) - \(displayAppName)"
    }

    func tabDisplayTitle(maxWindowTitleLength: Int = 18, maxAppNameLength: Int = 14) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let clippedAppName = Self.clipped(displayAppName, maxLength: maxAppNameLength)
        guard !trimmedTitle.isEmpty else {
            return clippedAppName
        }
        return "\(Self.clipped(trimmedTitle, maxLength: maxWindowTitleLength)) - \(clippedAppName)"
    }

    private static func clipped(_ value: String, maxLength: Int) -> String {
        guard maxLength > 1 else { return String(value.prefix(max(0, maxLength))) }
        guard value.count > maxLength else { return value }
        return "\(value.prefix(maxLength - 1))..."
    }
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

    var isCurrentProcess: Bool {
        pid == ProcessInfo.processInfo.processIdentifier
    }

    var isControllable: Bool {
        !bundleId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && bundleId != Self.unknownBundleId
            && windowNumber >= 0
            && !isCurrentProcess
    }
}
