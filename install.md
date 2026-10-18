# Installing copy-on-select — instructions for AI coding agents

You are an AI coding agent installing copy-on-select for your user.

**Existing installation: read the [README agent maintenance runbook](README.md#agent-maintenance-runbook--read-before-updating-or-troubleshooting)
first.** This guide's `~/Applications/CopyOnSelect.app` path is a new-install
example, not this Mac's current path. Preserve its existing path, certificate,
permissions and config. Do not create another identity or run the new-install
sequence over a working deployment.

Work through the sections in order. Each one ends with a **Verify** block. **If a
verification fails, stop and show your user the output instead of improvising.**

Granting Accessibility and Input Monitoring (step 6) cannot be automated; macOS
requires the user to approve both in System Settings. Creating the code-signing
certificate (step 3) can and should be automated. A Keychain Access walkthrough
is included only as a fallback.

**Complete list of what this installs:**

| Path | What |
|---|---|
| `~/Applications/CopyOnSelect.app` | the app (a standard macOS bundle) |
| `~/Library/LaunchAgents/dev.copy-on-select.plist` | starts it at login |
| `~/Library/Application Support/copy-on-select/config.json` | config (only if the user edits defaults) |
| login keychain | a self-signed code-signing certificate named `copy-on-select-local` |

Nothing else is modified. The program makes no network connections.

---

## 1. Prerequisites

```sh
swift --version
```

Requires Swift 6.1+ and macOS 13+.

If `swift` is missing, your user needs the **Command Line Tools** — not the full
Xcode. The Command Line Tools ship the complete Swift toolchain including
SwiftPM (`swift`, `swiftc`, `swift-build`), and are roughly 1–2 GB rather than
Xcode's ~15 GB. Ask them to run:

```sh
xcode-select --install
```

That opens a system installer dialog, so it is a GUI action you cannot complete
for them. Anyone who already has Homebrew already has these.

**Verify**

```sh
swift --version && sw_vers -productVersion
```

---

## 2. Build

```sh
cd /path/to/copy-on-select
swift build -c release
```

**Verify**

```sh
test -x .build/release/copy-on-select && echo "built ok"
```

---

## 3. Code-signing certificate

Ad-hoc signing (the default) changes the binary's identity on every rebuild, and
macOS binds the Accessibility grant to that identity. Without a stable
certificate your user must re-approve Accessibility after every rebuild.

First check whether the certificate already exists:

```sh
security find-certificate -c copy-on-select-local >/dev/null 2>&1 && echo "exists" || echo "missing"
```

For a new installation only, first distinguish a genuinely absent identity
from a restricted/locked keychain or failed lookup. Inspect the login keychain
and match any existing signing identity by fingerprint; a certificate alone
does not prove a private key is available. For an existing installation, use
the README Keychain procedure and preserve its identity.

If the identity is genuinely absent on a new installation, create and import
the identity programmatically. This
avoids the nine-screen Certificate Assistant, leaves personal information out
of the certificate, and limits private-key access to Apple's `codesign` tool.
It uses a random, one-time password only to protect the temporary PKCS#12 file;
the file and password are deleted immediately after import.

Use macOS's bundled `/usr/bin/openssl` deliberately. Homebrew OpenSSL 3 emits a
newer PKCS#12 format by default that `security import` can reject with the
misleading error `MAC verification failed during PKCS12 import (wrong
password?)`. The bundled LibreSSL produces the legacy-compatible format macOS's
keychain importer expects.

```sh
(
  set -e
  CERT_TMP="$(mktemp -d)"
  chmod 700 "$CERT_TMP"

  cleanup_certificate_files() {
    rm -f "$CERT_TMP/key.pem" "$CERT_TMP/cert.pem" \
      "$CERT_TMP/identity.p12" "$CERT_TMP/pass.txt"
    rmdir "$CERT_TMP"
  }
  trap cleanup_certificate_files EXIT

  /usr/bin/openssl req -new -newkey rsa:2048 -nodes -x509 -days 7300 \
    -subj '/CN=copy-on-select-local' \
    -addext 'keyUsage=critical,digitalSignature' \
    -addext 'extendedKeyUsage=critical,codeSigning' \
    -addext 'basicConstraints=critical,CA:FALSE' \
    -keyout "$CERT_TMP/key.pem" -out "$CERT_TMP/cert.pem"

  /usr/bin/openssl rand -hex 32 > "$CERT_TMP/pass.txt"
  chmod 600 "$CERT_TMP/key.pem" "$CERT_TMP/cert.pem" "$CERT_TMP/pass.txt"

  /usr/bin/openssl pkcs12 -export -name copy-on-select-local \
    -inkey "$CERT_TMP/key.pem" -in "$CERT_TMP/cert.pem" \
    -out "$CERT_TMP/identity.p12" -passout file:"$CERT_TMP/pass.txt"

  security import "$CERT_TMP/identity.p12" \
    -k "$HOME/Library/Keychains/login.keychain-db" \
    -P "$(tr -d '\n' < "$CERT_TMP/pass.txt")" \
    -T /usr/bin/codesign
)
```

The import may ask the user to unlock the login keychain. Later, the first
`codesign` can show a key-access dialog; **Always Allow** prevents that prompt
from returning on each rebuild, while **Allow** works for the current build.
Never replace `-T /usr/bin/codesign` with `-A`: `-A` lets every application use
the private key.

If the programmatic import fails, stop and show the user its output instead of
weakening the key's access controls or retrying with `-A`. The Keychain Access
route below is the safe fallback. Do not just say "create a code-signing
certificate" — it is a nine-screen assistant with defaults that are wrong for
this purpose, and one screen leaks their email address into the certificate.
Give the user the screens one at a time, in order, and tell them exactly what
to enter.

> Open **Keychain Access** (⌘-Space → "Keychain Access"), then menu
> **Keychain Access → Certificate Assistant → Create a Certificate…**
>
> The assistant has several screens. Here is every one, in order:
>
> | # | Screen | What to do |
> |---|---|---|
> | 1 | **Create a Certificate** | Name: `copy-on-select-local` · Identity Type: **Self Signed Root** · Certificate Type: **Code Signing** · **tick "Let me override defaults"** (without this you cannot change the expiry) |
> | 2 | **Certificate Information** (serial / validity) | Validity Period: change **365** to something long, e.g. `7300` (20 years). When it silently expires, signing breaks and the cause is very hard to trace later. |
> | 3 | **Certificate Information** (personal info) | ⚠️ **The Email Address field is pre-filled with your real email — clear it.** Whatever is here is embedded in the certificate and appears in the binary's signature. Common Name should already be `copy-on-select-local`. Leave Organization, Unit, City, State blank. Country can stay as-is. |
> | 4 | **Key Pair Information** | Defaults: **2048 bits**, **RSA**. |
> | 5 | **Key Usage Extension** | Leave "Include" ticked. Ensure **Signature** is the only capability checked. |
> | 6 | **Extended Key Usage Extension** | Leave "Include" ticked. Ensure **Code Signing** is the only capability checked. |
> | 7 | **Basic Constraints Extension** | Leave **unchecked** — this certificate is not a CA. |
> | 8 | **Subject Alternate Name Extension** | **Uncheck** it. If you leave it on, make sure `rfc822Name` is empty (same email concern as screen 3). |
> | 9 | **Specify a Location** | Keychain: **login**. Click **Create**. |
>
> The final screen shows *"This certificate has not been verified by a third
> party."* **That is expected and fine** — self-signed means no certificate
> authority vouches for it. Nobody else is being asked to trust it; its only
> job is to give the binary a stable identity so macOS keeps the Accessibility
> grant across rebuilds.
>
> Tell me when it is created.

Wait for confirmation.

**Verify**

```sh
security find-certificate -c copy-on-select-local >/dev/null 2>&1 && echo "certificate exists"
```

---

## 4. Assemble the app bundle and sign it

Install as a real `.app` bundle, **not** a bare executable. This matters:
macOS's permission system (TCC) misbehaves around bare executables — the
Accessibility **+** file picker refuses to show them, `tccutil` cannot reset
them (no bundle identifier), and their permission records are fragile when the
signing identity ever changes. A bundle is the format macOS expects from
anything requesting Accessibility.

The Accessibility grant is also bound to the **path**, so assemble at the final
location before granting. Never grant permission to a build-directory copy.

```sh
APP="$HOME/Applications/CopyOnSelect.app"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/copy-on-select "$APP/Contents/MacOS/copy-on-select"
cp Sources/CopyOnSelect/Info.plist "$APP/Contents/Info.plist"
```

Now sign the bundle — **a keychain dialog may appear asking whether `codesign`
may use the key. "Always Allow" stops it reappearing on every rebuild; plain
"Allow" also works, it just prompts again next time.**

```sh
codesign --force --deep --sign copy-on-select-local "$HOME/Applications/CopyOnSelect.app"
```

**Verify**

```sh
APP="$HOME/Applications/CopyOnSelect.app"
codesign --verify --deep --strict "$APP"
codesign -dvv -r- "$APP"
```

Both commands must succeed. Inspect the expected certificate requirement,
Authority and bound `Info.plist entries=...`; reject ad-hoc signing or
`Info.plist=not bound`. A failed `codesign` piped into a negated grep can
incorrectly print “signed with a stable identity”; do not use that as proof.
Use the existing fingerprint rather than an ambiguous certificate name when
signing an update.

---

## 5. Signing warnings — read before touching the signature again

**Never re-sign this app with a different certificate.** macOS validates
saved permission requirements against the signing identity. Rebuilding with
the same certificate and valid metadata is different from changing identity.
Both Accessibility and Input Monitoring can retain stale requirements; use
daemon-attributed evidence and reset only an affected service if necessary.
A fresh path is a last resort, not an automatic requirement. Every rebuild
must preserve the same identity from step 3.

### Do NOT sign with an Apple Developer ID unless you also notarize

If your user has an Apple Developer ID certificate and suggests using it instead
of the self-signed one: **warn them**. A Developer ID signature *without*
notarization is actively rejected by Gatekeeper (`spctl` reports
"Unnotarized Developer ID") and macOS will refuse to honour Accessibility for
the binary — a state strictly worse than self-signed. Developer ID is only an
upgrade as a pair: sign **and** notarize. The self-signed certificate is the
right default for a personal build.

---

## 6. Grant Accessibility AND Input Monitoring — USER ACTION REQUIRED

Two separate permissions are required, and both are easy to miss because the
app can look completely healthy without either one — see
`TROUBLESHOOTING.md` under "Two permissions are needed" and "Event tap
silently stops delivering events" for what each one actually gates and what it
looks like when only one is granted.

Start it once so macOS registers it and shows the permission prompt:

```sh
open ~/Applications/CopyOnSelect.app
```

Then **stop** and give your user these instructions verbatim:

> A dialog should have appeared asking for Accessibility access.
>
> Open **System Settings → Privacy & Security → Accessibility**, find
> **CopyOnSelect**, and turn it **on**. If it is not listed, click **+**,
> press ⌘⇧G in the picker, enter `~/Applications`, and select
> **CopyOnSelect.app**.
>
> Then open **System Settings → Privacy & Security → Input Monitoring** and do
> the same: find **CopyOnSelect** and turn it **on** (add it with **+** if it
> is not listed). If macOS asks you to quit and reopen the app after toggling
> it, let it.
>
> Tell me when both are enabled.

Wait for confirmation. The running instance picks up an Accessibility grant
automatically; an Input Monitoring grant may require the quit-and-reopen macOS
itself prompts for.

**Verify**

```sh
~/Applications/CopyOnSelect.app/Contents/MacOS/copy-on-select --check
```

Note that the check reports the permission of the *responsible* process, so if
you run it from a terminal that itself holds Accessibility the result can be
misleading; the authoritative signal is the app working in step 9.

---

## 7. Start at login

Stop the copy you started by hand in step 6 first, or you will end up with two
instances — two menu bar icons, two event taps, two processes racing to write
the clipboard.

```sh
pkill -f "CopyOnSelect.app/Contents/MacOS/copy-on-select" 2>/dev/null

sed "s|REPLACE_WITH_INSTALL_PATH|$HOME/Applications/CopyOnSelect.app/Contents/MacOS/copy-on-select|" \
  examples/dev.copy-on-select.plist > ~/Library/LaunchAgents/dev.copy-on-select.plist
launchctl unload ~/Library/LaunchAgents/dev.copy-on-select.plist 2>/dev/null
launchctl load ~/Library/LaunchAgents/dev.copy-on-select.plist
```

**Verify**

```sh
launchctl list | grep dev.copy-on-select && echo "loaded"
grep -q "CopyOnSelect.app/Contents/MacOS/copy-on-select" ~/Library/LaunchAgents/dev.copy-on-select.plist \
  && echo "path substituted correctly"
```

If the second check fails the plist still contains the placeholder and the agent
will never start.

---

## 8. Exclusions (optional)

Defaults already exclude Finder plus common terminals and editors — apps that
either already copy on selection or where a drag is not a text selection. To
change them, create the config:

```sh
mkdir -p ~/Library/Application\ Support/copy-on-select
```

Then use **Reveal Config…** from the menu bar icon to write a default file, and
edit `excludedBundleIDs`.

To find an app's bundle id:

```sh
osascript -e 'id of app "Slack"'
```

**Verify**

```sh
~/Applications/CopyOnSelect.app/Contents/MacOS/copy-on-select --check | grep "Config"
```

---

## 9. End-to-end test

Prefer a user-driven test of fresh, non-sensitive text in a local app. It
validates the experience they actually use without collecting their clipboard.

**Stop** and ask them:

> Open TextEdit, type a harmless test sentence, select it with the mouse,
> and check that the blue Copied snackbar appears. Without pressing ⌘C, paste
> with ⌘V into another blank document. Does it match the selected text?

Have the user also verify Chrome page text. The first gesture may activate
Chrome's web accessibility tree; allow three seconds and select another phrase.
Do not remove the enhanced-UI activation fallback or the container-role fix.

Also ask the user to drag a file in Finder and verify their clipboard is
unchanged. Finder is excluded; a file drag must not copy files. If diagnostics
need clipboard inspection, use a known test fixture and avoid printing arbitrary
user clipboard contents. Preserve the existing config and verify one running
process after Quit & Reopen.

---

## 10. Tell your user

Summarise for them:

- Selecting text with the mouse now copies it, in every app except the excluded
  ones (Finder, terminals, editors — see step 8).
- It starts automatically at login.
- The menu bar icon `⧉` has **Pause**, **Reveal Config…**, and **Quit**. A `⚠`
  icon means Accessibility was revoked or the event tap died — the latter can
  also mean Input Monitoring was revoked, since the icon can't tell the two
  apart (see `TROUBLESHOOTING.md`).
- It overwrites the clipboard often. A clipboard manager (Maccy, Raycast) is
  worth pairing with it.
- By default selections **do** appear in clipboard history. Setting
  `markClipboardConcealed: true` in the config marks writes
  `org.nspasteboard.ConcealedType`, which well-behaved clipboard managers and
  sync services skip — better privacy, no history.
- Rebuilding the app does **not** require re-granting Accessibility, thanks to
  the certificate from step 3 — as long as they sign each rebuild with it.

---

## Uninstall

Order matters: unload the LaunchAgent **before** removing the binary, so launchd
is never left pointing at a missing executable.

```sh
launchctl unload ~/Library/LaunchAgents/dev.copy-on-select.plist 2>/dev/null
rm -f ~/Library/LaunchAgents/dev.copy-on-select.plist
pkill -f "CopyOnSelect.app/Contents/MacOS/copy-on-select" 2>/dev/null
rm -rf ~/Applications/CopyOnSelect.app
rm -rf ~/Library/Application\ Support/copy-on-select
```

**Verify**

```sh
launchctl list | grep -q dev.copy-on-select && echo "FAIL: still loaded" || echo "unloaded"
test -e ~/Applications/CopyOnSelect.app && echo "FAIL: app remains" || echo "removed"
```

Then tell your user to remove the leftover entry manually — you cannot:

> Open **System Settings → Privacy & Security → Accessibility** and **→ Input
> Monitoring** and remove **CopyOnSelect** from both lists. Optionally delete
> the `copy-on-select-local` certificate from Keychain Access.
