import AppKit

/// Menu-bar control shown while the VM is running. The start menu dismisses at
/// launch, so relative/absolute switching has to live somewhere that survives
/// the accessory activation policy.
@MainActor
final class PointerModeStatusItem {
    private var statusItem: NSStatusItem?
    private var controller: QMPPointerInputController?
    private var onModeChanged: ((PointerInputMode) -> Void)?

    func show(
        controller: QMPPointerInputController,
        onModeChanged: @escaping (PointerInputMode) -> Void
    ) {
        hide()
        self.controller = controller
        self.onModeChanged = onModeChanged

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "computermouse",
                accessibilityDescription: "Omarchy pointer mode"
            )
            button.image?.isTemplate = true
        }
        item.menu = makeMenu(mode: controller.mode)
        statusItem = item
    }

    func hide() {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        controller = nil
        onModeChanged = nil
    }

    private func makeMenu(mode: PointerInputMode) -> NSMenu {
        let menu = NSMenu(title: "Pointer")
        menu.autoenablesItems = false
        menu.addItem(modeItem(
            title: "Desktop pointer",
            toolTip: "Absolute tablet pointing for the Omarchy desktop.",
            action: #selector(selectAbsolute),
            selected: mode == .absolute
        ))
        menu.addItem(modeItem(
            title: "Game pointer",
            toolTip: "Relative mouse so games can lock and capture the cursor.",
            action: #selector(selectRelative),
            selected: mode == .relative
        ))
        menu.addItem(.separator())
        let help = NSMenuItem(
            title: "Ctrl-Alt releases a grabbed cursor",
            action: nil,
            keyEquivalent: ""
        )
        help.isEnabled = false
        menu.addItem(help)
        return menu
    }

    private func modeItem(
        title: String,
        toolTip: String,
        action: Selector,
        selected: Bool
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = selected ? .on : .off
        item.toolTip = toolTip
        return item
    }

    @objc private func selectAbsolute() {
        apply(.absolute)
    }

    @objc private func selectRelative() {
        apply(.relative)
    }

    private func apply(_ mode: PointerInputMode) {
        guard let controller else { return }
        do {
            try controller.setMode(mode)
            onModeChanged?(mode)
            statusItem?.menu = makeMenu(mode: mode)
        } catch {
            fputs(
                "omarchy-vm-helper: could not switch pointer mode: \(error.localizedDescription)\n",
                stderr
            )
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Couldn’t change the pointer"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "OK")
            alert.runModal()
            statusItem?.menu = makeMenu(mode: controller.mode)
        }
    }
}
