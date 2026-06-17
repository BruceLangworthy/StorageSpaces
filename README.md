# StorageSpaces PowerShell Module

**Author:** Bruce Langworthy  
**Supported on:** Windows 10, Windows 11, Windows Server 2016, 2019, 2022

A PowerShell module that provides streamlined management of Windows Storage Spaces. It wraps the built-in Storage Management API (SMAPI) into task-oriented cmdlets designed to complete common workflows — creating pools, provisioning volumes, checking health, and monitoring disk reliability — with far fewer steps than the native Storage module requires.

> **Note:** This module manages **local storage only**. Cluster and MPIO support have been removed from this version.

---

## Why use this module?

The built-in `Storage` module gives you full access to the Storage Management API, but end-to-end workflows require chaining multiple cmdlets and understanding the API's object model. For example, creating a mirrored Storage Space and making it ready to use requires this with the native Storage module:

```powershell
# Create the virtual disk
New-VirtualDisk -FriendlyName MirrorTest -StoragePoolFriendlyName Internal `
    -ResiliencySettingName Mirror -ProvisioningType Thin -Size 20GB

# Find the disk it created
$disk = Get-VirtualDisk -FriendlyName MirrorTest | Get-Disk

# Initialize, partition, and format
Initialize-Disk -Number $disk.Number
New-Partition -DiskNumber $disk.Number -UseMaximumSize -AssignDriveLetter
Format-Volume -DriveLetter E -NewFileSystemLabel MirrorTest
```

With this module, the same result is a single command:

```powershell
New-SpacesVolume -StoragePoolFriendlyName Internal -SpaceFriendlyName MirrorTest `
    -Size 20GB -ResiliencyType Mirror -ProvisioningType Thin -DriveLetterToUse E
```

---

## Requirements

- Windows 10, Windows 11, or Windows Server 2016 or later
- Windows PowerShell 5.1 or PowerShell 7+ (Windows only)
- An elevated (Administrator) PowerShell session
- Physical disks compatible with Windows Storage Spaces (SAS, SATA, USB, or NVMe)

---

## Installation

1. Create the module directory if it does not already exist:
   ```powershell
   New-Item -ItemType Directory -Force `
       -Path "$env:SystemRoot\System32\WindowsPowerShell\v1.0\Modules\StorageSpaces"
   ```

2. Copy the following files into that directory:
   - `StorageSpaces.psm1`
   - `StorageSpaces.psd1`
   - `Notification_Script.ps1`

3. Unblock the files so PowerShell will load them:
   ```powershell
   Get-ChildItem "$env:SystemRoot\System32\WindowsPowerShell\v1.0\Modules\StorageSpaces" |
       Unblock-File
   ```

4. If you intend to use `New-StorageSpacesEventLog`, set the execution policy to `RemoteSigned`:
   ```powershell
   Set-ExecutionPolicy RemoteSigned
   ```

5. Open an elevated PowerShell window and import the module:
   ```powershell
   Import-Module StorageSpaces
   ```

6. Confirm everything loaded correctly:
   ```powershell
   Get-Command -Module StorageSpaces
   ```

---

## Getting Help

Each cmdlet ships with external help. Run `Update-Help` once to download it, then use `Get-Help`:

```powershell
# Download help (use -Force to refresh after 24 hours)
Update-Help

# See examples for a specific cmdlet
Get-Help New-SpacesPool -Examples

