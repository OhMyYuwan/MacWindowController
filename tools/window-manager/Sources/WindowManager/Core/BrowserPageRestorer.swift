import Foundation

struct BrowserPageInfo {
    let title: String
    let url: String
    let kind: String
}

final class BrowserPageRestorer {
    private let browserKindsByBundleId: [String: String] = [
        "com.google.Chrome": "chrome",
        "com.microsoft.edgemac": "edge",
        "company.thebrowser.Browser": "arc",
        "com.apple.Safari": "safari"
    ]

    func browserKind(for bundleId: String) -> String? {
        browserKindsByBundleId[bundleId]
    }

    func capturedPage(for bundleId: String, windowTitle: String) -> BrowserPageInfo? {
        guard let kind = browserKind(for: bundleId) else { return nil }
        let pages = capturePages(bundleId: bundleId, kind: kind)
        guard !pages.isEmpty else { return nil }
        let normalizedTitle = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedTitle.isEmpty {
            return pages.first
        }
        return pages.first { page in
            let pageTitle = page.title.lowercased()
            return pageTitle == normalizedTitle
                || pageTitle.contains(normalizedTitle)
                || normalizedTitle.contains(pageTitle)
        } ?? pages.first
    }

    func restorePage(bundleId: String, url: String) {
        guard !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if browserKind(for: bundleId) == "safari" {
            runAppleScript("""
            tell application id "\(escapeAppleScript(bundleId))"
                make new document with properties {URL:"\(escapeAppleScript(url))"}
            end tell
            """)
            return
        }

        if browserKind(for: bundleId) != nil {
            runAppleScript("""
            tell application id "\(escapeAppleScript(bundleId))"
                make new window
                set URL of active tab of front window to "\(escapeAppleScript(url))"
            end tell
            """)
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-b", bundleId, url]
        try? process.run()
        process.waitUntilExit()
    }

    private func capturePages(bundleId: String, kind: String) -> [BrowserPageInfo] {
        let script: String
        if kind == "safari" {
            script = """
            set output to ""
            tell application id "\(escapeAppleScript(bundleId))"
                repeat with d in documents
                    try
                        set pageTitle to name of d
                        set pageURL to URL of d
                        set output to output & pageTitle & tab & pageURL & linefeed
                    end try
                end repeat
            end tell
            return output
            """
        } else {
            script = """
            set output to ""
            tell application id "\(escapeAppleScript(bundleId))"
                repeat with w in windows
                    try
                        set pageTitle to title of active tab of w
                        set pageURL to URL of active tab of w
                        set output to output & pageTitle & tab & pageURL & linefeed
                    end try
                end repeat
            end tell
            return output
            """
        }

        return runAppleScript(script)
            .split(separator: "\n")
            .compactMap { line in
                let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
                guard parts.count == 2, !parts[1].isEmpty else { return nil }
                return BrowserPageInfo(title: parts[0], url: parts[1], kind: kind)
            }
    }

    @discardableResult
    private func runAppleScript(_ script: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return "" }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    private func escapeAppleScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
