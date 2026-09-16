# cd2here Development Plan

English | [简体中文](PLAN.zh-CN.md)

## Goal

Build two tiny, auditable macOS Finder toolbar applications:

- `cd2hereWindow.app`: always opens a new window in the selected terminal.
- `cd2hereTab.app`: opens a tab in the selected terminal's front window, or falls back to a new window.

The user chooses an installed terminal on first use. Normal clicks use the saved choice; Option-click changes it.

## Scope and constraints

- Swift with Foundation/AppKit; no SwiftUI.
- Shared core for Finder resolution, terminal selection, terminal backends, application flow, and errors.
- Finder and terminal integration through `NSAppleScript` / Apple Events.
- Initial backends: Ghostty, iTerm2, Terminal.app, WezTerm, Alacritty and Kitty; **adding a new backend touches 3 files**: one new controller file (conforming to `AppleScriptTerminalControlling` or `CLITerminalControlling`), five small edits to `TerminalController.swift` (new `TerminalKind` case + `displayName` + `bundleIdentifier` + `cliBinaryName` + `TerminalControllerFactory.make` switch arm), and one test in `TerminalControllerTests.swift`.
- No Finder Sync extension, daemon, network access, terminal configuration changes, or shell replacement.
- Do not enumerate or probe the target directory; Finder provides the path and the terminal owns file access.
- Both apps are `LSUIElement` applications and remain out of the Dock and Command-Tab switcher.
- Local builds and tests must not require a paid Apple Developer account.
- User documentation is maintained in English and Simplified Chinese.

## Finder resolution policy

`FinderSnapshot` is an enum with two unrepresentable variants: `.noWindow(directory)` and `.window(currentDirectory, selection, desktopDirectory)`. A folder/file selection without a Finder window is therefore a compile-time error, not a runtime fallback.

1. One selected folder: use that folder.
2. One selected file: use its parent directory.
3. No selection: use the front Finder window's current directory.
4. Multiple selections: use the front Finder window's current directory.
5. No Finder window: use Desktop.

## Implementation

### Module layout

`Shared/` is a single Swift package target (`Cd2HereCore`). The split between Foundation-only and AppKit-dependent code lives at the file boundary, not the package boundary:

| File | Foundation-only? | AppKit? |
| --- | --- | --- |
| `TerminalController.swift` | yes | — |
| `FinderContext.swift` | yes | — |
| `AppleScriptExecutor.swift` | yes | — |
| `AppleScriptLiteral.swift` | yes | — |
| `CommandExecutor.swift` | yes | — |
| `BinaryLocator.swift` | yes | — |
| `Cd2HereError.swift` | yes | — |
| `ShellLiteral.swift` | yes | — |
| 6 × `*TerminalController.swift` | yes | — |
| `TerminalKindUI.swift` | — | yes (`NSWorkspace.urlForApplication`) |
| `TerminalPreferences.swift` | yes (UserDefaults) | — |
| `AppRunner.swift` | — | yes (`NSApplication`, `NSAlert`) |
| `TerminalPicker.swift` | — | yes (`NSAlert`, `NSPopUpButton`) |

### Steps

1. Create a Swift package containing `Cd2HereCore` and unit tests.
2. Implement the Finder context, terminal backends, shared preferences, chooser, application flow, and errors in `Shared/`.
3. Create minimal entry points and property lists for `cd2hereWindow` and `cd2hereTab`.
4. Generate and retain an Xcode project from a checked-in XcodeGen specification.
5. Configure Apple Events usage text, automation entitlement, hardened runtime, and ad-hoc/local signing compatibility.
6. Add README, MIT license, and gitignore suitable for an open-source repository.

### Backend protocol extensions

`TerminalControlling` is split into two sub-protocols with default implementations:

- `AppleScriptTerminalControlling` — declares `static func script(mode:directory:) -> String`. `open` and `isCompatible` come from the default extension and dispatch through `AppleScriptExecutor`. Used by Ghostty / iTerm2 / Terminal.app.
- `CLITerminalControlling` — declares `binaryName`, `executor`, `binaryLocator`, `arguments(mode:directory:)`. `open` (binary-not-found check + run) and `isCompatible` (`binaryLocator() != nil`) come from the default extension. Used by WezTerm / Alacritty / Kitty.

Adding a new backend therefore means implementing one of these two protocols plus the four `TerminalKind` switches.

### Process model

`CommandExecuting.run` is fire-and-forget: it throws only on spawn failure and NSLogs non-zero exits asynchronously via `ProcessTracker` + `terminationHandler`. This is mandatory for CLI terminals whose main process is the GUI (Alacritty, Kitty, WezTerm `start`). `BinaryLocator.locateViaWhich` keeps synchronous semantics because it needs the exit code to decide "found".

## Interaction

1. First launch or missing saved terminal: show the terminal chooser.
2. Normal click: open immediately with the saved terminal.
3. Option-click: show the chooser, persist the selection, and perform the requested open action.
4. Uninstalled terminals remain visible but disabled in the chooser.

`TerminalKind.option` is computed via a static `[TerminalKind: TerminalOption]` cache (`@MainActor`), so the chooser does not re-probe on every read within a single launch.

## Verification

- Run Swift package tests for Finder policy, backend script compilation, escaping, selection policy, command-executor fire-and-forget, and option caching.
- Build both app targets with Xcode without requiring a development team.
- Inspect the resulting app bundles and property lists.
- Run static checks for accidental SwiftUI, networking, daemon, or shell-selection code.
- Keep the English and Simplified Chinese documentation behaviorally equivalent.

### Verified vs. unverified backends

Ghostty, iTerm2 and Terminal.app have been manually exercised by the maintainer on real hardware. WezTerm, Alacritty and Kitty are only covered by unit tests because the maintainer's machine does not have them installed. The unit tests verify only that the generated AppleScript or argv is syntactically valid; they do not verify that the terminal actually accepts the arguments, that remote-control sockets are reachable, or that the spawned process changes directory. This boundary is documented in the user-facing README under "Verified backends".

### Manual release matrix

- Finder state: one folder, one file, no selection, multiple selection, and no Finder window.
- Location: local folder, iCloud Drive, OneDrive or another File Provider domain, network volume, and removable volume.
- Terminal and mode: every supported backend in both window and tab modes, including tab fallback when no terminal window exists.
- Interaction: first launch, normal click, Option-click, chooser cancellation, saved terminal removed, and installed but incompatible terminal.
- Permissions: first Automation prompt, denied Automation permission, and denied Files and Folders permission in the selected terminal.
- Paths: spaces, quotes, non-ASCII characters, and a volume that becomes unavailable after Finder returns its path.

## Known integration boundary

Automated tests cover path policy, selection policy, escaping, and script construction. End-to-end automation requires a logged-in macOS GUI session and user-approved Apple Events permissions. The iTerm2 backend sends `cd <path> && clear` to the default profile's session, so that profile should start a local interactive shell.
