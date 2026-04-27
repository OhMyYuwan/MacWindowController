import Foundation

struct LayoutWindow: Codable {
    var bundleId: String
    var appName: String
    var title: String
    var windowNumber: Int?
    var frame: RectData
    var iconPath: String?
    var zoneName: String?  // Schema v2: which zone this window belongs to
    var browserURL: String?  // Schema v3: restorable browser page URL
    var browserKind: String?  // Schema v3: chrome, safari, edge, arc, etc.
}

struct LayoutStack: Codable {
    var name: String
    var frame: RectData
    var windows: [LayoutWindow]
    var activeIndex: Int
    var zoneName: String?  // Schema v2: which zone this stack belongs to (usually same as name)
}

struct DesktopLayout: Codable {
    var schemaVersion: Int = 3
    var name: String
    var description: String
    var createdAt: Date
    var windows: [LayoutWindow]
    var stacks: [LayoutStack]
    var partition: DesktopPartitionSnapshot?  // Schema v2: partition distribution
    var preferredDisplay: LayoutDisplaySnapshot?  // Schema v3: display used when saving
}

struct LayoutDisplaySnapshot: Codable, Hashable {
    var id: UInt32
    var index: Int
    var name: String
    var frame: RectData
    var visibleFrame: RectData
}

struct DesktopLayoutListResponse: Codable {
    var desktops: [DesktopLayout]
}
