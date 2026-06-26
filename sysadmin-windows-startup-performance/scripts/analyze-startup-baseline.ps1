[CmdletBinding()]
param(
    [string]$BaselinePath = '',
    [string]$OutputPath = '',
    [string]$AnalysisOutputPath = '',
    [switch]$NoJsonOutput
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Findings = [System.Collections.Generic.List[object]]::new()

function Get-PropertyValue {
    param(
        [AllowNull()]$Object,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }

    if ($Object -is [System.Collections.IDictionary] -and $Object.Contains($Name)) {
        return $Object[$Name]
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($property) {
        return $property.Value
    }

    return $null
}

function ConvertTo-NumberOrNull {
    param([AllowNull()]$Value)

    if ($null -eq $Value) {
        return $null
    }

    $text = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    $longValue = [int64]0
    if ([int64]::TryParse($text, [ref]$longValue)) {
        return $longValue
    }

    $doubleValue = [double]0
    if ([double]::TryParse($text, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$doubleValue)) {
        return $doubleValue
    }

    return $null
}

function Get-EventDataValue {
    param(
        [AllowNull()]$Event,
        [Parameter(Mandatory = $true)][string[]]$Names
    )

    $data = Get-PropertyValue -Object $Event -Name 'data'
    if ($null -eq $data) {
        return $null
    }

    foreach ($name in $Names) {
        $value = Get-PropertyValue -Object $data -Name $name
        if (-not [string]::IsNullOrWhiteSpace([string]$value)) {
            return $value
        }
    }

    return $null
}

function Get-MaxDurationFromEvent {
    param([AllowNull()]$Event)

    $data = Get-PropertyValue -Object $Event -Name 'data'
    if ($null -eq $data) {
        return $null
    }

    $maxValue = $null
    foreach ($property in $data.PSObject.Properties) {
        if ($property.Name -notmatch '(?i)(time|duration|delay)$') {
            continue
        }

        $number = ConvertTo-NumberOrNull -Value $property.Value
        if ($null -eq $number) {
            continue
        }

        if ($null -eq $maxValue -or $number -gt $maxValue) {
            $maxValue = $number
        }
    }

    return $maxValue
}

function Add-Finding {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('high', 'medium', 'low', 'info')][string]$Severity,
        [Parameter(Mandatory = $true)][string]$Category,
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$Evidence,
        [Parameter(Mandatory = $true)][string]$Recommendation,
        [ValidateSet('high', 'medium', 'low')][string]$Confidence = 'medium'
    )

    $script:Findings.Add([pscustomobject]@{
        severity = $Severity
        category = $Category
        title = $Title
        evidence = $Evidence
        recommendation = $Recommendation
        confidence = $Confidence
    })
}

function Format-TableText {
    param([AllowNull()]$Value)

    if ($null -eq $Value) {
        return ''
    }

    return ([string]$Value).Replace('|', '/').Replace("`r", ' ').Replace("`n", ' ')
}

function Format-Milliseconds {
    param([AllowNull()]$Value)

    $number = ConvertTo-NumberOrNull -Value $Value
    if ($null -eq $number) {
        return ''
    }

    if ($number -ge 1000) {
        return ('{0:n1}s' -f ($number / 1000.0))
    }

    return ('{0:n0}ms' -f $number)
}

function Format-Bytes {
    param([AllowNull()]$Value)

    $number = ConvertTo-NumberOrNull -Value $Value
    if ($null -eq $number) {
        return ''
    }

    $units = @('B', 'KB', 'MB', 'GB', 'TB')
    $size = [double]$number
    $index = 0
    while ($size -ge 1024 -and $index -lt ($units.Count - 1)) {
        $size = $size / 1024
        $index += 1
    }

    return ('{0:n1} {1}' -f $size, $units[$index])
}

