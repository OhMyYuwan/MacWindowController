import Foundation

struct LayoutWindow: Codable {
    var bundleId: String
    var appName: String
    var title: String
    var windowNumber: Int?
    var frame: RectData
    var iconPath: String?
    var zoneName: String?  // Schema v2: which zone this window belongs to
}

struct LayoutStack: Codable {
    var name: String
    var frame: RectData
    var windows: [LayoutWindow]
    var activeIndex: Int
    var zoneName: String?  // Schema v2: which zone this stack belongs to (usually same as name)
}

struct DesktopLayout: Codable {
    var schemaVersion: Int = 2
    var name: String
    var description: String
    var createdAt: Date
    var windows: [LayoutWindow]
    var stacks: [LayoutStack]
    var partition: DesktopPartitionSnapshot?  // Schema v2: partition distribution
}

struct DesktopLayoutListResponse: Codable {
    var desktops: [DesktopLayout]
}

