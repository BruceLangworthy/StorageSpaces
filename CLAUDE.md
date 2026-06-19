# CLAUDE.md — Instructions for Claude Code

This file tells Claude Code everything needed to resume work on this project.
Read `CONTEXT.md` and `DECISIONS.md` for full background before making any changes.

---

## Project Summary

This is a PowerShell module (`StorageSpaces.psm1`) for managing Windows Storage
Spaces via the Storage Management API (SMAPI). A comprehensive revision has been
completed and lives in `StorageSpaces_Revised.psm1`. The original is preserved
untouched for reference.

**The module is local-storage only.** Cluster and MPIO support have been
intentionally removed. Do not add them back.

---

## Current State

- `StorageSpaces_Revised.psm1` — the revised module, ready for final review
- `StorageSpaces.psm1` — original, unmodified, do not edit
- `README.md` — fully updated documentation
- `CONTEXT.md` — project overview and remaining work items
- `DECISIONS.md` — detailed log of every change and rationale

---

## Exported Public Cmdlets (15)

These are the only functions exported by the module. Do not add or remove
exports without updating this list.

```
Get-SpacesProvider
Get-SpacesSubsystem
Get-SpacesPhysicalDisk
New-SpacesPool
Get-SpacesVolume
New-SpacesVolume
Get-SpacesPool
Resize-SpacesVolume
Get-SpacesConfiguration
Test-SpacesConfiguration
Repair-SpacesConfiguration
Get-AvailableDriveLetter
Get-SpacesPoolPhysicalDiskHWCounter
New-StorageSpacesEventLog
Remove-StorageSpacesEventLog
```

## Internal Utility Functions (not exported)

```
Get-PhysicalBackingDisksForSpace
```

---

## Known Remaining Work Items

These items were identified during the review session but not yet actioned.
They are the most likely starting points for the next session.

### High Priority

**1. Update `StorageSpaces.psd1`**
The module manifest still references the three removed MPIO function names in
its `FunctionsToExport` list and has not had its version number, description,
or PowerShell version requirement updated.

Specifically update:
- `FunctionsToExport` — remove `Enable-StorageSpacesMpioSupport`,
  `Disable-StorageSpacesMpioSupport`, `Get-StorageSpacesMpioConfiguration`
- `ModuleVersion` — increment to reflect this revision
- `Description` — update to reflect local-only scope
- `PowerShellVersion` — should be `'5.1'` minimum
- `CompatiblePSEditions` — should be `@('Desktop', 'Core')` with Windows-only note

**2. Review `Notification_Script.ps1`**
This script powers `New-StorageSpacesEventLog` and was not reviewed in the
original session. It likely contains:
- `gwmi`/`Get-WmiObject` calls that need replacing with `Get-CimInstance`
- Potentially deprecated Storage cmdlets
- Its own comment and style issues

Apply the same standards as the main module revision.

### Medium Priority

**3. Create or remove external help references**
Every public function has `#.ExternalHelp StorageSpaces.psm1-help.xml` but the
help XML file does not exist in the repository.

Two options — pick one:
- **Create the XML** using `New-ExternalHelp` (from the `platyPS` module) by
  first adding full comment-based help to each function, then generating the XML.
- **Replace the directives** with inline comment-based help (`.SYNOPSIS`,
  `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE` blocks) directly in the source.

The inline approach is simpler and keeps everything in one file.

**4. Promote `Get-SpacesVolume` metadata adds to `[PSCustomObject]`**
After the script block returns its `[PSCustomObject]`, six properties are
appended via `Add-Member`. These could be folded into the object construction
inside the script block by passing the pool object as an additional parameter,
eliminating the `Add-Member` calls entirely.

### Low Priority

**5. Replace `New-EventLog` / `Remove-EventLog`**
These are deprecated in PS 6+ but work on Windows. When ready to fully
modernize, the replacement is:
```powershell
# Create
[System.Diagnostics.EventLog]::CreateEventSource($LogName, $LogName)
# Remove
[System.Diagnostics.EventLog]::Delete($LogName)
```

**6. Add `-SkipCacheUpdate` switch to `Test-SpacesConfiguration`**
The function unconditionally calls `Update-StorageProviderCache -DiscoveryLevel Full`
which is the slowest discovery mode. Add an optional switch for callers who know
their cache is current.

**7. Consider consolidating `StorageSpaces_Revised.psm1` → `StorageSpaces.psm1`**
Once the revision is accepted, rename/replace the original. Update `.psd1` at
the same time (see item 1 above).

---

## Coding Standards for This Module

Follow these when making any changes:

- **No cluster or MPIO code** — ever
- **No `gwmi`/`Get-WmiObject`** — use `Get-CimInstance`
- **No aliases** (`%`, `?`, `FT`, etc.) — use full cmdlet names
- **No `Invoke-Expression`** — use splatting for dynamic parameter sets
- **No trailing semicolons** on statement-terminating lines
- **No `New-Object Object` + `Add-Member` chains** — use `[PSCustomObject]@{}`
- **`$true`/`$false`/`$null`** — always lowercase
- **`$null` comparisons** — always left-side: `$null -eq $variable`
- **Function definitions** — lowercase `function` keyword
- **String table** — add new user-facing messages to `$SCStringTable`; do not
  hardcode them inline
- **`SupportsShouldProcess`** — if declared, must include `$PSCmdlet.ShouldProcess()`
  guard around destructive operations
- **Parameter types** — use specific types (`[System.UInt64]`, `[System.Int32]`
  etc.); avoid `[String]` for numeric parameters
- **Polling over sleeping** — use retry loops rather than hardcoded `Start-Sleep`
  when waiting for async operations

---

## Testing

This module requires Windows with Storage Spaces capable hardware. There is no
automated test suite. Manual testing requires:
- At least 3 physical disks available for pool creation
- An elevated PowerShell session
- Windows 10/11 or Windows Server 2016+

Before committing changes, at minimum verify:
```powershell
Import-Module .\StorageSpaces_Revised.psm1
Get-Command -Module StorageSpaces_Revised  # verify all 15 cmdlets present
Get-Help New-SpacesPool                     # verify help loads
Get-SpacesProvider                          # verify basic connectivity
```
