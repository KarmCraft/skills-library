#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string]$OutputPath = '',
    [ValidateRange(1, 10000)]
    [int]$DiagnosticsEventCount = 300,
    [ValidateRange(0, 500)]
    [int]$DiagnosticsBootEventTarget = 25,
    [ValidateRange(100, 100000)]
    [int]$DiagnosticsEventScanCount = 5000,
    [int]$RecentEventCount = 120,
    [switch]$IncludeCommandLines,
    [switch]$NoWrite
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:CollectionErrors = [System.Collections.Generic.List[object]]::new()

function Add-CollectionError {
    param(
        [Parameter(Mandatory = $true)][string]$Section,
        [Parameter(Mandatory = $true)]$ErrorRecord
    )

    $script:CollectionErrors.Add([ordered]@{
        section = ConvertTo-SafeString -Value $Section -MaxLength 300
        message = ConvertTo-SafeString -Value $ErrorRecord.Exception.Message -MaxLength 500
    })
}

function ConvertTo-SafeString {
    param(
        [AllowNull()]$Value,
        [int]$MaxLength = 500
    )

    if ($null -eq $Value) {
        return $null
    }

    $text = [string]$Value
    $profile = [Environment]::GetFolderPath('UserProfile')
    if (-not [string]::IsNullOrWhiteSpace($profile)) {
        $text = $text.Replace($profile, '%USERPROFILE%')
    }

    $userName = [Environment]::UserName
    if (-not [string]::IsNullOrWhiteSpace($userName)) {
        $text = $text.Replace("\Users\$userName\", '\Users\%USERNAME%\')
    }

    $text = $text -replace '(?i)(token|apikey|api_key|password|secret|bearer)=([^\s;&]+)', '$1=<redacted>'

    if ($text.Length -gt $MaxLength) {
        $prefixLength = [Math]::Max(0, $MaxLength - 3)
        return $text.Substring(0, $prefixLength) + '...'
    }

    return $text
}

function Get-Sha256Hex {
    param([AllowNull()][string]$Text)

    if ($null -eq $Text) {
        return $null
    }

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
        $hashBytes = $sha.ComputeHash($bytes)
        return [BitConverter]::ToString($hashBytes).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Get-CommandSummary {
    param(
        [AllowNull()][string]$CommandLine,
        [switch]$IncludeFullCommandLine
    )

    if ([string]::IsNullOrWhiteSpace($CommandLine)) {
        return [ordered]@{
            executable = $null
            executable_name = $null
            arguments_present = $false
            command_hash_sha256 = $null
        }
    }

    $safe = ConvertTo-SafeString -Value $CommandLine -MaxLength 2000
    $executable = $null
    $remaining = ''
    if ($safe -match '^\s*"([^"]+)"\s*(.*)$') {
        $executable = $Matches[1]
        $remaining = $Matches[2]
    } elseif ($safe -match '^\s*([^\s]+)\s*(.*)$') {
        $executable = $Matches[1]
        $remaining = $Matches[2]
    }

    $name = $null
    if (-not [string]::IsNullOrWhiteSpace($executable)) {
        try {
            $name = Split-Path -Leaf $executable
        } catch {
            $name = $executable
        }
    }

    $summary = [ordered]@{
        executable = ConvertTo-SafeString -Value $executable -MaxLength 500
        executable_name = $name
        arguments_present = -not [string]::IsNullOrWhiteSpace($remaining)
        command_hash_sha256 = Get-Sha256Hex -Text $safe
    }

    if ($IncludeFullCommandLine) {
        $summary['command_line_preview'] = ConvertTo-SafeString -Value $safe -MaxLength 1000
    }

    return $summary
}

function Get-EventDataValue {
    param(
        [Parameter(Mandatory = $true)]$DataNode,
        [Parameter(Mandatory = $true)][string]$FallbackName,
        [int]$Index
    )

    $name = $null
    try {
        $name = [string]$DataNode.Name
    } catch {
        $name = $null
    }

    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = "${FallbackName}_${Index}"
    }

    $value = $null
    try {
        $value = [string]$DataNode.'#text'
    } catch {
        $value = [string]$DataNode
    }

    return @($name, (ConvertTo-SafeString -Value $value -MaxLength 500))
}

function Convert-WinEventRecord {
    param([Parameter(Mandatory = $true)]$Event)

    $data = [ordered]@{}
    try {
        $xml = [xml]$Event.ToXml()
        $index = 0
        foreach ($node in $xml.Event.EventData.Data) {
            $pair = Get-EventDataValue -DataNode $node -FallbackName 'data' -Index $index
            $data[$pair[0]] = $pair[1]
            $index += 1
        }
    } catch {
        $data['parse_error'] = ConvertTo-SafeString -Value $_.Exception.Message -MaxLength 300
    }

    return [ordered]@{
        time_created = if ($Event.TimeCreated) { $Event.TimeCreated.ToString('o') } else { $null }
        id = [int]$Event.Id
        provider = $Event.ProviderName
        level = $Event.LevelDisplayName
        record_id = $Event.RecordId
        data = $data
    }
}

function Convert-WinEventSummary {
    param(
        [Parameter(Mandatory = $true)]$Event,
        [Parameter(Mandatory = $true)][string]$LogName
    )

    return [ordered]@{
        log = $LogName
        time_created = if ($Event.TimeCreated) { $Event.TimeCreated.ToString('o') } else { $null }
        id = [int]$Event.Id
        provider = $Event.ProviderName
        level = $Event.LevelDisplayName
        record_id = $Event.RecordId
    }
}

function Get-DiagnosticsPerformanceEvents {
    param(
        [int]$MaxEvents,
        [int]$BootEventTarget,
        [int]$ScanCount
    )

    $logName = 'Microsoft-Windows-Diagnostics-Performance/Operational'

    try {
        $null = Get-WinEvent -ListLog $logName -ErrorAction Stop
    } catch {
        Add-CollectionError -Section 'diagnostics_performance_log' -ErrorRecord $_
        return [ordered]@{
            events = @()
            metadata = [ordered]@{
                log_name = $logName
                requested_recent_event_count = $MaxEvents
                requested_boot_event_target = $BootEventTarget
                requested_scan_count = $ScanCount
                effective_scan_count = $null
                scanned_event_count = 0
                matched_diagnostics_event_count = 0
                matched_boot_event_count = 0
                returned_event_count = 0
                returned_boot_event_count = 0
                boot_target_satisfied = $false
                scan_limit_reached = $false
                mode = 'unavailable'
            }
        }
    }

    try {
        $effectiveScanCount = [Math]::Max($ScanCount, [Math]::Max($MaxEvents * 10, 500))
        $rawEvents = @(Get-WinEvent -FilterHashtable @{
            LogName = $logName
        } -MaxEvents $effectiveScanCount -ErrorAction Stop)

        $diagnosticEvents = @($rawEvents |
            Where-Object { $_.Id -ge 100 -and $_.Id -le 199 })
        $bootEvents = @($diagnosticEvents |
            Where-Object { $_.Id -eq 100 })

        $recentWindow = @($diagnosticEvents | Select-Object -First $MaxEvents)
        $selectedEvents = $recentWindow
        $targetWindowEventCount = $null
        $oldestTargetBootTime = $null
        $mode = 'recent-count'

        if ($BootEventTarget -gt 0 -and $bootEvents.Count -gt 0) {
            $targetBootEvents = @($bootEvents | Select-Object -First $BootEventTarget)
            $oldestTargetBoot = $targetBootEvents[-1]
            $oldestTargetBootTime = if ($oldestTargetBoot.TimeCreated) { $oldestTargetBoot.TimeCreated.ToString('o') } else { $null }
            $targetWindow = @($diagnosticEvents | Where-Object {
                if ($oldestTargetBoot.TimeCreated -and $_.TimeCreated) {
                    $_.TimeCreated -ge $oldestTargetBoot.TimeCreated
                } else {
                    $_.RecordId -ge $oldestTargetBoot.RecordId
                }
            })
            $targetWindowEventCount = $targetWindow.Count

            if ($targetWindow.Count -gt $selectedEvents.Count) {
                $selectedEvents = $targetWindow
                $mode = 'boot-targeted'
            } else {
                $mode = 'recent-count-with-boot-target'
            }
        }

        $returnedBootCount = @($selectedEvents | Where-Object { $_.Id -eq 100 }).Count
        $newestReturned = $selectedEvents | Select-Object -First 1
        $oldestReturned = $selectedEvents | Select-Object -Last 1

        return [ordered]@{
            events = @($selectedEvents | ForEach-Object { Convert-WinEventRecord -Event $_ })
            metadata = [ordered]@{
                log_name = $logName
                requested_recent_event_count = $MaxEvents
                requested_boot_event_target = $BootEventTarget
                requested_scan_count = $ScanCount
                effective_scan_count = $effectiveScanCount
                scanned_event_count = $rawEvents.Count
                matched_diagnostics_event_count = $diagnosticEvents.Count
                matched_boot_event_count = $bootEvents.Count
                returned_event_count = $selectedEvents.Count
                returned_boot_event_count = $returnedBootCount
                boot_target_satisfied = if ($BootEventTarget -gt 0) { $returnedBootCount -ge $BootEventTarget } else { $null }
                scan_limit_reached = $rawEvents.Count -ge $effectiveScanCount
                target_window_event_count = $targetWindowEventCount
                oldest_target_boot_time = $oldestTargetBootTime
                newest_returned_time = if ($newestReturned -and $newestReturned.TimeCreated) { $newestReturned.TimeCreated.ToString('o') } else { $null }
                oldest_returned_time = if ($oldestReturned -and $oldestReturned.TimeCreated) { $oldestReturned.TimeCreated.ToString('o') } else { $null }
                mode = $mode
            }
        }
    } catch {
        if ($_.Exception.Message -like '*No events were found*') {
            return [ordered]@{
                events = @()
                metadata = [ordered]@{
                    log_name = $logName
                    requested_recent_event_count = $MaxEvents
                    requested_boot_event_target = $BootEventTarget
                    requested_scan_count = $ScanCount
                    effective_scan_count = $null
                    scanned_event_count = 0
                    matched_diagnostics_event_count = 0
                    matched_boot_event_count = 0
                    returned_event_count = 0
                    returned_boot_event_count = 0
                    boot_target_satisfied = $false
                    scan_limit_reached = $false
                    mode = 'empty'
                }
            }
        }
        Add-CollectionError -Section 'diagnostics_performance_events' -ErrorRecord $_
        return [ordered]@{
            events = @()
            metadata = [ordered]@{
                log_name = $logName
                requested_recent_event_count = $MaxEvents
                requested_boot_event_target = $BootEventTarget
                requested_scan_count = $ScanCount
                effective_scan_count = $null
                scanned_event_count = 0
                matched_diagnostics_event_count = 0
                matched_boot_event_count = 0
                returned_event_count = 0
                returned_boot_event_count = 0
                boot_target_satisfied = $false
                scan_limit_reached = $false
                mode = 'error'
            }
        }
    }
}

function Get-RegistryStartupEntries {
    param([switch]$IncludeFullCommandLine)

    $keys = @(
        @{ scope = 'CurrentUser'; kind = 'Run'; path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' },
        @{ scope = 'CurrentUser'; kind = 'RunOnce'; path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce' },
        @{ scope = 'LocalMachine'; kind = 'Run'; path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run' },
        @{ scope = 'LocalMachine'; kind = 'RunOnce'; path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce' },
        @{ scope = 'LocalMachine32'; kind = 'Run'; path = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run' },
        @{ scope = 'LocalMachine32'; kind = 'RunOnce'; path = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce' }
    )

    $entries = @()
    foreach ($key in $keys) {
        try {
            if (-not (Test-Path -LiteralPath $key.path)) {
                continue
            }

            $item = Get-ItemProperty -LiteralPath $key.path -ErrorAction Stop
            foreach ($property in $item.PSObject.Properties) {
                if ($property.Name -in @('PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider')) {
                    continue
                }

                $entries += [ordered]@{
                    scope = $key.scope
                    kind = $key.kind
                    key_path = $key.path
                    name = $property.Name
                    command = Get-CommandSummary -CommandLine ([string]$property.Value) -IncludeFullCommandLine:$IncludeFullCommandLine
                }
            }
        } catch {
            Add-CollectionError -Section "startup_registry:$($key.path)" -ErrorRecord $_
        }
    }

    return $entries
}

function Get-ShortcutTarget {
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($Path)
        $target = [string]$shortcut.TargetPath
        $arguments = [string]$shortcut.Arguments
        if ([string]::IsNullOrWhiteSpace($arguments)) {
            return $target
        }
        return ('"{0}" {1}' -f $target, $arguments)
    } catch {
        Add-CollectionError -Section "startup_shortcut:$Path" -ErrorRecord $_
        return $null
    }
}

function Get-StartupFolderItems {
    param([switch]$IncludeFullCommandLine)

    $folders = @(
        @{ scope = 'CurrentUser'; path = [Environment]::GetFolderPath('Startup') },
        @{ scope = 'AllUsers'; path = [Environment]::GetFolderPath('CommonStartup') }
    )

    $items = @()
    foreach ($folder in $folders) {
        try {
            if ([string]::IsNullOrWhiteSpace($folder.path) -or -not (Test-Path -LiteralPath $folder.path)) {
                continue
            }

            foreach ($file in Get-ChildItem -LiteralPath $folder.path -File -Force -ErrorAction Stop) {
                $commandLine = $file.FullName
                if ($file.Extension -ieq '.lnk') {
                    $target = Get-ShortcutTarget -Path $file.FullName
                    if (-not [string]::IsNullOrWhiteSpace($target)) {
                        $commandLine = $target
                    }
                }

                $items += [ordered]@{
                    scope = $folder.scope
                    name = $file.Name
                    extension = $file.Extension
                    path = ConvertTo-SafeString -Value $file.FullName -MaxLength 500
                    command = Get-CommandSummary -CommandLine $commandLine -IncludeFullCommandLine:$IncludeFullCommandLine
                }
            }
        } catch {
            Add-CollectionError -Section "startup_folder:$($folder.path)" -ErrorRecord $_
        }
    }

    return $items
}

function Get-ScheduledTaskTriggerTypes {
    param([AllowNull()]$Task)

    if ($null -eq $Task) {
        return @()
    }

    $types = @()
    foreach ($trigger in @($Task.Triggers)) {
        if ($null -eq $trigger) {
            continue
        }

        $className = $null
        $cimClassProperty = $trigger.PSObject.Properties['CimClass']
        if ($cimClassProperty -and $null -ne $cimClassProperty.Value) {
            try {
                $className = [string]$cimClassProperty.Value.CimClassName
            } catch {
                $className = $null
            }
        }

        if ([string]::IsNullOrWhiteSpace($className)) {
            foreach ($typeName in $trigger.PSObject.TypeNames) {
                if ($typeName -match 'MSFT_Task[A-Za-z]+Trigger') {
                    $className = $Matches[0]
                    break
                }
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($className)) {
            $types += $className
        }
    }

    return @($types | Select-Object -Unique)
}
function Get-ScheduledStartupTasks {
    param([switch]$IncludeFullCommandLine)

    try {
        $tasks = Get-ScheduledTask -ErrorAction Stop
    } catch {
        Add-CollectionError -Section 'scheduled_tasks' -ErrorRecord $_
        return @()
    }

    $results = @()
    foreach ($task in $tasks) {
        try {
            $triggerTypes = Get-ScheduledTaskTriggerTypes -Task $task
            $isStartupOrLogon = $false
            foreach ($type in $triggerTypes) {
                if ($type -in @('MSFT_TaskBootTrigger', 'MSFT_TaskLogonTrigger')) {
                    $isStartupOrLogon = $true
                }
            }
            if (-not $isStartupOrLogon) {
                continue
            }

            $actions = @()
            foreach ($action in $task.Actions) {
                $execute = $null
                $arguments = $null
                if ($action.PSObject.Properties['Execute']) {
                    $execute = [string]$action.Execute
                }
                if ($action.PSObject.Properties['Arguments']) {
                    $arguments = [string]$action.Arguments
                }

                $actionRecord = [ordered]@{
                    execute = ConvertTo-SafeString -Value $execute -MaxLength 500
                    execute_name = if ([string]::IsNullOrWhiteSpace($execute)) { $null } else { Split-Path -Leaf $execute }
                    arguments_present = -not [string]::IsNullOrWhiteSpace($arguments)
                    arguments_hash_sha256 = if ([string]::IsNullOrWhiteSpace($arguments)) { $null } else { Get-Sha256Hex -Text (ConvertTo-SafeString -Value $arguments -MaxLength 2000) }
                }
                if ($IncludeFullCommandLine -and -not [string]::IsNullOrWhiteSpace($arguments)) {
                    $actionRecord['arguments_preview'] = ConvertTo-SafeString -Value $arguments -MaxLength 1000
                }
                $actions += $actionRecord
            }

            $results += [ordered]@{
                task_path = $task.TaskPath
                task_name = $task.TaskName
                state = [string]$task.State
                author = ConvertTo-SafeString -Value $task.Author -MaxLength 300
                trigger_types = $triggerTypes
                actions = $actions
            }
        } catch {
            Add-CollectionError -Section "scheduled_task:$($task.TaskPath)$($task.TaskName)" -ErrorRecord $_
        }
    }

    return @($results | Sort-Object task_path, task_name)
}

function Get-AutoStartServices {
    param([switch]$IncludeFullCommandLine)

    try {
        $services = Get-CimInstance -ClassName Win32_Service -ErrorAction Stop | Where-Object { $_.StartMode -eq 'Auto' }
    } catch {
        Add-CollectionError -Section 'auto_start_services' -ErrorRecord $_
        return @()
    }

    $results = @()
    foreach ($service in $services) {
        $delayed = $false
        try {
            $keyPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$($service.Name)"
            $property = Get-ItemProperty -LiteralPath $keyPath -Name DelayedAutoStart -ErrorAction SilentlyContinue
            if ($null -ne $property -and $property.PSObject.Properties['DelayedAutoStart']) {
                $delayed = [int]$property.DelayedAutoStart -eq 1
            }
        } catch {
            $delayed = $false
        }

        $results += [ordered]@{
            name = $service.Name
            display_name = $service.DisplayName
            state = $service.State
            status = $service.Status
            delayed_auto_start = $delayed
            service_account = ConvertTo-SafeString -Value $service.StartName -MaxLength 300
            path = Get-CommandSummary -CommandLine ([string]$service.PathName) -IncludeFullCommandLine:$IncludeFullCommandLine
        }
    }

    return @($results | Sort-Object display_name, name)
}

function Get-DiskSummary {
    try {
        $disks = Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction Stop
        return @($disks | ForEach-Object {
            $size = [double]$_.Size
            $free = [double]$_.FreeSpace
            [ordered]@{
                device_id = $_.DeviceID
                volume_name = ConvertTo-SafeString -Value $_.VolumeName -MaxLength 200
                size_bytes = [int64]$_.Size
                free_bytes = [int64]$_.FreeSpace
                free_percent = if ($size -gt 0) { [Math]::Round(($free / $size) * 100, 2) } else { $null }
            }
        })
    } catch {
        Add-CollectionError -Section 'disk_summary' -ErrorRecord $_
        return @()
    }
}

function Get-MemorySummary {
    param([Parameter(Mandatory = $true)]$OperatingSystem)

    try {
        $totalKb = [double]$OperatingSystem.TotalVisibleMemorySize
        $freeKb = [double]$OperatingSystem.FreePhysicalMemory
        return [ordered]@{
            total_visible_bytes = [int64]($totalKb * 1024)
            free_physical_bytes = [int64]($freeKb * 1024)
            free_percent = if ($totalKb -gt 0) { [Math]::Round(($freeKb / $totalKb) * 100, 2) } else { $null }
        }
    } catch {
        Add-CollectionError -Section 'memory_summary' -ErrorRecord $_
        return [ordered]@{}
    }
}

function Get-PageFileSummary {
    try {
        $pageFiles = Get-CimInstance -ClassName Win32_PageFileUsage -ErrorAction Stop
        return @($pageFiles | ForEach-Object {
            [ordered]@{
                name = ConvertTo-SafeString -Value $_.Name -MaxLength 500
                allocated_base_mb = [int]$_.AllocatedBaseSize
                current_usage_mb = [int]$_.CurrentUsage
                peak_usage_mb = [int]$_.PeakUsage
            }
        })
    } catch {
        Add-CollectionError -Section 'page_file_summary' -ErrorRecord $_
        return @()
    }
}

function Get-ProcessCpuSeconds {
    param([Parameter(Mandatory = $true)]$Process)

    try {
        $totalProcessorTime = $Process.TotalProcessorTime
        if ($null -eq $totalProcessorTime) {
            return $null
        }

        if ($totalProcessorTime -is [TimeSpan]) {
            return [Math]::Round([double]$totalProcessorTime.TotalSeconds, 2)
        }

        $totalSecondsProperty = $totalProcessorTime.PSObject.Properties['TotalSeconds']
        if ($null -ne $totalSecondsProperty) {
            return [Math]::Round([double]$totalSecondsProperty.Value, 2)
        }
    } catch {
        return $null
    }

    return $null
}

function Get-ProcessSnapshotRecord {
    param([Parameter(Mandatory = $true)]$Process)

    $id = $null
    $name = $null
    $workingSetBytes = $null
    $privateMemoryBytes = $null

    try {
        $id = [int]$Process.Id
    } catch {
        $id = $null
    }

    try {
        $name = [string]$Process.ProcessName
    } catch {
        $name = $null
    }

    try {
        $workingSetBytes = [int64]$Process.WorkingSet64
    } catch {
        $workingSetBytes = $null
    }

    try {
        $privateMemoryBytes = [int64]$Process.PrivateMemorySize64
    } catch {
        $privateMemoryBytes = $null
    }

    if ($null -eq $id -and [string]::IsNullOrWhiteSpace($name)) {
        return $null
    }

    return [ordered]@{
        id = $id
        name = $name
        cpu_seconds = Get-ProcessCpuSeconds -Process $Process
        working_set_bytes = $workingSetBytes
        private_memory_bytes = $privateMemoryBytes
    }
}

function Get-TopProcessSummary {
    try {
        $processes = Get-Process -ErrorAction Stop
        $records = @($processes | ForEach-Object {
            Get-ProcessSnapshotRecord -Process $_
        } | Where-Object { $null -ne $_ })

        $topCpu = @($records |
            Where-Object { $null -ne $_['cpu_seconds'] } |
            Sort-Object { $_['cpu_seconds'] } -Descending |
            Select-Object -First 12)
        $topMemory = @($records |
            Where-Object { $null -ne $_['working_set_bytes'] } |
            Sort-Object { $_['working_set_bytes'] } -Descending |
            Select-Object -First 12)

        return [ordered]@{
            by_cumulative_cpu = $topCpu
            by_working_set = $topMemory
        }
    } catch {
        Add-CollectionError -Section 'top_process_summary' -ErrorRecord $_
        return [ordered]@{}
    }
}
function Get-PerfProcessSummary {
    try {
        $perf = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfProc_Process -ErrorAction Stop |
            Where-Object { $_.Name -notin @('_Total', 'Idle') }

        $topCpu = @($perf | Sort-Object PercentProcessorTime -Descending | Select-Object -First 12 | ForEach-Object {
            [ordered]@{
                id = [int]$_.IDProcess
                name = $_.Name
                percent_processor_time = [int64]$_.PercentProcessorTime
                io_data_bytes_per_sec = [int64]$_.IODataBytesPersec
                working_set_bytes = [int64]$_.WorkingSet
            }
        })
        $topIo = @($perf | Sort-Object IODataBytesPersec -Descending | Select-Object -First 12 | ForEach-Object {
            [ordered]@{
                id = [int]$_.IDProcess
                name = $_.Name
                percent_processor_time = [int64]$_.PercentProcessorTime
                io_data_bytes_per_sec = [int64]$_.IODataBytesPersec
                working_set_bytes = [int64]$_.WorkingSet
            }
        })

        return [ordered]@{
            by_cpu_now = $topCpu
            by_io_now = $topIo
        }
    } catch {
        Add-CollectionError -Section 'perf_process_summary' -ErrorRecord $_
        return [ordered]@{}
    }
}

function Get-RecentBootWarnings {
    param(
        [Parameter(Mandatory = $true)][DateTime]$StartTime,
        [int]$MaxEvents
    )

    $logs = @('System', 'Application')
    $results = @()
    foreach ($log in $logs) {
        try {
            $events = Get-WinEvent -FilterHashtable @{
                LogName = $log
                StartTime = $StartTime
                Level = @(2, 3)
            } -MaxEvents $MaxEvents -ErrorAction Stop
            $results += @($events | ForEach-Object { Convert-WinEventSummary -Event $_ -LogName $log })
        } catch {
            if ($_.Exception.Message -like '*No events were found*') {
                continue
            }
            Add-CollectionError -Section "recent_boot_events:$log" -ErrorRecord $_
        }
    }

    return @($results | Sort-Object time_created -Descending | Select-Object -First $MaxEvents)
}

$scriptRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptRoot)) {
    $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$hubRoot = Split-Path -Parent $scriptRoot
if ([string]::IsNullOrWhiteSpace($OutputPath) -and -not $NoWrite) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $OutputPath = Join-Path $hubRoot "state\startup-baseline-$stamp.json"
}

$now = Get-Date
$os = $null
$computer = $null
try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
} catch {
    Add-CollectionError -Section 'operating_system' -ErrorRecord $_
}
try {
    $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
} catch {
    Add-CollectionError -Section 'computer_system' -ErrorRecord $_
}

$lastBoot = $null
if ($null -ne $os) {
    $lastBoot = $os.LastBootUpTime
}
if ($null -eq $lastBoot) {
    $lastBoot = $now
}

$diagnosticsPerformance = Get-DiagnosticsPerformanceEvents `
    -MaxEvents $DiagnosticsEventCount `
    -BootEventTarget $DiagnosticsBootEventTarget `
    -ScanCount $DiagnosticsEventScanCount

$baseline = [ordered]@{
    schema_version = 1
    kind = 'windows_startup_baseline'
    collected_at_local = $now.ToString('o')
    collected_at_utc = $now.ToUniversalTime().ToString('o')
    machine = [ordered]@{
        computer_name = if ($null -ne $computer) { $computer.Name } else { $env:COMPUTERNAME }
        manufacturer = if ($null -ne $computer) { ConvertTo-SafeString -Value $computer.Manufacturer -MaxLength 200 } else { $null }
        model = if ($null -ne $computer) { ConvertTo-SafeString -Value $computer.Model -MaxLength 200 } else { $null }
        domain_role = if ($null -ne $computer) { $computer.DomainRole } else { $null }
    }
    operating_system = [ordered]@{
        caption = if ($null -ne $os) { $os.Caption } else { $null }
        version = if ($null -ne $os) { $os.Version } else { $null }
        build_number = if ($null -ne $os) { $os.BuildNumber } else { $null }
    }
    boot = [ordered]@{
        last_boot_local = $lastBoot.ToString('o')
        uptime_seconds = [int64]([Math]::Max(0, ($now - $lastBoot).TotalSeconds))
    }
    diagnostics_performance_events = $diagnosticsPerformance.events
    diagnostics_performance_collection = $diagnosticsPerformance.metadata
    startup = [ordered]@{
        registry_entries = Get-RegistryStartupEntries -IncludeFullCommandLine:$IncludeCommandLines
        startup_folder_items = Get-StartupFolderItems -IncludeFullCommandLine:$IncludeCommandLines
        scheduled_startup_logon_tasks = Get-ScheduledStartupTasks -IncludeFullCommandLine:$IncludeCommandLines
        auto_start_services = Get-AutoStartServices -IncludeFullCommandLine:$IncludeCommandLines
    }
    resources = [ordered]@{
        disks = Get-DiskSummary
        memory = Get-MemorySummary -OperatingSystem $os
        page_files = Get-PageFileSummary
        top_processes = Get-TopProcessSummary
        perf_processes = Get-PerfProcessSummary
    }
    recent_boot_events = Get-RecentBootWarnings -StartTime $lastBoot.AddMinutes(-5) -MaxEvents $RecentEventCount
    collection_errors = $script:CollectionErrors
}

$json = $baseline | ConvertTo-Json -Depth 14
if (-not $NoWrite) {
    $directory = Split-Path -Parent $OutputPath
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }
    Set-Content -LiteralPath $OutputPath -Value $json -Encoding UTF8
}

$json
