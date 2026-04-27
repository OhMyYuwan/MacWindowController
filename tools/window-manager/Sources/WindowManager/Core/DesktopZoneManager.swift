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

@MainActor
final class DesktopZoneManager {
    private let windowController: WindowController
    private let screenManager: ScreenManager
    private let stackManager: StackManager
    private let layoutEngine: LayoutEngine
    private var config: DesktopConfig
    private weak var partitionState: DesktopPartitionState?

    /// Gap between zones in points — creates visible separation and room for drag handles
    static let zoneGap: CGFloat = 8

    /// Custom split ratios (0~1), default 0.5. Backed by partitionState if available.
    var splitX: CGFloat {
        get { partitionState?.splitX ?? _splitX }
        set {
            _splitX = newValue
            partitionState?.splitX = newValue
        }
    }
    var splitY: CGFloat {
        get { partitionState?.splitY ?? _splitY }
        set {
            _splitY = newValue
            partitionState?.splitY = newValue
        }
    }
    private var _splitX: CGFloat = 0.5
    private var _splitY: CGFloat = 0.5

    init(
        windowController: WindowController,
        screenManager: ScreenManager,
        stackManager: StackManager,
        layoutEngine: LayoutEngine = LayoutEngine(),
        config: DesktopConfig = .load(),
        partitionState: DesktopPartitionState? = nil
    ) {
        self.windowController = windowController
        self.screenManager = screenManager
        self.stackManager = stackManager
        self.layoutEngine = layoutEngine
        self.config = config
        self.partitionState = partitionState
    }

