# Hydra Scripts

Scripts intended to run inside a Windows guest through Hydra's scripting engine. Use them in the appropriate deployment rollout, script collection, scheduled script, or maintenance workflow after editing their configuration blocks.

Run machine-level installation and diagnostic work as SYSTEM or an administrator as appropriate. Scripts that reference `$global:Hydra_ServiceAccount_PSC` need Hydra's host-pool service account configured and the script's service-account option enabled. The credential's permissions depend on the task; the disk-tier script specifically requires an Azure service principal rather than an AD account.

## Script catalog

| Script | Purpose | Configuration and requirements |
| --- | --- | --- |
| [Add-HydraMachineToGroups.ps1](Add-HydraMachineToGroups.ps1) | Adds the current computer, or another configured account, to AD groups. | Set `$DomainFqdn`, `$TargetSamAccountName`, and `$GroupSamAccountNames`. Uses the Hydra credential to bind through LDAP; grant it permission to modify the target groups. |
| [AppMaskingSync.ps1](AppMaskingSync.ps1) | Downloads a ZIP of FSLogix app masking rules and assignments and deploys `.fxr`/`.fxa` files locally. | Set `$ZipUrl` and `$RulesDir`. Requires elevation and HTTPS access. Backups and overwrite are enabled; `$SyncMode` is off by default. Enabling sync removes local rules absent from the ZIP. |
| [Cleanup-FSLogixProfiles.ps1](Cleanup-FSLogixProfiles.ps1) | Reports, archives, or deletes profile folders for missing AD users, optionally including stale VHD/VHDX profiles. | PowerShell 5.1+, AD/LDAP connectivity, and share permissions. Configure roots, archive destination, search scope, and optional CSV/log paths. Defaults to `Report`; Hydra share authentication is enabled by default. |
| [ConvertHostPoolForTesting.ps1](ConvertHostPoolForTesting.ps1) | Downloads Login Enterprise's logon app and creates an all-users Startup shortcut for testing hosts. | Set `$applianceFQDN` to the appliance's HTTPS base URL. Uses Hydra's `LogWriter`; writes under `C:\LoginVSI` and the all-users Startup folder. Intended for deployment rollout. |
| [Get-LoginTimers.ps1](Get-LoginTimers.ps1) | Analyzes logged-on sessions using a ControlUp-derived logon analyzer and sends a compact timing summary to Hydra. | PowerShell 5.1+, SYSTEM/admin, and Hydra's `OutputWriter`. Run without arguments. Detailed reports are written under `%windir%\Temp\ALD`. `$EnableAuditing` is off by default; enable it to collect process events for future logons. |
| [Install-AppFromHttps.ps1](Install-AppFromHttps.ps1) | Downloads and runs an EXE/MSI installer, or selects an installer from a ZIP. | Set `$InstallerUrl`, silent arguments, working directory, optional download filename, and ZIP search patterns. Uses `OutputWriter` when available and otherwise writes to the console. The included URL is an example package. |
| [Install-FSLogixApps-HTTPS.ps1](Install-FSLogixApps-HTTPS.ps1) | Downloads the FSLogix ZIP and runs `FSLogixAppsSetup.exe` with unattended arguments. | Defaults to the FSLogix download URL and `C:\temp`; review arguments and installer selection before deployment. Uses the same optional Hydra logging as the generic installer. |
| [SelfDeleteADObjectWithBind.ps1](SelfDeleteADObjectWithBind.ps1) | Deletes the current machine's on-premises AD computer object using an explicit LDAP bind. | Requires the Hydra credential with computer-object deletion rights. Optional `-Server`, `-UseSSL`, and `-WhatIf`. Preview with `-WhatIf` before a deletion workflow. |
| [SessionConsolidationHelper.ps1](SessionConsolidationHelper.ps1) | Watches RemoteDesktopServices messages for consolidation text and logs off local sessions after a delay. | Configure matching terms, runtime, polling interval, and delay. Defaults: eight-hour watch, 30-second polling, 900-second delay, active/disconnected sessions, `$WhatIf = $false`. Forced logoff can discard unsaved work. |
| [Set-OwnAzureDiskTier.ps1](Set-OwnAzureDiskTier.ps1) | Changes an Azure managed disk's performance tier, discovering its VM through IMDS or using a configured VM name. | PowerShell 5.1+. Set tenant ID, target tier, VM mode, and OS/data disk selection. Hydra credential username must be the service principal client ID and password its secret, with Azure disk-update rights. `$WhatIf` defaults to false. |

## FSLogix cleanup

Start with `$ActionMode = 'Report'` and review the results before choosing `Move` or `Delete`. Configure `$FslogixRoots` and, for Move mode, `$ArchiveRoot`. Stale-profile cleanup is optional (`$CleanupIfVhdStale`, default false; `$VhdStaleDays`, default 90). User resolution uses AD/ADSI without requiring RSAT; this is not an Entra-only user cleanup implementation.

For standalone use, supply the share credential explicitly or disable `$UseHydraServiceAccountForShares` and run under an identity with share access.

## Choosing an execution context

The installers and app masking utility can also run standalone with suitable local rights. They are grouped here for their guest-side deployment role. The cleanup utility supports optional Hydra credentials; the AD membership/deletion and disk-tier scripts explicitly consume them. `Get-LoginTimers.ps1` requires Hydra logging, and `ConvertHostPoolForTesting.ps1` calls Hydra's `LogWriter`.

The previous repository README marked SessionConsolidationHelper as functionality incorporated into Hydra 2.0. Treat it as a legacy helper and check your deployment's built-in consolidation options before scheduling it.
