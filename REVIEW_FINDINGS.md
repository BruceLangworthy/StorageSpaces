# StorageSpaces — Review Findings & SMAPI Modernization Assessment

**Captured:** 2026-06-18
**Status:** 🔎 **FOR REVIEW — do NOT action yet.** These items were identified during a
Microsoft Learn SMAPI documentation review plus a full code scan of `StorageSpaces.psm1`,
`Notification_Script.ps1`, and `StorageSpaces.psd1`. Nothing here has been implemented.
Decide priority/scope before any work begins.

Scope reminder: **the module is local-storage only** (no cluster, no MPIO). Candidates
below are screened against that constraint.

---

## Part A — Findings (problems, deprecations, usability)

### Problems / bugs

**P1 — Event-log feature is broken end-to-end (HIGH).**
`New-StorageSpacesEventLog` and `Notification_Script.ps1` disagree on every shared
identifier, and the script was never updated for the module's move from scheduled *jobs*
to scheduled *tasks*.

| Item | Module (`New-StorageSpacesEventLog`) | Script (`Notification_Script.ps1`) |
|------|--------------------------------------|------------------------------------|
| Log name     | `StorageSpaces Events`                              | `SpaceCommand Events` |
| Event source | `StorageSpaces Events`                              | `SpaceCommand Events` |
| Scheduler    | `Register-ScheduledTask` "StorageSpaces Event Monitor" | `Get-ScheduledJob`/`*-JobTrigger` "SpaceCommand Event Monitor" |

Result: after install, the script writes to a non-existent log and tries to update a
scheduled *job* that was never created (the module now creates a *task*). The script
throws on the first loop iteration (`Notification_Script.ps1:129`). Fixing P1 likely
overlaps with the D1 rewrite — treat them together.

**P2 — `break` used outside a loop (MEDIUM).** In a function with no enclosing loop,
`break` propagates up the call stack and can terminate a *caller's* loop/script. Should
be `return`.
- `New-SpacesPool` END block — `StorageSpaces.psm1:288, 296, 303, 311`
- `Get-SpacesVolume` — `StorageSpaces.psm1:405`
- `Resize-SpacesVolume` — `StorageSpaces.psm1:741, 748`
- `Get-SpacesConfiguration` — `StorageSpaces.psm1:784`

**P3 — `Write-Warning ... -ErrorAction Stop` does nothing (MEDIUM).**
`StorageSpaces.psm1:1016` (`Repair-SpacesConfiguration`). `-ErrorAction` does not apply
to warnings, so the intended "no active repair jobs — exiting" early-out never fires;
execution falls into the job-monitoring loop regardless. Use `return` (or
`Write-Error -ErrorAction Stop`).

### Deprecated items (confirmed removed in PowerShell 7+)