function Resolve-LatestBaselinePath {
    param([Parameter(Mandatory = $true)][string]$HubRoot)

    $stateDir = Join-Path $HubRoot 'state'
    if (-not (Test-Path -LiteralPath $stateDir)) {
        throw "No local-performance state directory found at $stateDir. Run collect-startup-baseline.ps1 first."
    }

    $latest = Get-ChildItem -LiteralPath $stateDir -Filter 'startup-baseline-*.json' -File -ErrorAction Stop |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($null -eq $latest) {
        throw "No startup baseline JSON files found under $stateDir. Run collect-startup-baseline.ps1 first."
    }

    return $latest.FullName
}

function Get-DegradationIdentity {
    param([Parameter(Mandatory = $true)]$Event)

    $identity = Get-EventDataValue -Event $Event -Names @('FriendlyName', 'FileName', 'Name', 'ServiceName', 'ImagePath', 'Path', 'ProcessName')
    if ([string]::IsNullOrWhiteSpace([string]$identity)) {
        $identity = 'Unspecified component'
    }

    return [string]$identity
}

$scriptRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptRoot)) {
    $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$hubRoot = Split-Path -Parent $scriptRoot
if ([string]::IsNullOrWhiteSpace($BaselinePath)) {
    $BaselinePath = Resolve-LatestBaselinePath -HubRoot $hubRoot
}
$BaselinePath = [IO.Path]::GetFullPath($BaselinePath)

$raw = Get-Content -Raw -LiteralPath $BaselinePath
$baseline = $raw | ConvertFrom-Json
$generatedAt = Get-Date
$stamp = $generatedAt.ToString('yyyyMMdd-HHmmss')

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $hubRoot "reports\startup-baseline-analysis-$stamp.md"
}
if ([string]::IsNullOrWhiteSpace($AnalysisOutputPath) -and -not $NoJsonOutput) {
    $AnalysisOutputPath = Join-Path $hubRoot "state\startup-analysis-$stamp.json"
}

$diagnostics = @(Get-PropertyValue -Object $baseline -Name 'diagnostics_performance_events')
$bootEvents = @($diagnostics | Where-Object { [int](Get-PropertyValue -Object $_ -Name 'id') -eq 100 } | Sort-Object time_created -Descending)
$degradationEvents = @($diagnostics | Where-Object { [int](Get-PropertyValue -Object $_ -Name 'id') -ne 100 })

if ($bootEvents.Count -eq 0) {
    Add-Finding -Severity 'medium' -Category 'measurement' -Title 'No Diagnostics-Performance boot event found' -Evidence 'The collector did not return event ID 100 from Microsoft-Windows-Diagnostics-Performance/Operational.' -Recommendation 'Confirm the Diagnostics-Performance operational log is enabled and rerun the collector after a reboot.' -Confidence 'medium'
} elseif ($bootEvents.Count -lt 3) {
    Add-Finding -Severity 'info' -Category 'measurement' -Title 'Baseline history is still thin' -Evidence ("Only {0} boot timing event(s) were included in this baseline." -f $bootEvents.Count) -Recommendation 'Collect at least three post-reboot baselines before applying startup changes.' -Confidence 'high'
}

