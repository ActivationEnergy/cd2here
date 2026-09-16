import AppKit
import Foundation

@MainActor
public final class AppRunner: NSObject, NSApplicationDelegate {
    private let mode: LaunchMode
    private let optionPressedAtLaunch: Bool

    private init(mode: LaunchMode, optionPressedAtLaunch: Bool) {
        self.mode = mode
        self.optionPressedAtLaunch = optionPressedAtLaunch
    }

    public static func run(mode: LaunchMode) {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let runner = AppRunner(
            mode: mode,
            optionPressedAtLaunch: NSEvent.modifierFlags.contains(.option)
        )
        application.delegate = runner
        // TODO: latent delegate-release risk. `application.delegate` is a
        // `weak` reference and `runner` is a local — it only stays alive
        // because `application.run()` blocks the calling thread for the
        // entire app lifetime. If this method ever returns before
        // `applicationDidFinishLaunching` fires (e.g. via a future Task
        // refactor), the delegate would be released and `openLocation`
        // would never run. Today the call is direct and synchronous, so
        // the invariant holds — but the invariant is fragile.
        application.run()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        openLocation()
        NSApp.terminate(nil)
    }

    private func openLocation() {
        do {
            let preferences = TerminalPreferences()
            var terminal = preferences.selectedTerminal
            let savedOption = terminal.map(\.option)
            let savedTerminalIsAvailable = savedOption?.availability == .available
            if TerminalSelectionPolicy.requiresSelection(
                savedTerminal: terminal,
                isSavedTerminalAvailable: savedTerminalIsAvailable,
                optionPressed: optionPressedAtLaunch
            ) {
                let terminalOptions = TerminalKind.allCases.map { candidate in
                    if let savedOption, savedOption.terminal == candidate {
                        return savedOption
                    }
                    return candidate.option
                }
                guard terminalOptions.contains(where: { $0.availability == .available }) else {
                    throw Cd2HereError.noCompatibleTerminalAvailable
                }
                terminal = TerminalPicker.choose(
                    from: terminalOptions,
                    selected: terminal
                )
                guard let terminal else { return }
                preferences.select(terminal)
            }

            guard let terminal else { return }
            let directory = try FinderContext().directory()
            try TerminalControllerFactory.make(terminal).open(mode: mode, at: directory)
        } catch {
            Self.present(error: error)
        }
    }

    private static func present(error: Error) {
        let details = error.localizedDescription
        NSLog("cd2here error: %@", details)
        // TODO: switch to `NSApp.activate()` once deployment target >= 14.
        // `ignoringOtherApps:` is deprecated as of macOS 14.
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "cd2here could not open this location"
        alert.informativeText = details
        alert.runModal()
    }
}
