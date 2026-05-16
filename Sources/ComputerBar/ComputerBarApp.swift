import AppKit
import SwiftUI

@main
struct ComputerBarApp: App {
    @NSApplicationDelegateAdaptor(ComputerBarAppDelegate.self) private var appDelegate
    private let model = AppModel.shared

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        appDelegate.configure(model: model)
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class ComputerBarAppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var settingsWindowController: ComputerBarSettingsWindowController?
    private var statusController: ComputerBarStatusController?

    func configure(model: AppModel) {
        self.model = model
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let model else { return }

        let settingsWindowController = ComputerBarSettingsWindowController(model: model)
        self.settingsWindowController = settingsWindowController
        statusController = ComputerBarStatusController(
            model: model,
            settingsWindowController: settingsWindowController
        )

        if ProcessInfo.processInfo.arguments.contains("--open-settings") {
            settingsWindowController.show()
        }
    }
}
