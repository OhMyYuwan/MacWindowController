import CoreGraphics
import Foundation

struct DesktopZone {
    let name: String
    let frame: CGRect
    var windows: [WindowInfo] = []

    var isStack: Bool { windows.count >= threshold }
    var threshold: Int = 3
}

struct DesktopZoneScanResult {
    let zones: [DesktopZone]
    let screenFrame: CGRect
}

final class DesktopZoneManager {
    private let windowController: WindowController
    private let screenManager: ScreenManager
    private let stackManager: StackManager
    private let layoutEngine: LayoutEngine
    private var config: DesktopConfig

    /// Custom split ratios (0~1). nil = use 0.5 (equal split)
    var splitX: CGFloat = 0.5
    var splitY: CGFloat = 0.5

    init(
        windowController: WindowController,
        screenManager: ScreenManager,
        stackManager: StackManager,
        layoutEngine: LayoutEngine = LayoutEngine(),
        config: DesktopConfig = .load()
    ) {
        self.windowController = windowController
        self.screenManager = screenManager
        self.stackManager = stackManager
        self.layoutEngine = layoutEngine
        self.config = config
    }

    var stackThreshold: Int {
        get { config.stackThreshold }
        set {
            config.stackThreshold = newValue
            try? config.save()
        }
    }

    // MARK: - Scan & Auto-assign

    /// Scan all on-screen windows and assign them to zones based on center point
    func scan(mergeMode: DesktopMergeMode) -> DesktopZoneScanResult {
        let screenFrame = screenManager.mainVisibleFrameInScreenCoordinates()
        let zoneDefinitions = defineZones(for: mergeMode, in: screenFrame)
        let windows = windowController.listWindows(onScreenOnly: true)

        var zones = zoneDefinitions.map { def in
            var zone = def
            zone.threshold = config.stackThreshold
            return zone
        }

        for window in windows {
            let center = CGPoint(
                x: window.frame.cgRect.midX,
                y: window.frame.cgRect.midY
            )
            if let bestIndex = closestZoneIndex(for: center, in: zones) {
                zones[bestIndex].windows.append(window)
            }
        }

        return DesktopZoneScanResult(zones: zones, screenFrame: screenFrame)
    }

    /// Current zone geometry for the selected merge mode.
    func zoneDefinitions(mergeMode: DesktopMergeMode) -> [DesktopZone] {
        let screenFrame = screenManager.mainVisibleFrameInScreenCoordinates()
        return defineZones(for: mergeMode, in: screenFrame)
    }

    /// Find closest/current zone for a point in AX/screen coordinates.
    func zoneFor(point: CGPoint, mergeMode: DesktopMergeMode) -> DesktopZone? {
        let zones = zoneDefinitions(mergeMode: mergeMode)
        guard let idx = closestZoneIndex(for: point, in: zones) else { return nil }
        return zones[idx]
    }

    /// Apply scan result: create stacks for zones that exceed threshold,
    /// resize single windows to fill their zone
    func applyScanResult(_ result: DesktopZoneScanResult) throws {
        for zone in result.zones {
            if zone.windows.isEmpty { continue }

            if zone.isStack {
                try applyStackZone(zone)
            } else {
                try applySingleZone(zone)
            }
        }
    }

    /// One-shot: scan + apply, clearing any stacks that conflict with the new zones
    func autoAssign(mergeMode: DesktopMergeMode) throws {
        let result = scan(mergeMode: mergeMode)
        let newZoneNames = Set(result.zones.map(\.name))
        for stack in stackManager.listStacks() where !newZoneNames.contains(stack.name) {
            try? stackManager.deleteStack(name: stack.name)
        }
        try applyScanResult(result)
    }

    // MARK: - Zone Definitions

