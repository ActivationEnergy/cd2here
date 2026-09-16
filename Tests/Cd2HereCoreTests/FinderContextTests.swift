import Foundation
import Testing
@testable import Cd2HereCore

@Suite("Finder location policy")
struct FinderContextTests {
    @Test("No Finder window uses the supplied directory")
    func noWindow() {
        let snapshot = FinderSnapshot.noWindow(directory: "/Users/test/Desktop/")
        #expect(snapshot.resolvedDirectory == "/Users/test/Desktop/")
    }

    @Test("One selected folder uses that folder")
    func selectedFolder() {
        let snapshot = windowSnapshot(selection: .folder("/tmp/project/"))
        #expect(snapshot.resolvedDirectory == "/tmp/project/")
    }

    @Test("One selected file uses its parent")
    func selectedFile() {
        let snapshot = windowSnapshot(selection: .file(parentDirectory: "/tmp/project/"))
        #expect(snapshot.resolvedDirectory == "/tmp/project/")
    }

    @Test("No or multiple selections use the current directory", arguments: [
        FinderSnapshot.Selection.none,
        FinderSnapshot.Selection.multiple,
    ])
    func currentDirectory(selection: FinderSnapshot.Selection) {
        let snapshot = windowSnapshot(selection: selection)
        #expect(snapshot.resolvedDirectory == "/tmp/current/")
    }

    @Test("Empty current directory with no/multiple selection falls back to desktop")
    func emptyCurrentDirectoryFallback() {
        let snapshot = FinderSnapshot.window(
            currentDirectory: "",
            selection: .none,
            desktopDirectory: "/Users/test/Desktop"
        )
        #expect(snapshot.resolvedDirectory == "/Users/test/Desktop")
    }

    @Test("Illegal combination (folder selection without window) cannot be constructed")
    func illegalCombinationUnrepresentable() {
        // This is a compile-time guarantee, not a runtime check. We use the
        // `_ = .noWindow(directory:)` form to confirm the API only offers
        // the no-window case for "no Finder window" states.
        let snapshot: FinderSnapshot = .noWindow(directory: "/tmp/")
        #expect(snapshot.resolvedDirectory == "/tmp/")
    }

    @Test("Finder paths are passed through without probing the file system")
    func unmountedOrProtectedPath() throws {
        let response = NSAppleEventDescriptor.list()
        response.insert(NSAppleEventDescriptor(string: "0"), at: 1)
        response.insert(NSAppleEventDescriptor(string: "/Volumes/External Card/"), at: 2)

        let context = FinderContext(executor: StubAppleScriptExecutor(result: response))
        #expect(try context.directory() == "/Volumes/External Card")
    }

    @Test("Desktop fallback is injected without Finder alias coercion")
    func desktopFallbackIsInjected() {
        let desktop = FinderContext.defaultDesktopDirectory
        let script = FinderContext.snapshotScript(desktopDirectory: desktop)

        #expect(desktop.hasPrefix("/"))
        #expect(script.contains("set desktopPath to \(AppleScriptLiteral.string(desktop))"))
        #expect(!script.contains("desktop folder as alias"))
    }

    @Test("parseSnapshot builds .noWindow when first item is 0")
    func parseSnapshotNoWindow() throws {
        let descriptor = NSAppleEventDescriptor.list()
        descriptor.insert(NSAppleEventDescriptor(string: "0"), at: 1)
        descriptor.insert(NSAppleEventDescriptor(string: "/Users/test/Desktop"), at: 2)
        let snapshot = try FinderContext.parseSnapshot(descriptor)
        #expect(snapshot == .noWindow(directory: "/Users/test/Desktop"))
    }

    @Test("parseSnapshot builds .window with folder selection")
    func parseSnapshotWindowFolder() throws {
        let descriptor = NSAppleEventDescriptor.list()
        descriptor.insert(NSAppleEventDescriptor(string: "1"), at: 1)
        descriptor.insert(NSAppleEventDescriptor(string: "/Users/test/Desktop"), at: 2)
        descriptor.insert(NSAppleEventDescriptor(string: "/tmp/front/"), at: 3)
        descriptor.insert(NSAppleEventDescriptor(string: "1"), at: 4)
        descriptor.insert(NSAppleEventDescriptor(string: "folder"), at: 5)
        descriptor.insert(NSAppleEventDescriptor(string: "/tmp/selected/"), at: 6)
        let snapshot = try FinderContext.parseSnapshot(descriptor)
        #expect(snapshot == .window(
            currentDirectory: "/tmp/front/",
            selection: .folder("/tmp/selected/"),
            desktopDirectory: "/Users/test/Desktop"
        ))
    }

    @Test("parseSnapshot builds .window with file selection (parent dir)")
    func parseSnapshotWindowFile() throws {
        let descriptor = NSAppleEventDescriptor.list()
        descriptor.insert(NSAppleEventDescriptor(string: "1"), at: 1)
        descriptor.insert(NSAppleEventDescriptor(string: "/Users/test/Desktop"), at: 2)
        descriptor.insert(NSAppleEventDescriptor(string: "/tmp/front/"), at: 3)
        descriptor.insert(NSAppleEventDescriptor(string: "1"), at: 4)
        descriptor.insert(NSAppleEventDescriptor(string: "file"), at: 5)
        descriptor.insert(NSAppleEventDescriptor(string: "/tmp/parent/"), at: 6)
        let snapshot = try FinderContext.parseSnapshot(descriptor)
        #expect(snapshot == .window(
            currentDirectory: "/tmp/front/",
            selection: .file(parentDirectory: "/tmp/parent/"),
            desktopDirectory: "/Users/test/Desktop"
        ))
    }

    @Test("parseSnapshot builds .window with multiple selection")
    func parseSnapshotWindowMultiple() throws {
        let descriptor = NSAppleEventDescriptor.list()
        descriptor.insert(NSAppleEventDescriptor(string: "1"), at: 1)
        descriptor.insert(NSAppleEventDescriptor(string: "/Users/test/Desktop"), at: 2)
        descriptor.insert(NSAppleEventDescriptor(string: "/tmp/front/"), at: 3)
        descriptor.insert(NSAppleEventDescriptor(string: "3"), at: 4)
        descriptor.insert(NSAppleEventDescriptor(string: "none"), at: 5)
        let snapshot = try FinderContext.parseSnapshot(descriptor)
        #expect(snapshot == .window(
            currentDirectory: "/tmp/front/",
            selection: .multiple,
            desktopDirectory: "/Users/test/Desktop"
        ))
    }

    @Test("parseSnapshot rejects malformed responses")
    func parseSnapshotRejectsMalformed() {
        let empty = NSAppleEventDescriptor.list()
        #expect(throws: Cd2HereError.self) {
            _ = try FinderContext.parseSnapshot(empty)
        }
        let badHasWindow = NSAppleEventDescriptor.list()
        badHasWindow.insert(NSAppleEventDescriptor(string: "not-a-number"), at: 1)
        badHasWindow.insert(NSAppleEventDescriptor(string: "/tmp/desktop"), at: 2)
        #expect(throws: Cd2HereError.self) {
            _ = try FinderContext.parseSnapshot(badHasWindow)
        }
    }

    private func windowSnapshot(selection: FinderSnapshot.Selection) -> FinderSnapshot {
        FinderSnapshot.window(
            currentDirectory: "/tmp/current/",
            selection: selection,
            desktopDirectory: "/Users/test/Desktop/"
        )
    }
}

private struct StubAppleScriptExecutor: AppleScriptExecuting {
    let result: NSAppleEventDescriptor

    func execute(source: String) throws -> NSAppleEventDescriptor {
        result
    }
}