    var stackThreshold: Int {
        get { partitionState?.stackThreshold ?? config.stackThreshold }
        set {
            config.stackThreshold = newValue
            partitionState?.stackThreshold = newValue
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

        // Gap between zones — leaves room for the desktop drag handles and prevents
        // window edges from sitting directly on the divider line.
        let zoneGap: CGFloat = Self.zoneGap

        let leftW = xSplit - screenFrame.minX
        let rightW = screenFrame.maxX - xSplit
        let topH = ySplit - screenFrame.minY
        let bottomH = screenFrame.maxY - ySplit

        // Build raw rects, then inset each toward the divider sides by gap/2
        func insetTL(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX, y: r.minY, width: max(40, r.width - zoneGap / 2), height: max(40, r.height - zoneGap / 2))
        }
        func insetTR(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX + zoneGap / 2, y: r.minY, width: max(40, r.width - zoneGap / 2), height: max(40, r.height - zoneGap / 2))
        }
        func insetBL(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX, y: r.minY + zoneGap / 2, width: max(40, r.width - zoneGap / 2), height: max(40, r.height - zoneGap / 2))
        }
        func insetBR(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX + zoneGap / 2, y: r.minY + zoneGap / 2, width: max(40, r.width - zoneGap / 2), height: max(40, r.height - zoneGap / 2))
        }
        func insetLeftHalf(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX, y: r.minY, width: max(40, r.width - zoneGap / 2), height: r.height)
        }
        func insetRightHalf(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX + zoneGap / 2, y: r.minY, width: max(40, r.width - zoneGap / 2), height: r.height)
        }
        func insetTopHalf(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX, y: r.minY, width: r.width, height: max(40, r.height - zoneGap / 2))
        }
        func insetBottomHalf(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX, y: r.minY + zoneGap / 2, width: r.width, height: max(40, r.height - zoneGap / 2))
        }

        let tl = CGRect(x: screenFrame.minX, y: screenFrame.minY, width: leftW, height: topH)
        let tr = CGRect(x: xSplit, y: screenFrame.minY, width: rightW, height: topH)
        let bl = CGRect(x: screenFrame.minX, y: ySplit, width: leftW, height: bottomH)
        let br = CGRect(x: xSplit, y: ySplit, width: rightW, height: bottomH)

        switch mode {
        case .grid:
            return [
                DesktopZone(name: "top-left", frame: insetTL(tl)),
                DesktopZone(name: "top-right", frame: insetTR(tr)),
                DesktopZone(name: "bottom-left", frame: insetBL(bl)),
                DesktopZone(name: "bottom-right", frame: insetBR(br)),
            ]
        case .leftColumn:
            let left = CGRect(x: screenFrame.minX, y: screenFrame.minY, width: leftW, height: screenFrame.height)
            return [
                DesktopZone(name: "left", frame: insetLeftHalf(left)),
                DesktopZone(name: "top-right", frame: insetTR(tr)),
                DesktopZone(name: "bottom-right", frame: insetBR(br)),
            ]
        case .rightColumn:
            let right = CGRect(x: xSplit, y: screenFrame.minY, width: rightW, height: screenFrame.height)
            return [
                DesktopZone(name: "top-left", frame: insetTL(tl)),
                DesktopZone(name: "bottom-left", frame: insetBL(bl)),
                DesktopZone(name: "right", frame: insetRightHalf(right)),
            ]
        case .topRow:
            let top = CGRect(x: screenFrame.minX, y: screenFrame.minY, width: screenFrame.width, height: topH)
            return [
                DesktopZone(name: "top", frame: insetTopHalf(top)),
                DesktopZone(name: "bottom-left", frame: insetBL(bl)),
                DesktopZone(name: "bottom-right", frame: insetBR(br)),
            ]
        case .bottomRow:
            let bottom = CGRect(x: screenFrame.minX, y: ySplit, width: screenFrame.width, height: bottomH)
            return [
                DesktopZone(name: "top-left", frame: insetTL(tl)),
                DesktopZone(name: "top-right", frame: insetTR(tr)),
                DesktopZone(name: "bottom", frame: insetBottomHalf(bottom)),
            ]
        case .leftRight:
            let left = CGRect(x: screenFrame.minX, y: screenFrame.minY, width: leftW, height: screenFrame.height)
            let right = CGRect(x: xSplit, y: screenFrame.minY, width: rightW, height: screenFrame.height)
            return [
                DesktopZone(name: "left", frame: insetLeftHalf(left)),
                DesktopZone(name: "right", frame: insetRightHalf(right)),
            ]
        case .topBottom:
            let top = CGRect(x: screenFrame.minX, y: screenFrame.minY, width: screenFrame.width, height: topH)
            let bottom = CGRect(x: screenFrame.minX, y: ySplit, width: screenFrame.width, height: bottomH)
            return [
                DesktopZone(name: "top", frame: insetTopHalf(top)),
                DesktopZone(name: "bottom", frame: insetBottomHalf(bottom)),
            ]
        case .threeColumns:
            let thirdW = screenFrame.width / 3
            let c1 = CGRect(x: screenFrame.minX, y: screenFrame.minY, width: thirdW - zoneGap / 2, height: screenFrame.height)
            let c2 = CGRect(x: screenFrame.minX + thirdW + zoneGap / 2, y: screenFrame.minY, width: thirdW - zoneGap, height: screenFrame.height)
            let c3 = CGRect(x: screenFrame.minX + thirdW * 2 + zoneGap / 2, y: screenFrame.minY, width: thirdW - zoneGap / 2, height: screenFrame.height)
            return [
                DesktopZone(name: "col-left", frame: c1),
                DesktopZone(name: "col-center", frame: c2),
                DesktopZone(name: "col-right", frame: c3),
            ]
        case .threeRows:
            let thirdH = screenFrame.height / 3
            let r1 = CGRect(x: screenFrame.minX, y: screenFrame.minY, width: screenFrame.width, height: thirdH - zoneGap / 2)
            let r2 = CGRect(x: screenFrame.minX, y: screenFrame.minY + thirdH + zoneGap / 2, width: screenFrame.width, height: thirdH - zoneGap)
            let r3 = CGRect(x: screenFrame.minX, y: screenFrame.minY + thirdH * 2 + zoneGap / 2, width: screenFrame.width, height: thirdH - zoneGap / 2)
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

    /// Determine current zone membership for visible windows.
    func currentZoneAssignments(windows: [WindowInfo], mergeMode: DesktopMergeMode) -> [Int: String] {
        var assignments: [Int: String] = [:]
        for window in windows {
            let center = CGPoint(x: window.frame.cgRect.midX, y: window.frame.cgRect.midY)
            if let zone = zoneFor(point: center, mergeMode: mergeMode) {
                assignments[window.windowNumber] = zone.name
            }
        }
        return assignments
    }

    /// Apply forced zone behavior based on current assignments and threshold.
    func applyForcedZones(windows: [WindowInfo], mergeMode: DesktopMergeMode) throws {
        let zoneDefs = zoneDefinitions(mergeMode: mergeMode)
        let assignments = currentZoneAssignments(windows: windows, mergeMode: mergeMode)
        let windowsByZone = Dictionary(grouping: windows) { assignments[$0.windowNumber] ?? "unassigned" }

        // Remove stacks for zones that are no longer above threshold
        for stack in stackManager.listStacks() {
            let zoneWindows = windowsByZone[stack.name] ?? []
            if zoneWindows.count <= stackThreshold {
                try? stackManager.deleteStack(name: stack.name)
            }
        }

        for zone in zoneDefs {
            let zoneWindows = windowsByZone[zone.name] ?? []
            guard !zoneWindows.isEmpty else { continue }

            if zoneWindows.count > stackThreshold {
                // Stack behavior
                for window in zoneWindows {
                    let identity = WindowIdentity(
                        bundleId: window.bundleId,
                        title: window.title,
                        windowNumber: window.windowNumber
                    )
                    _ = try? stackManager.putWindowInStack(name: zone.name, frame: zone.frame, window: identity)
                }
            } else {
                // Ordinary behavior: all windows fill the full zone frame
                try? stackManager.deleteStack(name: zone.name)
                for window in zoneWindows {
                    try? windowController.setWindowFrame(
                        bundleId: window.bundleId,
                        windowNumber: window.windowNumber,
                        frame: zone.frame
                    )
                }
            }
        }
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
