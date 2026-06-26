# Target Types

Use this reference to choose conservative actions for common startup targets.

## Registry Run Entries

Typical fields: `scope`, `kind`, `key_path`, `name`, `command`.

Preferred actions:

- use the application's own setting if available
- disable through Windows Startup Apps UI or Task Manager when possible
- as a fallback, export or record the value and move it to a rollback-safe holding key instead of deleting it

Rollback: restore the original value name and command to the original key.

## Startup Folder Items

Typical fields: `scope`, `name`, `extension`, `path`, `command`.

Preferred action: move the shortcut or file to a timestamped quarantine folder outside the Startup folder.

Rollback: move the exact file back to the original path.

## Scheduled Startup Or Logon Tasks

Typical fields: `task_path`, `task_name`, `state`, `author`, `trigger_types`, `actions`.

Preferred action: `Disable-ScheduledTask` for clearly nonessential third-party tasks.

Rollback: `Enable-ScheduledTask` for the same task path and name.

Do not modify tasks from Microsoft, security software, backup tools, device drivers, or update systems without a stronger reason and explicit user approval.

## Auto-Start Services

Typical fields: `name`, `display_name`, `state`, `status`, `delayed_auto_start`, `service_account`, `path`.

Preferred actions:

- leave services unchanged unless evidence is strong
- prefer vendor app settings first
- prefer delayed automatic or manual over disabled when appropriate

Rollback: restore original startup type and delayed-auto setting, then start the service if it was running before.

## Vendor Launchers And Updaters

Prefer application settings or vendor-supported startup toggles. If the component only checks updates or opens a tray UI, disabling startup may be reasonable. If it controls hardware, licensing, backup, sync, or security, stop and ask.

## Uninstall Guidance

Uninstall is not the default remediation path. Provide uninstall guidance only when the user explicitly asks or when the analysis shows an unwanted application and disabling startup does not address the problem.

Prefer standard Windows Apps and Features entries, the application's own uninstaller, or the vendor's documented installer maintenance mode first. When a program has no Add/Remove Programs entry, has a broken uninstall entry, or uses an extended installer that requires a cleanup utility, guidance may include a dedicated remover only after source vetting.

Prefer tools in this order:

- first-party vendor removal or cleanup tools from official support/download pages
- operating-system or package-manager supported uninstall mechanisms
- trusted third-party tools with a long community and professional-use history, only when no first-party option exists

Avoid unproven cleanup tools, SEO download portals, repackaged installers, mirror sites without provenance, and utilities that bundle unrelated software. For any downloaded tool, record the source URL, publisher, reason it is trusted, signature or hash when available, required elevation, expected scope, and rollback limitations. Ask for explicit approval before downloading and again before running any removal tool.
