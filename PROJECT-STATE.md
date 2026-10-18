# Project State

## Mac mini update — 2026-10-18

Version 1.1.0 (build 2) installed at /Applications/CopyOnSelect.app; menu includes the version from bundle metadata. Release build, signature, installed-binary comparison and one running LaunchAgent process verified. Original Mac mini certificate retained. Backup and details in SESSION-LOG.md. Joel confirmed the menu/version update works on 2026-10-18.

Next action: scope the proposed hold-to-paste gesture before implementation. The October 17 installation below belongs to the jediOne Mac, not this Mac mini.

## Current status — 2026-10-17

User confirmed CopyOnSelect works after the October 17 repair. The current app
is `~/Applications/copy-on-select/CopyOnSelect.app`, with executable
`Contents/MacOS/copy-on-select` and certificate fingerprint
`050390D8565BE77F55FAB7558F43BBC5B7E1A3FC`. Strict signature verification
passes, metadata agrees, both daemon-attributed permission checks were allowed,
and the final trace reached selection, commit and toast. One LaunchAgent
process remained; temporary diagnostics were disabled.

Preserve Chrome's enhanced-UI activation fallback and the earlier container-role
fix. Read the README agent maintenance runbook before changing the deployment.
It distinguishes original setup issues from this repair and records Keychain,
permission, packaging, process and execution-context lessons.

Recoverable backups currently present under
`~/Library/Application Support/copy-on-select/backups/`:

- `pre-update-20261017.bundle-backup`
- `pre-package-repair-20261017.bundle-backup`
- `pre-diagnostics-20261017.bundle-backup`

These represent different intermediate states, not equally suitable rollback
targets. Verify metadata/certificate before restoring one. Historical October 8
backup paths in session notes were not found in this backup-directory inventory;
do not assume those files exist on this Mac.

The earlier October 14 repository sync did not deploy an app. User authorized
committing and pushing the current repair and documentation on October 17;
consult Git history/remote status for publication state. Functional acceptance
is confirmed; no separate new color/gradient redesign was requested.
