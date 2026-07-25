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

    /// Whether to fall back to synthesizing Cmd+C when a text element's
    /// selection cannot be read over accessibility. The fallback is gated (see
    /// Engine) but it is still the riskiest path; users can turn it off.
    var enableCopyFallback: Bool

    /// Minimum drag distance, in points, to count as a selection drag.
    var dragThreshold: Double

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
        enableCopyFallback: true,
        dragThreshold: 4.0
    )

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
            return try JSONDecoder().decode(Config.self, from: data)
        } catch {
            FileHandle.standardError.write(
                "copy-on-select: config at \(fileURL.path) is invalid (\(error)); using defaults\n"
                    .data(using: .utf8)!)
            return .default
        }
    }
}
