import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

struct WindowPreviewSnapshot {
    let window: WindowInfo
    let image: NSImage?

    var hasImage: Bool { image != nil }
}

final class WindowPreviewProvider {
    private struct CachedPreview {
        let image: NSImage?
        let capturedAt: Date
    }

    private var previewCache: [Int: CachedPreview] = [:]
    private let previewCacheLock = NSLock()
    private let previewCacheTTL: TimeInterval = 4.0
    private let previewStaleTTL: TimeInterval = 20.0

    func hasScreenRecordingPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    func requestScreenRecordingPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    func snapshot(for window: WindowInfo) -> WindowPreviewSnapshot {
        let now = Date()
        if let cached = cachedPreview(for: window.windowNumber, at: now) {
            return WindowPreviewSnapshot(window: window, image: cached.image)
        }

        let image = previewImage(for: window)
        updateCachedPreview(windowNumber: window.windowNumber, image: image, at: now, keeping: [window.windowNumber])
        return WindowPreviewSnapshot(window: window, image: image)
    }

    func uncachedSnapshot(for window: WindowInfo) -> WindowPreviewSnapshot {
        WindowPreviewSnapshot(window: window, image: previewImage(for: window))
    }

    func snapshots(for windows: [WindowInfo]) -> [WindowPreviewSnapshot] {
        windows
            .filter { $0.isControllable && $0.windowNumber >= 0 }
            .map(snapshot(for:))
    }

    /// Cache-first snapshots: never blocks on image capture.
    func cachedSnapshots(for windows: [WindowInfo]) -> [WindowPreviewSnapshot] {
        let now = Date()
        return windows
            .filter { $0.isControllable && $0.windowNumber >= 0 }
            .map { window in
                let cachedImage = cachedPreview(for: window.windowNumber, at: now)?.image
                    ?? staleCachedPreview(for: window.windowNumber, at: now)?.image
                return WindowPreviewSnapshot(window: window, image: cachedImage)
            }
    }

    /// Performs capture for uncached windows and refreshes cache; intended for background execution.
    func hydratedSnapshots(for windows: [WindowInfo]) -> [WindowPreviewSnapshot] {
        let targets = windows.filter { $0.isControllable && $0.windowNumber >= 0 }
        guard !targets.isEmpty else { return [] }

        final class SnapshotStore: @unchecked Sendable {
            private let lock = NSLock()
            private var storage: [Int: WindowPreviewSnapshot] = [:]

            func set(_ snapshot: WindowPreviewSnapshot, at index: Int) {
                lock.lock()
                storage[index] = snapshot
                lock.unlock()
            }

            func snapshot(at index: Int) -> WindowPreviewSnapshot? {
                lock.lock()
                let value = storage[index]
                lock.unlock()
                return value
            }
        }

        // Capture in parallel to reduce first-render latency for multi-window apps.
        let store = SnapshotStore()
        let group = DispatchGroup()

        for (index, window) in targets.enumerated() {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                defer { group.leave() }
                guard let self else { return }
                let snapshot = self.snapshot(for: window)
                store.set(snapshot, at: index)
            }
        }
        group.wait()
        return (0..<targets.count).compactMap { store.snapshot(at: $0) }
    }

    private func trimPreviewCache(keeping currentWindowNumbers: [Int]) {
        guard previewCache.count > 40 else { return }
        let keep = Set(currentWindowNumbers)
        previewCache = previewCache.filter { keep.contains($0.key) || Date().timeIntervalSince($0.value.capturedAt) < previewCacheTTL }
    }

    private func cachedPreview(for windowNumber: Int, at now: Date) -> CachedPreview? {
        previewCacheLock.lock()
        defer { previewCacheLock.unlock() }
        guard let cached = previewCache[windowNumber], now.timeIntervalSince(cached.capturedAt) < previewCacheTTL else {
            return nil
        }
        return cached
    }

    private func staleCachedPreview(for windowNumber: Int, at now: Date) -> CachedPreview? {
        previewCacheLock.lock()
        defer { previewCacheLock.unlock() }
        guard let cached = previewCache[windowNumber], now.timeIntervalSince(cached.capturedAt) < previewStaleTTL else {
            return nil
        }
        return cached
    }

    private func updateCachedPreview(windowNumber: Int, image: NSImage?, at now: Date, keeping windowNumbers: [Int]) {
        previewCacheLock.lock()
        previewCache[windowNumber] = CachedPreview(image: image, capturedAt: now)
        trimPreviewCache(keeping: windowNumbers)
        previewCacheLock.unlock()
    }

    private func previewImage(for window: WindowInfo) -> NSImage? {
        guard window.windowNumber >= 0 else { return nil }

        let windowID = CGWindowID(window.windowNumber)
        let options: CGWindowImageOption = [.boundsIgnoreFraming, .bestResolution]
        guard let cgImage = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            options
        ) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

