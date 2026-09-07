import AppKit

/// Runtime pointer controls while the VM is running. The start menu dismisses
/// at launch, and Immersive hard-hides the Mac menu bar, so a status item alone
/// is invisible in the default presentation. Keep both: the menu-bar item for
/// windowed sessions, and a floating HUD that stays above Immersive Full Screen.
@MainActor
final class PointerModeStatusItem {
    private var statusItem: NSStatusItem?
    private var hud: NSPanel?
    private var segmentedControl: NSSegmentedControl?
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
        showHUD(mode: controller.mode)
    }

    func hide() {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        hud?.orderOut(nil)
        hud = nil
        segmentedControl = nil
        controller = nil
        onModeChanged = nil
    }

    private func showHUD(mode: PointerInputMode) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 248, height: 44),
            styleMask: [.titled, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Pointer"
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true

        let control = NSSegmentedControl(
            labels: ["Desktop", "Game"],
            trackingMode: .selectOne,
            target: self,
            action: #selector(changeSegment(_:))
        )
        control.segmentStyle = .rounded
        control.setSelected(true, forSegment: mode == .relative ? 1 : 0)
        control.setToolTip("Absolute tablet pointing for the Omarchy desktop.", forSegment: 0)
        control.setToolTip("Relative mouse so games can lock and capture the cursor.", forSegment: 1)
        control.setAccessibilityLabel("Pointer mode")
        control.translatesAutoresizingMaskIntoConstraints = false
        segmentedControl = control

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 248, height: 44))
        content.addSubview(control)
        NSLayoutConstraint.activate([
            control.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            control.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            control.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
        panel.contentView = content

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let origin = NSPoint(
                x: frame.maxX - panel.frame.width - 16,
                y: frame.maxY - panel.frame.height - 16
            )
            panel.setFrameOrigin(origin)
        }
        panel.orderFrontRegardless()
        hud = panel
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

    @objc private func changeSegment(_ sender: NSSegmentedControl) {
        apply(sender.selectedSegment == 1 ? .relative : .absolute)
    }

    private func apply(_ mode: PointerInputMode) {
        guard let controller else { return }
        do {
            try controller.setMode(mode)
            onModeChanged?(mode)
            refresh(mode: mode)
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
            refresh(mode: controller.mode)
        }
    }

    private func refresh(mode: PointerInputMode) {
        statusItem?.menu = makeMenu(mode: mode)
        segmentedControl?.setSelected(true, forSegment: mode == .relative ? 1 : 0)
    }
}
