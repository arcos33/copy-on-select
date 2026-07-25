# Installing copy-on-select — instructions for AI coding agents

You are an AI coding agent installing copy-on-select for your user.

Work through the sections in order. Each one ends with a **Verify** block. **If a
verification fails, stop and show your user the output instead of improvising.**

Two steps cannot be done by you — creating a code-signing certificate (step 3)
and granting Accessibility (step 5) are both GUI actions. For those, stop, give
your user the exact instructions, and wait for them to confirm before continuing.

**Complete list of what this installs:**

| Path | What |
|---|---|
| `~/Applications/copy-on-select` | the executable |
| `~/Library/LaunchAgents/dev.copy-on-select.plist` | starts it at login |
| `~/Library/Application Support/copy-on-select/config.json` | config (only if the user edits defaults) |
| login keychain | a self-signed code-signing certificate named `copy-on-select-local` |

Nothing else is modified. The program makes no network connections.

---

## 1. Prerequisites

```sh
swift --version
```

Requires Swift 6.1+ and macOS 13+. If `swift` is missing, ask your user to
install Xcode or the Command Line Tools (`xcode-select --install`) — that is a
GUI/admin action you cannot perform.

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

Wait for confirmation. Then sign — **a keychain dialog may appear asking whether
`codesign` may use the key. "Always Allow" stops it reappearing on every
rebuild; plain "Allow" also works, it just prompts again next time.** Either is
fine, and it can be changed later in Keychain Access (Keys → `copy-on-select-local`
→ ⌘I → Access Control).

```sh
codesign --force --sign copy-on-select-local \
  --identifier dev.copy-on-select \
  .build/release/copy-on-select
```

**Verify**

```sh
codesign -dv .build/release/copy-on-select 2>&1 | grep -q "Signature=adhoc" \
  && echo "FAIL: still ad-hoc" \
  || echo "signed with a stable identity"
```

---

## 4. Install to its final location

The Accessibility grant is bound to the binary's **path as well as its
signature**, so it must be installed before it is granted. Never grant
permission to the build-directory copy.

```sh
mkdir -p ~/Applications
cp .build/release/copy-on-select ~/Applications/copy-on-select
```

**Verify**

```sh
test -x ~/Applications/copy-on-select && echo "installed"
```

---

## 5. Grant Accessibility — USER ACTION REQUIRED

Start it once so macOS registers it and shows the permission prompt:

```sh
~/Applications/copy-on-select &
```

Then **stop** and give your user these instructions verbatim:

> A dialog should have appeared asking for Accessibility access.
>
> Open **System Settings → Privacy & Security → Accessibility**, find
> **copy-on-select**, and turn it **on**. If it is not listed, click **+** and
> select `~/Applications/copy-on-select`.
>
> Tell me when it is enabled.

Wait for confirmation. The running instance picks up the grant automatically —
your user does not need to restart it.

**Verify**

```sh
~/Applications/copy-on-select --check
```

Run the check against `~/Applications/copy-on-select`, **not** the build
directory — they have different identities and will report different answers.
Note that the check reports the permission of the *responsible* process, so if
you run it from a terminal that itself holds Accessibility the result can be
misleading; the authoritative signal is the app working in step 8.

---

## 6. Start at login

Stop the copy you started by hand in step 5 first, or you will end up with two
instances — two menu bar icons, two event taps, two processes racing to write
the clipboard.

```sh
pkill -f "$HOME/Applications/copy-on-select" 2>/dev/null

sed "s|REPLACE_WITH_INSTALL_PATH|$HOME/Applications/copy-on-select|" \
  examples/dev.copy-on-select.plist > ~/Library/LaunchAgents/dev.copy-on-select.plist
launchctl unload ~/Library/LaunchAgents/dev.copy-on-select.plist 2>/dev/null
launchctl load ~/Library/LaunchAgents/dev.copy-on-select.plist
```

**Verify**

```sh
launchctl list | grep dev.copy-on-select && echo "loaded"
grep -q "$HOME/Applications/copy-on-select" ~/Library/LaunchAgents/dev.copy-on-select.plist \
  && echo "path substituted correctly"
```

If the second check fails the plist still contains the placeholder and the agent
will never start.

---

## 7. Exclusions (optional)

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
~/Applications/copy-on-select --check | grep "Config"
```

---

## 8. End-to-end test

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

## 9. Tell your user

Summarise for them:

- Selecting text with the mouse now copies it, in every app except the excluded
  ones (Finder, terminals, editors — see step 7).
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
pkill -f "$HOME/Applications/copy-on-select" 2>/dev/null
rm -f ~/Applications/copy-on-select
rm -rf ~/Library/Application\ Support/copy-on-select
```

**Verify**

```sh
launchctl list | grep -q dev.copy-on-select && echo "FAIL: still loaded" || echo "unloaded"
test -e ~/Applications/copy-on-select && echo "FAIL: binary remains" || echo "removed"
```

Then tell your user to remove the leftover entry manually — you cannot:

> Open **System Settings → Privacy & Security → Accessibility** and remove
> **copy-on-select** from the list. Optionally delete the
> `copy-on-select-local` certificate from Keychain Access.
