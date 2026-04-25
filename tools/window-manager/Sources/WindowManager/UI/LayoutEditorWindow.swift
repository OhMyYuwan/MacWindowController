import AppKit
import Foundation

@MainActor
enum LayoutEditorLauncher {
    private static var runtimeHolder: LayoutEditorRuntime?

    static func open(layout: DesktopLayout, store: DesktopLayoutStore, displayFrame: CGRect) {
        let app = NSApplication.shared
        let runtime = LayoutEditorRuntime(layout: layout, store: store, displayFrame: displayFrame)
        runtimeHolder = runtime

        app.setActivationPolicy(.regular)
        app.delegate = runtime
        app.activate(ignoringOtherApps: true)
        app.run()

        runtimeHolder = nil
    }
}

@MainActor
private final class LayoutEditorRuntime: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let store: DesktopLayoutStore
    private let displayFrame: CGRect
    private var currentLayout: DesktopLayout

    private var window: NSWindow?
    private var canvas: LayoutCanvas?
    private var descriptionField: NSTextField?

    init(layout: DesktopLayout, store: DesktopLayoutStore, displayFrame: CGRect) {
        self.currentLayout = layout
        self.store = store
        self.displayFrame = displayFrame
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 120, width: 1100, height: 760),
            styleMask: [.titled, .resizable, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Desktop Layout Editor - \(currentLayout.name)"
        window.center()
        window.delegate = self

        let rootView = NSView()
        rootView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = rootView

        let titleLabel = NSTextField(labelWithString: "Layout: \(currentLayout.name)")
        titleLabel.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let descriptionField = NSTextField(string: currentLayout.description)
        descriptionField.placeholderString = "Layout description"
        descriptionField.translatesAutoresizingMaskIntoConstraints = false
        self.descriptionField = descriptionField

        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveLayout))
        saveButton.bezelStyle = .rounded
        saveButton.translatesAutoresizingMaskIntoConstraints = false

        let closeButton = NSButton(title: "Close", target: self, action: #selector(closeEditor))
        closeButton.bezelStyle = .rounded
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        let canvas = LayoutCanvas(layout: currentLayout, displayFrame: displayFrame)
        canvas.translatesAutoresizingMaskIntoConstraints = false
        self.canvas = canvas

        rootView.addSubview(titleLabel)
        rootView.addSubview(descriptionField)
        rootView.addSubview(saveButton)
        rootView.addSubview(closeButton)
        rootView.addSubview(canvas)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 16),

            descriptionField.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 12),
            descriptionField.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            descriptionField.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -12),

            saveButton.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 12),
            saveButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -10),
            saveButton.widthAnchor.constraint(equalToConstant: 90),

            closeButton.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 12),
            closeButton.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 90),

            canvas.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            canvas.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 16),
            canvas.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -16),
            canvas.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -16)
        ])

        self.window = window
        window.makeKeyAndOrderFront(nil)
    }

    @objc
    private func saveLayout() {
        guard let canvas else { return }
        let updated = canvas.updatedLayout(description: descriptionField?.stringValue ?? currentLayout.description)
        do {
            try store.save(updated)
            currentLayout = updated
            showAlert(title: "Saved", message: "Desktop layout has been saved.")
        } catch {
            showAlert(title: "Save Failed", message: error.localizedDescription)
        }
    }

    @objc
    private func closeEditor() {
        NSApplication.shared.terminate(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApplication.shared.terminate(nil)
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

