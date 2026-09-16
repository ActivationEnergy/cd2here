import AppKit
import Foundation
import Testing
@testable import Cd2HereCore

@Suite("TerminalKind.option caching")
struct TerminalKindTests {

    @Test("option is deterministic across calls")
    @MainActor
    func optionStable() {
        TerminalKind._resetOptionCacheForTesting()
        for kind in TerminalKind.allCases {
            let first = kind.option
            let second = kind.option
            #expect(first == second, "kind \(kind) returned different options")
        }
    }

    @Test("option probes at most once per kind per session")
    @MainActor
    func optionProbesAtMostOnce() {
        TerminalKind._resetOptionCacheForTesting()
        TerminalKind._resetProbeCountersForTesting()
        for kind in TerminalKind.allCases {
            _ = kind.option
            _ = kind.option
            _ = kind.option
        }
        for kind in TerminalKind.allCases {
            #expect(
                TerminalKind.probeCounters[kind] == 1,
                "kind \(kind) probed \(TerminalKind.probeCounters[kind] ?? -1) times after 3 accesses"
            )
        }
    }

    @Test("resetOptionCacheForTesting forces re-probe")
    @MainActor
    func resetForcesReprobe() {
        TerminalKind._resetOptionCacheForTesting()
        _ = TerminalKind.ghostty.option
        let countAfterFirst = TerminalKind.probeCounters[.ghostty] ?? 0
        TerminalKind._resetOptionCacheForTesting()
        _ = TerminalKind.ghostty.option
        let countAfterSecond = TerminalKind.probeCounters[.ghostty] ?? 0
        // The second probe must increment the counter, proving that reset
        // forced a re-evaluation rather than returning a cached value.
        #expect(countAfterSecond == countAfterFirst + 1)
    }
}