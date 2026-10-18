import Foundation

/// Opt-in state tracing only. Never records text, clipboard data or mouse coordinates.
enum DebugTrace {
    private static let enabled = ProcessInfo.processInfo.environment["COPY_ON_SELECT_DEBUG"] == "1"

    static func log(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        FileHandle.standardError.write(Data("copy-on-select: \(message())\n".utf8))
    }
}
