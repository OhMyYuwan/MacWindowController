import Foundation

enum DesktopLayoutStoreError: LocalizedError {
    case layoutNotFound(String)
    case invalidName

    var errorDescription: String? {
        switch self {
        case .layoutNotFound(let name):
            return "Desktop layout not found: \(name)"
        case .invalidName:
            return "Layout name cannot be empty."
        }
    }
}

final class DesktopLayoutStore {
    private let fileManager: FileManager
    private let supportDirectoryURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.supportDirectoryURL = DesktopLayoutStore.resolveSupportDirectory(fileManager: fileManager)
    }

    func save(_ layout: DesktopLayout) throws {
        try ensureLayoutsDirectory()
        let url = layoutURL(name: layout.name)
        let data = try encoder.encode(layout)
        try data.write(to: url, options: .atomic)
    }

    func load(name: String) throws -> DesktopLayout {
        let normalizedName = normalize(name)
        let url = layoutURL(name: normalizedName)
        guard fileManager.fileExists(atPath: url.path) else {
            throw DesktopLayoutStoreError.layoutNotFound(normalizedName)
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(DesktopLayout.self, from: data)
    }

    func list() -> [DesktopLayout] {
        guard
            let urls = try? fileManager.contentsOfDirectory(
                at: layoutsDirectoryURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return []
        }

        let layouts = urls
            .filter { $0.pathExtension.lowercased() == "json" }
            .compactMap { url -> DesktopLayout? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(DesktopLayout.self, from: data)
            }

        return layouts.sorted { $0.createdAt > $1.createdAt }
    }

    func delete(name: String) throws {
        let normalizedName = normalize(name)
        let url = layoutURL(name: normalizedName)
        guard fileManager.fileExists(atPath: url.path) else {
            throw DesktopLayoutStoreError.layoutNotFound(normalizedName)
        }
        try fileManager.removeItem(at: url)
    }

    func exportLayout(name: String, to outputURL: URL) throws {
        let layout = try load(name: name)
        let data = try encoder.encode(layout)
        try data.write(to: outputURL, options: .atomic)
    }

    func importLayout(from inputURL: URL) throws -> DesktopLayout {
        let data = try Data(contentsOf: inputURL)
        var layout = try decoder.decode(DesktopLayout.self, from: data)
        layout.name = normalize(layout.name)
        try save(layout)
        return layout
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func ensureLayoutsDirectory() throws {
        try fileManager.createDirectory(
            at: layoutsDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    private func layoutURL(name: String) -> URL {
        layoutsDirectoryURL.appendingPathComponent("\(normalize(name)).json", isDirectory: false)
    }

    private func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "_")
    }

    private var layoutsDirectoryURL: URL {
        supportDirectoryURL.appendingPathComponent("layouts", isDirectory: true)
    }

    private static func resolveSupportDirectory(fileManager: FileManager) -> URL {
        if let custom = ProcessInfo.processInfo.environment["WINDOW_MANAGER_LAYOUTS_DIR"] {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
        }

        let tempFallback = URL(fileURLWithPath: "/tmp/winctlmanager-layouts", isDirectory: true)
        if canCreateDirectory(at: tempFallback, fileManager: fileManager) {
            return tempFallback
        }

        let homeFallback = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".winctlmanager", isDirectory: true)
        return homeFallback
    }

    private static func canCreateDirectory(at url: URL, fileManager: FileManager) -> Bool {
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            return true
        } catch {
            return false
        }
    }
}