extension WindowPreviewProvider: @unchecked Sendable {}

enum DockPreviewEdge {
    case bottom
    case left
    case right
}

struct DockHoverMatch {
    let bundleId: String
    let appName: String
    let pid: Int32?
    let itemFrame: CGRect
    let dockFrame: CGRect
    let edge: DockPreviewEdge
}

final class DockPreviewResolver {
    private struct AppTarget {
        let bundleId: String
        let appName: String
        let aliases: Set<String>
    }

    private struct DockRegion {
        let frame: CGRect
        let edge: DockPreviewEdge
    }

    private struct DockItemRegion {
        let titles: [String]
        let frames: [CGRect]
        let bundleId: String?
        let appName: String?
        let element: AXUIElement
    }

    private var cachedAXItems: [DockItemRegion] = []
    private var lastAXItemRefresh = Date.distantPast

    func matchHover(at screenPoint: CGPoint, windows: [WindowInfo]) -> DockHoverMatch? {
        let visibleWindows = windows.filter { $0.isControllable && $0.windowNumber >= 0 }
        let targets = appTargets(from: visibleWindows)
        guard !targets.isEmpty else { return nil }

        if let selectedMatch = selectedDockItemMatch(at: screenPoint, targets: targets) {
            return selectedMatch
        }

        if let axMatch = accessibilityDockMatch(at: screenPoint, targets: targets) {
            return axMatch
        }

        return nil
    }

    private func selectedDockItemMatch(at screenPoint: CGPoint, targets: [AppTarget]) -> DockHoverMatch? {
        guard let dockRegion = inferredDockRegion(containing: screenPoint),
              let selected = selectedDockApplicationItem()
        else {
            return nil
        }

        guard let bundleId = selected.bundleId,
              let target = targets.first(where: { $0.bundleId == bundleId })
        else {
            return nil
        }

        guard let frame = preferredFrame(
            for: selected,
            screenPoint: screenPoint,
            dockRegion: dockRegion
        ) else {
            return nil
        }

        let pid = selectedProcessIdentifier(for: selected)
        return DockHoverMatch(
            bundleId: target.bundleId,
            appName: target.appName,
            pid: pid,
            itemFrame: frame,
            dockFrame: dockRegion.frame,
            edge: edge(for: frame)
        )
    }

