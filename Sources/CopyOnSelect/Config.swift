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

    /// Apps where, once accessibility has confirmed a safe selection, the app
    /// is asked to copy it itself instead of using the text accessibility
    /// returned.
    ///
    /// An **allowlist**, not a global default, because asking the app to copy
    /// means synthesizing a keystroke, and that hands control of the result to
    /// the app: a web page can register a copy handler that rewrites what lands
    /// on the clipboard. The accessibility read cannot be influenced that way.
    /// So the higher-fidelity route is used only where it measurably helps.
    ///
    /// Measured 2026-07-25: Chrome and Linear return zero newlines and Notes
    /// returns no bullet characters, because list markers are formatting rather
    /// than text. Safari needs nothing here — its marker path already preserves
    /// line breaks.
    var preferNativeCopyApps: [String]

    /// Use the app's own copy everywhere rather than only in
    /// `preferNativeCopyApps`. Structure and styling everywhere — the result is
    /// what pressing ⌘C yourself would produce, with the correspondence check
    /// rejecting anything a page's copy handler injected. The risk mechanism is
    /// identical to a manual ⌘C; this only fires it on more occasions.
    var preferNativeCopyEverywhere: Bool

    /// Apps where the native copy is never used, even in everywhere-mode.
    /// The per-app escape hatch for an app whose ⌘C misbehaves.
    var nativeCopyDisabledApps: [String]

    /// If something else wrote to the clipboard while this gesture was being
    /// resolved, leave it alone.
    ///
    /// Terminals with their own copy-on-select — Claude Code's TUI via OSC 52,
    /// iTerm2, VS Code's `terminal.integrated.copyOnSelection` — copy the same
    /// selection a moment before we would. Deferring keeps their result, which
    /// is authoritative for their own content, instead of overwriting it with a
    /// possibly different accessibility reading.
    ///
    /// General rather than app-specific: no list to maintain, and it fails in
    /// the safe direction — the worst case is skipping a copy that had already
    /// been made correctly.
    var yieldToExistingCopy: Bool

    /// Discard the styling flavors an app's own copy puts on the pasteboard,
    /// keeping only plain text. List structure survives either way — bullets
    /// and newlines are real characters in the plain-text flavor — so this only
    /// controls fonts, colors and other formatting.
    ///
    /// Off by default: pasting keeps the source's formatting, which is what
    /// pressing ⌘C yourself would do.
    ///
    /// Only affects apps in `preferNativeCopyApps`. Everywhere else the text
    /// comes from accessibility, which returns a plain string and has no
    /// styling to preserve in the first place.
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
        // Seeded from measurement: these are the apps whose accessibility text
        // loses list structure. Safari is deliberately absent.
        preferNativeCopyApps: [
            "com.google.Chrome",
            "com.linear",
            "com.apple.Notes",
        ],
        preferNativeCopyEverywhere: true,
        nativeCopyDisabledApps: [],
        yieldToExistingCopy: true,
        plainTextOnly: false,
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
        preferNativeCopyApps =
            try container.decodeIfPresent([String].self, forKey: .preferNativeCopyApps)
            ?? fallback.preferNativeCopyApps
        preferNativeCopyEverywhere =
            try container.decodeIfPresent(Bool.self, forKey: .preferNativeCopyEverywhere)
            ?? fallback.preferNativeCopyEverywhere
        nativeCopyDisabledApps =
            try container.decodeIfPresent([String].self, forKey: .nativeCopyDisabledApps)
            ?? fallback.nativeCopyDisabledApps
        yieldToExistingCopy =
            try container.decodeIfPresent(Bool.self, forKey: .yieldToExistingCopy)
            ?? fallback.yieldToExistingCopy
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
        preferNativeCopyApps: [String], preferNativeCopyEverywhere: Bool,
        nativeCopyDisabledApps: [String], yieldToExistingCopy: Bool, plainTextOnly: Bool,
        enableCopyFallback: Bool, dragThreshold: Double, maxAncestorWalk: Int,
        markClipboardConcealed: Bool
    ) {
        self.excludedBundleIDs = excludedBundleIDs
        self.settleMilliseconds = settleMilliseconds
        self.maxCharacters = maxCharacters
        self.preferNativeCopyApps = preferNativeCopyApps
        self.preferNativeCopyEverywhere = preferNativeCopyEverywhere
        self.nativeCopyDisabledApps = nativeCopyDisabledApps
        self.yieldToExistingCopy = yieldToExistingCopy
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
