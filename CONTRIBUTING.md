# Contributing

Contributions should keep skills small, composable, and safe by default.

## Guidelines

- Keep `SKILL.md` concise and move detailed material into directly linked `references/` files.
- Prefer deterministic scripts for repeated or fragile workflows.
- Keep generated state, reports, logs, and machine-specific artifacts out of git.
- Avoid destructive behavior in diagnostic skills. When remediation is needed, make it a separate reviewed workflow.
- Include synthetic examples rather than real machine captures.
- Put skill-specific usage, safety, data-handling, and validation details inside the owning skill folder.

## Validation

Before opening a pull request:

- Run your runtime's skill validator for every changed skill.
- Parse or lint bundled scripts with the language's normal tooling.
- Run the synthetic examples or validation commands documented by each changed skill.
- Confirm generated outputs remain ignored by git.

The repository workflow also checks PowerShell parsing, Markdown final newlines, and the current synthetic analysis example.