    private func accessibilityDockMatch(at screenPoint: CGPoint, targets: [AppTarget]) -> DockHoverMatch? {
        let items = dockAccessibilityItems()
        guard !items.isEmpty else { return nil }
        guard let dockRegion = inferredDockRegion(containing: screenPoint) else { return nil }
        let targetByBundleId = Dictionary(uniqueKeysWithValues: targets.map { ($0.bundleId, $0) })

        let directBundleHits = items.compactMap { item -> (target: AppTarget, frame: CGRect, frameScore: CGFloat)? in
            guard let bundleId = item.bundleId,
                  let target = targetByBundleId[bundleId],
                  let frame = bestHitFrame(at: screenPoint, frames: item.frames, dockRegion: dockRegion)
            else {
                return nil
            }
            return (target, frame, frameScore(frame, screenPoint: screenPoint, dockRegion: dockRegion))
        }

        if let exactHit = directBundleHits.min(by: { $0.frameScore < $1.frameScore }) {
            return DockHoverMatch(
                bundleId: exactHit.target.bundleId,
                appName: exactHit.target.appName,
                pid: nil,
                itemFrame: exactHit.frame,
                dockFrame: dockRegion.frame,
                edge: edge(for: exactHit.frame)
            )
        }

        let hits = items.compactMap { item -> (target: AppTarget, frame: CGRect, frameScore: CGFloat, titleScore: Int)? in
            guard let match = target(matching: item.titles, in: targets) else { return nil }
            guard let frame = bestHitFrame(at: screenPoint, frames: item.frames, dockRegion: dockRegion) else { return nil }
            let score = frameScore(frame, screenPoint: screenPoint, dockRegion: dockRegion)
            return (match.target, frame, score, match.score)
        }

        guard let hit = hits.min(by: { lhs, rhs in
            if lhs.titleScore != rhs.titleScore {
                // Prefer semantically stronger app-title matches first.
                return lhs.titleScore > rhs.titleScore
            }
            return lhs.frameScore < rhs.frameScore
        }) else {
            return nil
        }

        return DockHoverMatch(
            bundleId: hit.target.bundleId,
            appName: hit.target.appName,
            pid: nil,
            itemFrame: hit.frame,
            dockFrame: dockRegion.frame,
            edge: edge(for: hit.frame)
        )
    }

    private func dockAccessibilityItems() -> [DockItemRegion] {
        guard AXIsProcessTrusted() else { return [] }
        if Date().timeIntervalSince(lastAXItemRefresh) < 1.0 {
            return cachedAXItems
        }

        lastAXItemRefresh = Date()
        guard let root = dockApplicationElement() else {
            cachedAXItems = []
            return []
        }

        var items: [DockItemRegion] = []
        var visited = 0
        collectDockItems(from: root, depth: 0, visited: &visited, into: &items)
        cachedAXItems = items
        return items
    }

    private func dockApplicationElement() -> AXUIElement? {
        guard AXIsProcessTrusted(),
              let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else {
            return nil
        }
        return AXUIElementCreateApplication(dockApp.processIdentifier)
    }

    private func collectDockItems(from element: AXUIElement, depth: Int, visited: inout Int, into items: inout [DockItemRegion]) {
        guard depth < 8, visited < 500 else { return }
        visited += 1

        let titles = directStringCandidates(from: element)
        if !titles.isEmpty,
           let position = pointAttribute(element, attribute: kAXPositionAttribute as CFString),
           let size = sizeAttribute(element, attribute: kAXSizeAttribute as CFString),
           size.width > 8,
           size.height > 8
        {
            items.append(DockItemRegion(
                titles: titles,
                frames: screenFrameCandidates(position: position, size: size),
                bundleId: bundleIdentifier(from: element),
                appName: appName(from: element),
                element: element
            ))
        }

        guard let children = childrenAttribute(element) else { return }
        for child in children {
            collectDockItems(from: child, depth: depth + 1, visited: &visited, into: &items)
        }
    }

    private func inferredDockRegion(containing screenPoint: CGPoint) -> DockRegion? {
        let candidateScreens = NSScreen.screens.filter { $0.frame.insetBy(dx: -20, dy: -20).contains(screenPoint) }
        let screens = candidateScreens.isEmpty ? NSScreen.screens : candidateScreens

        for screen in screens {
            let frame = screen.frame
            let visible = screen.visibleFrame
            let leftInset = max(0, visible.minX - frame.minX)
            let rightInset = max(0, frame.maxX - visible.maxX)
            let bottomInset = max(0, visible.minY - frame.minY)
            let largestInset = max(leftInset, rightInset, bottomInset)

            let edge: DockPreviewEdge
            if largestInset > 24 {
                if leftInset == largestInset {
                    edge = .left
                } else if rightInset == largestInset {
                    edge = .right
                } else {
                    edge = .bottom
                }
            } else {
                edge = userDockOrientationFallback()
            }

            let thickness = max(largestInset, 86)
            let regionFrame: CGRect
            switch edge {
            case .bottom:
                regionFrame = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: thickness)
            case .left:
                regionFrame = CGRect(x: frame.minX, y: frame.minY, width: thickness, height: frame.height)
            case .right:
                regionFrame = CGRect(x: frame.maxX - thickness, y: frame.minY, width: thickness, height: frame.height)
            }

            if regionFrame.insetBy(dx: -4, dy: -16).contains(screenPoint) {
                return DockRegion(frame: regionFrame, edge: edge)
            }
        }

