# Installing copy-on-select — instructions for AI coding agents

You are an AI coding agent installing copy-on-select for your user.

Work through the sections in order. Each one ends with a **Verify** block. **If a
verification fails, stop and show your user the output instead of improvising.**

Two steps cannot be done by you — creating a code-signing certificate (step 3)
and granting Accessibility (step 6) are both GUI actions. For those, stop, give
your user the exact instructions, and wait for them to confirm before continuing.

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

## 3. Code-signing certificate — USER ACTION REQUIRED

Ad-hoc signing (the default) changes the binary's identity on every rebuild, and
macOS binds the Accessibility grant to that identity. Without a stable
certificate your user must re-approve Accessibility after every rebuild.

First check whether the certificate already exists:

```sh
security find-certificate -c copy-on-select-local >/dev/null 2>&1 && echo "exists" || echo "missing"
```

If it prints `missing`, **stop** and walk your user through the wizard below.
Do not just say "create a code-signing certificate" — it is an eight-screen
assistant with defaults that are wrong for this purpose, and one screen leaks
their email address into the certificate. Give them the screens one at a time,
in order, and tell them exactly what to enter.

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
cp .build/release/copy-on-select "$APP/Contents/MacOS/CopyOnSelect"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>dev.copy-on-select</string>
    <key>CFBundleName</key><string>CopyOnSelect</string>
    <key>CFBundleExecutable</key><string>CopyOnSelect</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSUIElement</key><true/>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
</dict>
</plist>
EOF
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
codesign -dv "$APP" 2>&1 | grep -q "Signature=adhoc" \
  && echo "FAIL: still ad-hoc" \
  || echo "signed with a stable identity"
codesign --verify --strict "$APP" && echo "bundle signature valid"
```

---

## 5. Signing warnings — read before touching the signature again

**Never re-sign this app with a different certificate.** macOS pins the
Accessibility grant to the code signature, so any re-sign silently revokes it,
and repeated identity changes at one path poison macOS's permission records
(recovery then needs a fresh install path — see `TROUBLESHOOTING.md`). Every
rebuild must use the same `copy-on-select-local` identity from step 3.

### Do NOT sign with an Apple Developer ID unless you also notarize

If your user has an Apple Developer ID certificate and suggests using it instead
of the self-signed one: **warn them**. A Developer ID signature *without*
notarization is actively rejected by Gatekeeper (`spctl` reports
"Unnotarized Developer ID") and macOS will refuse to honour Accessibility for
the binary — a state strictly worse than self-signed. Developer ID is only an
upgrade as a pair: sign **and** notarize. The self-signed certificate is the
right default for a personal build.

---

## 6. Grant Accessibility — USER ACTION REQUIRED

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
> Tell me when it is enabled.

Wait for confirmation. The running instance picks up the grant automatically —
your user does not need to restart it.

**Verify**

```sh
~/Applications/CopyOnSelect.app/Contents/MacOS/CopyOnSelect --check
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
pkill -f "CopyOnSelect.app/Contents/MacOS/CopyOnSelect" 2>/dev/null

sed "s|REPLACE_WITH_INSTALL_PATH|$HOME/Applications/CopyOnSelect.app/Contents/MacOS/CopyOnSelect|" \
  examples/dev.copy-on-select.plist > ~/Library/LaunchAgents/dev.copy-on-select.plist
launchctl unload ~/Library/LaunchAgents/dev.copy-on-select.plist 2>/dev/null
launchctl load ~/Library/LaunchAgents/dev.copy-on-select.plist
```

**Verify**

```sh
launchctl list | grep dev.copy-on-select && echo "loaded"
grep -q "CopyOnSelect.app/Contents/MacOS/CopyOnSelect" ~/Library/LaunchAgents/dev.copy-on-select.plist \
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
~/Applications/CopyOnSelect.app/Contents/MacOS/CopyOnSelect --check | grep "Config"
```

---

## 9. End-to-end test

This one needs your user, because only a human can make a selection.

**Stop** and ask them:

> Open TextEdit, type a sentence, and select it with the mouse. Tell me when
> you have.

Then confirm the selection reached the clipboard:

```sh
pbpaste
```

If `pbpaste` shows the selected sentence, the install works.

Also confirm the safety behaviour — ask your user to drag a file in Finder, then:

```sh
pbpaste
```

The output must be **unchanged** (Finder is excluded, and a file drag must never
land on the clipboard).

---

## 10. Tell your user

Summarise for them:

- Selecting text with the mouse now copies it, in every app except the excluded
  ones (Finder, terminals, editors — see step 8).
- It starts automatically at login.
- The menu bar icon `⧉` has **Pause**, **Reveal Config…**, and **Quit**. A `⚠`
  icon means Accessibility was revoked or the event tap died.
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
pkill -f "CopyOnSelect.app/Contents/MacOS/CopyOnSelect" 2>/dev/null
rm -rf ~/Applications/CopyOnSelect.app
rm -rf ~/Library/Application\ Support/copy-on-select
```

**Verify**

```sh
launchctl list | grep -q dev.copy-on-select && echo "FAIL: still loaded" || echo "unloaded"
test -e ~/Applications/CopyOnSelect.app && echo "FAIL: app remains" || echo "removed"
```

Then tell your user to remove the leftover entry manually — you cannot:

> Open **System Settings → Privacy & Security → Accessibility** and remove
> **CopyOnSelect** from the list. Optionally delete the
> `copy-on-select-local` certificate from Keychain Access.
