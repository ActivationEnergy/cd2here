import Foundation

struct TerminalPreferences {
    static let suiteName = "io.github.activationenergy.cd2here"
    /// Suite name used by the previous xiaojf-owned fork. Existing users
    /// upgrading from that fork have their `selectedTerminal` saved here.
    /// On init we migrate any legacy value to the current suite so users
    /// do not lose their saved choice (or trigger a second Automation
    /// permission grant — the OS sees the new bundle ID as a different
    /// sender, but the saved preference carries over).
    private static let legacySuiteName = "io.github.xiaojf.cd2here"
    private static let selectedTerminalKey = "selectedTerminal"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = UserDefaults(suiteName: suiteName) ?? .standard) {
        self.defaults = defaults
        Self.migrateLegacyIfNeeded(into: defaults)
    }

    var selectedTerminal: TerminalKind? {
        guard let value = defaults.string(forKey: Self.selectedTerminalKey) else {
            return nil
        }
        return TerminalKind(rawValue: value)
    }

    func select(_ terminal: TerminalKind) {
        defaults.set(terminal.rawValue, forKey: Self.selectedTerminalKey)
    }

    /// One-shot migration: if the legacy suite has a saved terminal and
    /// the current suite does not, copy it across. Idempotent.
    private static func migrateLegacyIfNeeded(into defaults: UserDefaults) {
        guard defaults.string(forKey: selectedTerminalKey) == nil,
              let legacy = UserDefaults(suiteName: legacySuiteName),
              let value = legacy.string(forKey: selectedTerminalKey) else {
            return
        }
        defaults.set(value, forKey: selectedTerminalKey)
    }
}

enum TerminalSelectionPolicy {
    static func requiresSelection(
        savedTerminal: TerminalKind?,
        isSavedTerminalAvailable: Bool,
        optionPressed: Bool
    ) -> Bool {
        optionPressed || savedTerminal == nil || !isSavedTerminalAvailable
    }
}