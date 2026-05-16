import AppKit
import Observation
import SwiftUI

@MainActor
final class ComputerBarStatusController: NSObject {
    private static let popoverMaximumContentSize = CGSize(width: 1_440, height: 960)
    private static let popoverScreenMargin: CGFloat = 80

    private let model: AppModel
    private let settingsWindowController: ComputerBarSettingsWindowController
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()

    private var hostingController: NSHostingController<MenuBarView>?
    private var preferredPopoverContentSize = MenuBarView.minimumContentSize

    init(model: AppModel, settingsWindowController: ComputerBarSettingsWindowController) {
        self.model = model
        self.settingsWindowController = settingsWindowController
        super.init()
        configureStatusItem()
        configurePopover()
        startStatusItemObservation()
        startPopoverObservation()
        updateStatusItem()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover)
        button.sendAction(on: [.leftMouseUp])
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.lineBreakMode = .byClipping
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = false

        let hostingController = NSHostingController(
            rootView: MenuBarView(
                model: model,
                openSettingsAction: { [weak self] in
                    self?.showSettings()
                },
                quitAction: {
                    NSApp.terminate(nil)
                },
                onPreferredSizeChange: { [weak self] size in
                    self?.updatePopoverContentSize(preferredSize: size)
                }
            )
        )

        self.hostingController = hostingController
        popover.contentViewController = hostingController
        updatePopoverContentSize(preferredSize: preferredPopoverContentSize)
    }

    private func startStatusItemObservation() {
        withObservationTracking {
            _ = model.menuBarAccessibilityTitle
            _ = model.menuBarStatusBars
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.updateStatusItem()
                self?.startStatusItemObservation()
            }
        }
    }

    private func startPopoverObservation() {
        withObservationTracking {
            _ = model.windowHosts
            _ = model.configErrorMessage
            _ = model.lastRefreshAt
            for host in model.windowHosts {
                _ = model.statusState(for: host)
            }
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                if self?.popover.isShown == true {
                    self?.updatePopoverContentSize()
                }
                self?.startPopoverObservation()
            }
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }

        let image = MenuBarStatusImage.make(bars: model.menuBarStatusBars)
        button.image = image
        statusItem.length = ceil(image.size.width)
        button.title = ""
        button.attributedTitle = NSAttributedString()
        button.contentTintColor = nil
        button.setAccessibilityTitle(model.menuBarAccessibilityTitle)
        button.toolTip = model.menuBarAccessibilityTitle
    }

    @objc
    private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            updatePopoverContentSize(screen: button.window?.screen)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showSettings() {
        popover.performClose(nil)
        settingsWindowController.show()
    }

    private func updatePopoverContentSize(preferredSize: CGSize? = nil, screen: NSScreen? = nil) {
        if let preferredSize {
            preferredPopoverContentSize = preferredSize
        } else if let hostingController {
            hostingController.view.layoutSubtreeIfNeeded()
            let fittedSize = hostingController.view.fittingSize
            preferredPopoverContentSize = CGSize(
                width: max(fittedSize.width, MenuBarView.minimumContentSize.width),
                height: max(fittedSize.height, MenuBarView.minimumContentSize.height)
            )
        }

        popover.contentSize = constrainedPopoverContentSize(
            for: preferredPopoverContentSize,
            screen: screen ?? statusItem.button?.window?.screen
        )
    }

    private func constrainedPopoverContentSize(for preferredSize: CGSize, screen: NSScreen?) -> CGSize {
        let visibleFrame = (screen ?? NSScreen.main)?.visibleFrame
        let maximumWidth = min(
            Self.popoverMaximumContentSize.width,
            max(
                MenuBarView.minimumContentSize.width,
                (visibleFrame?.width ?? Self.popoverMaximumContentSize.width) - Self.popoverScreenMargin
            )
        )
        let maximumHeight = min(
            Self.popoverMaximumContentSize.height,
            max(
                MenuBarView.minimumContentSize.height,
                (visibleFrame?.height ?? Self.popoverMaximumContentSize.height) - Self.popoverScreenMargin
            )
        )

        return CGSize(
            width: min(max(preferredSize.width, MenuBarView.minimumContentSize.width), maximumWidth),
            height: min(max(preferredSize.height, MenuBarView.minimumContentSize.height), maximumHeight)
        )
    }

}
