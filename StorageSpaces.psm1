##################################################################################
# Created by:   Bruce Langworthy                                                 #
#--------------------------------------------------------------------------------#
# Module Name: StorageSpaces                                                     #
# Synopsis   : Advanced functions for managing Windows Storage Spaces via the   #
#            : Storage Management API (SMAPI). Supports local storage only;     #
#            : cluster and MPIO functionality have been removed.                 #
#            : Tested on Windows 10, Windows 11, and Windows Server 2016+.      #
##################################################################################

<#
.CHANGELOG

  This revision is a comprehensive update to the module. Cluster and MPIO
  support have been removed; the module now manages local storage only.
  The module has been reduced from 1,835 to 1,242 lines (-32%).

  --------------------------------------------------------------------------------
  BUG FIXES
  --------------------------------------------------------------------------------

  New-SpacesPool
    - Added a BEGIN block to initialize the disk accumulator before the PROCESS
      block runs, fixing undefined behavior with pipeline input.
    - $NumberOfHotsparesToUse now defaults to 0, fixing incorrect behavior when
      the parameter was omitted.

  New-SpacesVolume
    - $Size parameter type corrected to [System.UInt64] so [ValidateRange]
      functions as intended.
    - Added a $PSCmdlet.ShouldProcess() guard so -WhatIf and -Confirm correctly
      prevent disk operations.
    - Replaced string-building and Invoke-Expression with splatting for both
      New-VirtualDisk and Format-Volume calls.
    - Drive letter presence check corrected to use $PSBoundParameters.ContainsKey()
      rather than [String]::IsNullOrEmpty() on a [System.Char] parameter.
    - Replaced hardcoded Start-Sleep delays with polling loops for more reliable
      disk and partition availability detection.

  Resize-SpacesVolume
    - $NewSize parameter type corrected to [System.UInt64].

  Get-SpacesVolume
    - Script block now invoked directly with & rather than via Invoke-Command.
    - Internal script block refactored to return a [PSCustomObject] directly.

  Get-SpacesConfiguration
    - Removed several variables that were computed but never referenced.
    - Removed unnecessary pre-initialization of output variables to $null.

  Get-AvailableDriveLetter
    - Fixed a bug where the unsorted result was returned on both code paths
      instead of the sorted $AvailableDriveLetters variable.

  Get-SpacesPool
    - Now passes -FriendlyName directly to Get-StoragePool instead of
      post-filtering with Where-Object.

  Repair-SpacesConfiguration
    - Integer counts now compared against 0 (integer) rather than "0" (string).
    - Removed redundant empty-string pre-initialization of $Name in two places.

  New-StorageSpacesEventLog
    - Fixed two Write-Warning calls that were silently dropping variable values
      due to multiple positional arguments.
    - Fixed misplaced -ErrorAction on a filter rather than the cmdlet it was
      intended to suppress.

  --------------------------------------------------------------------------------
  MODERNIZATION
  --------------------------------------------------------------------------------

    - All WMI calls replaced with CIM equivalents (Get-CimInstance).
    - Scheduled task management updated to use the ScheduledTasks module
      (Register-ScheduledTask, New-ScheduledTaskTrigger, New-ScheduledTaskAction,
      Unregister-ScheduledTask, Get-ScheduledTask).
    - Event log existence check updated to use Get-WinEvent -ListLog.
    - ForEach-Object and Where-Object aliases replaced with full cmdlet names.

  Note: New-EventLog and Remove-EventLog are retained. They are deprecated in
  PowerShell 6+ but remain available on Windows via the compatibility layer.
  The replacement path is [System.Diagnostics.EventLog]::CreateEventSource() /
  ::Delete() if this becomes a concern in a future version.

  --------------------------------------------------------------------------------
  CODE QUALITY AND STYLE
  --------------------------------------------------------------------------------

    - All output object construction updated to use [PSCustomObject]@{} literals
      throughout, replacing verbose New-Object / Add-Member patterns.
    - Trailing semicolons removed from all statement-terminating lines.
    - Function definitions standardized to lowercase 'function' keyword.
    - $true / $false / $null standardized to lowercase throughout.
    - Prominent $null comparisons updated to left-side form ($null -eq $var).
    - Export-ModuleMember consolidated into a single call.
    - Column count calculation simplified using [Math]::Min and [Math]::Floor.
    - Module header updated to reflect local-only scope and supported Windows
      versions (10, 11, Server 2016+).

  --------------------------------------------------------------------------------
  STRING TABLE
  --------------------------------------------------------------------------------

    - $SCStringTable reduced from 47 entries to 22. Removed entries covered
      functionality that no longer exists in the module, or were never referenced
      anywhere in the original codebase.
    - Typos corrected in remaining entries.

  --------------------------------------------------------------------------------
  COMMENTS AND DOCUMENTATION
  --------------------------------------------------------------------------------

    - Inaccurate, stale, and misleading comments corrected throughout.
    - Comment typos fixed throughout.
    - New explanatory comments added to all functions where intent was not
      self-evident from the code.
    - README.md fully rewritten to reflect the current local-only scope, with
      updated cmdlet reference, real output examples, and current resource links.
#>

