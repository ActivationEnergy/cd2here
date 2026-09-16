import Foundation
import Testing
@testable import Cd2HereCore

@Suite("AppleScriptExecutor error mapping")
struct AppleScriptExecutorTests {

    @Test("errorNumber -1743 maps to automationPermissionDenied")
    func automationPermissionDenied() {
        let errorInfo: NSDictionary = [
            NSAppleScript.errorMessage: "Not authorized to send Apple events to Finder.",
            NSAppleScript.errorNumber: -1743,
        ]
        #expect(throws: Cd2HereError.automationPermissionDenied(message: "Not authorized to send Apple events to Finder.")) {
            try AppleScriptExecutor.mapAppleScriptError(errorInfo)
        }
    }

    @Test("other error numbers map to appleScriptFailed with context")
    func otherErrorMapped() {
        let errorInfo: NSDictionary = [
            NSAppleScript.errorMessage: "Some other error",
            NSAppleScript.errorNumber: -10000,
        ]
        #expect(throws: Cd2HereError.appleScriptFailed(message: "Some other error", number: -10000)) {
            try AppleScriptExecutor.mapAppleScriptError(errorInfo)
        }
    }

    @Test("nil errorInfo is a no-op (success path)")
    func nilErrorInfoIsSuccess() throws {
        // Should not throw.
        try AppleScriptExecutor.mapAppleScriptError(nil)
    }

    @Test("missing errorMessage falls back to 'Unknown AppleScript error'")
    func missingMessage() {
        let errorInfo: NSDictionary = [
            NSAppleScript.errorNumber: -2700,
        ]
        #expect(throws: Cd2HereError.appleScriptFailed(message: "Unknown AppleScript error", number: -2700)) {
            try AppleScriptExecutor.mapAppleScriptError(errorInfo)
        }
    }
}