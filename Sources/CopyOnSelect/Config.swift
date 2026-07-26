import Foundation

/// User configuration. Read from disk at launch; never written to by this app.
///
/// The app reads this file and nothing else. It never writes selection or
/// clipboard contents anywhere — not to disk, not to stdout, not to a log.
struct Config: Codable {
    /// Apps that already implement copy-on-select, or where a synthetic copy is
    /// unsafe. See README "Why an exclusion list".
    var excludedBundleIDs: [String]

    /// Settle delay before reading the selection. Serves two purposes: it lets
    /// the target app finish updating its accessibility state (an immediate read
    /// races), and it coalesces incremental selection expansion into one write.
    var settleMilliseconds: Int

    /// Selections longer than this are ignored. Cmd+A in a large document can
    /// return megabytes and take seconds to marshal across the AX boundary.
    var maxCharacters: Int

    /// Once accessibility has confirmed a safe, non-empty selection, ask the
    /// app to copy it itself rather than using the text accessibility returned.
    ///
    /// The app's own copy is higher fidelity: it preserves bullet markers,
    /// numbering and line breaks, which accessibility flattens or drops
    /// entirely. Measured 2026-07-25: Chrome and Linear return zero newlines,
    /// and Notes returns no bullet characters at all, because list markers are
    /// formatting rather than text.
    ///
    /// Accessibility still decides *whether* to copy and whether it is safe;
    /// this only changes where the text comes from. If the copy produces
    /// nothing — secure input mode, an app that rebinds Cmd+C — the
    /// accessibility text is used instead, so this degrades rather than fails.
    var preferNativeCopy: Bool

    /// Apps to exclude from `preferNativeCopy`, forcing the accessibility text.
    /// An escape hatch for anywhere the synthetic copy misbehaves.
    var nativeCopyDisabledApps: [String]

    /// Write only plain text, discarding the styling flavors an app's own copy
    /// puts on the pasteboard. List structure survives — bullets and newlines
    /// are characters in the plain-text flavor — while fonts and colors do not.
    var plainTextOnly: Bool

    /// Last resort only: synthesize Cmd+C when accessibility finds **no**
    /// selection at all in a text element. Distinct from `preferNativeCopy`,
    /// which fires when a selection *was* found.
    ///
    /// Off by default because firing blind is what caused an audible system
    /// beep in apps where nothing was selected.
    var enableCopyFallback: Bool

    /// Minimum drag distance, in points, to count as a selection drag.
    var dragThreshold: Double

    /// How far up the accessibility tree to look for an element that can answer
    /// "what is selected". Browsers and PDF views hit-test to a deep leaf while
    /// implementing the selection on an ancestor.
    var maxAncestorWalk: Int

    /// Mark clipboard writes `org.nspasteboard.ConcealedType`. Well-behaved
    /// clipboard managers and sync services skip concealed items — good for
    /// privacy, but it also means selections will not appear in clipboard
    /// history. Off by default so history still works; turn on if you would
    /// rather selections never reach Universal Clipboard or a history app.
    var markClipboardConcealed: Bool

    static let `default` = Config(
        excludedBundleIDs: [
            // Finder: a drag here is a file drag. A synthetic Cmd+C would put
            // *files* on the clipboard.
            "com.apple.finder",

            // Terminals and editors: Claude Code's TUI already copies on
            // selection (OSC 52) and captures mouse/clipboard handling itself.
            // Terminals also run tmux/vim with mouse reporting, where a drag is
            // consumed by the program and no selection exists at all.
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "dev.warp.Warp-Stable",
            "com.mitchellh.ghostty",
            "net.kovidgoyal.kitty",
            "org.alacritty",
            "com.github.wez.wezterm",
            "com.todesktop.230313mzl4w4u92", // Cursor
            "com.microsoft.VSCode",
            "com.microsoft.VSCodeInsiders",
        ],
        settleMilliseconds: 180,
        maxCharacters: 1_000_000,
        preferNativeCopy: true,
        nativeCopyDisabledApps: [],
        plainTextOnly: true,
        enableCopyFallback: false,
        dragThreshold: 4.0,
        // Measured 2026-07-25 across Safari, Chrome and Linear: every real
        // selection was answered at depth 0 by the element under the cursor.
        // A deep walk was neither necessary nor sufficient — the earlier
        // failures were a role-gating bug, not insufficient depth. A few levels
        // are kept for apps that answer on a container instead.
        maxAncestorWalk: 5,
        markClipboardConcealed: false
    )

