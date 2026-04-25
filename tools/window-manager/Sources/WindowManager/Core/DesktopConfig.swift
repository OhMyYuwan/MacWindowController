import Foundation

struct DesktopConfig: Codable {
    /// 超过此数量的窗口重叠时自动创建堆栈组
    var stackThreshold: Int = 3

    /// 是否启用自动扫描
    var autoScanEnabled: Bool = false

    /// 自动扫描间隔（秒）
    var autoScanInterval: TimeInterval = 1.5

    static let `default` = DesktopConfig()

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
