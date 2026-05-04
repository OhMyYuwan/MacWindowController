import Foundation

struct DesktopConfig: Codable {
    struct Shortcut: Codable {
        var keyCode: UInt16 = 37 // L
        var command: Bool = true
        var option: Bool = true
        var shift: Bool = false
        var control: Bool = false
    }

    enum WorkbenchAppearance: String, Codable, CaseIterable {
        case system
        case titaniumLight
        case titaniumDark

        var title: String {
            switch self {
            case .system: return "跟随系统"
            case .titaniumLight: return "浅色钛"
            case .titaniumDark: return "深色钛"
            }
        }
    }

    enum StackTabGlassStyle: String, Codable, CaseIterable {
        case crystalClear
        case softFrost
        case milkyTitanium
        case graphiteSmoke

        var title: String {
            switch self {
            case .crystalClear: return "清透玻璃"
            case .softFrost: return "标准磨砂"
            case .milkyTitanium: return "乳白钛"
            case .graphiteSmoke: return "深烟灰"
            }
        }

        var subtitle: String {
            switch self {
            case .crystalClear: return "最高透明度，适合背景干净的桌面"
            case .softFrost: return "接近 Apple 示例里的常规 Liquid Glass 控件"
            case .milkyTitanium: return "更强磨砂和钛色反光，适合浅色桌面"
            case .graphiteSmoke: return "深色烟灰玻璃，适合复杂或深色桌面"
            }
        }
    }

    /// 超过此数量的窗口重叠时自动创建堆栈组
    var stackThreshold: Int = 3

    /// 是否启用自动扫描
    var autoScanEnabled: Bool = false

    /// 自动扫描间隔（秒）
    var autoScanInterval: TimeInterval = 1.5

    /// 长按显示九宫格布局 HUD 的快捷键
    var layoutHUDShortcut: Shortcut = .init()

    /// Workbench visual appearance.
    var workbenchAppearance: WorkbenchAppearance = .system

    /// Desktop stack tab bar Liquid Glass variant.
    var stackTabGlassStyle: StackTabGlassStyle = .softFrost

    /// Show floating window previews when hovering over the macOS Dock.
    var dockPreviewEnabled: Bool = true

    /// Bundle identifiers explicitly disabled from preview/switcher surfaces.
    var previewDisabledBundleIds: Set<String> = []

    /// User-recorded shortcuts keyed by Workbench shortcut action id.
    var shortcutBindings: [String: Shortcut] = [:]

    /// Actions where the user explicitly accepted an occupied shortcut.
    var shortcutConflictOverrides: [String: Bool] = [:]

    static let `default` = DesktopConfig()

    init() {}

    enum CodingKeys: String, CodingKey {
        case stackThreshold
        case autoScanEnabled
        case autoScanInterval
        case layoutHUDShortcut
        case workbenchAppearance
        case stackTabGlassStyle
        case dockPreviewEnabled
        case previewDisabledBundleIds
        case shortcutBindings
        case shortcutConflictOverrides
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        stackThreshold = try values.decodeIfPresent(Int.self, forKey: .stackThreshold) ?? 3
        autoScanEnabled = try values.decodeIfPresent(Bool.self, forKey: .autoScanEnabled) ?? false
        autoScanInterval = try values.decodeIfPresent(TimeInterval.self, forKey: .autoScanInterval) ?? 1.5
        layoutHUDShortcut = try values.decodeIfPresent(Shortcut.self, forKey: .layoutHUDShortcut) ?? .init()
        workbenchAppearance = try values.decodeIfPresent(WorkbenchAppearance.self, forKey: .workbenchAppearance) ?? .system
        stackTabGlassStyle = try values.decodeIfPresent(StackTabGlassStyle.self, forKey: .stackTabGlassStyle) ?? .softFrost
        dockPreviewEnabled = try values.decodeIfPresent(Bool.self, forKey: .dockPreviewEnabled) ?? true
        previewDisabledBundleIds = try values.decodeIfPresent(Set<String>.self, forKey: .previewDisabledBundleIds) ?? []
        shortcutBindings = try values.decodeIfPresent([String: Shortcut].self, forKey: .shortcutBindings) ?? [:]
        shortcutConflictOverrides = try values.decodeIfPresent([String: Bool].self, forKey: .shortcutConflictOverrides) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(stackThreshold, forKey: .stackThreshold)
        try values.encode(autoScanEnabled, forKey: .autoScanEnabled)
        try values.encode(autoScanInterval, forKey: .autoScanInterval)
        try values.encode(layoutHUDShortcut, forKey: .layoutHUDShortcut)
        try values.encode(workbenchAppearance, forKey: .workbenchAppearance)
        try values.encode(stackTabGlassStyle, forKey: .stackTabGlassStyle)
        try values.encode(dockPreviewEnabled, forKey: .dockPreviewEnabled)
        try values.encode(previewDisabledBundleIds, forKey: .previewDisabledBundleIds)
        try values.encode(shortcutBindings, forKey: .shortcutBindings)
        try values.encode(shortcutConflictOverrides, forKey: .shortcutConflictOverrides)
    }

    private static var configURL: URL {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        return homeDir
            .appendingPathComponent(".winctlmanager", isDirectory: true)
            .appendingPathComponent("config.json", isDirectory: false)
    }

    static func load() -> DesktopConfig {
        guard let data = try? Data(contentsOf: configURL) else {
            return .default
        }
        let decoder = JSONDecoder()
        return (try? decoder.decode(DesktopConfig.self, from: data)) ?? .default
    }

    func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)

        let dir = Self.configURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: Self.configURL, options: .atomic)
    }
}
