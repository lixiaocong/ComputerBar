import AppKit
import SwiftUI

@MainActor
final class ComputerBarSettingsWindowController: NSWindowController {
    init(model: AppModel) {
        let rootView = SettingsView(model: model)
            .frame(width: 560)
            .padding(20)

        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 760),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Computer Bar Settings"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentViewController = hostingController
        window.identifier = NSUserInterfaceItemIdentifier("ComputerBarSettingsWindow")
        window.setContentSize(NSSize(width: 600, height: 760))

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        NSRunningApplication.current.activate(options: [])
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }
}
