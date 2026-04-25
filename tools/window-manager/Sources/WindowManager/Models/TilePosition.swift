import Foundation

enum TilePosition: String, Codable, CaseIterable {
    case left
    case right
    case top
    case bottom
    case fullscreen
    case topLeft = "top-left"
    case topRight = "top-right"
    case bottomLeft = "bottom-left"
    case bottomRight = "bottom-right"

    static func parse(_ value: String) -> TilePosition? {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
        return TilePosition(rawValue: normalized)
    }
}