    /// Keeps user-supplied values in a range where the app still behaves.
    /// `maxAncestorWalk: 0` would make it a silent no-op; `maxCharacters: 0`
    /// would send every selection to the Cmd+C fallback.
    func clamped() -> Config {
        var copy = self
        copy.settleMilliseconds = min(max(settleMilliseconds, 0), 5000)
        copy.maxCharacters = max(maxCharacters, 1)
        copy.dragThreshold = min(max(dragThreshold, 0), 200)
        copy.maxAncestorWalk = min(max(maxAncestorWalk, 1), 64)
        return copy
    }

    /// Every key is optional on decode, falling back to the default. A config
    /// written against an older version keeps working when new keys are added,
    /// instead of failing to decode and silently reverting everything —
    /// including the user's exclusion list — to defaults.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Config.default
        excludedBundleIDs =
            try container.decodeIfPresent([String].self, forKey: .excludedBundleIDs)
            ?? fallback.excludedBundleIDs
        settleMilliseconds =
            try container.decodeIfPresent(Int.self, forKey: .settleMilliseconds)
            ?? fallback.settleMilliseconds
        maxCharacters =
            try container.decodeIfPresent(Int.self, forKey: .maxCharacters) ?? fallback.maxCharacters
        preferNativeCopy =
            try container.decodeIfPresent(Bool.self, forKey: .preferNativeCopy)
            ?? fallback.preferNativeCopy
        nativeCopyDisabledApps =
            try container.decodeIfPresent([String].self, forKey: .nativeCopyDisabledApps)
            ?? fallback.nativeCopyDisabledApps
        plainTextOnly =
            try container.decodeIfPresent(Bool.self, forKey: .plainTextOnly) ?? fallback.plainTextOnly
        enableCopyFallback =
            try container.decodeIfPresent(Bool.self, forKey: .enableCopyFallback)
            ?? fallback.enableCopyFallback
        dragThreshold =
            try container.decodeIfPresent(Double.self, forKey: .dragThreshold)
            ?? fallback.dragThreshold
        maxAncestorWalk =
            try container.decodeIfPresent(Int.self, forKey: .maxAncestorWalk)
            ?? fallback.maxAncestorWalk
        markClipboardConcealed =
            try container.decodeIfPresent(Bool.self, forKey: .markClipboardConcealed)
            ?? fallback.markClipboardConcealed
    }

    init(
        excludedBundleIDs: [String], settleMilliseconds: Int, maxCharacters: Int,
        preferNativeCopy: Bool, nativeCopyDisabledApps: [String], plainTextOnly: Bool,
        enableCopyFallback: Bool, dragThreshold: Double, maxAncestorWalk: Int,
        markClipboardConcealed: Bool
    ) {
        self.excludedBundleIDs = excludedBundleIDs
        self.settleMilliseconds = settleMilliseconds
        self.maxCharacters = maxCharacters
        self.preferNativeCopy = preferNativeCopy
        self.nativeCopyDisabledApps = nativeCopyDisabledApps
        self.plainTextOnly = plainTextOnly
        self.enableCopyFallback = enableCopyFallback
        self.dragThreshold = dragThreshold
        self.maxAncestorWalk = maxAncestorWalk
        self.markClipboardConcealed = markClipboardConcealed
    }

    static var fileURL: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/copy-on-select/config.json")
    }

    /// Loads config, falling back to defaults. A malformed file is reported to
    /// stderr and the defaults are used, so a typo can never leave the app in a
    /// state where it silently copies from excluded apps.
    static func load() -> Config {
        guard let data = try? Data(contentsOf: fileURL) else { return .default }
        do {
            return try JSONDecoder().decode(Config.self, from: data).clamped()
        } catch {
            FileHandle.standardError.write(
                "copy-on-select: config at \(fileURL.path) is invalid (\(error)); using defaults\n"
                    .data(using: .utf8)!)
            return .default
        }
    }
}