Reference: [PowerShell 5.1 vs 7.x — cmdlets removed](https://learn.microsoft.com/powershell/scripting/whats-new/differences-from-windows-powershell#cmdlets-removed-from-powershell)

**D1 — `Notification_Script.ps1` is full of removed/legacy cmdlets (HIGH).**
- `Register-WmiEvent` — removed in PS7. Replacement: **`Register-CimIndicationEvent`**
  (same `root\microsoft\windows\storage` namespace, same `MSFT_Storage*Event` classes).
  See [Register-CimIndicationEvent](https://learn.microsoft.com/powershell/module/cimcmdlets/register-cimindicationevent)
  and the storage-event example in
  [Storage QoS — monitor health](https://learn.microsoft.com/windows-server/storage/storage-qos/storage-qos-overview#monitor-health-using-storage-qos).
- `Write-EventLog` — removed in PS7.
- `Get-ScheduledJob` / `Get-JobTrigger` / `Set-JobTrigger` — old PSScheduledJob family the
  main module already migrated away from (`Register-ScheduledTask` etc.).
- Aliases `?` / `%`, `sleep`, post-filtering (`Get-StoragePool | ? {...}`), and an
  unapproved-verb function (`Create-Message`). Apply the same standards as the main module.

**D2 — Event-log feature is effectively Windows-PowerShell-5.1-only (MEDIUM).**
`New-EventLog`/`Remove-EventLog` (already TODO #5 in CLAUDE.md) **plus** the script's
`Write-EventLog` are all gone in PS7. The module header advertises PS 5.1 + Core compat,
but the notification feature only works under 5.1. State this limitation explicitly (or
move to `[System.Diagnostics.EventLog]` + `Register-CimIndicationEvent`, which work on both).

### Usability improvements

**U1 — `Get-SpacesPhysicalDisk -BusType` ValidateSet missing `NVMe` (MEDIUM).**
`StorageSpaces.psm1:207` allows only `SAS/iSCSI/SATA/USB`. NVMe is a first-class Storage
Spaces bus type and very common now; users can't filter for their actual disks. Consider
adding `NVMe` (and `SCM`). Valid bus-type names per
[STORAGE_BUS_TYPE](https://learn.microsoft.com/windows-hardware/drivers/ddi/ntddstor/ne-ntddstor-storage_bus_type).

**U2 — `New-SpacesVolume` can be drastically simplified with `New-Volume` (MEDIUM/HIGH).**
`New-Volume` now creates the virtual disk, initializes, partitions, formats, and assigns a
drive letter in a single call — eliminating both polling loops and their race conditions
(`StorageSpaces.psm1:564-631`).
See [New-Volume](https://learn.microsoft.com/powershell/module/storage/new-volume).
Caveat: `New-Volume`'s column/interleave control is thinner than `New-VirtualDisk`, so the
`-MaximumColumnCount` / `-InterleaveBytes` paths may still need the manual route. Evaluate;
not a blind swap.

**U3 — Hardcoded install path in `New-StorageSpacesEventLog` (MEDIUM).**
`StorageSpaces.psm1:1156` hardcodes
`C:\Windows\System32\WindowsPowerShell\v1.0\Modules\StorageSpaces\Notification_Script.ps1`.
Breaks for any non-default install (user module path, PS7 path, PSGallery). Derive from
`$PSScriptRoot`.

**U4 — `Repair-SpacesConfiguration` also calls unscoped `Update-StorageProviderCache -DiscoveryLevel Full` (LOW).**
`StorageSpaces.psm1:1046`. Docs warn Full discovery without scoping is "extremely time
intensive." Same concern as existing TODO #6 (which only covers `Test-SpacesConfiguration`);
scope to the Storage Spaces subsystem.
See [Update-StorageProviderCache](https://learn.microsoft.com/powershell/module/storage/update-storageprovidercache).

**U5 — Minor consistency / robustness (LOW).**
- Mapped-drive detection differs between functions: `Get-AvailableDriveLetter` reads
  `HKCU:\Network` (`StorageSpaces.psm1:1079`) while `New-SpacesVolume` uses
  `Win32_MappedLogicalDisk` (`StorageSpaces.psm1:500`). HKCU is per-user and won't reflect
  the elevated/SYSTEM context reliably. Pick one approach.
- `ThinProvisioningAlertThresholds[0]` indexing can throw if the array is empty
  (`StorageSpaces.psm1:798`); `Get-SpacesVolume` uses the whole array for the same concept
  (`StorageSpaces.psm1:430`) — inconsistent.

---

## Part B — New SMAPI cmdlets worth considering

Assessment of Storage-module capabilities that postdate the original 2011/2012-era authoring
and align with this module's feature set (pool/volume lifecycle, health, monitoring). Each
is screened for **local (stand-alone) support** since the module is local-only.

### Strong fit

**B1 — Storage Tiers** — `New-StorageTier`, `Get-StorageTier`, `Set-StorageTier`
*(Server 2012 R2+, stand-alone supported.)*
Group physical disks by media type (SSD/HDD) into tiers and build tiered virtual disks.
`New-Volume` and `New-VirtualDisk` accept `-StorageTiers` / `-StorageTierSizes`.
**Alignment:** extends `New-SpacesVolume` (tiered space creation) and warrants a read-only
`Get-SpacesTier`. High value for mixed SSD+HDD boxes — the most common modern home/SMB setup.
[Get-StorageTier](https://learn.microsoft.com/powershell/module/storage/get-storagetier)

**B2 — `Debug-StorageSubSystem`** — plain-language fault diagnosis + recommended solutions
*(Server 2016+, confirmed stand-alone: `Get-StorageSubsystem | Debug-StorageSubSystem`.)*
**Alignment:** directly complements/strengthens `Test-SpacesConfiguration` — instead of just
returning `$true/$false` + component objects, surface MS's own fault descriptions and
remediation. Could back a new switch on `Test-SpacesConfiguration` or a `Get-SpacesFault`.
[Debug-StorageSubSystem](https://learn.microsoft.com/powershell/module/storage/debug-storagesubsystem)
*(Note: the Health Service `Get-HealthFault` is S2D/cluster-only — out of scope.)*

**B3 — Pool expansion: `Add-PhysicalDisk` / `Remove-PhysicalDisk`**
The module can *create* a pool (with hotspares) but cannot grow/shrink one afterward.
**Alignment:** natural completeness gap — a `Add-SpacesPhysicalDisk` (and removal) closes the
pool lifecycle. Pairs with B4.

**B4 — `Optimize-StoragePool`** — rebalance allocations onto newly added disks
*(Server 2016+, stand-alone supported.)*
**Alignment:** the logical follow-up to B3 ("I added disks — now spread data across them").
I/O intensive → gate behind `SupportsShouldProcess`.
[Optimize-StoragePool](https://learn.microsoft.com/powershell/module/storage/optimize-storagepool)

### Worth considering

**B5 — Disk-replacement workflow:** `Set-PhysicalDisk -Usage Retired` → `Repair-VirtualDisk`
→ `Remove-PhysicalDisk`.
**Alignment:** completes the `Repair-SpacesConfiguration` story into a real "replace a failing
disk" path (retire the bad disk, rebuild onto a spare/new disk, remove the old one).

**B6 — Teardown (CRUD completeness):** `Remove-VirtualDisk` / `Remove-StoragePool`.
The module creates spaces and pools but provides no way to destroy them. `Remove-SpacesVolume`
/ `Remove-SpacesPool` (with `SupportsShouldProcess` + `ConfirmImpact='High'`) would round out
the lifecycle.

**B7 — Sizing helpers:** `Get-StoragePoolSupportedSize` / `Get-VirtualDiskSupportedSize`.
**Alignment:** `New-SpacesVolume` / `Resize-SpacesVolume` currently use a hardcoded
`[ValidateRange(1073741824, 69268158808064)]` magic max (`StorageSpaces.psm1:455, 677`).
Querying the actual supported size would remove the magic number and tell users the real
ceiling for their pool/resiliency choice.

### Likely out of scope (note and skip)

- **Storage Bus Cache** (`Enable-StorageBusCache`, Server 2022) — primarily S2D/server.
- **Health Service / `Get-HealthFault`, Get-StorageHealthReport/Setting/Action** — cluster/S2D.
- **Fault domains / `Enable-StorageMaintenanceMode`, Get-StorageFaultDomain** — mostly
  clustered/S2D semantics. (Maintenance mode *can* apply locally but is rarely useful on a
  single box.)