# Localized string table for all user-facing messages.
# The Data block restricts content to pure data (no executable code),
# which is required if localization support is re-enabled in the future.
$SCStringTable = Data {
    ConvertFrom-StringData @'
    MinNumOfPD            = At least 3 physical disks, excluding hot spares, should be provided.
    MaxNumOfPD            = The maximum number of physical disks (including hotspares) is 100.
    NotEnoughPhysicalDisk = Not enough physical disks available.
    CreatePool            = Now creating a Storage Pool using Storage Spaces.
    CreateSpace           = Now creating Storage Space, please wait...
    NoSpaceFound          = No space is found.
    CannotObtainPool      = Cannot obtain associated pool from the input space object.
    RetrieveObject        = Retrieving objects...
    InitDiskCreatePar     = Initializing disk and creating partition...
    RetrieveCreatedObject = Retrieving created objects...
    FormatVolume          = Formatting volume — this may take a while, please be patient...
    OneObjectOnly         = This cmdlet can only work on one space object. Nothing is resized.
    ExpandOnly            = This cmdlet only supports expanding the space; shrinking is not permitted.
    ObtainSpaceAfterResize = Obtaining space information after resize operation...
    NoNameMatch           = No storage pool found matching this name.
    PoolNotFound          = Pool object is not found.
    ProcessPool           = Now processing Storage Pool data, please wait...
    PoolUnhealthy         = Pool object is unhealthy.
    AllHealthy            = This Storage Pool, the Storage Spaces created from this pool, and the Physical Disks in the Storage Pool are all currently healthy.
    CollectSpace          = Now collecting data about each Storage Space and associated filesystem volumes...
    CollectPhysicalDisk   = Now collecting data about the Physical Disks used for the Storage Pool...
    NameNotFound          = A pool with the specified name cannot be found: {0}.
'@
}

# To enable localized error messages, uncomment the line below and provide a
# StorageSpacesMsg.psd1 file with translated key/value pairs.
# Import-LocalizedData -BindingVariable SCStringTable -FileName "StorageSpacesMsg.psd1"

################################################
#               Utility Functions              #
################################################

# Note: Utility functions are only available within the scope of the module
# and are not exported to the caller.

# Returns the physical disks backing a named virtual disk.
# Useful for diagnosing which drives underlie a given Storage Space.
function Get-PhysicalBackingDisksForSpace
{
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $true)]
        [string]
        $StorageSpaceFriendlyName
    )

    return Get-VirtualDisk -FriendlyName $StorageSpaceFriendlyName | Get-PhysicalDisk
}

################################################
#                Main Functions                #
################################################

#.ExternalHelp StorageSpaces.psm1-help.xml
function Get-SpacesProvider
{
    # Returns the Storage Spaces Management Provider object.
    # Use this to access top-level provider properties or pass to other SMAPI cmdlets.
    Get-StorageProvider -Name 'Storage Spaces Management Provider'
}

#.ExternalHelp StorageSpaces.psm1-help.xml
function Get-SpacesSubsystem
{
    # Returns the StorageSubsystem object for Storage Spaces.
    # This is the root object required as input for pool and disk cmdlets.
    Get-StorageSubSystem -Model 'Storage Spaces'
}

#.ExternalHelp StorageSpaces.psm1-help.xml
function Get-SpacesPhysicalDisk
{
    [CmdletBinding()]
    param(
        [parameter(Mandatory = $false, Position = 0)]
        [switch]
        $OnlyListAvailable,

        [parameter(Mandatory = $false, Position = 1)]
        [ValidateSet('SAS', 'iSCSI', 'SATA', 'USB')]
        [string]
        $BusType
    )

    $Subsystem     = Get-StorageSubSystem -Model 'Storage Spaces'
    $PhysicalDisks = @(Get-PhysicalDisk -StorageSubSystem $Subsystem)

    # If -OnlyListAvailable is specified, return only disks available for pool creation.
    if ($OnlyListAvailable)
    {
        $PhysicalDisks = @($PhysicalDisks | Where-Object { $_.CanPool -eq $true })
    }

    # If -BusType was specified, filter to only disks of that bus type.
    if (-not [string]::IsNullOrEmpty($BusType))
    {
        $PhysicalDisks = @($PhysicalDisks | Where-Object { $_.BusType -eq $BusType })
    }

    return $PhysicalDisks
}

#.ExternalHelp StorageSpaces.psm1-help.xml
function New-SpacesPool
{
    [CmdletBinding(ConfirmImpact = 'High')]
    param(
        [parameter(Mandatory = $true, Position = 0)]
        [string]
        $FriendlyName,

        # Two usage modes:
        # ByDiskArray    — pipe or pass specific PhysicalDisk objects.
        # ByLocalStorage — let the function auto-select available disks by count.
        [Parameter(Mandatory = $true,
                   ValueFromPipeline = $true,
                   ValueFromPipelineByPropertyName = $true,
                   ParameterSetName = 'ByDiskArray',
                   Position = 1)]
        [System.Object[]]
        $PhysicalDisks,

        [parameter(Mandatory = $true,
                   ParameterSetName = 'ByLocalStorage',
                   Position = 1)]
        [ValidateRange(3, 100)]
        [System.Int32]
        $NumberofPhysicalDiskstoUse,

        [parameter(Mandatory = $false, Position = 2)]
        [ValidateRange(1, 10)]
        [System.Int32]
        $NumberOfHotsparesToUse = 0
    )

    BEGIN
    {
        # Initialize the disk accumulator before the PROCESS block runs.
        $DisksToUse = @()
    }

    # The PROCESS block runs once per piped object, accumulating disks into $DisksToUse.
    PROCESS
    {
        if ($PhysicalDisks)
        {
            $DisksToUse += $PhysicalDisks
        }
    }

    END
    {
        $SubSystem = Get-SpacesSubsystem

        if ($DisksToUse.Count -gt 0)
        {
            if ($DisksToUse.Count -lt ($NumberOfHotsparesToUse + 3))
            {
                Write-Error $SCStringTable.MinNumOfPD
                break
            }
        }
        else
        {
            if ($NumberOfPhysicalDisksToUse -gt 100)
            {
                Write-Error $SCStringTable.MaxNumOfPD
                break
            }

            # A minimum of 3 data disks (excluding hotspares) is required.
            if (($NumberOfPhysicalDisksToUse - $NumberOfHotsparesToUse) -lt 3)
            {
                Write-Error $SCStringTable.MinNumOfPD
                break
            }

            # Get all poolable physical disks from the subsystem.
            $DisksTemp = @(Get-PhysicalDisk -StorageSubsystem $SubSystem -CanPool $true)

            if ($DisksTemp.Count -lt $NumberOfPhysicalDisksToUse)
            {
                Write-Error $SCStringTable.NotEnoughPhysicalDisk
                break
            }

            $DisksToUse = $DisksTemp[0..($NumberofPhysicalDiskstoUse - 1)]
        }

        Write-Verbose $SCStringTable.CreatePool

        if ($NumberOfHotsparesToUse -eq 0)
        {
            $Pool = New-StoragePool -InputObject $SubSystem -FriendlyName $FriendlyName -PhysicalDisks $DisksToUse
        }
        else
        {
            # Partition the disk array: data disks first, hotspares at the end.
            $PhysicalDisksForPool = $DisksToUse[0..($DisksToUse.Count - 1 - $NumberOfHotsparesToUse)]
            $HotSparePDObjects    = $DisksToUse[-$NumberOfHotsparesToUse..-1]

            $CreatedStoragePool = New-StoragePool -InputObject $SubSystem -FriendlyName $FriendlyName -PhysicalDisks $PhysicalDisksForPool
            $CreatedStoragePool | Add-PhysicalDisk -PhysicalDisks $HotSparePDObjects -Usage HotSpare

            # Refresh the pool object to reflect the newly added hotspares.
            $Pool = Get-StoragePool -FriendlyName $FriendlyName
        }

        $Pool
    }
}

