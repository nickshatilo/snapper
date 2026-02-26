import AppKit

final class MenuBarController {
    private var statusItem: NSStatusItem?
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        setupStatusItem()
    }

    private func setupStatusItem() {
        guard appState.menuBarVisible else { return }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Snapper")
            button.image?.isTemplate = true
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