        return nil
    }

    private func fallbackDockIndex(at screenPoint: CGPoint, region: DockRegion, itemCount: Int) -> Int? {
        guard itemCount > 0 else { return nil }
        let rawProgress: CGFloat
        switch region.edge {
        case .bottom:
            rawProgress = (screenPoint.x - region.frame.minX) / max(1, region.frame.width)
        case .left, .right:
            rawProgress = (region.frame.maxY - screenPoint.y) / max(1, region.frame.height)
        }
        guard rawProgress >= 0, rawProgress <= 1 else { return nil }
        return min(itemCount - 1, max(0, Int(rawProgress * CGFloat(itemCount))))
    }

    private func fallbackItemFrame(at index: Int, itemCount: Int, region: DockRegion) -> CGRect {
        guard itemCount > 0 else { return region.frame }
        switch region.edge {
        case .bottom:
            let width = region.frame.width / CGFloat(itemCount)
            return CGRect(x: region.frame.minX + CGFloat(index) * width, y: region.frame.minY, width: width, height: region.frame.height)
        case .left, .right:
            let height = region.frame.height / CGFloat(itemCount)
            return CGRect(x: region.frame.minX, y: region.frame.maxY - CGFloat(index + 1) * height, width: region.frame.width, height: height)
        }
    }

    private func edge(for frame: CGRect) -> DockPreviewEdge {
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(frame) }) ?? NSScreen.main else {
            return .bottom
        }
        let leftDistance = abs(frame.minX - screen.frame.minX)
        let rightDistance = abs(screen.frame.maxX - frame.maxX)
        let bottomDistance = abs(frame.minY - screen.frame.minY)
        if leftDistance < rightDistance && leftDistance < bottomDistance {
            return .left
        }
        if rightDistance < bottomDistance {
            return .right
        }
        return .bottom
    }

    private func selectedDockApplicationItem() -> DockItemRegion? {
        guard let dockList = dockListElement(),
              let selectedChildren = selectedChildrenAttribute(dockList)
        else {
            return nil
        }

        for child in selectedChildren {
            if subrole(of: child) == "AXApplicationDockItem",
               let item = makeDockItemRegion(from: child) {
                return item
            }
        }
        return nil
    }

    private func selectedProcessIdentifier(for selected: DockItemRegion) -> Int32? {
        guard let bundleId = selected.bundleId else { return nil }
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        guard !runningApps.isEmpty else { return nil }
        guard runningApps.count > 1 else { return runningApps.first?.processIdentifier }

        let instanceIndex = dockItemInstanceIndex(for: selected.element, bundleId: bundleId)
        if instanceIndex >= 0, instanceIndex < runningApps.count {
            return runningApps[instanceIndex].processIdentifier
        }
        return runningApps.first?.processIdentifier
    }

    private func dockItemInstanceIndex(for selectedElement: AXUIElement, bundleId: String) -> Int {
        guard let dockList = dockListElement(),
              let children = childrenAttribute(dockList)
        else {
            return 0
        }

        var matchingItems: [AXUIElement] = []
        for child in children {
            guard subrole(of: child) == "AXApplicationDockItem",
                  bundleIdentifier(from: child) == bundleId
            else {
                continue
            }
            matchingItems.append(child)
        }

        for (index, item) in matchingItems.enumerated() where CFEqual(item, selectedElement) {
            return index
        }
        return 0
    }

    private func preferredFrame(for item: DockItemRegion, screenPoint: CGPoint, dockRegion: DockRegion) -> CGRect? {
        if let exact = bestHitFrame(at: screenPoint, frames: item.frames, dockRegion: dockRegion) {
            return exact
        }

        let validFrames = item.frames.filter { frame in
            frame.width > 8
                && frame.height > 8
                && frame.width < 220
                && frame.height < 220
                && frame.intersects(dockRegion.frame.insetBy(dx: -14, dy: -14))
        }
        guard !validFrames.isEmpty else { return nil }
        return validFrames.min { lhs, rhs in
            frameScore(lhs, screenPoint: screenPoint, dockRegion: dockRegion)
                < frameScore(rhs, screenPoint: screenPoint, dockRegion: dockRegion)
        }
    }

    private func appTargets(from windows: [WindowInfo]) -> [AppTarget] {
        var grouped: [String: WindowInfo] = [:]
        for window in windows where grouped[window.bundleId] == nil {
            grouped[window.bundleId] = window
        }

        return grouped.values.map { window in
            let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: window.bundleId).first
            let localizedName = runningApp?.localizedName ?? ""
            let executableName = runningApp?.executableURL?.deletingPathExtension().lastPathComponent ?? ""
            let aliases = [window.appName, localizedName, executableName, window.bundleId]
                .map(normalized)
                .filter { !$0.isEmpty }
            return AppTarget(bundleId: window.bundleId, appName: window.appName, aliases: Set(aliases))
        }
    }

    private func userDockOrientationFallback() -> DockPreviewEdge {
        let orientation = UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation")
        switch orientation {
        case "left": return .left
        case "right": return .right
        default: return .bottom
        }
    }

    private func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func target(matching rawStrings: [String], in targets: [AppTarget]) -> (target: AppTarget, score: Int)? {
        let normalizedStrings = rawStrings
            .map(normalizedDockTitle)
            .filter { !$0.isEmpty }
        guard !normalizedStrings.isEmpty else { return nil }

        var best: (target: AppTarget, score: Int)?

        for text in normalizedStrings {
            let tokens = Set(tokenize(text))
            for target in targets {
                for alias in target.aliases where !alias.isEmpty {
                    let score = aliasMatchScore(text: text, tokens: tokens, alias: alias)
                    guard score > 0 else { continue }
                    if best == nil || score > best!.score {
                        best = (target, score)
                    }
                }
            }
        }

        return best
    }

    private func aliasMatchScore(text: String, tokens: Set<String>, alias: String) -> Int {
        if alias == text {
            return 120
        }

        if tokens.contains(alias) {
            return 95
        }

        if alias.count >= 4, text.contains(alias) {
            return 70
        }

        if alias.count >= 5, alias.contains(text) {
            return 40
        }

        return 0
    }

    private func tokenize(_ value: String) -> [String] {
        value
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .map(normalized)
            .filter { !$0.isEmpty }
    }

    private func bestHitFrame(at screenPoint: CGPoint, frames: [CGRect], dockRegion: DockRegion) -> CGRect? {
        frames
            .filter { frame in
                frame.width > 8
                    && frame.height > 8
                    && frame.width < 220
                    && frame.height < 220
                    && frame.intersects(dockRegion.frame.insetBy(dx: -12, dy: -12))
                    && frame.insetBy(dx: -6, dy: -6).contains(screenPoint)
            }
            .min { lhs, rhs in
                let lhsScore = frameScore(lhs, screenPoint: screenPoint, dockRegion: dockRegion)
                let rhsScore = frameScore(rhs, screenPoint: screenPoint, dockRegion: dockRegion)
                return lhsScore < rhsScore
            }
    }

    private func frameScore(_ frame: CGRect, screenPoint: CGPoint, dockRegion: DockRegion) -> CGFloat {
        let centerDistance = hypot(frame.midX - screenPoint.x, frame.midY - screenPoint.y)
        let area = frame.width * frame.height
        let edgeDistance: CGFloat = {
            switch dockRegion.edge {
            case .bottom:
                return abs(frame.midY - dockRegion.frame.midY)
            case .left, .right:
                return abs(frame.midX - dockRegion.frame.midX)
            }
        }()
        return centerDistance + area / 10_000 + edgeDistance * 0.25
    }

    private func normalizedDockTitle(_ value: String) -> String {
        let lowered = normalized(value)
        let separators = [",", "\n", "\t"]
        let firstSegment = separators.reduce(lowered) { partial, separator in
            partial.components(separatedBy: separator).first ?? partial
        }
        return firstSegment
            .replacingOccurrences(of: "application", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func directStringCandidates(from element: AXUIElement) -> [String] {
        var candidates: [String] = []

        for attribute in [
            kAXTitleAttribute as CFString,
            kAXDescriptionAttribute as CFString,
            kAXHelpAttribute as CFString,
            kAXValueAttribute as CFString
        ] {
            if let value = stringAttribute(element, attribute: attribute), !value.isEmpty {
                candidates.append(value)
            }
        }

        return candidates
    }

    private func makeDockItemRegion(from element: AXUIElement) -> DockItemRegion? {
        guard let position = pointAttribute(element, attribute: kAXPositionAttribute as CFString),
              let size = sizeAttribute(element, attribute: kAXSizeAttribute as CFString),
              size.width > 8,
              size.height > 8
        else {
            return nil
        }
        let titles = directStringCandidates(from: element)
        return DockItemRegion(
            titles: titles,
            frames: screenFrameCandidates(position: position, size: size),
            bundleId: bundleIdentifier(from: element),
            appName: appName(from: element),
            element: element
        )
    }

    private func dockListElement() -> AXUIElement? {
        guard let root = dockApplicationElement(),
              let children = childrenAttribute(root) else {
            return nil
        }
        return children.first(where: { role(of: $0) == kAXListRole as String })
    }

    private func screenFrameCandidates(position: CGPoint, size: CGSize) -> [CGRect] {
        let rawFrame = CGRect(origin: position, size: size)
        var frames = [rawFrame]

        let desktopFrame = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
        if !desktopFrame.isNull {
            frames.append(CGRect(
                x: position.x,
                y: desktopFrame.maxY - position.y - size.height + desktopFrame.minY,
                width: size.width,
                height: size.height
            ))
        }

        for screen in NSScreen.screens {
            let flipped = CGRect(
                x: position.x,
                y: screen.frame.maxY - position.y - size.height,
                width: size.width,
                height: size.height
            )
            if screen.frame.insetBy(dx: -200, dy: -200).intersects(flipped) {
                frames.append(flipped)
            }
        }
        return frames
    }

    private func stringAttribute(_ element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success else { return nil }
        return value as? String
    }

    private func bundleIdentifier(from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXURLAttribute as CFString, &value)
        guard result == .success else { return nil }
        if let url = value as? URL {
            return Bundle(url: url)?.bundleIdentifier
        }
        if let nsURL = value as? NSURL, let url = nsURL.absoluteURL {
            return Bundle(url: url)?.bundleIdentifier
        }
        if let rawString = value as? String, let url = URL(string: rawString) {
            return Bundle(url: url)?.bundleIdentifier
        }
        return nil
    }

    private func appName(from element: AXUIElement) -> String? {
        guard let bundleId = bundleIdentifier(from: element),
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId),
              let bundle = Bundle(url: appURL)
        else {
            return nil
        }
        return bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
    }

    private func childrenAttribute(_ element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? [AXUIElement]
    }

    private func selectedChildrenAttribute(_ element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXSelectedChildrenAttribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? [AXUIElement]
    }

    private func role(of element: AXUIElement) -> String? {
        stringAttribute(element, attribute: kAXRoleAttribute as CFString)
    }

    private func subrole(of element: AXUIElement) -> String? {
        stringAttribute(element, attribute: kAXSubroleAttribute as CFString)
    }

    private func pointAttribute(_ element: AXUIElement, attribute: CFString) -> CGPoint? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard
            result == .success,
            let cfValue = value,
            CFGetTypeID(cfValue) == AXValueGetTypeID()
        else {
            return nil
        }
        let axValue = cfValue as! AXValue
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    private func sizeAttribute(_ element: AXUIElement, attribute: CFString) -> CGSize? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard
            result == .success,
            let cfValue = value,
            CFGetTypeID(cfValue) == AXValueGetTypeID()
        else {
            return nil
        }
        let axValue = cfValue as! AXValue
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }
}
