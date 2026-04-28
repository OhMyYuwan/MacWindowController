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
        if let direct = TilePosition(rawValue: normalized) {
            return direct
        }

        // Friendly aliases for block-style naming.
        switch normalized {
        case "left-up", "left-top", "lu", "lt":
            return .topLeft
        case "left-down", "left-bottom", "ld", "lb":
            return .bottomLeft
        case "right-up", "right-top", "ru", "rt":
            return .topRight
        case "right-down", "right-bottom", "rd", "rb":
            return .bottomRight
        default:
            return nil
        }
    }
}
