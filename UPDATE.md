# Updating the installed Mac app

“Update the app” means sync source safely, build, test, back up, sign, replace
the installed bundle, restart, and verify. Complete the routine update directly;
the user does not need to execute Terminal commands. Respect any tool approval
requirements and let the user handle macOS password/private-key prompts.

Read the README maintenance runbook for troubleshooting and signing details.
This procedure was used successfully on the jediOne Mac on October 19, 2026;
the user subsequently confirmed: **“it's working perfectly now.”**

## 1. Discover and record the current deployment

Read PROJECT-STATE.md and inspect the actual machine. The jediOne baseline is:

| Item | Value |
|---|---|
| App | `~/Applications/copy-on-select/CopyOnSelect.app` |
| Executable | `Contents/MacOS/copy-on-select` |
| LaunchAgent | `~/Library/LaunchAgents/dev.copy-on-select.plist` |
| Certificate SHA-1 | `050390D8565BE77F55FAB7558F43BBC5B7E1A3FC` |
| Config | `~/Library/Application Support/copy-on-select/config.json` |
| Last accepted version | 1.1.0 build 3, source commit `37a4689` |

The Mac mini uses a different app path and certificate. Do not use its values
on this Mac or assume the table applies to a different machine.

```sh
git status --short --branch
git remote -v
plutil -p "$HOME/Library/LaunchAgents/dev.copy-on-select.plist"
launchctl print "gui/$(id -u)/dev.copy-on-select"
ps -axo pid,ppid,comm | rg 'CopyOnSelect.app/Contents/MacOS/'
```

Set `app` from the verified deployment, then inspect it before replacing it:

```sh
app="$HOME/Applications/copy-on-select/CopyOnSelect.app"
agent="$HOME/Library/LaunchAgents/dev.copy-on-select.plist"
identity=050390D8565BE77F55FAB7558F43BBC5B7E1A3FC
plutil -p "$app/Contents/Info.plist"
codesign --verify --deep --strict "$app"
codesign -dvv -r- "$app"
security find-identity -v -p codesigning
```

Match the certificate fingerprint against the installed designated requirement.
Record installed metadata, signature, process state, and current source commit.
Use the current UID via `id -u`; this Mac's UID is 502, not 501.

## 2. Sync safely, then build and test before stopping anything

Fetch and inspect upstream status. For a clean branch tracking the intended
upstream, use `git pull --ff-only`. Preserve local changes; do not reset,
overwrite, stash blindly, or merge conflicts automatically as part of deployment.
If the latest source was already pulled in this session, do not pull again
without a reason. Record the actual commit being built with `git rev-parse HEAD`.

From the repo root, run both commands and require successful exit codes:

```sh
./scripts/test.sh
swift build -c release
```

The current test script runs ten deterministic gesture/placement checks. Keep
the working app running until the staged replacement has passed verification.

## 3. Back up and stage a signed replacement

Use a fresh timestamp, preserve metadata with `ditto`, and keep backups out of
app discovery. These variables/snippets assume one shell session and the verified
values above. Stop on any failed command; do not execute later phases after failure.

```sh
stamp=$(date +%Y%m%d-%H%M%S)
backup="$HOME/Library/Application Support/copy-on-select/backups/pre-update-$stamp"
stage_root=$(mktemp -d /private/tmp/copy-on-select-update.XXXXXX)
stage="$stage_root/CopyOnSelect.app"
mkdir -p "$backup"
ditto "$app" "$backup/CopyOnSelect.bundle-backup"
ditto "$agent" "$backup/dev.copy-on-select.plist"
config="$HOME/Library/Application Support/copy-on-select/config.json"
if test -f "$config"; then ditto "$config" "$backup/config.json"; fi
codesign -dvv -r- "$app" > "$backup/signature.txt" 2>&1
launchctl print "gui/$(id -u)/dev.copy-on-select" > "$backup/launchagent-state.txt"
git rev-parse HEAD > "$backup/new-source-commit.txt"
ditto "$app" "$stage"
cp .build/release/copy-on-select "$stage/Contents/MacOS/copy-on-select"
cp Sources/CopyOnSelect/Info.plist "$stage/Contents/Info.plist"
codesign --force --deep --sign "$identity" "$stage"
codesign --verify --deep --strict "$stage"
codesign -dvv -r- "$stage"
```