$latestBoot = if ($bootEvents.Count -gt 0) { $bootEvents[0] } else { $null }
if ($null -ne $latestBoot) {
    $bootTime = ConvertTo-NumberOrNull -Value (Get-EventDataValue -Event $latestBoot -Names @('BootTime'))
    $mainPath = ConvertTo-NumberOrNull -Value (Get-EventDataValue -Event $latestBoot -Names @('MainPathBootTime'))
    $postBoot = ConvertTo-NumberOrNull -Value (Get-EventDataValue -Event $latestBoot -Names @('BootPostBootTime'))

    if ($null -ne $bootTime) {
        if ($bootTime -ge 120000) {
            Add-Finding -Severity 'high' -Category 'boot' -Title 'Latest boot time is high' -Evidence ("Latest Diagnostics-Performance BootTime is {0}." -f (Format-Milliseconds $bootTime)) -Recommendation 'Prioritize boot degradation events and startup/logon load before making changes.' -Confidence 'high'
        } elseif ($bootTime -ge 90000) {
            Add-Finding -Severity 'medium' -Category 'boot' -Title 'Latest boot time is elevated' -Evidence ("Latest Diagnostics-Performance BootTime is {0}." -f (Format-Milliseconds $bootTime)) -Recommendation 'Review repeated degradation events and collect two more post-reboot baselines.' -Confidence 'high'
        }
    }

    if ($null -ne $mainPath -and $mainPath -ge 45000) {
        Add-Finding -Severity 'medium' -Category 'boot' -Title 'Main boot path is slow' -Evidence ("MainPathBootTime is {0}." -f (Format-Milliseconds $mainPath)) -Recommendation 'Look first at driver/service degradation events rather than only login startup apps.' -Confidence 'medium'
    }

    if ($null -ne $postBoot -and $postBoot -ge 60000) {
        Add-Finding -Severity 'medium' -Category 'login' -Title 'Post-boot phase is slow' -Evidence ("BootPostBootTime is {0}." -f (Format-Milliseconds $postBoot)) -Recommendation 'Inspect startup apps, logon scheduled tasks, sync tools, launchers, and post-login resource pressure.' -Confidence 'medium'
    }
}

$degradationGroups = @($degradationEvents | Group-Object -Property { "{0}|{1}" -f (Get-PropertyValue -Object $_ -Name 'id'), (Get-DegradationIdentity -Event $_) })
foreach ($group in $degradationGroups) {
    $events = @($group.Group)
    $id = Get-PropertyValue -Object $events[0] -Name 'id'
    $identity = Get-DegradationIdentity -Event $events[0]
    $durations = @($events | ForEach-Object { Get-MaxDurationFromEvent -Event $_ } | Where-Object { $null -ne $_ })
    $maxDuration = if ($durations.Count -gt 0) { ($durations | Measure-Object -Maximum).Maximum } else { $null }
    $latestTime = ($events | Sort-Object time_created -Descending | Select-Object -First 1).time_created

    if ($events.Count -ge 3 -or ($null -ne $maxDuration -and $maxDuration -ge 10000)) {
        $severity = if ($events.Count -ge 3 -and $null -ne $maxDuration -and $maxDuration -ge 15000) { 'high' } else { 'medium' }
        $durationText = if ($null -ne $maxDuration) { Format-Milliseconds $maxDuration } else { 'unknown duration' }
        Add-Finding -Severity $severity -Category 'degradation' -Title ("Repeated boot degradation: {0}" -f $identity) -Evidence ("Event ID {0} appeared {1} time(s); max observed duration {2}; most recent {3}." -f $id, $events.Count, $durationText, $latestTime) -Recommendation 'Investigate this component across more baselines before disabling or changing it.' -Confidence 'medium'
    }
}

$startup = Get-PropertyValue -Object $baseline -Name 'startup'
$registryEntries = @(Get-PropertyValue -Object $startup -Name 'registry_entries')
$startupFolderItems = @(Get-PropertyValue -Object $startup -Name 'startup_folder_items')
$scheduledTasks = @(Get-PropertyValue -Object $startup -Name 'scheduled_startup_logon_tasks')
$autoServices = @(Get-PropertyValue -Object $startup -Name 'auto_start_services')
$delayedServices = @($autoServices | Where-Object { [bool](Get-PropertyValue -Object $_ -Name 'delayed_auto_start') })
$nonDelayedServices = @($autoServices | Where-Object { -not [bool](Get-PropertyValue -Object $_ -Name 'delayed_auto_start') })