# Full parameter reference
Get-Help New-SpacesVolume -Full
```

---

## Cmdlet Reference

| Cmdlet | Description |
|--------|-------------|
| `Get-SpacesPhysicalDisk` | Lists physical disks visible to Storage Spaces. Use `-OnlyListAvailable` to show only disks eligible for pool creation, and `-BusType` to filter by interface type (SAS, SATA, USB, iSCSI). |
| `New-SpacesPool` | Creates a new storage pool. Pass specific disk objects via the pipeline, or provide a count and let the cmdlet auto-select available disks. |
| `Get-SpacesPool` | Returns Storage Spaces pool objects. Pools created by other storage providers are not shown. |
| `New-SpacesVolume` | Creates a Storage Space from an existing pool, initializes the disk, creates a partition, and formats the volume — all in one step. |
| `Get-SpacesVolume` | Returns detailed information about a Storage Space, including health status, drive letter, volume size, and backing physical disk names. |
| `Resize-SpacesVolume` | Expands a Storage Space and its filesystem. Shrinking is not supported. |
| `Get-SpacesConfiguration` | Returns a full configuration report for a pool, including all Storage Spaces and their associated volumes. Useful for baseline tracking and disaster recovery documentation. |
| `Test-SpacesConfiguration` | Checks the health of a pool and all associated Storage Spaces and physical disks. Returns `$true` if everything is healthy, or `$false` / detailed objects if not. |
| `Repair-SpacesConfiguration` | Repairs configuration issues such as read-only pools, manually attached spaces, and degraded spaces following a drive failure or replacement. |
| `Get-SpacesProvider` | Returns the Storage Spaces storage provider object for use with other SMAPI cmdlets. |
| `Get-SpacesSubsystem` | Returns the Storage Spaces subsystem object for use with other SMAPI cmdlets. |
| `Get-AvailableDriveLetter` | Returns a sorted list of all unassigned drive letters (C–Z). Use `-ReturnFirstLetterOnly` to get just the next available letter. |
| `Get-SpacesPoolPhysicalDiskHWCounter` | Reports hardware reliability counters — temperature, power-on hours, read/write error totals, and latency peaks — for all physical disks in a pool. |
| `New-StorageSpacesEventLog` | Installs a scheduled task and a custom Windows Event Log that monitors and records changes to Storage Spaces state. |
| `Remove-StorageSpacesEventLog` | Unregisters the monitoring task and removes the event log created by `New-StorageSpacesEventLog`. |

---

## Examples

### Create a storage pool and provision a volume

```powershell
# Create a pool using 4 automatically selected available disks
New-SpacesPool -FriendlyName SpacesPool -NumberOfPhysicalDisksToUse 4

# Create a thinly provisioned mirrored space, then partition and format it
New-SpacesVolume -StoragePoolFriendlyName SpacesPool `
    -SpaceFriendlyName MyData `
    -Size 500GB `
    -ResiliencyType Mirror `
    -ProvisioningType Thin
```

### Create a pool from specific disks with hotspares

```powershell
# Pipe specific available disks in, reserving the last 2 as hotspares
Get-SpacesPhysicalDisk -OnlyListAvailable |
    New-SpacesPool -FriendlyName SpacesPool -NumberOfHotsparesToUse 2
```

### Assign a specific drive letter

```powershell
# Get the next available letter, then use it when creating the volume
$Letter = Get-AvailableDriveLetter -ReturnFirstLetterOnly

New-SpacesVolume -StoragePoolFriendlyName SpacesPool `
    -SpaceFriendlyName MyData `
    -Size 1TB `
    -ResiliencyType Parity `
    -ProvisioningType Fixed `
    -DriveLetterToUse $Letter
```

### View space and volume details

```powershell
# All spaces across all local pools
Get-SpacesVolume

# A specific space
Get-SpacesVolume -SpaceFriendlyName USB-Backup
```

Example output:

```
OperationalStatus         : OK
HealthStatus              : Healthy
DiskUniqueID              : D3568BF49705E211BE6D002522F8BB58
DriveLetter               : Z
VolumeSize                : 4947667034112
SizeRemaining             : 1341698236416
VolumeObjectID            : \\?\Volume{f48b56da-0597-11e2-be6d-002522f8bb58}\
FileSystem                : NTFS
BackingPhysicalDisks      : {WD-Drive-Jan2012, WD-Drive-Jan2013, WD-Drive-Jan2013-B, WD-Drive-Jan2013-C}
PoolFriendlyName          : Backup
SpaceFriendlyName         : USB-Backup
StorageSpaceUniqueID      : D3568BF49705E211BE6D002522F8BB58
IsManualAttach            : False
DetachedReason            : None
SpaceUsageAlertPercentage : {70}
```

### Get a full configuration report

```powershell
Get-SpacesConfiguration -StoragePoolFriendlyName Backup
```

Example output:

```
StoragePoolFriendlyName        : Backup
HealthStatus                   : Healthy
IsReadOnly                     : False
ThinProvisionAlertThreshold    : 70 %
StoragePoolFreeGigabytes       : 4442
StoragePoolUsedSpacePercent    : 60.25
StoragePoolFreeSpacePercent    : 39.75
OperationalStatus              : OK
NumberofPhysicalDisksInPool    : 4
NumberofStorageSpacesInPool    : 1
NumberofUnhealthyPhysicalDisks : 0
NumberofUnhealthyStorageSpaces : 0
```

The report continues with a detail object for each Storage Space in the pool. To capture everything:

```powershell
$Report     = @(Get-SpacesConfiguration -StoragePoolFriendlyName Backup)
$PoolSummary = $Report[0]
$SpaceDetails = $Report[1..$Report.Count]
```

This report is useful for:
- **Disaster recovery** — documents pool configuration and all Storage Space details needed to recreate the environment.
- **Configuration monitoring** — track changes such as newly created spaces or shifts in free space.
- **Baseline tracking** — capture the initial state of a deployment for comparison later.

### Check health

