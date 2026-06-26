# Local Performance Hub

Template folder for using the `sysadmin-windows-startup-performance` skill as a project-local diagnostic hub.

Copy the skill scripts into `scripts/`, then run from an elevated PowerShell session:

```powershell
.\scripts\collect-startup-baseline.ps1
.\scripts\analyze-startup-baseline.ps1
```

Generated baselines go in `state/`; Markdown reports go in `reports/`; logs are reserved for future scheduled runs.

To install this skill into Codex from the repository root:

```powershell
Copy-Item -Recurse .\sysadmin-windows-startup-performance "$env:USERPROFILE\.codex\skills\sysadmin-windows-startup-performance"
```
