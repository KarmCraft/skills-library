# Remediation Cases

Use these examples as patterns for evaluating startup findings. They are synthetic and intentionally vendor-neutral.

## Clearly Nonessential Logon Task

Input finding:

- target: `\Vendor\PromoTray`
- type: scheduled logon task
- evidence: appears in multiple baselines, launches a tray promotion helper, no hardware/security role

Reasoning:

- classify as `nonessential`
- proposed action can be `Disable-ScheduledTask`
- capture task path, name, enabled state, triggers, actions, settings, and XML export
- ask approval for this exact task before changing it

Output stance: safe candidate for an approved reversible disable.

## Hardware Control Service

Input finding:

- target: `VendorDeviceControlService`
- type: auto-start service
- evidence: automatic service, controls keyboard lighting and fan profiles

Reasoning:

- classify as `workflow-dependent`
- device behavior may change if disabled
- prefer vendor startup settings or leave unchanged unless the user accepts the tradeoff
- do not disable based only on startup cost

Output stance: stop and ask how the user uses the device utility.

## Unknown Publisher Run Entry

Input finding:

- target: `Helper`
- type: registry Run entry
- evidence: command points to a user profile executable with unclear publisher

Reasoning:

- classify as `unknown`
- inspect signature, file location, publisher, install context, and user intent first
- do not delete the registry value
- if later approved, move to a rollback-safe holding key instead of removing

Output stance: identity investigation before remediation.

## Missing Uninstall Entry

Input finding:

- target: `LegacyVendorSuite`
- type: installed application remnants
- evidence: services and folders remain, but Apps and Features has no entry

Reasoning:

- uninstall is not the default startup remediation path
- first look for the vendor's official cleanup tool, installer maintenance mode, or support article
- third-party removers require strong trust rationale and explicit approval before download and execution
- record source URL, publisher, signature or hash when available, expected scope, and rollback limitations

Output stance: provide vetted uninstall guidance only after source verification.

## Disabled Item Still Present

Input finding:

- target: `VendorUpdaterLogon`
- type: scheduled logon task
- evidence: task appears in inventory but state is `Disabled`

Reasoning:

- disabled inventory is not active startup load
- do not claim disabling it will improve startup
- record it as residue only if cleanup is in scope

Output stance: no performance action; optional cleanup discussion.
