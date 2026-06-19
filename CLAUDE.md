# CLAUDE.md — Instructions for Claude Code

This file tells Claude Code everything needed to resume work on this project.
Read `CONTEXT.md` and `DECISIONS.md` for full background before making any changes.

---

## Project Summary

This is a PowerShell module (`StorageSpaces.psm1`) for managing Windows Storage
Spaces via the Storage Management API (SMAPI). A comprehensive revision has been
completed and is now consolidated directly into `StorageSpaces.psm1` (1,242 lines).
The pre-revision original (1,835 lines) is no longer retained on disk — recover it
from git history if a comparison is needed.

**The module is local-storage only.** Cluster and MPIO support have been
intentionally removed. Do not add them back.

---

## Current State

- `StorageSpaces.psm1` — the revised module (1,242 lines), ready for final review
- `README.md` — fully updated documentation
- `CONTEXT.md` — project overview and remaining work items
- `DECISIONS.md` — detailed log of every change and rationale
- `REVIEW_FINDINGS.md` — 🔎 captured-for-review items (doc review + code scan) and a
  SMAPI modernization assessment. NOT yet actioned; review/prioritize before any work.

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

> **➡️ NEXT UP / TODO:** Item 1 below — update `StorageSpaces.psd1`. This is the
> agreed next task. The `.psd1` uses a wildcard `FunctionsToExport = '*'` (it does
> NOT enumerate any names, so there are no MPIO entries to delete — the wildcard
> just re-exports whatever the `.psm1` defines) and has stale
> version/description/PS-version metadata plus the legacy `ModuleToProcess` key.

### High Priority

**1. Update `StorageSpaces.psd1`**
The module manifest currently sets `FunctionsToExport = '*'` (a wildcard). It does
NOT enumerate any function names, so there are no MPIO names to remove — the
wildcard simply re-exports whatever the `.psm1` defines. The manifest also has
stale metadata and uses the deprecated `ModuleToProcess` key instead of `RootModule`.

Specifically update:
- `FunctionsToExport` — replace the `'*'` wildcard with an explicit array of the
  15 public cmdlets (same names as the module's `Export-ModuleMember` list). This
  declares the public contract in the manifest and guarantees no removed function
  can ever be re-exported. Optionally set `CmdletsToExport`/`VariablesToExport`/
  `AliasesToExport` to `@()`.
- `ModuleVersion` — increment to reflect this revision (e.g. `2.0.0.0`)
- `Description` — update to reflect local-only scope (no cluster / no MPIO)
- `PowerShellVersion` — should be `'5.1'` minimum
- `CompatiblePSEditions` — should be `@('Desktop', 'Core')` with a Windows-only note
- `RootModule` — replace the deprecated `ModuleToProcess` key with
  `RootModule = 'StorageSpaces.psm1'`

**2. Review `Notification_Script.ps1`**
This script powers `New-StorageSpacesEventLog` and was not reviewed in the
original session. It likely contains:
- `gwmi`/`Get-WmiObject` calls that need replacing with `Get-CimInstance`
- Potentially deprecated Storage cmdlets
- Its own comment and style issues

Apply the same standards as the main module revision.

### Medium Priority

**3. Locate (or recreate) the external help file**
Every public function carries a `#.ExternalHelp StorageSpaces.psm1-help.xml`
directive (15 of them), and the README's "Getting Help" section tells users the
help "ships" and to run `Update-Help` — but the XML is not in the working tree.
Because the rest of the package assumes it exists, a copy may already exist
elsewhere.

**TODO — find it first:** search for an existing `StorageSpaces.psm1-help.xml` in
- the `master` branch and earlier git history (`git log --all -- '*help.xml'`),
- the remote, and
- any installed copy under
  `%SystemRoot%\System32\WindowsPowerShell\v1.0\Modules\StorageSpaces\`.

If found, restore it to the repo. Only if it genuinely does not exist anywhere,
pick one:
- **Create the XML** using `New-ExternalHelp` (from the `platyPS` module) by
  first adding full comment-based help to each function, then generating the XML.
- **Replace the directives** with inline comment-based help (`.SYNOPSIS`,
  `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE` blocks) directly in the source.

The inline approach is simpler and keeps everything in one file. (Note: the
README's `Update-Help` instruction stays as-is for now per the project owner.)

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

**7. ~~Consolidate `StorageSpaces_Revised.psm1` → `StorageSpaces.psm1`~~ — DONE**
The revision has already been consolidated into `StorageSpaces.psm1`; the separate
`_Revised` file no longer exists. The `.psd1` still needs updating (see item 1).

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
Import-Module .\StorageSpaces.psm1
Get-Command -Module StorageSpaces  # verify all 15 cmdlets present
Get-Help New-SpacesPool                     # verify help loads
Get-SpacesProvider                          # verify basic connectivity
```
