import AppKit
import Foundation

/// UI-layer extensions for `TerminalKind`. The base enum lives in the Core
/// layer and stays Foundation-only; this file is the only place that imports
/// AppKit for terminal-option probing.
extension TerminalKind {
    /// Resolves a `TerminalOption` for the chooser UI. Cached for the
    /// lifetime of the process; cleared via `_resetOptionCacheForTesting`.
    ///
    /// `probeCounters` records the cumulative number of probes per kind.
    /// In release builds the count is still maintained (cost: one dict
    /// increment per probe) so production crash logs and `Console.app`
    /// filtering by `cd2here:` can be correlated with cache behavior.
    @MainActor
    var option: TerminalOption {
        if let cached = Self.optionCache[self] {
            return cached
        }
        Self.probeCounters[self, default: 0] += 1
        let value = Self.computeOption(for: self)
        Self.optionCache[self] = value
        return value
    }

    @MainActor
    private static var optionCache: [TerminalKind: TerminalOption] = [:]

    /// Cumulative probe count per kind, process-lifetime. Always populated
    /// (DEBUG and release). Visible to tests via `@testable import`.
    @MainActor
    static var probeCounters: [TerminalKind: Int] = [:]

    @MainActor
    static func _resetOptionCacheForTesting() {
        // Clears the cache without touching the counter. Use this in tests
        // that want to verify "reset forces re-probe" — the counter then
        // records the cumulative number of probes across the test.
        optionCache.removeAll()
    }

    @MainActor
    static func _resetProbeCountersForTesting() {
        // Clears the counter without touching the cache. Use this in tests
        // that want to assert an absolute probe count (e.g. "exactly 1 probe
        // per kind") so prior tests' counter state does not leak in.
        probeCounters.removeAll()
    }

    @MainActor
    private static func computeOption(for kind: TerminalKind) -> TerminalOption {
        let hasAppBundle = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: kind.bundleIdentifier
        ) != nil
        let hasCliBinary = kind.cliBinaryName.flatMap {
            BinaryLocator.locate($0)
        } != nil
        guard hasAppBundle || hasCliBinary else {
            return TerminalOption(terminal: kind, availability: .notInstalled)
        }
        let isCompatible = TerminalControllerFactory.make(kind).isCompatible()
        if !isCompatible {
            // Marking a terminal "incompatible" without saying why is a
            // documentation smell — the chooser shows "Unsupported Version"
            // and users can't tell whether to upgrade, grant a permission, or
            // reinstall. NSLog the controller name + kind for now; richer
            // diagnostics (e.g. attaching the AppleScript error info) would
            // require expanding the `TerminalControlling` protocol.
            NSLog(
                "cd2here: %@ marked as incompatible. For diagnostics, run the controller's `script(...)` through `AppleScriptExecutor.compile(source:)` manually.",
                kind.displayName
            )
        }
        return TerminalOption(
            terminal: kind,
            availability: isCompatible ? .available : .incompatible
        )
    }
}