# StorageSpaces Module — Decisions & Findings Log

Full record of every change applied to `StorageSpaces_Revised.psm1`, including
the rationale. Use this to understand why any specific change was made.

---

## 1. Feature Removals

### 1.1 Cluster Support Removed

**Scope:** All cluster-specific code stripped from the module.

**What was removed:**
- 4 internal utility functions: `Get-ClusteredPoolFromStoragePool`,
  `Get-ClusterCSVFromStorageSpace`, `Get-ClusterPoolOwner`, `Test-PsRemoting`
- Cluster parameter sets from `Get-SpacesPhysicalDisk`
  (`-ServerToCompare`, `-ClusterFriendlyName`, `-Throttle`)
- Cluster ownership/CSV logic from `New-SpacesVolume`
  (`-CreateClusterSharedVolume` switch and associated blocks)
- `if ($Cluster)` branch from `Get-SpacesVolume`
- Cluster resize path from `Resize-SpacesVolume`
- Cluster property additions from `Get-SpacesConfiguration`
- `IsPoolClustered` check from `Test-SpacesConfiguration`
- Cluster filter from `Repair-SpacesConfiguration` pool query
- 8 cluster-only string table entries
- ~30 cluster-referencing inline comments

**Rationale:** Author no longer manages clustered storage. Removing cluster code
simplifies every affected function substantially.

### 1.2 MPIO Support Removed

**Scope:** Three cmdlets and one utility function removed entirely.

**What was removed:**
- `Enable-StorageSpacesMpioSupport`
- `Disable-StorageSpacesMpioSupport`
- `Get-StorageSpacesMpioConfiguration`
- `CheckForServerSKU` (utility function — had zero remaining callers after
  MPIO removal; its only purpose was the Windows Server SKU check required
  by the MPIO functions)
- 5 MPIO-only string table entries
- 3 `Export-ModuleMember` lines

**Rationale:** MPIO is only relevant in SAS/clustered multipath environments,
which the author no longer manages.

---

## 2. Bug Fixes

### 2.1 `New-SpacesPool` — `$DisksToUse` Uninitialized
**Problem:** `$DisksToUse` was accumulated with `+=` in the PROCESS block but
never initialized. Uninitialized `+= ` on an array produces undefined behavior.
**Fix:** Added `BEGIN { $DisksToUse = @() }` block.

### 2.2 `New-SpacesPool` — `$NumberOfHotsparesToUse` No Default Value
**Problem:** Parameter had no default. When omitted, value was `$null`, causing
`if ($NumberOfHotsparesToUse -eq 0)` to be `$false`, so the hotspare branch was
always taken even when no hotspares were requested.
**Fix:** Added `= 0` default to parameter declaration.

### 2.3 `New-SpacesVolume` — `$Size` Typed as `[String]` with `[ValidateRange]`
**Problem:** `[ValidateRange]` on a `[String]` parameter does not function as
intended — range validation requires a numeric type.
**Fix:** Changed type from `[System.String]` to `[System.UInt64]`.

### 2.4 `Resize-SpacesVolume` — `$NewSize` Typed as `[String]` with `[ValidateRange]`
**Problem:** Same issue as 2.3.
**Fix:** Changed type from `[System.String]` to `[System.UInt64]`.

### 2.5 `New-SpacesVolume` — `SupportsShouldProcess` Declared but Not Implemented
**Problem:** `SupportsShouldProcess=$true` and `ConfirmImpact='High'` were
declared, but no `$PSCmdlet.ShouldProcess()` call existed. `-WhatIf` and
`-Confirm` had no effect on actual disk operations.
**Fix:** Added `if (-not $PSCmdlet.ShouldProcess(...)) { return }` guard before
the provisioning try block.

### 2.6 `New-SpacesVolume` — `Invoke-Expression` Used to Build Cmdlet Calls
**Problem:** `New-VirtualDisk` and `Format-Volume` were called via string
concatenation and `Invoke-Expression`. This is fragile, undebuggable, and a
potential injection risk. The `ClusterSize` parameter (e.g. `'4KB'`) relied on
`Invoke-Expression` evaluating the KB literal.
**Fix:** Replaced with splatting (`@params`). `ClusterSize` string values
converted to bytes via `[int]($ClusterSize -replace 'KB','') * 1KB`.

### 2.7 `New-SpacesVolume` — Drive Letter Check Unreliable on `[System.Char]`
**Problem:** `![String]::IsNullOrEmpty($DriveLetterToUse)` does not reliably
detect an unset `[System.Char]` parameter (unset char = `[char]0`, not null).
**Fix:** Replaced with `$PSBoundParameters.ContainsKey('DriveLetterToUse')`.

### 2.8 `New-SpacesVolume` — Hardcoded `Start-Sleep` Delays
**Problem:** `Start-Sleep -Seconds 10` and `Start-Sleep -Seconds 5` were used
to wait for disk/partition availability after creation. These are race condition
workarounds — too slow on fast hardware, potentially too fast on slow storage.
**Fix:** Replaced with polling loops (`while ($null -eq $Disk -and $Retries -lt 30)`)
with 2-second sleep intervals and a maximum retry count.

