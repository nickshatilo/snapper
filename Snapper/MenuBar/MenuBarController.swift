import AppKit

final class MenuBarController {
    private var statusItem: NSStatusItem?
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        setupStatusItem()
    }

    private func setupStatusItem() {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        }

        guard let button = statusItem?.button else { return }
        let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Snapper")
            ?? NSImage(systemSymbolName: "camera", accessibilityDescription: "Snapper")
        if let image {
            image.isTemplate = true
            statusItem?.length = NSStatusItem.squareLength
            button.image = image
            button.title = ""
            button.imagePosition = .imageOnly
        } else {
            statusItem?.length = NSStatusItem.variableLength
            button.image = nil
            button.title = "Snapper"
            button.imagePosition = .imageLeading
        }

        statusItem?.menu = buildMenu()
    }

    func show() {
        if statusItem == nil {
            setupStatusItem()
        }
    }

    func hide() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = MenuBarMenu(appState: appState)
        return menu
    }
}