    private func defineZones(for mode: DesktopMergeMode, in screenFrame: CGRect) -> [DesktopZone] {
        let xSplit = screenFrame.minX + screenFrame.width * splitX
        let ySplit = screenFrame.minY + screenFrame.height * splitY

        let leftW = xSplit - screenFrame.minX
        let rightW = screenFrame.maxX - xSplit
        let topH = ySplit - screenFrame.minY
        let bottomH = screenFrame.maxY - ySplit

        let tl = CGRect(x: screenFrame.minX, y: screenFrame.minY, width: leftW, height: topH)
        let tr = CGRect(x: xSplit, y: screenFrame.minY, width: rightW, height: topH)
        let bl = CGRect(x: screenFrame.minX, y: ySplit, width: leftW, height: bottomH)
        let br = CGRect(x: xSplit, y: ySplit, width: rightW, height: bottomH)

        switch mode {
        case .grid:
            return [
                DesktopZone(name: "top-left", frame: tl),
                DesktopZone(name: "top-right", frame: tr),
                DesktopZone(name: "bottom-left", frame: bl),
                DesktopZone(name: "bottom-right", frame: br),
            ]
        case .leftColumn:
            let left = CGRect(x: screenFrame.minX, y: screenFrame.minY, width: leftW, height: screenFrame.height)
            return [
                DesktopZone(name: "left", frame: left),
                DesktopZone(name: "top-right", frame: tr),
                DesktopZone(name: "bottom-right", frame: br),
            ]
        case .rightColumn:
            let right = CGRect(x: xSplit, y: screenFrame.minY, width: rightW, height: screenFrame.height)
            return [
                DesktopZone(name: "top-left", frame: tl),
                DesktopZone(name: "bottom-left", frame: bl),
                DesktopZone(name: "right", frame: right),
            ]
        case .topRow:
            let top = CGRect(x: screenFrame.minX, y: screenFrame.minY, width: screenFrame.width, height: topH)
            return [
                DesktopZone(name: "top", frame: top),
                DesktopZone(name: "bottom-left", frame: bl),
                DesktopZone(name: "bottom-right", frame: br),
            ]
        case .bottomRow:
            let bottom = CGRect(x: screenFrame.minX, y: ySplit, width: screenFrame.width, height: bottomH)
            return [
                DesktopZone(name: "top-left", frame: tl),
                DesktopZone(name: "top-right", frame: tr),
                DesktopZone(name: "bottom", frame: bottom),
            ]
        case .leftRight:
            let left = CGRect(x: screenFrame.minX, y: screenFrame.minY, width: leftW, height: screenFrame.height)
            let right = CGRect(x: xSplit, y: screenFrame.minY, width: rightW, height: screenFrame.height)
            return [
                DesktopZone(name: "left", frame: left),
                DesktopZone(name: "right", frame: right),
            ]
        case .topBottom:
            let top = CGRect(x: screenFrame.minX, y: screenFrame.minY, width: screenFrame.width, height: topH)
            let bottom = CGRect(x: screenFrame.minX, y: ySplit, width: screenFrame.width, height: bottomH)
            return [
                DesktopZone(name: "top", frame: top),
                DesktopZone(name: "bottom", frame: bottom),
            ]
        case .threeColumns:
            let thirdW = screenFrame.width / 3
            let c1 = CGRect(x: screenFrame.minX, y: screenFrame.minY, width: thirdW, height: screenFrame.height)
            let c2 = CGRect(x: screenFrame.minX + thirdW, y: screenFrame.minY, width: thirdW, height: screenFrame.height)
            let c3 = CGRect(x: screenFrame.minX + thirdW * 2, y: screenFrame.minY, width: thirdW, height: screenFrame.height)
            return [
                DesktopZone(name: "col-left", frame: c1),
                DesktopZone(name: "col-center", frame: c2),
                DesktopZone(name: "col-right", frame: c3),
            ]
        case .threeRows:
            let thirdH = screenFrame.height / 3
            let r1 = CGRect(x: screenFrame.minX, y: screenFrame.minY, width: screenFrame.width, height: thirdH)
            let r2 = CGRect(x: screenFrame.minX, y: screenFrame.minY + thirdH, width: screenFrame.width, height: thirdH)
            let r3 = CGRect(x: screenFrame.minX, y: screenFrame.minY + thirdH * 2, width: screenFrame.width, height: thirdH)
            return [
                DesktopZone(name: "row-top", frame: r1),
                DesktopZone(name: "row-center", frame: r2),
                DesktopZone(name: "row-bottom", frame: r3),
            ]
        }
    }

    private func closestZoneIndex(for point: CGPoint, in zones: [DesktopZone]) -> Int? {
        guard !zones.isEmpty else { return nil }

        // First try: point is inside a zone
        for (index, zone) in zones.enumerated() {
            if zone.frame.contains(point) {
                return index
            }
        }

        // Fallback: closest zone by distance to center
        var bestIndex = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (index, zone) in zones.enumerated() {
            let zoneCenter = CGPoint(x: zone.frame.midX, y: zone.frame.midY)
            let dx = point.x - zoneCenter.x
            let dy = point.y - zoneCenter.y
            let distance = dx * dx + dy * dy
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }

    // MARK: - Apply Logic

    private func applyStackZone(_ zone: DesktopZone) throws {
        for window in zone.windows {
            let identity = WindowIdentity(
                bundleId: window.bundleId,
                title: window.title,
                windowNumber: window.windowNumber
            )
            do {
                _ = try stackManager.putWindowInStack(
                    name: zone.name,
                    frame: zone.frame,
                    window: identity
                )
            } catch {
                NSLog("auto-scan: skip \(window.bundleId) #\(window.windowNumber): \(error.localizedDescription)")
            }
        }
    }

    private func applySingleZone(_ zone: DesktopZone) throws {
        for window in zone.windows {
            do {
                try windowController.setWindowFrame(
                    bundleId: window.bundleId,
                    windowNumber: window.windowNumber,
                    frame: zone.frame
                )
            } catch {
                NSLog("auto-scan: skip \(window.bundleId) #\(window.windowNumber): \(error.localizedDescription)")
            }
        }
    }
}
