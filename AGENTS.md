# Repository instructions

## Requests to update the Mac app

When the user says **“update the app”** (or equivalent), perform the installed
Mac app update end to end. A Git pull alone does not update the running app.
Read [UPDATE.md](UPDATE.md), the [README maintenance runbook](README.md#agent-maintenance-runbook--read-before-updating-or-troubleshooting),
and the current [PROJECT-STATE.md](PROJECT-STATE.md) first.

The update request authorizes routine inspection, source sync when safe,
tests/build, backup, staging, signing with the existing identity, installation
at the existing path, and restarting the app. Carry out those steps without
asking the user to reconfirm each one, subject to actual tool/OS permissions.
Do not interpret it as authorization to discard local edits, replace the
certificate, reset privacy grants, change the installation path, or commit/push.

Discover the current machine's deployment; this repo is used on multiple Macs.
Never copy another Mac's app path or certificate. Preserve the current config.
Verify the actual launchd-managed process rather than relying on a shell
`--check` permission result. A user confirmation that the updated app works
completes acceptance: record it and do not rebuild/restart again just to check.

For documentation-only requests, edit documentation without deploying the app.
