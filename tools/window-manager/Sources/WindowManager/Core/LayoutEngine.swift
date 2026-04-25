import CoreGraphics
import Foundation

struct LayoutEngine {
    func frame(for position: TilePosition, in screenFrame: CGRect) -> CGRect {
        let halfWidth = screenFrame.width / 2.0
        let halfHeight = screenFrame.height / 2.0

        switch position {
        case .left:
            return CGRect(x: screenFrame.minX, y: screenFrame.minY, width: halfWidth, height: screenFrame.height)
        case .right:
            return CGRect(x: screenFrame.minX + halfWidth, y: screenFrame.minY, width: halfWidth, height: screenFrame.height)
        case .top:
            return CGRect(x: screenFrame.minX, y: screenFrame.minY + halfHeight, width: screenFrame.width, height: halfHeight)
        case .bottom:
            return CGRect(x: screenFrame.minX, y: screenFrame.minY, width: screenFrame.width, height: halfHeight)
        case .fullscreen:
            return screenFrame
        case .topLeft:
            return CGRect(x: screenFrame.minX, y: screenFrame.minY + halfHeight, width: halfWidth, height: halfHeight)
        case .topRight:
            return CGRect(x: screenFrame.minX + halfWidth, y: screenFrame.minY + halfHeight, width: halfWidth, height: halfHeight)
        case .bottomLeft:
            return CGRect(x: screenFrame.minX, y: screenFrame.minY, width: halfWidth, height: halfHeight)
        case .bottomRight:
            return CGRect(x: screenFrame.minX + halfWidth, y: screenFrame.minY, width: halfWidth, height: halfHeight)
        }
    }
}

