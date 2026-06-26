---
name: sysadmin-windows-startup-performance
description: Collect and analyze read-only Windows startup performance baselines. Use when an agent or automation harness is asked to investigate slow Windows boot, sign-in, login delay, startup apps, registry Run keys, Startup folder items, scheduled tasks, services, Diagnostics-Performance event IDs 100-110, boot warnings, resource pressure, or produce evidence-based recommendations without changing system configuration.
---

# Sysadmin Windows Startup Performance

## Overview

Use this skill for read-only Windows startup diagnostics. It collects sanitized startup baselines, analyzes likely bottlenecks, and produces JSON plus Markdown outputs that other skills can consume.

## Files

- `scripts/collect-startup-baseline.ps1`: elevated read-only collector for Diagnostics-Performance events, startup inventory, service/task signals, resources, and recent boot warnings.
- `scripts/analyze-startup-baseline.ps1`: analyzer that ranks findings and writes a Markdown report.
- `references/data-model.md`: baseline and analysis schema notes.
- `references/safety.md`: operating rules and remediation boundaries.
- `examples/synthetic-baseline.json`: synthetic fixture for analyzer validation.
- `tools/`: reserved for optional helper CLIs, adapters, or small utilities that support this skill.
- `templates/local-performance/`: optional project-local diagnostic hub scaffold.

## Workflow

1. Read `references/safety.md` before collecting data or recommending changes.
2. Create or use a local hub folder with `scripts/`, `state/`, `reports/`, and `logs/`. A template is available at `templates/local-performance/` when this repository is installed as a project.
3. Run the collector from an elevated PowerShell session. Do not fall back to non-admin collection because protected boot timing logs can be missed.
4. Run the analyzer on the latest or specified baseline.
5. Prefer at least three comparable post-reboot baselines before recommending startup changes.
6. If the user asks for remediation, produce a dry-run plan with rollback notes first. Do not mutate startup apps, registry entries, scheduled tasks, services, drivers, security tools, or Windows settings without explicit approval.

## Commands

Collect a baseline:

```powershell
.\scripts\collect-startup-baseline.ps1
```

Analyze the latest baseline from the same hub:

```powershell
.\scripts\analyze-startup-baseline.ps1
```

Analyze a specific baseline:

```powershell
.\scripts\analyze-startup-baseline.ps1 -BaselinePath .\state\startup-baseline-YYYYMMDD-HHMMSS.json
```

Include full command-line previews only when explicitly needed:

```powershell
.\scripts\collect-startup-baseline.ps1 -IncludeCommandLines
```

## Validation

When modifying this skill, run the analyzer against the synthetic baseline from the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\sysadmin-windows-startup-performance\scripts\analyze-startup-baseline.ps1 -BaselinePath .\sysadmin-windows-startup-performance\examples\synthetic-baseline.json -OutputPath .\sysadmin-windows-startup-performance\reports\synthetic-analysis.md -AnalysisOutputPath .\sysadmin-windows-startup-performance\state\synthetic-analysis.json
```

The command writes ignored `reports/` and `state/` outputs under the skill folder.

## Output

The collector writes `state/startup-baseline-*.json` unless `-NoWrite` or `-OutputPath` is used. The analyzer writes:

- `reports/startup-baseline-analysis-*.md`
- `state/startup-analysis-*.json`

See `references/data-model.md` before building downstream tooling against these files.
