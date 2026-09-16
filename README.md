# cd2here

> Send the directory you are looking at in Finder straight into a terminal — in one click.

<p>
  <img src="Design/IconMasters/cd2hereWindow.png" alt="cd2hereWindow" width="72" />
  &nbsp;&nbsp;
  <img src="Design/IconMasters/cd2hereTab.png" alt="cd2hereTab" width="72" />
</p>

**English** | [简体中文](README.zh-CN.md)

cd2here is two tiny macOS apps that live in the Finder toolbar. They ask Finder for the location you are currently looking at, then ask your terminal of choice to open it as the working directory.

- **`cd2hereWindow.app`** — always opens a new window in the selected terminal.
- **`cd2hereTab.app`** — opens a tab in the front window of the selected terminal; falls back to a new window when no window is open.

Both apps are `LSUIElement` — no Dock icon, no entry in the ⌘Tab app switcher, no menubar item, no preferences window. They launch, do one thing, and quit.

## Install

### Homebrew (recommended)

```sh
brew install --cask cd2here
```

Then drag `cd2hereWindow.app` and `cd2hereTab.app` from `/Applications/Caskroom/cd2here/...` into the Finder toolbar as described below.

### Download a prebuilt binary

1. Download `cd2here-v0.4-darwin-universal.zip` from [the v0.4 release page](https://github.com/ActivationEnergy/cd2here/releases/tag/v0.4).
2. Unzip it.
3. Drag `cd2hereWindow.app` and `cd2hereTab.app` to `/Applications`.

Because the binaries are ad-hoc unsigned builds, the first launch will be blocked by Gatekeeper. The dialog only shows **Move to Trash** and **Done** buttons (no "Open" option) on recent macOS versions, so the only way to approve the app is through System Settings:

1. Click **Done** to dismiss the dialog.
2. Open **System Settings → Privacy & Security**. Scroll to the bottom of the page.
3. Next to the line "`cd2hereWindow.app` (or `cd2hereTab.app`) was blocked…", click **Open Anyway**.
4. macOS will ask one more time to confirm; click **Open**.

After this one-time approval, double-clicking the app (or clicking it in the toolbar) no longer triggers the Gatekeeper dialog.

### Build from source

See [Build from source](#build-from-source) below.

## Use

### Add the apps to the Finder toolbar

cd2here ships as two small AppKit apps — `cd2hereWindow.app` (always-new-window) and `cd2hereTab.app` (new-tab-or-fallback-to-window). Drag each from `/Applications` onto the Finder toolbar of any open window.

If Finder does not accept the drag, use **View → Customize Toolbar…** (or hold `⌘` while dragging) — these put the toolbar in customize mode. Drag should be the common case after Gatekeeper has been approved for the first time.

### First click

The first time you click a cd2here toolbar icon, macOS shows a Gatekeeper dialog titled **"'cd2hereWindow.app' Not Opened"** with the message "Apple could not verify 'cd2hereWindow.app' is free of malware that may harm your Mac or compromise your privacy." The dialog typically only offers **Move to Trash** and **Done** (no direct "Open" option) on recent macOS versions, because the binary is ad-hoc unsigned — it is missing a Developer ID signature.

![Gatekeeper Not Opened dialog](docs/screenshots/gatekeeper-warning.png)

To proceed:

1. Click **Done** to dismiss the dialog.
2. Open **System Settings → Privacy & Security**. Scroll to the bottom of the page.
3. Next to the line "`cd2hereWindow.app` (or `cd2hereTab.app`) was blocked…", click **Open Anyway**.
4. macOS will ask one more time to confirm; click **Open**.

After this one-time approval, the click goes through. macOS then asks for **Automation** permission — to control Finder and your chosen terminal. Grant it in **System Settings → Privacy & Security → Automation**. `cd2hereWindow` and `cd2hereTab` each appear as a separate permission target because they have distinct bundle IDs; grant both.

The first time a terminal chooser appears. Pick the terminal you want to use. Both apps remember this choice.

![Terminal chooser alert](docs/screenshots/terminal_chooser.png)

### Subsequent clicks

- Click `cd2hereWindow` to always open a new window in your selected terminal.
- Click `cd2hereTab` to open a tab in the front window of your selected terminal.
- Hold **Option** while clicking either icon to change the default terminal.

That's it. The chosen terminal will start with its working directory set to the folder you had selected in Finder.

## Supported terminals

| Terminal | Mechanism |
| --- | --- |
| **Ghostty** | AppleScript surface configuration |
| **iTerm2** | `cd <dir> && clear` injected into default profile session |
| **Terminal.app** | `do script "cd <dir> && clear"` |
| **WezTerm** | `wezterm start --always-new-process --cwd <path>` (window) or `wezterm start --new-tab --cwd <path>` (tab) |
| **Alacritty** | `alacritty --working-directory <path>` for both modes (no tab IPC; falls back to new window) |
| **Kitty** | `kitty --directory <path>` (window) or `kitty @ launch --type tab --cwd <path>` (tab; requires `allow_remote_control yes`) |

Verified manually on real hardware: Ghostty, iTerm2, Terminal.app.
Unit-test coverage only (no manual smoke test): WezTerm, Alacritty, Kitty.

## How cd2here decides which directory to open

cd2here asks Finder once, applies the policy below, and hands the path to the terminal.

| Finder state | Directory opened |
| --- | --- |
| One folder selected | That folder |
| One file selected | The file's parent directory |
| Nothing selected | The front Finder window's current directory |
| Multiple items selected | The front Finder window's current directory |
| No Finder window open | `~/Desktop` |

## Terminal behaviour

**Ghostty** exposes an AppleScript surface configuration that accepts an initial working directory. cd2here sets it before opening the surface, so the shell starts in the right place with no post-hoc commands.

**iTerm2 and Terminal.app** do not expose an AppleScript property for setting an initial working directory. cd2here therefore uses Terminal.app's `do script` (or iTerm2's `create window` / `create tab` plus `write text`) to create the session with the **default profile** (it does not override the profile command or pick a shell) and then writes a safely single-quoted `cd <path>` command followed by `clear` once the session is ready.

For Terminal.app specifically, `do script` at the top level of `tell application "Terminal"` opens a new window, and `do script` inside `tell front window` opens a new tab in the front window.

**WezTerm, Alacritty and Kitty** are driven through their native CLI rather than AppleScript. See the [Supported terminals](#supported-terminals) table for the exact argv each backend uses.

## Permissions, cloud drives, and external folders

- **cd2here itself** normally needs only Automation permission for Finder and the selected terminal. Grant this under **System Settings → Privacy & Security → Automation**. Because `cd2hereWindow` and `cd2hereTab` ship as separate bundle IDs, macOS asks for the Automation grant **separately for each** — you will see one prompt per (app × terminal) combination the first time around.
- **The terminal** is the application that actually enters and reads the directory. macOS may ask it for **Files and Folders** access when the path lives in Desktop, Documents, Downloads, iCloud Drive, OneDrive or another File Provider domain, a network volume, or removable storage. Grant that access under **System Settings → Privacy & Security → Files and Folders**.
- External volumes must be mounted before clicking cd2here. If the Finder front window's directory cannot be resolved (e.g. a network volume drops while cd2here is reading it), cd2here **silently falls back to `~/Desktop`** rather than surfacing an error — the terminal will appear in the wrong place. Verify by re-clicking once the volume is back.
- Cloud-only files may trigger a download by the corresponding provider. That is expected and is the provider's behaviour, not cd2here's.

If a previously granted Automation permission is denied, re-enable it from **System Settings → Privacy & Security → Automation** and click the toolbar app again.

## System requirements

- macOS 13 (Ventura) or later — runs on both Apple Silicon and Intel Macs
- At least one of [Ghostty](https://ghostty.org), [iTerm2](https://iterm2.com), the built-in Terminal.app, [WezTerm](https://wezterm.org), [Alacritty](https://alacritty.org) or [Kitty](https://sw.kovidgoyal.net/kitty/). The latter three must be installed as `.app` bundles (e.g. via `brew install --cask …`) or have their CLI binary on `PATH`.

## Architecture

The two minimal AppKit entry points (`cd2hereWindow/main.swift`, `cd2hereTab/main.swift`) both call `AppRunner.run(mode:)`. Everything else lives in the `Cd2HereCore` Swift package and is shared:

| File | Responsibility |
| --- | --- |
| `AppRunner.swift` | Coordinates one launch, drives the selection policy, presents actionable errors for spawn / AppleScript failures. CLI non-zero exits are NSLog-only. |
| `FinderContext.swift` | Asks Finder for the current state via Apple Events and applies the path policy. |
| `TerminalController.swift` | Terminal identity, installed / incompatible detection, controller dispatch, sub-protocols (`AppleScriptTerminalControlling`, `CLITerminalControlling`). |
| `TerminalKindUI.swift` | UI-layer extension on `TerminalKind` that resolves `option` (uses `NSWorkspace.urlForApplication` and the option cache). |
| `GhosttyTerminalController.swift` | Opens Ghostty windows and tabs with an initial working directory. |
| `ITerm2TerminalController.swift` | Creates iTerm2 sessions with the default profile and `cd`s into them. |
| `TerminalAppTerminalController.swift` | Opens Terminal.app windows or tabs via `do script` and `cd`s into them. |
| `WezTermTerminalController.swift` | Spawns WezTerm via `wezterm start` with `--always-new-process` (window) or `--new-tab` (tab). |
| `AlacrittyTerminalController.swift` | Opens Alacritty windows via `alacritty --working-directory`. |
| `KittyTerminalController.swift` | Opens Kitty windows via `kitty --directory`; tabs via `kitty @ launch` with fallback to a new window. |
| `CommandExecutor.swift` | Wraps `Process`. `run` (fire-and-forget) only throws on spawn failure; non-zero exits go to NSLog. `runAndWait` is the synchronous variant used for fast probes (e.g. Kitty tab), turning non-zero exit + stderr into `Cd2HereError.commandFailed`. |
| `BinaryLocator.swift` | Resolves the absolute path of CLI binaries used by the three CLI-based controllers. |
| `ShellLiteral.swift` | POSIX shell single-quote escaping, shared by the iTerm2 and Terminal.app controllers. |
| `TerminalPicker.swift` | First-use and Option-click chooser dialog. |
| `TerminalPreferences.swift` | Persists the shared default terminal in `UserDefaults`. |
| `AppleScriptExecutor.swift` | Compiles and runs AppleScript under a global lock. |
| `AppleScriptLiteral.swift` | AppleScript string-literal escaping. |
| `Cd2HereError.swift` | User-facing error types. |

Adding a new terminal requires touching **3 files**: (1) one new controller file conforming to `AppleScriptTerminalControlling` or `CLITerminalControlling`; (2) five small edits to `TerminalController.swift` (new `TerminalKind` case + `displayName` + `bundleIdentifier` + `cliBinaryName` + `TerminalControllerFactory.make` switch arm); (3) one test in `TerminalControllerTests.swift`.

## Build from source

```sh
git clone https://github.com/ActivationEnergy/cd2here.git
cd cd2here

# Run the core unit tests
swift test

# (Optional) regenerate cd2here.xcodeproj after editing project.yml
xcodegen generate

# Build the two apps without code signing (works without an Apple Developer account)
xcodebuild -project cd2here.xcodeproj -scheme cd2hereWindow -configuration Release CODE_SIGNING_ALLOWED=NO build
xcodebuild -project cd2here.xcodeproj -scheme cd2hereTab     -configuration Release CODE_SIGNING_ALLOWED=NO build
```

Built `.app` bundles land under `~/Library/Developer/Xcode/DerivedData/`; copy them to `/Applications` (or another stable location — avoid iCloud-synced folders, which can break Gatekeeper on app bundles) before adding them to the toolbar.

## Testing

### Verified backends

The following terminals have been **manually exercised** by the maintainer on real hardware, covering all Finder states (one folder, one file, no selection, multiple selection, no Finder window) and both `window` and `tab` modes:

- **Ghostty**
- **iTerm2**
- **Terminal.app**

The following terminals have only had their AppleScript / argv generation **covered by unit tests** — they have *not* been manually verified because the maintainer's machine does not have them installed:

- WezTerm
- Alacritty
- Kitty

The unit tests guarantee only that the generated AppleScript or argv is syntactically valid. They do not guarantee that the terminal actually accepts the arguments, that remote-control sockets are reachable, or that the spawned process changes directory. **Bug reports for the untested backends are encouraged** and will be triaged quickly. If you are adding a new backend, please add the missing manual verification too.

### Automated tests

`swift test` covers:

- All five Finder state → resolved directory branches.
- The desktop fallback path (no `desktop folder as alias` coercion).
- Path pass-through for volumes that may be unmounted after Finder returns them (Finder is trusted as the source of truth).
- Ghostty, iTerm2 and Terminal.app AppleScript generation for both `window` and `tab` modes, including the tab-mode fallback when no terminal window exists.
- WezTerm argv construction for both modes (CLI-based; no AppleScript to compile).
- AppleScript compilation for whichever AppleScript-based backend is installed locally.
- AppleScript and POSIX shell single-quote escaping for paths containing backslashes, double quotes, newlines, and consecutive apostrophes.

End-to-end automation requires a logged-in macOS GUI session and approved Apple Events permissions, so it is documented in the [manual release matrix](PLAN.md#manual-release-matrix) rather than automated.

## Known limits

- macOS only. The project depends on `NSAppleScript` and the `LSUIElement` Info.plist key.
- Terminal support is currently Ghostty, iTerm2, Terminal.app, WezTerm, Alacritty and Kitty. Warp and Hyper are intentionally not supported: their AppleScript surface does not let a third-party app set an initial working directory, and the only workaround (keyboard synthesis) would require Accessibility permission and would not be reliable.
- The iTerm2 and Terminal.app backends write a `cd` into the session; they therefore inherit the default profile / default settings of those apps. Configure them to start a local interactive shell if they do not already.
- Kitty's tab mode requires `allow_remote_control yes` in `kitty.conf`; without it, the tab click falls back to opening a new window. The probe is synchronous (`runAndWait`), so the failure path is reliable.
- Alacritty does not have a public CLI/IPC surface for creating new tabs in an existing window, so `cd2hereTab.app` opens a new Alacritty window. Use `cd2hereWindow.app` if you do not want this.
- Apple Events Automation is a per-target permission: cd2here has to be re-allowed for Finder and the chosen terminal separately if macOS resets them. Because cd2hereWindow and cd2hereTab ship as separate bundle IDs, **each app** is a separate permission target — granting one does not grant the other.
- CLI backends (WezTerm / Alacritty / Kitty) launch their subprocess in fire-and-forget mode. **A non-zero exit is logged via `NSLog` only and does not surface an alert** — cd2here exits as soon as the spawn call returns, so there is no UI surface to display the error. Spawn failures (ENOENT, EACCES, launchd refusal) **do** surface an alert. For diagnostic logs, watch Console.app filtered by `cd2here:`.
- Kitty's tab mode requires `allow_remote_control yes` in `kitty.conf`; without it, the tab click falls back to opening a new window. The probe is synchronous (`runAndWait`), so the failure path is reliable.
- Alacritty does not have a public CLI/IPC surface for creating new tabs in an existing window, so `cd2hereTab.app` opens a new Alacritty window. Use `cd2hereWindow.app` if you do not want this.

## License

MIT. See [LICENSE](LICENSE).