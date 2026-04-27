import CoreGraphics
import Foundation

/// Shared partition state for both app canvas and desktop overlay.
/// Owned by DesktopWorkbenchRuntime and passed to views/managers.
@MainActor
final class DesktopPartitionState {
    var mergeMode: DesktopMergeMode
    var splitX: CGFloat
    var splitY: CGFloat
    var stackThreshold: Int

    /// Maps window number to zone name for forced zone membership
    var zoneAssignmentsByWindowNumber: [Int: String] = [:]

    init(
        mergeMode: DesktopMergeMode = .leftColumn,
        splitX: CGFloat = 0.5,
        splitY: CGFloat = 0.5,
        stackThreshold: Int = 3
    ) {
        self.mergeMode = mergeMode
        self.splitX = Self.clampSplit(splitX)
        self.splitY = Self.clampSplit(splitY)
        self.stackThreshold = max(1, stackThreshold)
    }

    func updateSplits(x: CGFloat, y: CGFloat) {
        splitX = Self.clampSplit(x)
        splitY = Self.clampSplit(y)
    }

    static func clampSplit(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 0.5 }
        return max(0.2, min(0.8, value))
    }
}

/// Snapshot of partition distribution for persistence
struct DesktopPartitionSnapshot: Codable {
    var mergeMode: Int  // DesktopMergeMode.rawValue
    var splitX: Double
    var splitY: Double
    var stackThreshold: Int

    @MainActor
    init(from state: DesktopPartitionState) {
        self.mergeMode = state.mergeMode.rawValue
        self.splitX = Double(state.splitX)
        self.splitY = Double(state.splitY)
        self.stackThreshold = state.stackThreshold
    }

    @MainActor
    func toState() -> DesktopPartitionState {
        let mode = DesktopMergeMode(rawValue: mergeMode) ?? .leftColumn
        return DesktopPartitionState(
            mergeMode: mode,
            splitX: CGFloat(splitX),
            splitY: CGFloat(splitY),
            stackThreshold: stackThreshold
        )
    }
}
