import AppKit
import Foundation

let version = "0.1.0"

func usage() {
    print(
        """
        copy-on-select \(version)

        Select text anywhere on macOS and it is copied to the clipboard.

        USAGE
          copy-on-select              run the daemon (normally started by launchd)
          copy-on-select --check      verify installation and permissions
          copy-on-select --version    print version
          copy-on-select --help       this message

        This program makes no network connections. It reads its configuration
        from:
          ~/Library/Application Support/copy-on-select/config.json
        and writes nothing to disk.
        """)
}

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.contains("--help") || arguments.contains("-h") {
    usage()
    exit(0)
}

if arguments.contains("--version") {
    print(version)
    exit(0)
}

if arguments.contains("--check") {
    exit(Doctor.run())
}

// MARK: - Daemon

let app = NSApplication.shared
// No Dock icon, no menu bar app switching. Set at runtime as well as via the
// embedded LSUIElement key, because this is a bare executable rather than a
// .app bundle.
app.setActivationPolicy(.accessory)

let engine = Engine(config: Config.load())
let menuBar = MenuBar(engine: engine)

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar.install()

        if engine.start() {
            return
        }

        // The tap could not be created, which in practice means accessibility
        // trust is missing. Prompt (this also creates the System Settings
        // entry), then keep checking: a grant that arrives while we are running
        // must take effect without the user knowing to relaunch.
        AX.requestTrust()
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { timer in
            guard AX.isTrusted else { return }
            if engine.start() {
                timer.invalidate()
            }
        }
    }
}

let delegate = AppDelegate()
app.delegate = delegate
app.run()
