import Foundation

struct WindowStack: Codable {
    var name: String
    var frame: RectData
    var windows: [WindowIdentity]
    var activeIndex: Int
    var createdAt: Date
}

