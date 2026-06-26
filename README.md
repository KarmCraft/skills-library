# Skills Library

A public collection of agent skills that I have found useful enough to package, maintain, and share.

The goal is to keep this library practical: composable, reusable skills that solve real workflow problems for humans and agents using `SKILL.md` compatible runtimes. Each skill should be small enough to understand, safe by default, and easy to combine with other skills.

Each top-level folder is a self-contained, directly installable skill.

## Skills

| Skill | Purpose |
| --- | --- |
| [`sysadmin-windows-startup-performance`](https://github.com/KarmCraft/skills-library/tree/main/sysadmin-windows-startup-performance) | Diagnose Windows startup performance with read-only baselines and data-driven analysis. |
| [`sysadmin-windows-startup-remediation`](https://github.com/KarmCraft/skills-library/tree/main/sysadmin-windows-startup-remediation) | Plan approved, reversible Windows startup changes from analysis findings. |

## Install

Copy the skill folder you want into the skill directory used by your agent runtime.

Generic Windows example from the repository root:

```powershell
$SkillName = "<skill-folder>"
$SkillRoot = "<path-to-your-agent-skill-directory>"
Copy-Item -Recurse ".\$SkillName" (Join-Path $SkillRoot $SkillName)
```

For other `SKILL.md` compatible tools, use their documented skill location.

## Repository Layout

```text
<skill-name>/
  SKILL.md
  agents/openai.yaml
  scripts/
  tools/
  references/
  examples/
  templates/
```

Use `tools/` for helper CLIs, adapters, or small utilities that support a skill but are not the primary workflow scripts. Keep primary repeatable workflows in `scripts/`, long-form guidance in `references/`, and avoid vendoring large binaries, secrets, or machine-specific executables.

Not every skill uses every optional folder. Generated reports, state files, and logs are intentionally ignored by git.

## Safety

Skills should be safe by default and explicit about their boundaries. Diagnostic skills should collect evidence before recommending changes, and any remediation workflow should be separately reviewed, reversible, and opt-in.
