# Safety

Use this skill for measurement first.

## Collector Rules

- Run `collect-startup-baseline.ps1` from an elevated PowerShell session.
- Do not run a non-admin fallback for final boot timing, because the Diagnostics-Performance operational log can require elevation.
- Keep command-line previews disabled unless the user explicitly asks for them.
- Treat generated JSON and reports as local diagnostic data.

## Data Handling

Do not attach real startup baselines that contain hostnames, usernames, command-line arguments, scheduled-task arguments, service metadata, or other local inventory unless you have reviewed and sanitized them first.

The collector summarizes command lines by default and omits full command-line previews unless explicitly run with `-IncludeCommandLines`.

## Remediation Rules

Do not change system configuration as part of this skill's default workflow.

Do not disable, remove, or modify:

- startup registry entries
- startup folder shortcuts
- scheduled tasks
- services
- drivers
- antivirus, EDR, backup, disk, sync-critical, update, or Microsoft components
- firmware, power, security, or Windows policy settings

If the user asks for changes, first provide a dry-run plan with:

- exact target
- evidence from baseline data
- expected effect
- risk
- rollback command or manual rollback path
- whether elevation is required

Require explicit approval before applying changes.

If uninstall guidance is requested and normal Windows uninstall entries are missing or broken, prefer first-party vendor cleanup tools from official sources. Recommend third-party removal tools only when no first-party option exists and the tool has a strong, long-standing community or professional-use history. Avoid unproven cleanup tools, repackaged installers, SEO download portals, and mirror-only sources.

## Recommendation Threshold

Prefer three or more comparable post-reboot baselines before recommending persistent startup changes. A single baseline is enough to identify what to measure next, not enough to aggressively optimize.
