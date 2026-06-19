# StorageSpaces Module — Project Context

This file captures the full state of the StorageSpaces PowerShell module revision
project so work can be resumed on another machine with Claude Code.

---

## Repository

**Local path:** `C:\Github\StorageSpaces`
**Remote:** https://github.com/BruceLangworthy/StorageSpaces.git

## Files in This Repository

| File | Description |
|------|-------------|
| `StorageSpaces.psm1` | **Original, unmodified** module — preserved as reference |
| `StorageSpaces_Revised.psm1` | **Revised module** — all changes applied, ready for review |
| `StorageSpaces.psd1` | Module manifest — not yet modified |
| `Notification_Script.ps1` | Event log notification script — not yet modified |
| `README.md` | Fully rewritten documentation |
| `CONTEXT.md` | This file |
| `DECISIONS.md` | Full record of every change made and why |
| `CLAUDE.md` | Instructions for Claude Code to resume work |

## Project Status

The revision is **complete and ready for final review**. All changes have been
applied to `StorageSpaces_Revised.psm1`. The original `StorageSpaces.psm1` has
not been touched.

When satisfied with the revision, replace the original:
```powershell
Copy-Item StorageSpaces_Revised.psm1 StorageSpaces.psm1
```

## What Was Done

A comprehensive revision of the module covering:

1. **Cluster support removed** — the module previously supported both local and
   Failover Cluster storage management. All cluster code has been removed; the
   module is now local-only.

2. **MPIO support removed** — three MPIO cmdlets and the `CheckForServerSKU`
   utility function (which had no remaining callers) were removed.

3. **Bug fixes** — ten bugs identified and fixed across multiple functions.

4. **Deprecated APIs updated** — all `gwmi`/`Get-WmiObject` replaced with
   `Get-CimInstance`; scheduled job cmdlets replaced with scheduled task cmdlets;
   `Get-EventLog` replaced with `Get-WinEvent`.

5. **Code quality improvements** — `[PSCustomObject]` refactor, trailing
   semicolons removed, aliases replaced, `Export-ModuleMember` consolidated.

6. **String table cleaned** — reduced from 47 entries to 20; 27 entries removed
   (cluster-only, MPIO-only, and entries that were never referenced).

7. **Comments overhauled** — stale/inaccurate comments removed or corrected;
   new explanatory comments added throughout; typos fixed.

8. **README.md rewritten** — updated for local-only scope, current Windows
   versions, real output examples, current Microsoft Learn links.

## Line Count Summary

| | Lines |
|---|---|
| Original `StorageSpaces.psm1` | 1,835 |
| Revised `StorageSpaces_Revised.psm1` | 1,242 |
| Reduction | 593 lines (32%) |

## Remaining Work / Known Items

- `StorageSpaces.psd1` — the module manifest has not been updated. It should be
  reviewed to remove the three exported MPIO function names
  and update the version number, supported PS version, and description.

- `Notification_Script.ps1` — not reviewed in this session. It powers
  `New-StorageSpacesEventLog` and may reference deprecated APIs or have its own
  issues worth reviewing separately.

- The `#.ExternalHelp StorageSpaces.psm1-help.xml` directive on every public
  function references an external help XML file. This file was not present in
  the repository and has not been created. Either the help XML should be created,
  or the directives should be replaced with inline comment-based help.

- `New-EventLog` / `Remove-EventLog` are still used in `New-StorageSpacesEventLog`
  and `Remove-StorageSpacesEventLog`. They work on Windows PS 5.1 and PS 7+ via
  the compatibility layer but are technically deprecated. Future replacement path
  is `[System.Diagnostics.EventLog]::CreateEventSource()` / `::Delete()`.