if (($registryEntries.Count + $startupFolderItems.Count) -ge 20) {
    Add-Finding -Severity 'medium' -Category 'startup' -Title 'Many startup app entries' -Evidence ("Registry startup entries: {0}; startup-folder items: {1}." -f $registryEntries.Count, $startupFolderItems.Count) -Recommendation 'Review third-party startup apps first and disable only nonessential items after a baseline comparison.' -Confidence 'medium'
}
if ($scheduledTasks.Count -ge 20) {
    Add-Finding -Severity 'medium' -Category 'startup' -Title 'Many startup/logon scheduled tasks' -Evidence ("Startup/logon scheduled tasks: {0}." -f $scheduledTasks.Count) -Recommendation 'Review logon-triggered third-party tasks and consider delayed triggers only after an approved dry-run plan.' -Confidence 'medium'
}
if ($nonDelayedServices.Count -ge 100) {
    Add-Finding -Severity 'low' -Category 'services' -Title 'Large auto-start service surface' -Evidence ("Auto-start services: {0}; delayed-auto services: {1}." -f $autoServices.Count, $delayedServices.Count) -Recommendation 'Do not bulk-disable services. Use boot degradation events to identify specific third-party candidates.' -Confidence 'low'
}

$resources = Get-PropertyValue -Object $baseline -Name 'resources'
$disks = @(Get-PropertyValue -Object $resources -Name 'disks')
foreach ($disk in $disks) {
    $freePercent = ConvertTo-NumberOrNull -Value (Get-PropertyValue -Object $disk -Name 'free_percent')
    if ($null -eq $freePercent) {
        continue
    }
    $deviceId = Get-PropertyValue -Object $disk -Name 'device_id'
    if ($freePercent -lt 15) {
        Add-Finding -Severity 'high' -Category 'disk' -Title ("Low free space on {0}" -f $deviceId) -Evidence ("Free space is {0:n1}% ({1} free)." -f $freePercent, (Format-Bytes (Get-PropertyValue -Object $disk -Name 'free_bytes'))) -Recommendation 'Free disk space before tuning startup; low space can amplify update, indexing, and paging delays.' -Confidence 'high'
    } elseif ($freePercent -lt 25) {
        Add-Finding -Severity 'medium' -Category 'disk' -Title ("Free space is getting tight on {0}" -f $deviceId) -Evidence ("Free space is {0:n1}% ({1} free)." -f $freePercent, (Format-Bytes (Get-PropertyValue -Object $disk -Name 'free_bytes'))) -Recommendation 'Plan cleanup if this is the system or active workspace drive.' -Confidence 'medium'
    }
}

$memory = Get-PropertyValue -Object $resources -Name 'memory'
$memoryFreePercent = ConvertTo-NumberOrNull -Value (Get-PropertyValue -Object $memory -Name 'free_percent')
if ($null -ne $memoryFreePercent) {
    if ($memoryFreePercent -lt 15) {
        Add-Finding -Severity 'high' -Category 'memory' -Title 'Low free physical memory at collection time' -Evidence ("Free physical memory was {0:n1}% ({1} free)." -f $memoryFreePercent, (Format-Bytes (Get-PropertyValue -Object $memory -Name 'free_physical_bytes'))) -Recommendation 'Compare post-login baselines and inspect high working-set processes before disabling startup items.' -Confidence 'medium'
    } elseif ($memoryFreePercent -lt 25) {
        Add-Finding -Severity 'medium' -Category 'memory' -Title 'Physical memory headroom is limited' -Evidence ("Free physical memory was {0:n1}% ({1} free)." -f $memoryFreePercent, (Format-Bytes (Get-PropertyValue -Object $memory -Name 'free_physical_bytes'))) -Recommendation 'Check whether the same processes dominate memory after reboot.' -Confidence 'medium'
    }
}

$pageFiles = @(Get-PropertyValue -Object $resources -Name 'page_files')
foreach ($pageFile in $pageFiles) {
    $currentUsageMb = ConvertTo-NumberOrNull -Value (Get-PropertyValue -Object $pageFile -Name 'current_usage_mb')
    $peakUsageMb = ConvertTo-NumberOrNull -Value (Get-PropertyValue -Object $pageFile -Name 'peak_usage_mb')
    if ($currentUsageMb -ge 2048 -or $peakUsageMb -ge 4096) {
        Add-Finding -Severity 'medium' -Category 'memory' -Title 'Pagefile usage is notable' -Evidence ("Current pagefile usage: {0} MB; peak: {1} MB." -f $currentUsageMb, $peakUsageMb) -Recommendation 'Look for post-login memory pressure before tuning services.' -Confidence 'medium'
    }
}

