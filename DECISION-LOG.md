# Decision Log

## 2026-10-08 — Scale existing confirmation

Interpret 4× as four times the linear dimensions and font size. Preserve position, timing, appearance and copy behavior. Keep the installed version’s source baseline rather than bundling unrelated remote AX changes into this visual adjustment.

Preserved the original certificate and designated requirement. `security find-identity -v` lists no valid identities because the local self-signed certificate is not trusted; the matching identity remains available and successfully signs the app. Strict bundle signature verification passed. Do not replace the certificate to resolve that listing.

Backup: `~/Library/Application Support/copy-on-select/backups/20261008-222622/CopyOnSelect.app`.

## 2026-10-08 — Muted teal contrast

Joel accepted the size but found the background difficult to see. Use opaque muted teal `#245C5C` with white text: 7.61:1 calculated contrast independent of content behind the panel. Preserve accepted size and existing timing/placement. Backup before color change: `~/Library/Application Support/copy-on-select/backups/20261008-222925/CopyOnSelect.app`.

## 2026-10-08 — Neutral color revision

Joel disliked teal. Changed to opaque charcoal #333333 with soft white #F5F5F5 (11.59:1 contrast). This is a proposed neutral alternative, not yet visually accepted. Preserved 4× size and timing. Pre-revision backup: `~/Library/Application Support/copy-on-select/backups/20261008-223206/CopyOnSelect.app`.

## 2026-10-08 — Blue direction

Joel rejected charcoal as too dark and requested the familiar blue associated with iMessage. Use opaque #007AFF with white text, preserving accepted 4× sizing. Calculated contrast 4.02:1 for large semibold text. This is an iMessage-style choice, not a claim that all current Messages interfaces use one exact hex. Backup: `~/Library/Application Support/copy-on-select/backups/20261008-223342/CopyOnSelect.app`.

## 2026-10-08 — Blue gradient

Joel approved blue and requested an iMessage-like gradient. Use AppKit NSGradient in a background NSView, clipped by the existing rounded layer: #0064E6 bottom to #2D92FF top. White-text contrast remains at least 3.15:1 for the existing large semibold label. Preserve accepted dimensions and timing. Backup of approved flat-blue app: `~/Library/Application Support/copy-on-select/backups/20261008-223825/CopyOnSelect.app`.
