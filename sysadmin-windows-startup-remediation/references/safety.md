# Safety

This skill is change-capable, so default to conservative behavior.

## Approval Rules

- Require explicit approval before every system change.
- Approval must name the target or plan item. If approval is broad or ambiguous, ask for clarification.
- Explain whether elevation is required before running elevated commands.
- Prefer one small change set at a time so boot impact can be attributed.

## Required Before Change

Every remediation item needs:

- target identity
- evidence from analysis or local inspection
- proposed action
- expected effect
- risk and side effects
- exact rollback path
- verification step

If any of these are missing, prepare the plan but do not apply the change.

## Stop Rules

Stop and ask before touching:

- Microsoft, Windows, driver, firmware, antivirus, EDR, firewall, backup, disk, update, or identity components
- services with unclear dependencies
- startup entries owned by active development tools, sync clients, device utilities, or hardware control software when the user's workflow may depend on them
- entries whose publisher, executable, or purpose cannot be identified
- anything that requires deletion instead of a reversible disable or move

## Download And Uninstall Tool Rules

Treat downloading or running any removal, cleanup, or uninstall helper as a separate approved system change. Prefer first-party vendor tools from official support or download pages. Use third-party tools only when there is no first-party option and the tool has a strong, long-standing community or professional-use history.

Do not use unproven cleanup tools, repackaged installers, SEO download portals, or mirror-only sources. Before proposing a tool, document its source URL, publisher, trust rationale, signature or hash when available, required elevation, expected scope, and rollback limitations.

## Rollback Rules

Capture current state before changing anything. Rollback must be feasible without guessing.

Examples:

- registry startup entry: record key path, value name, and original command
- Windows Task Scheduler task: record task path, task name, enabled state, triggers, actions, conditions, settings, and an exported XML copy before disabling; rollback by re-enabling the task or restoring the XML export
- service: record service name, startup type, delayed-auto setting if known, and current state
- startup-folder item: move to a clearly named quarantine folder and record original path

## Verification

After changes, verify the target state directly, then measure actual startup impact with a fresh reboot baseline. Do not claim startup improved from a configuration change alone.