### 2.9 `Get-AvailableDriveLetter` — Returns Unsorted Variable
**Problem:** `Sort-Object` result was assigned to `$AvailableDriveLetters` but
both `return` statements referenced the unsorted `$TempDriveLetters`. The sort
was computed and immediately discarded.
**Fix:** Return statements now reference `$AvailableDriveLetters`.

### 2.10 `Get-SpacesConfiguration` — Dead Variables
**Problem:** `$Allocated`, `$Total`, `$PoolName`, and `$PoolHealth` were
assigned values but never referenced anywhere in the function.
**Fix:** All four removed.

### 2.11 `Get-SpacesPool` — Post-Filter Instead of Parameter
**Problem:** When a name was provided, all pools were fetched and then filtered
with `Where-Object`. `Get-StoragePool` accepts `-FriendlyName` directly.
**Fix:** Pass `-FriendlyName $StoragePoolFriendlyName` directly to cmdlet.

### 2.12 `Repair-SpacesConfiguration` — Integer Counts Compared to String "0"
**Problem:** `$NumberRepairablePools -eq "0"` and similar comparisons used
string `"0"` instead of integer `0`. PowerShell coerces this but it is
misleading and a latent type-mismatch risk.
**Fix:** All such comparisons changed to use integer `0`.

### 2.13 `New-StorageSpacesEventLog` — `Write-Warning` Drops Arguments
**Problem:** `Write-Warning "text" $Variable "more text"` passes multiple
positional arguments to `Write-Warning`, which only accepts one. The variable
value and second string were silently dropped from the warning message.
**Fix:** Combined into single interpolated string:
`Write-Warning "text $Variable more text"`.

### 2.14 `New-StorageSpacesEventLog` — `-ErrorAction` Misplaced
**Problem:** `-ErrorAction SilentlyContinue` was on the `Where-Object` pipe
filter rather than on `Get-EventLog`, so errors from `Get-EventLog` itself
were not suppressed.
**Fix:** Moved `-ErrorAction SilentlyContinue` to the correct cmdlet.
(Note: `Get-EventLog` also replaced with `Get-WinEvent` — see §3.)

---

## 3. Deprecated API Replacements

| Old Call | Replacement | Reason |
|----------|-------------|--------|
| `gwmi Win32_OperatingSystem` | `Get-CimInstance Win32_OperatingSystem` | WMI cmdlets absent from PS 7+ |
| `gwmi Win32_ComputerSystem` | `Get-CimInstance Win32_ComputerSystem` | Same |
| `Get-WmiObject Win32_MappedLogicalDisk` | `Get-CimInstance Win32_MappedLogicalDisk` | Same |
| `Get-EventLog` | `Get-WinEvent -ListLog` | Deprecated PS 6+, absent PS 7+ non-Windows |
| `Register-ScheduledJob` | `Register-ScheduledTask` | PSScheduledJob module; ScheduledTasks is preferred |
| `New-JobTrigger` | `New-ScheduledTaskTrigger` | Same |
| `Unregister-ScheduledJob` | `Unregister-ScheduledTask` | Same |
| `Get-ScheduledJob` | `Get-ScheduledTask` | Same |
| `FT` alias | `Format-Table` | Aliases inappropriate in module code |
| `%` alias | `ForEach-Object` | Same |
| `?` alias | `Where-Object` | Same |

**Note on `New-EventLog` / `Remove-EventLog`:** These remain. They are
deprecated in PS 6+ but available on Windows in both PS 5.1 and PS 7+ via the
compatibility layer. Since this module is Windows-only this is acceptable for
now. Future replacement: `[System.Diagnostics.EventLog]::CreateEventSource()`
and `[System.Diagnostics.EventLog]::Delete()`.

---

## 4. Code Quality Changes

### 4.1 `[PSCustomObject]` Refactor
All `New-Object Object` + repeated `Add-Member -MemberType NoteProperty` chains
replaced with `[PSCustomObject]@{}` literals. Affected functions:
- `Get-SpacesVolume` (ScriptToExecute block)
- `Get-SpacesConfiguration` (pool summary output object)
- `Test-SpacesConfiguration` (pool, space, and disk health objects)
- `Get-SpacesPoolPhysicalDiskHWCounter` (reliability counter object)

Note: `Get-SpacesVolume` still uses `Add-Member` after the PSCustomObject is
returned from the script block, to append pool/space metadata that is only
available in the outer scope. This is intentional.

### 4.2 Trailing Semicolons Removed
All statement-terminating semicolons removed throughout. PowerShell does not
require them and they add visual noise.

### 4.3 Casing Standardized
- `function` keyword: standardized to lowercase throughout
- `$True`/`$False`/`$Null`: standardized to `$true`/`$false`/`$null`

### 4.4 `$null` Comparison Order
Updated prominent comparisons to left-side null form (`$null -eq $var`) in
revised code paths.