#.ExternalHelp StorageSpaces.psm1-help.xml
function Get-SpacesVolume
{
    param(
        [parameter(Mandatory = $false, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]
        $SpaceFriendlyName
    )

    # Encapsulated as a script block to isolate per-space data collection logic.
    $ScriptToExecute = {
        param($VirtualDisk)

        # Re-query locally to get current operational and health status.
        $Space   = Get-VirtualDisk -UniqueId $VirtualDisk.UniqueId
        $DiskObj = Get-Disk -VirtualDisk $VirtualDisk -ErrorAction SilentlyContinue

        if ($null -eq $DiskObj)
        {
            Write-Warning "No disk found for space '$($VirtualDisk.FriendlyName)'."
        }

        $VolumeObj = $null
        if ($null -ne $DiskObj)
        {
            $VolumeObj = Get-Partition -Disk $DiskObj -ErrorAction SilentlyContinue |
                         Where-Object { $_.Type -eq 'Basic' } |
                         Get-Volume -ErrorAction SilentlyContinue

            if ($null -eq $VolumeObj)
            {
                Write-Warning "No volume found on disk for space '$($VirtualDisk.FriendlyName)'."
            }
        }

        $BackDisks = $VirtualDisk | Get-PhysicalDisk | ForEach-Object { $_.FriendlyName }

        [PSCustomObject]@{
            OperationalStatus    = if ($Space)     { $Space.OperationalStatus }  else { $null }
            HealthStatus         = if ($Space)     { $Space.HealthStatus }       else { $null }
            DiskUniqueID         = if ($DiskObj)   { $DiskObj.UniqueID }         else { $null }
            DriveLetter          = if ($VolumeObj) { $VolumeObj.DriveLetter }    else { $null }
            VolumeSize           = if ($VolumeObj) { $VolumeObj.Size }           else { $null }
            SizeRemaining        = if ($VolumeObj) { $VolumeObj.SizeRemaining }  else { $null }
            VolumeObjectID       = if ($VolumeObj) { $VolumeObj.ObjectID }       else { $null }
            FileSystem           = if ($VolumeObj) { $VolumeObj.FileSystem }     else { $null }
            BackingPhysicalDisks = $BackDisks
        }
    }

    # Retrieve all local virtual disks matching the criteria.
    if ([string]::IsNullOrEmpty($SpaceFriendlyName))
    {
        $Space = Get-VirtualDisk -StorageSubsystem (Get-SpacesSubsystem)
    }
    else
    {
        $Space = Get-VirtualDisk -FriendlyName $SpaceFriendlyName
    }

    if ($null -eq $Space)
    {
        Write-Verbose $SCStringTable.NoSpaceFound
        break
    }

    foreach ($Object in $Space)
    {
        # Collect pool information for this space.
        $Pool = Get-StoragePool -VirtualDisk $Object
        if ($null -eq $Pool)
        {
            Write-Error $SCStringTable.CannotObtainPool
            return
        }

        $StorageSpaces = & $ScriptToExecute $Object
        if ($null -eq $StorageSpaces)
        {
            Write-Error "Get-SpacesVolume: failed to retrieve volume information for '$($Object.FriendlyName)'."
            continue
        }

        # Append pool and space metadata to the output object.
        $StorageSpaces | Add-Member 'PoolFriendlyName'          -Value $Pool.FriendlyName                    -MemberType NoteProperty
        $StorageSpaces | Add-Member 'SpaceFriendlyName'         -Value $Object.FriendlyName                  -MemberType NoteProperty
        $StorageSpaces | Add-Member 'StorageSpaceUniqueID'      -Value $Object.UniqueID                      -MemberType NoteProperty
        $StorageSpaces | Add-Member 'IsManualAttach'            -Value $Object.IsManualAttach                -MemberType NoteProperty
        $StorageSpaces | Add-Member 'DetachedReason'            -Value $Object.DetachedReason                -MemberType NoteProperty
        $StorageSpaces | Add-Member 'SpaceUsageAlertPercentage' -Value $Pool.ThinProvisioningAlertThresholds -MemberType NoteProperty

        $StorageSpaces
    }
}

#.ExternalHelp StorageSpaces.psm1-help.xml
function New-SpacesVolume
{
    [CmdletBinding(
        SupportsShouldProcess = $true,
        ConfirmImpact = 'High'
    )]
    param(
        [parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]
        $StoragePoolFriendlyName,

        [parameter(Mandatory = $true, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string]
        $SpaceFriendlyName,

        [parameter(Mandatory = $true, Position = 2)]
        [ValidateRange(1073741824, 69268158808064)]
        [System.UInt64]
        $Size,

        [parameter(Mandatory = $true, Position = 3)]
        [ValidateSet('Simple', 'Mirror', 'Parity')]
        [string]
        $ResiliencyType,

        [parameter(Mandatory = $true, Position = 4)]
        [ValidateSet('Fixed', 'Thin')]
        [string]
        $ProvisioningType,

        [parameter(Mandatory = $false,
                   ValueFromPipeline = $true,
                   ValueFromPipelineByPropertyName = $true,
                   Position = 5)]
        [System.Char]
        $DriveLetterToUse,

        [parameter(Mandatory = $false, Position = 6)]
        [switch]
        $MaximumColumnCount,

        [parameter(Mandatory = $false, Position = 7)]
        [System.UInt64]
        $InterleaveBytes,

        [parameter(Mandatory = $false, Position = 8)]
        [ValidateSet('4KB', '8KB', '16KB', '32KB', '64KB')]
        [string]
        $ClusterSize,

        [parameter(Mandatory = $false, Position = 9)]
        [ValidateSet('NTFS', 'ReFS')]
        [string]
        $FileSystem
    )

    # Validate the drive letter is not already in use.
    # DriveLetterToUse omits the colon; input is expected from Get-AvailableDriveLetter.
    if ($PSBoundParameters.ContainsKey('DriveLetterToUse'))
    {
        $UsedDriveLetters = @(Get-Volume | ForEach-Object { "$([char]$_.DriveLetter)" }) +
                            @(Get-CimInstance -Class Win32_MappedLogicalDisk | ForEach-Object { "$([char]$_.DeviceID.Trim(':'))" })
        if ($UsedDriveLetters | Where-Object { $_ -eq $DriveLetterToUse })
        {
            Write-Error "Parameter DriveLetterToUse='$DriveLetterToUse' is not valid — that letter is already in use."
            return
        }
    }

    $Pool = Get-StoragePool -FriendlyName $StoragePoolFriendlyName
    if ($null -eq $Pool)
    {
        Write-Error ($SCStringTable.NameNotFound -f $StoragePoolFriendlyName)
        return
    }

    # Guard all disk operations with ShouldProcess so -WhatIf and -Confirm work correctly.
    if (-not $PSCmdlet.ShouldProcess("Storage Pool '$StoragePoolFriendlyName'", "Create virtual disk '$SpaceFriendlyName'"))
    {
        return
    }

    # Promote non-terminating errors to terminating so the catch block handles
    # all failures uniformly during disk provisioning.
    try
    {
        $ErrorActionPreference = 'Stop'

        $NumberOfColumns = $null
        if ($MaximumColumnCount)
        {
            # Determine column count from the number of data (Auto-Select) disks in the pool.
            $DataPDCount = @(Get-PhysicalDisk -StoragePool $Pool | Where-Object { $_.Usage -eq 'Auto-Select' }).Length

            [System.UInt16]$NumberOfColumns = switch ($ResiliencyType)
            {
                'Simple' { $DataPDCount }
                'Mirror' {
                    $Cols = [Math]::Floor($DataPDCount / 2)
                    if ($Cols -eq 0)
                    {
                        Write-Error 'Mirrored space requires at least 2 physical disks.'
                        return
                    }
                    $Cols
                }
                # Parity spaces are capped at 8 columns by the Storage Spaces engine.
                'Parity' { [Math]::Min($DataPDCount, 8) }
            }
        }

        # Build the New-VirtualDisk parameter set, adding optional params only when provided.
        $VDParams = @{
            InputObject           = $Pool
            FriendlyName          = $SpaceFriendlyName
            Size                  = $Size
            ResiliencySettingName = $ResiliencyType
            ProvisioningType      = $ProvisioningType
        }
        if ($null -ne $NumberOfColumns) { $VDParams['NumberOfColumns'] = $NumberOfColumns }
        if ($InterleaveBytes)           { $VDParams['Interleave']      = $InterleaveBytes }

        Write-Verbose $SCStringTable.CreateSpace
        $Space = New-VirtualDisk @VDParams

        # Poll until the virtual disk is visible to the disk subsystem.
        # Creation is asynchronous and the disk object may not be immediately queryable.
        Write-Verbose $SCStringTable.RetrieveObject
        $Disk    = $null
        $Retries = 0
        while ($null -eq $Disk -and $Retries -lt 30)
        {
            Start-Sleep -Seconds 2
            $Disk = Get-Disk -VirtualDisk $Space -ErrorAction SilentlyContinue
            $Retries++
        }
        if ($null -eq $Disk)
        {
            Write-Error 'Timed out waiting for the virtual disk to become available.'
            return
        }

        Write-Verbose $SCStringTable.InitDiskCreatePar
        Initialize-Disk -InputObject $Disk
        $PartTemp = New-Partition -InputObject $Disk -UseMaximumSize

        # Poll until the new partition is queryable after initialization.
        Write-Verbose $SCStringTable.RetrieveCreatedObject
        $Part    = $null
        $Retries = 0
        while ($null -eq $Part -and $Retries -lt 15)
        {
            Start-Sleep -Seconds 2
            $Part = Get-Partition -DiskId $PartTemp.DiskId -Offset $PartTemp.Offset -ErrorAction SilentlyContinue
            $Retries++
        }
        if ($null -eq $Part)
        {
            Write-Error 'Timed out waiting for the partition to become available.'
            return
        }

        $Volume = Get-Volume -Partition $Part

        # Default to NTFS if no file system was specified.
        if ([string]::IsNullOrEmpty($FileSystem))
        {
            $FileSystem = 'NTFS'
        }

        # Build the Format-Volume parameter set.
        # ClusterSize values like '4KB' are converted to byte counts for the cmdlet.
        $FVParams = @{
            NewFileSystemLabel = $SpaceFriendlyName
            FileSystem         = $FileSystem
            Confirm            = $false
        }
        if ($ClusterSize)
        {
            $FVParams['ClusterSize'] = [int]($ClusterSize -replace 'KB', '') * 1KB
        }

        Write-Verbose $SCStringTable.FormatVolume
        $Volume | Format-Volume @FVParams | Out-Null

        if ($PSBoundParameters.ContainsKey('DriveLetterToUse'))
        {
            Add-PartitionAccessPath -InputObject $Part -AccessPath "$DriveLetterToUse`:"
        }
        else
        {
            Add-PartitionAccessPath -InputObject $Part -AssignDriveLetter
        }
    }
    catch
    {
        Write-Verbose $_
        return
    }

    Get-SpacesVolume -SpaceFriendlyName $SpaceFriendlyName
}

#.ExternalHelp StorageSpaces.psm1-help.xml
function Get-SpacesPool
{
    param(
        [parameter(Mandatory = $false)]
        [string]
        $StoragePoolFriendlyName
    )

    $Subsystem = Get-SpacesSubsystem

    if ([string]::IsNullOrEmpty($StoragePoolFriendlyName))
    {
        Get-StoragePool -StorageSubsystem $Subsystem
    }
    else
    {
        Get-StoragePool -StorageSubsystem $Subsystem -FriendlyName $StoragePoolFriendlyName
    }
}

#.ExternalHelp StorageSpaces.psm1-help.xml
function Resize-SpacesVolume
{
    [CmdletBinding(
        SupportsShouldProcess = $true,
        ConfirmImpact = 'Medium'
    )]
    param(
        [parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]
        $SpaceFriendlyName,

        [parameter(Mandatory = $true, Position = 1)]
        [ValidateRange(1073741824, 69268158808064)]
        [System.UInt64]
        $NewSize,

        [parameter(Mandatory = $false, Position = 2)]
        [ValidateNotNullOrEmpty()]
        [string]
        $StoragePoolFriendlyName
    )

    # Encapsulated as a script block to isolate the resize and partition-extension logic.
    $ScriptToExecute = {
        param(
            $VirtualDisk,
            $SizeToExtend
        )

        # One virtual disk may have multiple partitions, but this cmdlet only
        # addresses virtual disks with exactly one basic partition.
        $Disk = Get-Disk -VirtualDisk $VirtualDisk
        if ($null -eq $Disk)
        {
            Write-Error 'No Windows disk found for the given space.'
            return
        }

        $Partitions = @(Get-Partition -Disk $Disk | Where-Object { $_.Type -eq 'Basic' })
        if ($Partitions.Count -ne 1)
        {
            Write-Error 'This cmdlet can only resize virtual disks with exactly one basic partition. Nothing was resized.'
            return
        }

        Resize-VirtualDisk -InputObject $VirtualDisk -Size $SizeToExtend
        Write-Verbose 'Virtual disk has been resized.'

        # Refresh disk and partition objects — they must be re-queried after a resize.
        Update-Disk -InputObject $Disk
        $Disk       = Get-Disk -Number $Disk.Number
        $Partitions = @(Get-Partition -Disk $Disk | Where-Object { $_.Type -eq 'Basic' })

        $PartitionSizeRange = $Partitions[0] | Get-PartitionSupportedSize
        Write-Verbose "Maximum available partition size is $($PartitionSizeRange.SizeMax)."

        Resize-Partition -InputObject $Partitions[0] -Size $PartitionSizeRange.SizeMax
        Write-Verbose 'Partition has been resized.'
    }

    # Resolve the virtual disk(s) matching the specified name and optional pool filter.
    if (-not [string]::IsNullOrEmpty($StoragePoolFriendlyName))
    {
        $Pool         = Get-StoragePool -FriendlyName $StoragePoolFriendlyName
        $VirtualDisks = Get-VirtualDisk -StoragePool $Pool
    }
    else
    {
        $VirtualDisks = Get-VirtualDisk
    }
    $VirtualDisks = @($VirtualDisks | Where-Object { $_.FriendlyName -eq $SpaceFriendlyName })

    # Only a single matching virtual disk is supported.
    if ($VirtualDisks.Count -ne 1)
    {
        Write-Error $SCStringTable.OneObjectOnly
        break
    }

    # Only expansion is supported; shrinking a virtual disk is not permitted.
    if ([UInt64]$NewSize -le $VirtualDisks[0].Size)
    {
        Write-Error $SCStringTable.ExpandOnly
        break
    }

    if ($null -eq $Pool)
    {
        $Pool = Get-StoragePool -VirtualDisk $VirtualDisks[0]
    }

    & $ScriptToExecute $VirtualDisks[0] $NewSize

    # Return the updated space information.
    Write-Verbose $SCStringTable.ObtainSpaceAfterResize
    $ResizedSpace = @(Get-SpacesVolume -SpaceFriendlyName $SpaceFriendlyName)

    if ($ResizedSpace.Count -ne 1)
    {
        $ResizedSpace = $ResizedSpace | Where-Object { $_.PoolFriendlyName -eq $Pool.FriendlyName }
    }

    $ResizedSpace
}

#.ExternalHelp StorageSpaces.psm1-help.xml
function Get-SpacesConfiguration
{
    param(
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $StoragePoolFriendlyName
    )

    $PoolOBJ = Get-StoragePool -FriendlyName $StoragePoolFriendlyName
    if ($null -eq $PoolOBJ)
    {
        Write-Error $SCStringTable.NoNameMatch
        break
    }

    $SpaceObj = Get-VirtualDisk  -StoragePool $PoolOBJ
    $PDObj    = Get-PhysicalDisk -StoragePool $PoolOBJ

    ##########################
    # Basic Pool Information #
    ##########################

    # Compute free and used space metrics.
    [System.Int64]$PoolFree           = ($PoolOBJ.Size - $PoolOBJ.AllocatedSize) / 1GB
    $PoolUsedPercent                  = [Math]::Round(($PoolOBJ.AllocatedSize / $PoolOBJ.Size) * 100, 2)
    $PoolFreeRemainingPercent         = 100 - $PoolUsedPercent
    [string]$AlertPercent             = $PoolOBJ.ThinProvisioningAlertThresholds[0] + ' %'

    $SpaceCount      = @($SpaceOBJ).Count
    $PDCount         = @($PDObj).Count
    $UnhealthyPD     = @($PDObj    | Where-Object { $_.HealthStatus -ne 'Healthy' }).Count
    $UnhealthySpaces = @($SpaceOBJ | Where-Object { $_.HealthStatus -ne 'Healthy' }).Count

    # This function outputs multiple objects to the pipeline: first the pool summary,
    # then one detail object per Storage Space. Use -OutVariable or assign to an array
    # to capture all output.
    [PSCustomObject]@{
        StoragePoolFriendlyName        = $StoragePoolFriendlyName
        HealthStatus                   = $PoolOBJ.HealthStatus
        IsReadOnly                     = $PoolOBJ.IsReadOnly
        ThinProvisionAlertThreshold    = $AlertPercent
        StoragePoolFreeGigabytes       = $PoolFree
        StoragePoolUsedSpacePercent    = $PoolUsedPercent
        StoragePoolFreeSpacePercent    = $PoolFreeRemainingPercent
        OperationalStatus              = $PoolOBJ.OperationalStatus
        NumberofPhysicalDisksInPool    = $PDCount
        NumberofStorageSpacesInPool    = $SpaceCount
        NumberofUnhealthyPhysicalDisks = $UnhealthyPD
        NumberofUnhealthyStorageSpaces = $UnhealthySpaces
    }

    ##########################################
    # Information of each space in this pool #
    ##########################################

    foreach ($Space in $SpaceOBJ)
    {
        $FullSpaceDetail = Get-SpacesVolume -SpaceFriendlyName $Space.FriendlyName

        # Get-SpacesVolume may return multiple spaces with the same name from different pools.
        if (@($FullSpaceDetail).Count -gt 1)
        {
            $FullSpaceDetail = $FullSpaceDetail | Where-Object { $_.PoolFriendlyName -eq $StoragePoolFriendlyName }
        }

        $FullSpaceDetail
    }
}

#.ExternalHelp StorageSpaces.psm1-help.xml
function Test-SpacesConfiguration
{
    param(
        [parameter(Mandatory = $true,
                   Position = 0,
                   ParameterSetName = 'ByName')]
        [ValidateNotNullOrEmpty()]
        [string]
        $StoragePoolFriendlyName,

        [parameter(Mandatory = $true,
                   Position = 0,
                   ParameterSetName = 'ByPool')]
        [Microsoft.Management.Infrastructure.CimInstance]
        [PSTypeName('Microsoft.Management.Infrastructure.CimInstance#MSFT_StoragePool')]
        $StoragePool,

        # Without -Passthru: returns $true (healthy) or $false (unhealthy).
        # With -Passthru: outputs PSCustomObjects describing each unhealthy component
        # instead of $false, so callers can inspect exactly what is wrong.
        [parameter(Mandatory = $false, Position = 1)]
        [switch]
        $Passthru
    )

    # Force a cache update to ensure we have the most recent state before querying health.
    $Subsystem = Get-SpacesSubsystem
    Update-StorageProviderCache -DiscoveryLevel Full -StorageSubSystem $Subsystem
    Update-HostStorageCache

    # Resolve pool object from whichever parameter set was provided.
    if (-not [string]::IsNullOrEmpty($StoragePoolFriendlyName))
    {
        $PoolOBJ = Get-StoragePool -FriendlyName $StoragePoolFriendlyName
    }
    else
    {
        $PoolOBJ = $StoragePool
    }

    if ($null -eq $PoolOBJ)
    {
        Write-Error $SCStringTable.PoolNotFound
        return $false
    }

    ###################
    # Pool Collection #
    ###################
    Write-Verbose $SCStringTable.ProcessPool

    if (($PoolOBJ.HealthStatus -ne 'Healthy') -or ($PoolOBJ.OperationalStatus -ne 'OK'))
    {
        Write-Warning $SCStringTable.PoolUnhealthy

        if ($Passthru)
        {
            [PSCustomObject]@{
                StoragePoolFriendlyName      = $PoolOBJ.FriendlyName
                StoragePoolHealthStatus      = $PoolOBJ.HealthStatus
                StoragePoolOperationalStatus = $PoolOBJ.OperationalStatus
                StoragePoolUniqueID          = $PoolOBJ.UniqueID
                StoragePoolIsReadOnly        = $PoolOBJ.IsReadOnly
            }
        }
        else
        {
            return $false
        }
    }
    else
    {
        # If the pool is healthy, all spaces and disks are healthy — no further checks needed.
        Write-Host $SCStringTable.AllHealthy
        return $true
    }

    # Execution only reaches this point when the pool is unhealthy AND -Passthru was
    # specified; fall through to enumerate unhealthy spaces and physical disks.

    ####################
    # Space Collection #
    ####################
    Write-Verbose $SCStringTable.CollectSpace

    $SpacesObj = Get-VirtualDisk -StoragePool $PoolOBJ
    foreach ($Object in $SpacesObj)
    {
        $Space = Get-SpacesVolume -SpaceFriendlyName $Object.FriendlyName
        if (($Space.HealthStatus -ne 'Healthy') -or ($Space.OperationalStatus -ne 'OK'))
        {
            # Determine if the space is in a detached state.
            $SpaceIsDetached = ($Space.IsManualAttach -eq $true) -and ($Space.DetachedReason -ne 'None')

            [PSCustomObject]@{
                StorageSpaceFriendlyName      = $Space.SpaceFriendlyName
                StorageSpaceHealthStatus      = $Space.HealthStatus
                StorageSpaceOperationalStatus = $Space.OperationalStatus
                StorageSpaceUniqueID          = $Space.StorageSpaceUniqueID
                SpaceIsDetached               = $SpaceIsDetached
            }
        }
    }

    ############################
    # Physical Disk Collection #
    ############################
    Write-Verbose $SCStringTable.CollectPhysicalDisk

    $PDObj = Get-PhysicalDisk -StoragePool $PoolOBJ
    foreach ($PhysicalDisk in $PDObj)
    {
        if (($PhysicalDisk.HealthStatus -ne 'Healthy') -or ($PhysicalDisk.OperationalStatus -ne 'OK'))
        {
            [PSCustomObject]@{
                PhysicalDiskFriendlyName      = $PhysicalDisk.FriendlyName
                PhysicalDiskHealthStatus      = $PhysicalDisk.HealthStatus
                PhysicalDiskOperationalStatus = $PhysicalDisk.OperationalStatus
                PhysicalDiskUniqueID          = $PhysicalDisk.UniqueID
            }
        }
    }

    return $false
}

#.ExternalHelp StorageSpaces.psm1-help.xml
function Repair-SpacesConfiguration
{
    [CmdletBinding(SupportsShouldProcess = $false)]
    param()

    # Collect all non-primordial pools from the Storage Spaces subsystem.
    Write-Verbose 'Collecting Storage Pool information...'
    $RepairablePools       = @(Get-StorageSubSystem -Model *space* | Get-StoragePool -IsPrimordial $false)
    $NumberRepairablePools = $RepairablePools.Count

    if ($NumberRepairablePools -eq 0)
    {
        Write-Error 'No pools available to repair.' -ErrorAction Stop
    }

    # Collect all Storage Spaces across the repairable pools.
    Write-Verbose 'Collecting Storage Space information...'
    $AllSpaces = @($RepairablePools | Get-VirtualDisk)

    # Check and repair all read-only Storage Pools.
    foreach ($StoragePool in $RepairablePools)
    {
        if ($StoragePool.IsReadOnly -eq $true)
        {
            Write-Warning "The pool '$($StoragePool.FriendlyName)' is Read-Only. Change to read/write to allow repairs?" -WarningAction Inquire
            $StoragePool | Set-StoragePool -IsReadOnly $false
        }
    }

    # Reconnect any manually attached Storage Spaces before requesting repairs.
    foreach ($StorageSpace in $AllSpaces)
    {
        if ($StorageSpace.IsManualAttach -eq $true)
        {
            Write-Warning "The Storage Space '$($StorageSpace.FriendlyName)' is set to attach manually. Change to automatic and connect?" -WarningAction Inquire
            $StorageSpace | Set-VirtualDisk -IsManualAttach $false
            $StorageSpace | Connect-VirtualDisk
        }
    }

    # Request repairs for all Storage Spaces across all pools.
    Write-Verbose 'Requesting repairs of all Storage Spaces...'
    $AllSpaces | Repair-VirtualDisk

    # Exit early if no repair jobs were queued.
    if ((Get-StorageJob | Where-Object { $_.JobState -eq 'Running' }).Count -eq 0)
    {
        Write-Warning 'There are no active repair jobs. Exiting.' -ErrorAction Stop
    }

    # Monitor and display progress for running repair jobs.
    # Note: this can take a long time when replacing a physical disk.
    if ($null -ne (Get-StorageJob))
    {
        do
        {
            # Cache job state once per iteration to avoid redundant API calls.
            $ActiveJobs    = @(Get-StorageJob)
            $RunningJobs   = @($ActiveJobs | Where-Object { $_.JobState -eq 'Running' })
            $PendingJobs   = @($ActiveJobs | Where-Object { $_.JobState -ne 'Running' })

            $PercentComplete    = if ($RunningJobs) { $RunningJobs[0].PercentComplete } else { 100 }
            $RemainingJobNumber = if ($PendingJobs.Count -eq 0) { 'No' } else { $PendingJobs.Count }

            Write-Progress `
                -Activity   "Repair $PercentComplete% complete" `
                -PercentComplete $PercentComplete `
                -Status     "$RemainingJobNumber additional repair job(s) remaining."

            Start-Sleep -Seconds 2
        }
        while ($null -ne (Get-StorageJob))
    }

    # Update the cache to get a consistent view of storage before re-checking health.
    Write-Verbose 'Updating storage cache...'
    Update-HostStorageCache
    Update-StorageProviderCache -DiscoveryLevel Full

    # Re-fetch space objects to get current health status after repair jobs have run.
    $ResultList = $AllSpaces | Get-VirtualDisk

    foreach ($StorageSpace in $ResultList)
    {
        # If the Space is still not healthy after repair jobs completed, surface an error.
        if ($StorageSpace.HealthStatus -ne 'Healthy')
        {
            Write-Error "The Storage Space '$($StorageSpace.FriendlyName)' is still not healthy. Try adding additional physical disks to the pool and run again." -ErrorAction Stop
        }
    }
}

#.ExternalHelp StorageSpaces.psm1-help.xml
function Get-AvailableDriveLetter
{
    param(
        [parameter(Mandatory = $false)]
        [switch]
        $ReturnFirstLetterOnly
    )

    $CurrentUserPriv = [Security.Principal.WindowsIdentity]::GetCurrent()
    $IsElevated      = (New-Object Security.Principal.WindowsPrincipal $CurrentUserPriv).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)

    if ($IsElevated -eq $false)
    {
        Write-Error 'This command must be run from an elevated PowerShell window.' -ErrorAction Stop
    }

    # Collect drive letters currently in use by local volumes and mapped network drives.
    $MappedDrives       = @((Get-ChildItem 'HKCU:\Network' | Get-ItemProperty).PSChildName)
    $VolumeDriveLetters = @(Get-Volume | ForEach-Object { "$([char]$_.DriveLetter)" })

    if ($null -ne $MappedDrives)
    {
        $UsedDriveLetters = @($VolumeDriveLetters) + @($MappedDrives)
    }
    else
    {
        $UsedDriveLetters = $VolumeDriveLetters
    }

    # Compare the letters C-Z against the used-letters list.
    # SideIndicator '<=' means present in the reference set (C-Z) but absent from
    # the difference set (used letters) — i.e., the letter is available.
    $AvailableDriveLetters = @(
        Compare-Object `
            -DifferenceObject $UsedDriveLetters `
            -ReferenceObject  $(67..90 | ForEach-Object { "$([char]$_)" }) |
        Where-Object   { $_.SideIndicator -eq '<=' } |
        ForEach-Object { $_.InputObject } |
        Sort-Object
    )

    if ($ReturnFirstLetterOnly)
    {
        $AvailableDriveLetters[0]
    }
    else
    {
        $AvailableDriveLetters
    }
}

#.ExternalHelp StorageSpaces.psm1-help.xml
function Get-SpacesPoolPhysicalDiskHWCounter
{
    [CmdletBinding(SupportsShouldProcess = $false)]
    param(
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $StoragePoolFriendlyName
    )

    $Pool      = Get-StoragePool -FriendlyName $StoragePoolFriendlyName
    $PoolDisks = $Pool | Get-PhysicalDisk

    foreach ($PhysicalDisk in $PoolDisks)
    {
        $ReliabilityData = $PhysicalDisk | Get-StorageReliabilityCounter

        [PSCustomObject]@{
            PhysicalDiskFriendlyName  = $PhysicalDisk.FriendlyName
            PhysicalDiskUniqueID      = $PhysicalDisk.UniqueId
            CurrentTemperatureCelsius = $ReliabilityData.Temperature
            PowerOnHours              = $ReliabilityData.PowerOnHours
            ReadErrorsTotal           = $ReliabilityData.ReadErrorsTotal
            WriteErrorsTotal          = $ReliabilityData.WriteErrorsTotal
            ReadLatencyMax            = $ReliabilityData.ReadLatencyMax
            WriteLatencyMax           = $ReliabilityData.WriteLatencyMax
        }
    }
}

#.ExternalHelp StorageSpaces.psm1-help.xml
function New-StorageSpacesEventLog
{
    [CmdletBinding(SupportsShouldProcess = $false)]
    param()

    # Author: Tobias Klima
    # Organization: Microsoft
    # Last Updated: July 25, 2012

    $JobName     = 'StorageSpaces Event Monitor'
    $LogName     = 'StorageSpaces Events'
    $Script_Path = 'C:\Windows\System32\WindowsPowerShell\v1.0\Modules\StorageSpaces\Notification_Script.ps1'

    $CurrentPolicy = Get-ExecutionPolicy
    if ($CurrentPolicy -eq 'Restricted')
    {
        Write-Error 'The PowerShell execution policy must be set to RemoteSigned or Unrestricted to enable event logging.' -ErrorAction Stop
    }

    if (-not (Test-Path $Script_Path))
    {
        Write-Host "The script file Notification_Script.ps1 cannot be found at: $Script_Path" -ForegroundColor Red
        return
    }

    if ($null -ne (Get-ScheduledTask -TaskName $JobName -ErrorAction SilentlyContinue))
    {
        Write-Warning "The scheduled task '$JobName' already exists. If there are issues, uninstall and re-install."
        return
    }

    if ($null -ne (Get-WinEvent -ListLog $LogName -ErrorAction SilentlyContinue))
    {
        Write-Warning "The event log '$LogName' already exists. If there are issues, uninstall and re-install."
        return
    }

    # Define the two triggers: run at startup (with a 1-minute delay) and daily.
    $TriggerStartup = New-ScheduledTaskTrigger -AtStartup -RandomDelay (New-TimeSpan -Minutes 1)
    $TriggerDaily   = New-ScheduledTaskTrigger -Daily -At (Get-Date).AddMinutes(30)
    $Action         = New-ScheduledTaskAction -Execute 'PowerShell.exe' `
                          -Argument "-NonInteractive -File `"$Script_Path`""

    Register-ScheduledTask `
        -TaskName $JobName `
        -Action   $Action `
        -Trigger  @($TriggerStartup, $TriggerDaily) `
        -RunLevel Highest

    # Create the Windows event log for StorageSpaces notifications.
    New-EventLog -LogName $LogName -Source $LogName -ErrorAction SilentlyContinue

    Write-Warning 'Installation successful — a reboot is required for the startup trigger to activate.'
}

#.ExternalHelp StorageSpaces.psm1-help.xml
function Remove-StorageSpacesEventLog
{
    [CmdletBinding(SupportsShouldProcess = $false)]
    param()

    $JobName = 'StorageSpaces Event Monitor'
    $LogName = 'StorageSpaces Events'

    Write-Warning 'Warning: the contents of the StorageSpaces Event Log will be permanently removed.' -WarningAction Inquire

    # Unregister the scheduled task and remove the event log.
    Unregister-ScheduledTask -TaskName $JobName -Confirm:$false
    Start-Sleep -Seconds 5
    Remove-EventLog -LogName $LogName

    Write-Host 'Scheduled task unregistered and StorageSpaces event log removed. Uninstall complete.' -ForegroundColor Yellow
}

################################################
#                Export Cmdlets                #
################################################

# Note: internal utility functions (Get-PhysicalBackingDisksForSpace) are
# intentionally not exported and remain module-private.

Export-ModuleMember -Function @(
    'Get-SpacesProvider',
    'Get-SpacesSubsystem',
    'Get-SpacesPhysicalDisk',
    'New-SpacesPool',
    'Get-SpacesVolume',
    'New-SpacesVolume',
    'Get-SpacesPool',
    'Resize-SpacesVolume',
    'Get-SpacesConfiguration',
    'Test-SpacesConfiguration',
    'Repair-SpacesConfiguration',
    'Get-AvailableDriveLetter',
    'Get-SpacesPoolPhysicalDiskHWCounter',
    'New-StorageSpacesEventLog',
    'Remove-StorageSpacesEventLog'
)
