# Data Model

The collector writes `schema_version = 1` JSON with `kind = "windows_startup_baseline"`.

## Baseline Fields

- `machine`: computer name, manufacturer, model, and domain role.
- `operating_system`: Windows caption, version, and build.
- `boot`: last boot timestamp and uptime.
- `diagnostics_performance_events`: recent events from `Microsoft-Windows-Diagnostics-Performance/Operational`, especially IDs 100-199.
- `diagnostics_performance_collection`: metadata about scan depth, returned events, and boot-event target satisfaction.
- `startup.registry_entries`: startup registry Run entries.
- `startup.startup_folder_items`: user and common startup-folder shortcuts.
- `startup.scheduled_startup_logon_tasks`: scheduled tasks triggered at startup or logon.
- `startup.auto_start_services`: automatic and delayed-automatic services.
- `resources.disks`: fixed disk free-space summary.
- `resources.memory`: physical memory summary.
- `resources.page_files`: pagefile usage summary.
- `resources.top_processes`: process snapshot ranked by cumulative CPU seconds and working set.
- `resources.perf_processes`: current formatted performance counters ranked by CPU and I/O.
- `recent_boot_events`: recent System/Application warning and error events around boot.
- `collection_errors`: non-fatal partial collection errors.

## Analysis Fields

The analyzer writes `schema_version = 1` JSON with `kind = "windows_startup_analysis"`.

- `summary`: finding counts and inventory counts.
- `findings`: ranked findings with `severity`, `category`, `title`, `evidence`, `recommendation`, and `confidence`.
- `report_path`: Markdown report path.
- `baseline_path`: source baseline path.

Downstream skills should consume the analysis JSON for structured automation and the Markdown report for user-facing summaries.