```powershell
# Returns $true if everything is healthy
Test-SpacesConfiguration -StoragePoolFriendlyName SpacesPool

# Returns objects describing exactly what is unhealthy
Test-SpacesConfiguration -StoragePoolFriendlyName SpacesPool -Passthru
```

When `-Passthru` is used on an unhealthy pool, you receive separate objects for the pool, each unhealthy space, and each unhealthy physical disk — making it easy to pipe results to further diagnostics or alerting.

### Repair after a drive failure

```powershell
# Reconnects manually attached spaces and requests repair across all pools
Repair-SpacesConfiguration
```

The cmdlet prompts interactively before making any changes to read-only pools or manually attached spaces, then requests repairs and displays a live progress bar while jobs run.

### Expand a volume

```powershell
# Increase the size of a Space and its filesystem
Resize-SpacesVolume -SpaceFriendlyName MyData -NewSize 2TB
```

Only expansion is supported. Both the virtual disk and the partition are resized in a single operation.

### Check disk hardware reliability

```powershell
Get-SpacesPoolPhysicalDiskHWCounter -StoragePoolFriendlyName Backup
```

Example output:

```
PhysicalDiskFriendlyName  : WD-Drive-Jan2012
PhysicalDiskUniqueID      : USBSTOR\Disk&Ven_WDC_WD30&Prod_EZRX-00MMMB0&Rev_\...
CurrentTemperatureCelsius : 33
PowerOnHours              : 4836
ReadErrorsTotal           : 0
WriteErrorsTotal          :
ReadLatencyMax            : 445
WriteLatencyMax           : 424
```

> **Note:** The data returned depends on what the physical disk firmware reports. Some drives do not expose temperature, error counts, or latency figures, in which case those fields will be blank.

If any disk shows elevated error counts, high temperature, or abnormal latency peaks, consider scheduling a replacement.

### Enable Storage Spaces event logging

```powershell
# Install the scheduled task and create the event log
New-StorageSpacesEventLog
```

This creates a `StorageSpaces Events` log under **Applications and Services Logs** in Event Viewer. The log is updated approximately once per minute and captures arrivals, departures, alerts, and modifications to Storage Spaces, Storage Pools, and Physical Disks.

A reboot is required for the startup trigger to activate. The task persists across reboots automatically once it fires for the first time.

To remove logging:

```powershell
Remove-StorageSpacesEventLog
```

---

## Terminology

| Term | Definition |
|------|------------|
| **Storage Management Provider (SMP)** | An interface with the Storage Management API that provides access to manage storage. The Storage Spaces SMP is included in all Windows 8 and later SKUs. |
| **Storage Subsystem** | Exposed by a Storage Management Provider; contains the Physical Disks available for pool creation. |
| **Physical Disk** | A physical disk object located in a Storage Subsystem, used as a building block for Storage Pools. |
| **Primordial Storage Pool** | A system-managed pool that exposes all Physical Disks in the subsystem regardless of whether they have been assigned to a Concrete Pool. |
| **Concrete Storage Pool** | A pool you create, containing specifically allocated Physical Disks drawn from the Primordial Pool. |
| **Virtual Disk / Storage Space** | A virtual disk created from a Storage Pool. The Storage Spaces provider refers to these as Storage Spaces. They are exposed to Windows as a standard Disk object. |
| **Disk** | A disk as seen by Windows — the object that appears in Disk Management. For Storage Spaces, this is the disk that backs a Virtual Disk. |
| **Partition** | A partition created on a Disk. |
| **Volume** | Created on a Partition; contains a filesystem such as NTFS or ReFS. |
| **Hotspare** | A Physical Disk held in reserve inside a pool. If an active disk fails, Storage Spaces automatically rebuilds onto the hotspare without requiring manual intervention. |
| **Resiliency Type** | Determines how data is protected: **Simple** (no redundancy, striped), **Mirror** (two or three-way copy), or **Parity** (distributed parity, similar to RAID-5). |
| **Provisioning Type** | **Fixed** allocates space upfront from the pool. **Thin** only consumes pool space as data is written, up to the declared size limit. |

---

## Additional Resources

- [Storage cmdlets in Windows PowerShell](https://learn.microsoft.com/en-us/powershell/module/storage/) — Official documentation for the built-in Storage module that this module builds on.
- [Storage Spaces overview](https://learn.microsoft.com/en-us/windows-server/storage/storage-spaces/overview) — Microsoft documentation covering Storage Spaces architecture, resiliency types, and design guidance.
- [Plan a Storage Spaces deployment](https://learn.microsoft.com/en-us/windows-server/storage/storage-spaces/storage-spaces-states) — Guidance on storage pool states and health monitoring.