Require the same designated requirement as the installed app, the expected
Authority, and bound `Info.plist entries=...`. Validate the source and staged
plist executable/version/build values. The executable filename and embedded
and bundle `CFBundleExecutable` must all remain `copy-on-select`.
Do not substitute ad-hoc signing or create a new certificate. If signing fails,
leave the live app running and inspect the specific failure/Keychain prompt.

## 4. Stop, install at the same path, and start one managed process

```sh
launchctl bootout "gui/$(id -u)/dev.copy-on-select"
ps -axo pid,ppid,comm | rg 'CopyOnSelect.app/Contents/MacOS/'
```

Wait for teardown. If a manually launched copy remains, verify its exact
executable path and terminate only that PID with `kill PID`. This happened on
October 19: the LaunchAgent was stopped, but a manually launched app was running.
Require zero processes at the live executable path before replacing it. If the
agent is already unloaded, distinguish that condition from other bootout errors.

```sh
ditto "$stage" "$app"
codesign --verify --deep --strict "$app"
cmp "$stage/Contents/MacOS/copy-on-select" "$app/Contents/MacOS/copy-on-select"
if test -f "$backup/config.json"; then cmp "$backup/config.json" "$config"; fi
cmp "$backup/dev.copy-on-select.plist" "$agent"
launchctl bootstrap "gui/$(id -u)" "$agent"
launchctl print "gui/$(id -u)/dev.copy-on-select"
ps -axo pid,ppid,comm | rg 'CopyOnSelect.app/Contents/MacOS/'
"$app/Contents/MacOS/copy-on-select" --version
plutil -extract CFBundleVersion raw "$app/Contents/Info.plist"
```

Require one process at the intended path whose PID matches launchctl's running
job. Compare the **signed staged** executable, not the unsigned build. A transient
bootstrap error 5 can indicate teardown is unfinished; do not run the user agent
as root. If installation/verification fails, retain the backup and staged bundle,
diagnose before proceeding, and restore the verified backup at the original path
if necessary, following the README rollback guidance.

## 5. Verify permissions and behavior without unnecessary changes

`--check` is useful for metadata/config/signature checks, but its permission
verdict can belong to the terminal host. On October 19 it reported Accessibility
denied under Orca Terminal Host attribution while the actual launchd daemon
retained both permissions. This is not grounds to reset grants.

Inspect daemon-attributed TCC evidence, matching the **new PID**:

```sh
/usr/bin/log show --last 5m --style compact --info --debug \
  --predicate 'process == "tccd" AND eventMessage CONTAINS "dev.copy-on-select"'
```

Require allowed Accessibility and ListenEvent (Input Monitoring) results for the
actual daemon. A certificate's failed `anchor apple` comparison is not itself
a denial; this app uses its existing local certificate. Inspect the final access
verdict. Only add temporary diagnostics if evidence requires them; remove them
after verification. Do not reset privacy permissions or change paths speculatively.

Use permitted computer controls to verify behavior if available. Otherwise ask
the user for a brief test: select fresh text without Command-C, see the blue
Copied popup and paste; hold left-click still for half a second in an editable
field, slide onto Paste and release; release outside to cancel. Respect a denied
computer-control permission and do not use another UI tool to bypass it.

## 6. Record acceptance and finish

- Rename/move the temporary staging `.app` to a `.bundle-backup` name after
  verification so it is no longer discoverable as a second app. Never launch backups.
- Update README, PROJECT-STATE, CHANGELOG and SESSION-LOG with installed version,
  source revision, backup path, checks performed, and any remaining uncertainty.
- Record the user's confirmation when it arrives. A clear “working perfectly”
  closes acceptance; do not demand another test or restart/re-sign afterward.
- Report installed/running status separately from committed/pushed status.
  Updating the app does not by itself request a Git commit or push.
