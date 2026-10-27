<#
.SYNOPSIS
    Removes the Hydra (Login VSI / ITProCloud) agent from a session host.

.DESCRIPTION
    - Stops and removes the ITPC-AVD-Hydra-Helper scheduled task
      (plus any other scheduled task whose action points into the install folder)
    - Stops and removes any service whose binary lives in the install folder
    - Kills any processes running from, or referencing, the install folder
    - Deletes C:\Program Files\ITProCloud.de\HydraAgent
    - Removes the parent ITProCloud.de folder if it is left empty

    Supports -WhatIf for a dry run. Must be run elevated.

.EXAMPLE
    .\Uninstall-HydraAgent.ps1 -WhatIf
    .\Uninstall-HydraAgent.ps1
    .\Uninstall-HydraAgent.ps1 -LogPath C:\Temp\HydraUninstall.log
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$TaskName    = 'ITPC-AVD-Hydra-Helper',
    [string]$InstallPath = 'C:\Program Files\ITProCloud.de\HydraAgent',
    [string]$LogPath     = "$env:ProgramData\HydraAgentUninstall.log"
)

$ErrorActionPreference = 'Stop'

function Write-Log {
    param([string]$Message, [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $line
    try { Add-Content -Path $LogPath -Value $line -ErrorAction SilentlyContinue } catch {}
}

# --- Elevation check ---------------------------------------------------------
$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error 'This script must be run as Administrator.'
    exit 1
}

Write-Log "Starting Hydra agent removal on $env:COMPUTERNAME"
$escapedPath = [regex]::Escape($InstallPath)
$exitCode = 0

# --- 1. Scheduled tasks ------------------------------------------------------
try {
    $tasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
        $_.TaskName -eq $TaskName -or
        ($_.Actions | Where-Object { "$($_.Execute) $($_.Arguments) $($_.WorkingDirectory)" -match $escapedPath })
    })

    if ($tasks.Count -eq 0) {
        Write-Log "No matching scheduled tasks found."
    }

    foreach ($t in $tasks) {
        $id = "$($t.TaskPath)$($t.TaskName)"
        if ($PSCmdlet.ShouldProcess($id, 'Stop and unregister scheduled task')) {
            if ($t.State -eq 'Running') {
                Stop-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction SilentlyContinue
                Write-Log "Stopped running task $id"
            }
            Unregister-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -Confirm:$false
            Write-Log "Removed scheduled task $id"
        }
    }
} catch {
    Write-Log "Scheduled task removal failed: $($_.Exception.Message)" 'ERROR'
    $exitCode = 1
}

# --- 2. Services (defensive; normally none) ---------------------------------
try {
    $services = @(Get-CimInstance Win32_Service | Where-Object { $_.PathName -match $escapedPath })
    foreach ($svc in $services) {
        if ($PSCmdlet.ShouldProcess($svc.Name, 'Stop and delete service')) {
            Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
            & sc.exe delete $svc.Name | Out-Null
            Write-Log "Removed service $($svc.Name)"
        }
    }
} catch {
    Write-Log "Service check failed: $($_.Exception.Message)" 'WARN'
}

# --- 3. Processes running from / referencing the install folder -------------
try {
    $procs = @(Get-CimInstance Win32_Process | Where-Object {
        $_.ProcessId -ne $PID -and (
            ($_.ExecutablePath -and $_.ExecutablePath -match $escapedPath) -or
            ($_.CommandLine    -and $_.CommandLine    -match $escapedPath)
        )
    })
    foreach ($p in $procs) {
        if ($PSCmdlet.ShouldProcess("$($p.Name) (PID $($p.ProcessId))", 'Stop process')) {
            Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
            Write-Log "Killed process $($p.Name) (PID $($p.ProcessId))"
        }
    }
    if ($procs.Count) { Start-Sleep -Seconds 3 }   # let file handles release
} catch {
    Write-Log "Process cleanup failed: $($_.Exception.Message)" 'WARN'
}

# --- 4. Install folder -------------------------------------------------------
if (Test-Path -LiteralPath $InstallPath) {
    if ($PSCmdlet.ShouldProcess($InstallPath, 'Delete folder')) {
        $removed = $false
        for ($i = 1; $i -le 3 -and -not $removed; $i++) {
            try {
                Remove-Item -LiteralPath $InstallPath -Recurse -Force
                $removed = $true
                Write-Log "Deleted $InstallPath"
            } catch {
                Write-Log "Attempt $i to delete folder failed: $($_.Exception.Message)" 'WARN'
                Start-Sleep -Seconds 5
            }
        }
        if (-not $removed) {
            Write-Log "Could not delete $InstallPath. A reboot may be required to release locks." 'ERROR'
            $exitCode = 1
        }
    }
} else {
    Write-Log "Install folder not found: $InstallPath"
}

# --- 5. Parent folder if empty -----------------------------------------------
$parent = Split-Path -Path $InstallPath -Parent
if ((Test-Path -LiteralPath $parent) -and -not (Get-ChildItem -LiteralPath $parent -Force)) {
    if ($PSCmdlet.ShouldProcess($parent, 'Delete empty parent folder')) {
        Remove-Item -LiteralPath $parent -Force -ErrorAction SilentlyContinue
        Write-Log "Deleted empty parent folder $parent"
    }
}

Write-Log "Hydra agent removal finished with exit code $exitCode"
exit $exitCode