$perfProcesses = Get-PropertyValue -Object $resources -Name 'perf_processes'
$topCpuNow = @(Get-PropertyValue -Object $perfProcesses -Name 'by_cpu_now')
$topIoNow = @(Get-PropertyValue -Object $perfProcesses -Name 'by_io_now')
$cpuHot = @($topCpuNow | Where-Object { (ConvertTo-NumberOrNull -Value (Get-PropertyValue -Object $_ -Name 'percent_processor_time')) -ge 25 } | Select-Object -First 5)
if ($cpuHot.Count -gt 0) {
    $names = ($cpuHot | ForEach-Object { "{0} ({1}%)" -f (Get-PropertyValue -Object $_ -Name 'name'), (Get-PropertyValue -Object $_ -Name 'percent_processor_time') }) -join ', '
    Add-Finding -Severity 'medium' -Category 'resource-pressure' -Title 'CPU pressure at collection time' -Evidence ("Top current CPU process samples: {0}." -f $names) -Recommendation 'Collect a post-login snapshot 3-5 minutes after reboot to see whether this repeats.' -Confidence 'low'
}
$ioHot = @($topIoNow | Where-Object { (ConvertTo-NumberOrNull -Value (Get-PropertyValue -Object $_ -Name 'io_data_bytes_per_sec')) -ge 5242880 } | Select-Object -First 5)
if ($ioHot.Count -gt 0) {
    $names = ($ioHot | ForEach-Object { "{0} ({1}/s)" -f (Get-PropertyValue -Object $_ -Name 'name'), (Format-Bytes (Get-PropertyValue -Object $_ -Name 'io_data_bytes_per_sec')) }) -join ', '
    Add-Finding -Severity 'medium' -Category 'resource-pressure' -Title 'Disk I/O pressure at collection time' -Evidence ("Top current I/O process samples: {0}." -f $names) -Recommendation 'Correlate with post-login boot timing and sync/indexing processes before changing startup.' -Confidence 'low'
}

$topProcesses = Get-PropertyValue -Object $resources -Name 'top_processes'
$topMemory = @(Get-PropertyValue -Object $topProcesses -Name 'by_working_set')
$memoryHot = @($topMemory | Where-Object { (ConvertTo-NumberOrNull -Value (Get-PropertyValue -Object $_ -Name 'working_set_bytes')) -ge 1610612736 } | Select-Object -First 5)
if ($memoryHot.Count -gt 0) {
    $names = ($memoryHot | ForEach-Object { "{0} ({1})" -f (Get-PropertyValue -Object $_ -Name 'name'), (Format-Bytes (Get-PropertyValue -Object $_ -Name 'working_set_bytes')) }) -join ', '
    Add-Finding -Severity 'low' -Category 'resource-pressure' -Title 'Large working-set processes observed' -Evidence ("Top memory processes: {0}." -f $names) -Recommendation 'Treat this as a snapshot signal; compare after a fresh reboot before changing anything.' -Confidence 'low'
}

$recentEvents = @(Get-PropertyValue -Object $baseline -Name 'recent_boot_events')
$recentGroups = @($recentEvents | Group-Object -Property { "{0}|{1}|{2}" -f (Get-PropertyValue -Object $_ -Name 'log'), (Get-PropertyValue -Object $_ -Name 'provider'), (Get-PropertyValue -Object $_ -Name 'id') })
foreach ($group in $recentGroups) {
    if ($group.Count -lt 3) {
        continue
    }
    $first = $group.Group[0]
    Add-Finding -Severity 'low' -Category 'event-log' -Title 'Repeated warning/error near boot' -Evidence ("{0} provider {1}, event ID {2}, appeared {3} time(s) near the current boot." -f (Get-PropertyValue -Object $first -Name 'log'), (Get-PropertyValue -Object $first -Name 'provider'), (Get-PropertyValue -Object $first -Name 'id'), $group.Count) -Recommendation 'Inspect the full event details locally if this provider also correlates with boot degradation.' -Confidence 'low'
}

