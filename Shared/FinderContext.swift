import Foundation

/// A snapshot of the relevant Finder state for resolving the target directory.
/// Two variants make illegal combinations (e.g. a folder selection without
/// an open Finder window) unrepresentable.
enum FinderSnapshot: Equatable {
    enum Selection: Equatable {
        case none
        case folder(String)
        case file(parentDirectory: String)
        case multiple
    }

    case noWindow(directory: String)
    case window(currentDirectory: String?, selection: Selection, desktopDirectory: String)

    var resolvedDirectory: String {
        switch self {
        case let .noWindow(directory):
            return directory
        case let .window(currentDirectory, selection, desktopDirectory):
            switch selection {
            case let .folder(path):
                return path
            case let .file(parentDirectory):
                return parentDirectory
            case .none, .multiple:
                // Normalise empty strings here too — `parseSnapshot` already
                // does this, but direct construction (tests, future callers)
                // also needs the desktop fallback rather than "".
                return (currentDirectory?.isEmpty == false ? currentDirectory : nil)
                    ?? desktopDirectory
            }
        }
    }
}

public struct FinderContext {
    private let executor: any AppleScriptExecuting
    private let desktopDirectory: String

    public init() {
        self.executor = AppleScriptExecutor()
        self.desktopDirectory = Self.defaultDesktopDirectory
    }

    init(
        executor: any AppleScriptExecuting,
        desktopDirectory: String = "/Users/test/Desktop"
    ) {
        self.executor = executor
        self.desktopDirectory = desktopDirectory
    }

    public func directory() throws -> String {
        let descriptor = try executor.execute(
            source: Self.snapshotScript(desktopDirectory: desktopDirectory)
        )
        let snapshot = try Self.parseSnapshot(descriptor)
        let rawPath = snapshot.resolvedDirectory
        guard rawPath.hasPrefix("/") else {
            throw Cd2HereError.invalidDirectory(rawPath)
        }
        return (rawPath as NSString).standardizingPath
    }

    static func parseSnapshot(_ descriptor: NSAppleEventDescriptor) throws -> FinderSnapshot {
        guard descriptor.numberOfItems >= 2 else {
            throw Cd2HereError.invalidFinderResponse
        }

        let values = (1...descriptor.numberOfItems).map {
            descriptor.atIndex($0)?.stringValue ?? ""
        }
        guard let hasWindow = Int(values[0]) else {
            throw Cd2HereError.invalidFinderResponse
        }
        let desktop = values[1]
        guard hasWindow != 0 else {
            return .noWindow(directory: desktop)
        }
        guard values.count >= 5 else {
            throw Cd2HereError.invalidFinderResponse
        }

        let current = values[2]
        // Normalise empty strings to nil so the `?? desktopDirectory`
        // fallback in `resolvedDirectory` actually triggers when Finder
        // returns a blank current-directory (which it does in some edge
        // cases, e.g. a freshly opened window whose target is still
        // resolving).
        let currentDirectory: String? = current.isEmpty ? nil : current
        let count = Int(values[3]) ?? 0
        let selection: FinderSnapshot.Selection
        if count == 0 {
            selection = .none
        } else if count > 1 {
            selection = .multiple
        } else {
            switch values[4] {
            case "folder":
                guard values.count >= 6 else { throw Cd2HereError.invalidFinderResponse }
                selection = .folder(values[5])
            case "file":
                guard values.count >= 6 else { throw Cd2HereError.invalidFinderResponse }
                selection = .file(parentDirectory: values[5])
            default:
                selection = .none
            }
        }

        return .window(currentDirectory: currentDirectory, selection: selection, desktopDirectory: desktop)
    }

    static var defaultDesktopDirectory: String {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.path
            ?? (NSHomeDirectory() as NSString).appendingPathComponent("Desktop")
    }

    static func snapshotScript(desktopDirectory: String) -> String {
        """
    set desktopPath to \(AppleScriptLiteral.string(desktopDirectory))
    tell application "Finder"
        if (count of Finder windows) is 0 then
            return {"0", desktopPath}
        end if

        set selectedItems to selection
        set selectedCount to count of selectedItems
        if selectedCount is 1 then
            set selectedItem to item 1 of selectedItems
            set selectedClass to class of selectedItem
            if selectedClass is folder or selectedClass is disk then
                return {"1", desktopPath, "", "1", "folder", POSIX path of (selectedItem as alias)}
            end if

            return {"1", desktopPath, "", "1", "file", POSIX path of (container of selectedItem as alias)}
        end if

        try
            set currentPath to POSIX path of (target of front Finder window as alias)
        on error
            set currentPath to desktopPath
        end try
        return {"1", desktopPath, currentPath, selectedCount as text, "none"}
    end tell
    """
    }
}
