import Foundation

struct LayoutWindow: Codable {
    var bundleId: String
    var appName: String
    var title: String
    var windowNumber: Int?
    var frame: RectData
    var iconPath: String?
}

struct LayoutStack: Codable {
    var name: String
    var frame: RectData
    var windows: [LayoutWindow]
    var activeIndex: Int
}

struct DesktopLayout: Codable {
    var name: String
    var description: String
    var createdAt: Date
    var windows: [LayoutWindow]
    var stacks: [LayoutStack]
}

struct DesktopLayoutListResponse: Codable {
    var desktops: [DesktopLayout]
}

