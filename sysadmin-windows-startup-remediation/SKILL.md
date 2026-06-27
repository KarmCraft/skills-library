---
name: sysadmin-windows-startup-remediation
description: Plan and apply approved, reversible Windows startup remediation, producing dry-run remediation plans and change records from prior analysis. Use when an agent or automation harness is asked to act on startup findings, disable or reconfigure autostart entries, registry Run keys, Startup folder items, Task Scheduler logon or startup tasks, auto-start services, vendor launchers or updaters, prepare rollback, vet uninstall tools, or verify post-change startup behavior with explicit approval.
---

# Sysadmin Windows Startup Remediation

## Overview

Use this skill after Windows startup performance analysis identifies candidates for action. It turns evidence into a dry-run remediation plan, requires explicit approval per target, applies only reversible changes, and records verification and rollback details.

## Files

- `references/safety.md`: approval, rollback, and stop rules.
- `references/decision-framework.md`: target classification, action preference, approval quality, and stop conditions.
- `references/target-types.md`: supported Windows startup target types and preferred actions.
- `examples/remediation-cases.md`: synthetic examples for safe candidates, stop-and-ask cases, unknown targets, uninstall guidance, and disabled residue.
- `templates/remediation-plan.md`: dry-run plan template to prepare before changes.
- `templates/change-record.md`: execution and verification record template.
- `reports/`: generated remediation plans and human-readable records.
- `state/`: local machine-specific execution state, snapshots, and rollback notes.
- `tools/`: reserved for future small helper utilities; no mutation tool is bundled yet.

## Workflow

1. Start from evidence: use a startup analysis JSON or report, preferably from the [`sysadmin-windows-startup-performance`](https://github.com/KarmCraft/skills-library/tree/main/sysadmin-windows-startup-performance) skill. If no analysis exists, ask to collect/read one first.
2. Read `references/safety.md` before proposing or applying changes.
3. Read `references/decision-framework.md` before classifying targets or asking for approval.
4. Read `references/target-types.md` for target-specific action and rollback patterns.
5. Use `examples/remediation-cases.md` when a target resembles a common safe, risky, unknown, uninstall, or residue case.
6. Produce a dry-run plan using `templates/remediation-plan.md`; include exact target identity, evidence, proposed action, risk, expected effect, elevation needs, and rollback.
7. Ask for explicit approval for each target or clearly named group of identical low-risk targets. Do not treat general optimization intent as approval.
8. Before applying a change, capture current state needed for rollback and write/update a local record under `state/` or `reports/`.
9. Apply the least invasive reversible action. Prefer supported product settings or Windows-supported enable/disable operations over deleting registry values or files.
10. Verify immediately where possible, then recommend a reboot and a fresh performance baseline to measure effect.
11. Write a change record using `templates/change-record.md` with what changed, commands or manual steps used, verification result, and rollback path.

## Operating Rules

- Do not change startup entries, scheduled tasks, services, drivers, security tools, update tools, backup tools, sync-critical tools, or vendor utilities without explicit approval.
- Do not uninstall software by default. Prefer disabling startup behavior first unless the user explicitly requests uninstall guidance.
- Do not remove registry values or startup shortcuts when a reversible disable, rename, move-to-quarantine, or app setting is available.
- Do not batch many unrelated changes into one approval. Keep changes small enough to attribute startup impact.
- After each material change set, recommend rebooting, waiting 3 to 5 minutes after login, and collecting another read-only baseline.

## Output

Use `reports/` for human-readable plans and records, and `state/` for local snapshots or rollback state. These folders are ignored except for `.gitkeep` placeholders.