$collectionErrors = @(Get-PropertyValue -Object $baseline -Name 'collection_errors')
if ($collectionErrors.Count -gt 0) {
    $diagnosticsAccessError = @($collectionErrors | Where-Object { (Get-PropertyValue -Object $_ -Name 'section') -eq 'diagnostics_performance_log' } | Select-Object -First 1)
    if ($diagnosticsAccessError.Count -gt 0) {
        Add-Finding -Severity 'info' -Category 'measurement' -Title 'Diagnostics-Performance log was not accessible' -Evidence 'The protected Diagnostics-Performance operational log could not be listed from this shell, so boot timing event IDs 100-199 were unavailable.' -Recommendation 'For exact boot-path timing, rerun the collector from an elevated PowerShell session after reboot. Continue using the rest of the baseline for startup inventory and resource-pressure signals.' -Confidence 'high'
    }
    $otherErrors = @($collectionErrors | Where-Object { (Get-PropertyValue -Object $_ -Name 'section') -ne 'diagnostics_performance_log' })
    if ($otherErrors.Count -gt 0) {
        Add-Finding -Severity 'info' -Category 'measurement' -Title 'Collector had partial read errors' -Evidence ("Collector recorded {0} non-Diagnostics partial error(s)." -f $otherErrors.Count) -Recommendation 'Review collection_errors in the JSON if an expected signal is missing.' -Confidence 'high'
    }
}

$severityWeight = @{ high = 0; medium = 1; low = 2; info = 3 }
$orderedFindings = @($script:Findings | Sort-Object @{ Expression = { $severityWeight[[string]$_.severity] } }, @{ Expression = { $_.category } }, @{ Expression = { $_.title } })

$summary = [ordered]@{
    finding_count = $orderedFindings.Count
    high = @($orderedFindings | Where-Object { $_.severity -eq 'high' }).Count
    medium = @($orderedFindings | Where-Object { $_.severity -eq 'medium' }).Count
    low = @($orderedFindings | Where-Object { $_.severity -eq 'low' }).Count
    info = @($orderedFindings | Where-Object { $_.severity -eq 'info' }).Count
    boot_event_count = $bootEvents.Count
    startup_registry_entry_count = $registryEntries.Count
    startup_folder_item_count = $startupFolderItems.Count
    startup_logon_task_count = $scheduledTasks.Count
    auto_start_service_count = $autoServices.Count
}

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('# Windows Startup Baseline Analysis')
$lines.Add('')
$lines.Add(('- Generated: {0}' -f $generatedAt.ToString('yyyy-MM-dd HH:mm:ss K')))
$lines.Add(('- Baseline: `{0}`' -f $BaselinePath))
$lines.Add('- Mode: read-only analysis; no startup or system settings were changed.')
$lines.Add('')

$machine = Get-PropertyValue -Object $baseline -Name 'machine'
$os = Get-PropertyValue -Object $baseline -Name 'operating_system'
$boot = Get-PropertyValue -Object $baseline -Name 'boot'
$lines.Add('## Machine')
$lines.Add('')
$lines.Add(('- Computer: {0}' -f (Format-TableText (Get-PropertyValue -Object $machine -Name 'computer_name'))))
$lines.Add(('- Model: {0} {1}' -f (Format-TableText (Get-PropertyValue -Object $machine -Name 'manufacturer')), (Format-TableText (Get-PropertyValue -Object $machine -Name 'model'))))
$lines.Add(('- OS: {0} {1} build {2}' -f (Format-TableText (Get-PropertyValue -Object $os -Name 'caption')), (Format-TableText (Get-PropertyValue -Object $os -Name 'version')), (Format-TableText (Get-PropertyValue -Object $os -Name 'build_number'))))
$lines.Add(('- Last boot: {0}' -f (Format-TableText (Get-PropertyValue -Object $boot -Name 'last_boot_local'))))
$lines.Add('')