### 4.5 `Export-ModuleMember` Consolidated
17 individual `Export-ModuleMember` calls (one per function) replaced with a
single `Export-ModuleMember -Function @(...)` call listing all 15 public
cmdlets. Internal utility function `Get-PhysicalBackingDisksForSpace` is
intentionally absent.

### 4.6 Column Count Calculation Simplified
`New-SpacesVolume` column calculation for Mirror and Parity cases simplified
using `[Math]::Floor` and `[Math]::Min` respectively.

### 4.7 Script Block Invocation
`Get-SpacesVolume` and `Resize-SpacesVolume` both used `Invoke-Command -ScriptBlock`
for local execution. Replaced with direct script block invocation (`& $ScriptToExecute`)
which is more idiomatic for local calls and avoids unnecessary overhead.

---

## 5. String Table Changes

`$SCStringTable` reduced from 47 entries to 20.

### Removed — Cluster-only (8)
`RSDNotObtained`, `NullPoolOwnerInfo`, `OnNodeNull`, `ProvisioningTypeClustered`,
`RemoteNotEnabled`, `EnableRemote`, `ResizeSpaceRemotely`, `RSRFinished`

### Removed — MPIO-only (5)
`ServerMPIORequired`, `ServerRequired`, `InstallMPIO`, `EnableAutoClaiming`,
`SetRoundRobin`

### Removed — Never referenced anywhere (11)
`VirtualDiskNotNull`, `NotObtainNodeInfo`, `NoDiskOnSpace`, `NoVolumeOnDisk`,
`NullCSVInfo`, `NoWDInSpace`, `VDOnePartition`, `VDResized`, `MaxPartitionSize`,
`PartitionResized`, `ClusterSwitch`

These 11 were stubbed into the table in the original authoring but the code
that would have used them was either never written or was later hardcoded inline.

### Removed — Replaced with inline message (1)
`LocallyNull` — replaced with descriptive inline error in `Get-SpacesVolume`.

### Typos corrected in remaining entries
- `Physial Disks` → `Physical Disks` (AllHealthy)
- `Retreiving` → `Retrieving` (RetrieveObject, RetrieveCreatedObject keys renamed)

---

## 6. Comment Changes

### 6.1 Stale Comments Removed
Approximately 30 cluster/MPIO-referencing comments removed from:
`Get-SpacesVolume`, `New-SpacesVolume`, `Resize-SpacesVolume`,
`Get-SpacesConfiguration`, `Test-SpacesConfiguration`

### 6.2 Inaccurate Comments Corrected
| Location | Old Text | New Text |
|----------|----------|----------|
| `New-SpacesPool` | "in the clustered pool" | "in the storage pool" |
| `New-SpacesPool` | Said "locate subsystem object" but code gets physical disks | Corrected to describe actual behavior |
| `Resize-SpacesVolume` | "confine to the criteria" | "matching the criteria" |
| `Resize-SpacesVolume` | "only allows to expand the size" | "only supports expanding; shrinking is not permitted" |
| `Test-SpacesConfiguration` | "avoid re-query to the API" | "Resolve pool object from whichever parameter set was provided" |
| `Test-SpacesConfiguration` | "$Passthru should be true if we reach here" | Explicit flow-through description |
| `Repair-SpacesConfiguration` | "which are not clustered, and not primordial" | "non-primordial" |
| `Repair-SpacesConfiguration` | "across all non-clustered pools" | "across all pools" |
| `Repair-SpacesConfiguration` | "not still performing repairs" | Removed — code only checks HealthStatus |
| `Remove-StorageSpacesEventLog` | "check if uninstall switch is toggled" | "Unregister the scheduled task and remove the event log" |

### 6.3 Typos Fixed
`proggress`, `addtional`, `Definte`, `their are`, `detailsbefore proceeeding`,
`Prouduct`, missing `# ` spacing on several inline comments.

### 6.4 New Comments Added
| Location | Comment Added |
|----------|---------------|
| `$SCStringTable` block | Explains `Data {}` wrapper purpose |
| `Get-PhysicalBackingDisksForSpace` | Purpose description (had none) |
| `New-SpacesPool` param block | Explains `ByDiskArray` vs `ByLocalStorage` modes |
| `New-SpacesPool` BEGIN block | Explains accumulator initialization |
| `New-SpacesVolume` | Parity 8-column engine cap |
| `New-SpacesVolume` | Why `$ErrorActionPreference = 'Stop'` inside try block |
| `New-SpacesVolume` | Polling loop approach for disk availability |
| `Get-SpacesVolume` `$ScriptToExecute` | Why it remains a script block |
| `Get-SpacesConfiguration` | Multiple-object pipeline output behavior |
| `Test-SpacesConfiguration` `-Passthru` | Dual return-type behavior (bool vs objects) |
| `Get-AvailableDriveLetter` `Compare-Object` | Explains `SideIndicator '<='` logic |
| `Export-ModuleMember` section | Notes `Get-PhysicalBackingDisksForSpace` not exported |
