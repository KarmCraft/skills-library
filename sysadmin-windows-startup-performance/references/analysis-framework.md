# Analysis Framework

Use this reference when turning startup baseline data into findings or recommendations.

## Reasoning Principles

- Separate measurement from remediation. A finding can say what looks suspicious without saying it should be disabled.
- Prefer repeated evidence over a single observation. One boot can identify what to measure next; recurring patterns justify stronger recommendations.
- Rank by user-visible startup impact first, then by confidence, then by reversibility.
- Treat missing or partial data as a confidence limit, not as proof that no issue exists.
- Explain whether the evidence points to boot, sign-in, post-login startup, or general resource pressure.

## Confidence Levels

- `high`: repeated across comparable baselines, clear component identity, and direct timing or resource evidence.
- `medium`: plausible component identity and one strong signal, or repeated weak signals.
- `low`: weak, indirect, stale, or context-dependent evidence.
- `info`: useful measurement context, inventory, or next data to collect.

## Recommendation Quality

Good recommendations:

- name the exact component or artifact
- cite the baseline signal that caused the finding
- state the confidence level
- distinguish investigation, measurement, and remediation
- avoid changing Microsoft, security, driver, backup, disk, sync-critical, or update components by default

Avoid recommendations that:

- infer causality from one baseline without saying so
- suggest disabling services or tasks without rollback context
- treat high process CPU after login as proof of boot delay
- mention command-line details that were not explicitly collected

## Edge Cases

- Thin baseline history: recommend collecting more baselines before persistent changes.
- Long uptime: note that current process/resource data may not represent startup.
- Disabled item still appears: report it as inventory, not an active startup cost.
- Update or installer activity: identify it as potentially transient unless repeated.
- Hardware/vendor utilities: treat performance cost and device-control value as separate considerations.