$lines.Add('## Boot Timing')
$lines.Add('')
if ($bootEvents.Count -eq 0) {
    $lines.Add('No Diagnostics-Performance boot timing events were collected.')
} else {
    $lines.Add('| Time | BootTime | MainPath | PostBoot |')
    $lines.Add('| --- | ---: | ---: | ---: |')
    foreach ($event in ($bootEvents | Select-Object -First 5)) {
        $lines.Add(('| {0} | {1} | {2} | {3} |' -f
            (Format-TableText (Get-PropertyValue -Object $event -Name 'time_created')),
            (Format-Milliseconds (Get-EventDataValue -Event $event -Names @('BootTime'))),
            (Format-Milliseconds (Get-EventDataValue -Event $event -Names @('MainPathBootTime'))),
            (Format-Milliseconds (Get-EventDataValue -Event $event -Names @('BootPostBootTime')))))
    }
}
$lines.Add('')

$lines.Add('## Startup Inventory')
$lines.Add('')
$lines.Add('| Signal | Count |')
$lines.Add('| --- | ---: |')
$lines.Add(('| Registry startup entries | {0} |' -f $registryEntries.Count))
$lines.Add(('| Startup-folder items | {0} |' -f $startupFolderItems.Count))
$lines.Add(('| Startup/logon scheduled tasks | {0} |' -f $scheduledTasks.Count))
$lines.Add(('| Auto-start services | {0} |' -f $autoServices.Count))
$lines.Add(('| Delayed auto-start services | {0} |' -f $delayedServices.Count))
$lines.Add('')

$lines.Add('## Ranked Findings')
$lines.Add('')
if ($orderedFindings.Count -eq 0) {
    $lines.Add('No material bottleneck candidates were identified from this baseline. Collect more post-reboot baselines before concluding startup is clean.')
} else {
    $index = 1
    foreach ($finding in $orderedFindings) {
        $lines.Add(("{0}. [{1}] {2}" -f $index, ([string]$finding.severity).ToUpperInvariant(), $finding.title))
        $lines.Add(("   - Category: {0}; confidence: {1}" -f $finding.category, $finding.confidence))
        $lines.Add(("   - Evidence: {0}" -f $finding.evidence))
        $lines.Add(("   - Next step: {0}" -f $finding.recommendation))
        $index += 1
    }
}
$lines.Add('')

$lines.Add('## Suggested Next Measurement')
$lines.Add('')
$lines.Add('- Reboot normally, wait 3-5 minutes after login, then run the collector again.')
$lines.Add('- Repeat until there are at least three comparable baselines.')
$lines.Add('- Do not apply startup changes from a single snapshot; use a dry-run plan first.')
$lines.Add('')

$reportDirectory = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($reportDirectory)) {
    New-Item -ItemType Directory -Force -Path $reportDirectory | Out-Null
}
Set-Content -LiteralPath $OutputPath -Value $lines -Encoding UTF8

$analysis = [ordered]@{
    schema_version = 1
    kind = 'windows_startup_analysis'
    generated_at_local = $generatedAt.ToString('o')
    baseline_path = $BaselinePath
    report_path = [IO.Path]::GetFullPath($OutputPath)
    summary = $summary
    findings = $orderedFindings
}
$analysisJson = $analysis | ConvertTo-Json -Depth 10
if (-not $NoJsonOutput) {
    $analysisDirectory = Split-Path -Parent $AnalysisOutputPath
    if (-not [string]::IsNullOrWhiteSpace($analysisDirectory)) {
        New-Item -ItemType Directory -Force -Path $analysisDirectory | Out-Null
    }
    Set-Content -LiteralPath $AnalysisOutputPath -Value $analysisJson -Encoding UTF8
}

$analysisJson