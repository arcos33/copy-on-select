import AppKit
import Foundation

/// `copy-on-select --check`
///
/// Exists so an automated installer has something to verify against: the
/// accessibility grant is a GUI action nobody can script, and the TCC database
/// is not readable, so without this there is no way to confirm the step worked.
///
/// Deliberately does not shell out to `launchctl`. Spawning processes would put
/// `Process` in the source, which undermines the "grep the source and see there
/// is no way out to the network" audit story. Checking that the LaunchAgent
/// plist is installed is enough for an install-time check.
enum Doctor {
    enum Severity {
        case required  // failing means the app cannot work
        case advisory  // failing means degraded or dev-only setup
        case info
    }

    struct Check {
        let name: String
        let passed: Bool
        let detail: String
        var severity: Severity = .advisory
    }

    /// `copy-on-select --apps`
    ///
    /// Lists running apps with their bundle identifiers, so the exclusion and
    /// native-copy lists in the config can be filled in without hunting through
    /// Info.plist files or remembering the osascript incantation.
    static func listApps() -> Int32 {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> (String, String)? in
                guard let id = app.bundleIdentifier else { return nil }
                return (app.localizedName ?? id, id)
            }
            .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }

        let width = apps.map(\.0.count).max() ?? 20
        print("Running apps and their bundle identifiers:\n")
        for (name, id) in apps {
            print("  \(name.padding(toLength: width, withPad: " ", startingAt: 0))  \(id)")
        }
        print("\nUse these in \"excludedBundleIDs\" or \"nativeCopyDisabledApps\" in:")
        print("  \(Config.fileURL.path)")
        return 0
    }

    static func run() -> Int32 {
        var checks: [Check] = []

        let executablePath = Bundle.main.executablePath ?? CommandLine.arguments[0]
        checks.append(
            Check(
                name: "Executable path",
                passed: true,
                detail: executablePath,
                severity: .info))

        // TCC keys on code identity AND path, so a check run against the build
        // directory reports a different answer than the installed copy.
        let looksInstalled = !executablePath.contains("/.build/")
        checks.append(
            Check(
                name: "Running from an installed location",
                passed: looksInstalled,
                detail: looksInstalled
                    ? "not a build-directory binary"
                    : "this is the build-directory binary; the accessibility grant applies to the INSTALLED path, so check that one instead"))

        // Caveat that matters for installers: TCC attributes permission to the
        // *responsible* process. Run from a terminal that already holds
        // accessibility, a child process inherits that verdict — so a "granted"
        // here can be the terminal's grant, not this binary's. Only the result
        // from a launchd-started copy at the installed path is authoritative.
        let trusted = AX.isTrusted
        let launchedByTerminal = ProcessInfo.processInfo.environment["TERM"] != nil
        checks.append(
            Check(
                name: "Accessibility permission",
                passed: trusted,
                detail: trusted
                    ? (launchedByTerminal
                        ? "granted — WARNING: run from a terminal, so this may reflect the terminal's own grant, not this binary's. Verify by starting it via launchd."
                        : "granted")
                    : "NOT granted — open System Settings > Privacy & Security > Accessibility and enable copy-on-select for THIS binary",
                severity: .required))

        let signature = codeSignature()
        checks.append(
            Check(
                name: "Code signature",
                passed: signature.isStable,
                detail: signature.description))

        let configExists = FileManager.default.fileExists(atPath: Config.fileURL.path)
        let config = Config.load()
        checks.append(
            Check(
                name: "Config",
                passed: true,
                detail: configExists
                    ? "\(Config.fileURL.path) (\(config.excludedBundleIDs.count) excluded apps)"
                    : "using defaults (\(config.excludedBundleIDs.count) excluded apps); no file at \(Config.fileURL.path)",
                severity: .info))

        let agentPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/dev.copy-on-select.plist").path
        let agentInstalled = FileManager.default.fileExists(atPath: agentPath)
        checks.append(
            Check(
                name: "LaunchAgent",
                passed: agentInstalled,
                detail: agentInstalled ? agentPath : "not installed (app will not start at login)"))

        for check in checks {
            let mark: String
            switch (check.passed, check.severity) {
            case (true, _): mark = "ok  "
            case (false, .required): mark = "FAIL"
            case (false, .advisory): mark = "warn"
            case (false, .info): mark = "info"
            }
            print("[\(mark)] \(check.name): \(check.detail)")
        }

        let failedRequired = checks.filter { !$0.passed && $0.severity == .required }
        let warnings = checks.filter { !$0.passed && $0.severity == .advisory }

        print("")
        if !failedRequired.isEmpty {
            print("copy-on-select: NOT ready — \(failedRequired.count) required check(s) failed")
            return 1
        }
        if !warnings.isEmpty {
            print("copy-on-select: ready, with \(warnings.count) warning(s)")
            return 0
        }
        print("copy-on-select: ready")
        return 0
    }

    /// Reads the embedded code signature without spawning `codesign`.
    ///
    /// Ad-hoc signing is reported as a failure on purpose: the accessibility
    /// grant is bound to code identity, so an ad-hoc signature that changes
    /// every build forces the user to re-approve after each rebuild.
    private static func codeSignature() -> (isStable: Bool, description: String) {
        guard let raw = codeSignatureDescription() else {
            return (false, "unsigned — the accessibility grant will reset on every rebuild")
        }
        if raw.hasPrefix("adhoc") {
            return (false, "ad-hoc signed — the accessibility grant will reset on every rebuild")
        }
        return (true, raw)
    }

    private static func codeSignatureDescription() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else {
            return nil
        }
        var info: CFDictionary?
        guard
            SecCodeCopySigningInformation(
                staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
            let dict = info as? [String: Any]
        else { return nil }

        if let certs = dict["certificates"] as? [SecCertificate], let leaf = certs.first {
            let name = SecCertificateCopySubjectSummary(leaf) as String? ?? "unknown"
            return "signed by \(name)"
        }
        if dict["identifier"] != nil {
            return "adhoc"
        }
        return nil
    }
}
