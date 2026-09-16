import AppKit

@MainActor
enum TerminalPicker {
    static func choose(
        from options: [TerminalOption],
        selected: TerminalKind?
    ) -> TerminalKind? {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Choose a terminal"
        alert.informativeText = "Normal clicks will use this terminal. Hold Option while clicking either cd2here app to change it later."

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 280, height: 26))

        for option in options {
            let terminal = option.terminal
            let title: String
            switch option.availability {
            case .available:
                title = terminal.displayName
            case .notInstalled:
                title = "\(terminal.displayName) — Not Installed"
            case .incompatible:
                title = "\(terminal.displayName) — Unsupported Version"
            }
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.representedObject = terminal.rawValue
            item.isEnabled = option.availability == .available
            popup.menu?.addItem(item)
        }

        if let selected,
           let selectedItem = popup.itemArray.first(where: {
               ($0.representedObject as? String) == selected.rawValue && $0.isEnabled
           }) {
            popup.select(selectedItem)
        } else if let firstAvailable = popup.itemArray.first(where: \.isEnabled) {
            popup.select(firstAvailable)
        }

        alert.accessoryView = popup
        alert.addButton(withTitle: "Use Terminal")
        alert.addButton(withTitle: "Cancel")

        // TODO: switch to `NSApp.activate()` once deployment target >= 14.
        // `ignoringOtherApps:` is deprecated as of macOS 14.
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn,
              let value = popup.selectedItem?.representedObject as? String else {
            return nil
        }
        return TerminalKind(rawValue: value)
    }
}
