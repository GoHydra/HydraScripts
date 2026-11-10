# Run on the target AVD session host as SYSTEM or from elevated PowerShell.
# Use a runner independent of HydraAgent.exe so stopping it cannot interrupt cleanup.

function Write-UninstallProgress {
    param([string]$Message)

    if (Get-Command -Name OutputWriter -CommandType Function -ErrorAction SilentlyContinue) {
        OutputWriter($Message)
    }
    else {
        Write-Host $Message
    }
}

function Get-HydraAgentTask {
    Get-ScheduledTask -ErrorAction Stop |
        Where-Object { $_.TaskPath -eq '\' -and $_.TaskName -eq 'ITPC-AVD-Hydra-Helper' }
}

$programFiles = $env:ProgramW6432
if (-not $programFiles) {
    $programFiles = $env:ProgramFiles
}

try {
    $agentDirectory = Join-Path $programFiles 'ITProCloud.de\HydraAgent' -ErrorAction Stop
    $agentExecutable = Join-Path $agentDirectory 'HydraAgent.exe'
    Write-UninstallProgress "Starting Hydra Agent uninstall on $env:COMPUTERNAME."

    # Check the installation path before removing the task or touching the files.
    foreach ($path in @($programFiles, (Split-Path -Parent $agentDirectory), $agentDirectory)) {
        try {
            $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
        }
        catch [System.Management.Automation.ItemNotFoundException] {
            continue
        }
        if ($item.FullName -ne $path -or -not $item.PSIsContainer -or
            ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Expected a regular directory at '$path'. Review the installation path before retrying."
        }
    }

    $task = Get-HydraAgentTask
    if ($task) {
        if ($task.State -eq 'Running' -or $task.State -eq 'Queued') {
            Write-UninstallProgress "Stopping scheduled task '$($task.TaskName)'."
            Stop-ScheduledTask -InputObject $task -ErrorAction Stop
            $deadline = (Get-Date).AddSeconds(30)
            do {
                Start-Sleep -Milliseconds 500
                $task = Get-HydraAgentTask
            } while ($task.State -in 'Running', 'Queued' -and (Get-Date) -lt $deadline)

            if ($task.State -in 'Running', 'Queued') {
                throw 'The scheduled task did not stop within 30 seconds.'
            }
        }
        else {
            Write-UninstallProgress "Scheduled task '$($task.TaskName)' is already stopped."
        }

        if ($task) {
            Write-UninstallProgress "Removing scheduled task '$($task.TaskName)'."
            Unregister-ScheduledTask -InputObject $task -Confirm:$false -ErrorAction Stop
        }
    }
    else {
        Write-UninstallProgress 'Scheduled task is already absent.'
    }

    if (Get-HydraAgentTask) {
        throw 'The scheduled task is still registered.'
    }

    $processes = Get-CimInstance -ClassName Win32_Process -Filter "Name = 'HydraAgent.exe'" -ErrorAction Stop |
        Where-Object { $_.ExecutablePath -eq $agentExecutable }
    foreach ($process in $processes) {
        Write-UninstallProgress "Stopping remaining Hydra Agent process $($process.ProcessId)."
        Stop-Process -Id $process.ProcessId -Force -ErrorAction Stop
    }

    if (Test-Path -LiteralPath $agentDirectory -ErrorAction Stop) {
        Write-UninstallProgress "Deleting '$agentDirectory'."
        Remove-Item -LiteralPath $agentDirectory -Recurse -Force -ErrorAction Stop
    }
    else {
        Write-UninstallProgress 'Agent directory is already absent.'
    }

    if ((Test-Path -LiteralPath $agentDirectory -ErrorAction Stop) -or (Get-HydraAgentTask)) {
        throw 'Uninstall verification failed. The task or agent directory is still present.'
    }
    Write-UninstallProgress 'Hydra Agent uninstall complete. The scheduled task and agent directory are absent.'
}
catch {
    Write-UninstallProgress "Hydra Agent uninstall failed: $($_.Exception.Message)"
    throw
}
