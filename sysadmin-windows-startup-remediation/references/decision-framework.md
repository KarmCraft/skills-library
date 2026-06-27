# Decision Framework

Use this reference when deciding whether a startup target is a safe remediation candidate.

## Target Classification

Classify each target before proposing action:

- `nonessential`: tray UI, marketing launcher, telemetry, one-shot helper, stale updater, or leftover vendor task.
- `workflow-dependent`: development tool, sync client, VPN, remote access, device utility, licensing helper, backup tool, or app the user may rely on.
- `system-critical`: Microsoft, Windows, driver, firmware, security, identity, disk, backup, or update component.
- `unknown`: unclear publisher, missing executable, unclear purpose, or conflicting evidence.

## Decision Rules

- For `nonessential` targets, prefer the least invasive reversible disable or app setting.
- For `workflow-dependent` targets, ask how the user uses it before changing anything.
- For `system-critical` targets, stop unless there is an explicit, well-understood vendor-supported fix.
- For `unknown` targets, inspect identity first; do not guess.

## Action Preference

Choose actions in this order:

1. Application or vendor-supported startup setting.
2. Windows-supported disable operation, such as Startup Apps, Task Manager, `Disable-ScheduledTask`, or service startup-type change.
3. Reversible quarantine or holding location with exact rollback notes.
4. Uninstall guidance only when the user asks or disabling startup does not address an unwanted application.

Prefer delayed automatic or manual over disabled for services when the component may still be needed.

## Approval Quality

Ask for approval using target-specific language:

- exact target identity
- proposed action
- expected startup effect
- risk and side effects
- elevation needs
- rollback path

Do not treat broad optimization intent as approval for multiple unrelated targets.

## Stop Conditions

Stop and ask when:

- evidence does not clearly connect the target to startup impact
- the target controls hardware, security, backup, sync, licensing, or remote access
- rollback cannot be described before the change
- a cleanup or uninstall tool would need to be downloaded
- the source or publisher cannot be verified
