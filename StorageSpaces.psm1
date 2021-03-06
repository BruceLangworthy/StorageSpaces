##################################################################################
# Created by:   Bruce Langworthy                                                 #
#--------------------------------------------------------------------------------#
# Module Name: StorageSpaces                                                     #
# Synopsis   : This script module provides advanced functions for the management #
#            : of the Storage Spaces feature using functionality exposed by the  #
#            : Storage Management API (SMAPI) in Windows 8.                      #
#                                                                                #
##################################################################################

$SCStringTable = Data {
    ConvertFrom-StringData @'
    ServerMPIORequired = This command requires Windows Server and the MPIO feature
    ServerRequired = This command requires Windows Server.
    RSDNotObtained = Remote shared disks cannot be obtained.
    MinNumOfPD = At least 3 physical disks, excluding those for hot spares, should be provided.
    MaxNumOfPD = The maximum number of physical disks (including hotspares) is 100
    NotEnoughPhysicalDisk = Not enough physical disks available
    CreatePool = Now creating a Storage Pool using Storage Spaces
    VirtualDiskNotNull = Virtual disk parameter cannot be null to execute ScriptToExecute.
    NotObtainNodeInfo = Failed to obtain full information on the owner node for space
    NoDiskOnSpace = No disk is found on the space
    NoVolumeOnDisk = No volume is found on the disk
    CreateSpace = Now creating Storage Space, please wait...
    NoSpaceFound = No space is found.
    CannotObtainPool = Cannot obtain associated pool from the input space object.
    NullCSVInfo = Null information of CSV is obtained. This space is not a cluster shared volume.
    NullPoolOwnerInfo = Null information of pool owner is obtained.
    LocallyNull = locally returns null.
    RetreiveObject = Retreiving Objects....
    InitDiskCreatePar = Initializing Disk and creating Partition..
    RetreiveCreatedObject = Retreiving created objects....
    FormatVolume = Now formatting volume, this can take a while please be patient...
    NoWDInSpace = Windows disk is not found in the given space
    VDOnePartition = This cmdlet can only deal with virtual disks with one basic partition on it.  Nothing is resized.
    VDResized = Virtual disk has been resized.
    MaxPartitionSize = Maximum available partition size is
    PartitionResized = Partition on virtual disk has been resized.
    OneObjectOnly = This cmdlet can only work on one space object. Nothing is resized.
    ExpandOnly = This cmdlet only allows to expand the space.
    ResizeSpaceRemotely = Resizing space remotely ...
    RSRFinished = Resizing space remotely finished normally.
    ObtainSpaceAfterResize = Obtaining space information after resize operation ...
    NoNameMatch = No storage pool found matching this name.
    PoolNotFound = Pool object is not found.
    ProcessPool = Now processing Storage Pool data, please wait...
    PoolUnhealthy = Pool object is unhealthy.
    AllHealthy = This Storage Pool, the Storage Spaces created from this pool, and the Physial Disks in the Storage Pool are all currently healthy.
    CollectSpace = Now collecting data about each Storage Space and associated Filesystem Volumes...
    CollectPhysicalDisk = Now collecting data about the Physical Disks used for the Storage Pool...
    InstallMPIO = Installing the MPIO Feature, Please wait..
    EnableAutoClaiming = Enabling automatic claiming for all SAS devices
    SetRoundRobin = Setting default Load Balance policy to Round Robin
    OnNodeNull = on node {0} returns null.
    ProvisioningTypeClustered = Provisioning type can only be {0} when the pool is clustered.
    RemoteNotEnabled = Ps Remoting is not enabled on node {0}. Please run cmdlet {1} on all nodes first.
    EnableRemote = Please run cmdlet {0} on cluster node {1} first.
    ClusterSwitch = Please run again with {0} switch to obtain information of clustered pool
    NameNotFound = A pool with specified name cannot be found: {0} .
'@
}

# The line below is only required to support localized error messages, remarking out so we don't require localized help.
# Import-LocalizedData -BindingVariable SCStringTable -FileName "StorageSpacesMsg.psd1"

################################################
#               Utility Functions              #
################################################

# Note: Utility functions are only available within the scope of the module and are not exposed to the user.

function Get-ClusteredPoolFromStoragePool
{
    [CmdletBinding()]
    Param(
    [ValidateNotNullOrEmpty()]
    [Parameter(Mandatory=$true)]
    [Microsoft.Management.Infrastructure.CimInstance]
    [PSTypeName("Microsoft.Management.Infrastructure.CimInstance#MSFT_StoragePool")]
    $StoragePool
    )
    # Convert the ID format to one usable with FailoverClusters module
    $ClusterPoolID = $StoragePool.UniqueID
    $ClusterPoolID = $ClusterPoolID.Replace(" ","")
    $ClusterPoolID = $ClusterPoolID.Replace('{','')
    $ClusterPoolID = $ClusterPoolID.Replace('}','')

    # Get the Cluster resource corresponding with the ID from the Storage Pool.
    $ClusterPoolResource = Get-ClusterResource | Where-Object { ($_.State -eq "Online") -and ($_.ResourceType -eq "Storage Pool") -and ($_ | Get-ClusterParameter | Where-Object {$_.Value -eq $ClusterPoolID}) }

    #Return the Cluster Resource representing the Storage Pool as output.
    Return $ClusterPoolResource;
}

Function Get-ClusterCSVFromStorageSpace
{

    [CmdletBinding()]
    Param(
    [ValidateNotNullOrEmpty()]
    [Parameter(Mandatory=$true)]
    [Microsoft.Management.Infrastructure.CimInstance]
    [PSTypeName("Microsoft.Management.Infrastructure.CimInstance#MSFT_VirtualDisk")]
    $VirtualDisk
    )

    $TempID = ($VirtualDisk.ObjectID)
    $TempID = ($TempID.Replace(" ",""))
    $TempID = ($TempID.Replace('{',''))
    $TempID = ($TempID.Replace('}',''))

    $CSV = Get-ClusterSharedVolume | Where-Object { ($_.State -eq "Online") -and ((Get-ClusterParameter -Name VirtualDiskID -InputObject $_).Value -eq $TempID)}

    Return $CSV;
}

Function Get-ClusterPoolOwner 
{

    [CmdletBinding()]
    Param(
    [ValidateNotNullOrEmpty()]
    [Parameter(Mandatory=$true)]
    [Microsoft.Management.Infrastructure.CimInstance]
    [PSTypeName("Microsoft.Management.Infrastructure.CimInstance#MSFT_StoragePool")]
    $StoragePool
    )
    # Convert the ID format to one usable with FailoverClusters module;
    $ClusterPoolID = $StoragePool.UniqueID
    $ClusterPoolID = $ClusterPoolID.Replace(" ","")
    $ClusterPoolID = $ClusterPoolID.Replace('{','')
    $ClusterPoolID = $ClusterPoolID.Replace('}','')

    # Get the Cluster resource corresponding with the ID from the Storage Pool.;
    $PoolRes = Get-ClusteredPoolFromStoragePool -StoragePool $StoragePool;
    if($PoolRes -eq $null)
    {
        # The callers of this function don't consider this situation. Should we fix them later???
        return $null;
    }
    $ClusterPoolResourceName    = $PoolRes.Name;
    $ClusterResourceState       = $PoolRes.State;
    $ClusterOwnerNode           = (($PoolRes.OwnerNode).Name);
    
    # Assemble the output object 
    $ClusterPool = New-Object Object
    $ClusterPool | Add-Member "ClusterResourceName"  -Value $ClusterPoolResourceName  -MemberType NoteProperty;
    $ClusterPool | Add-Member "ClusterOwnerNode"     -Value $ClusterOwnerNode         -MemberType NoteProperty;
    $ClusterPool | Add-Member "ClusterResourceState" -Value $ClusterResourceState     -MemberType NoteProperty;
    Return $ClusterPool;
}

function Get-PhysicalBackingDisksForSpace
{
    [CmdletBinding()]
    Param(
    [ValidateNotNullOrEmpty()]
    [Parameter(Mandatory=$true)]
    [String]
    $StorageSpaceFriendlyName
    )
    $BackingPhysicalDisks =(Get-VirtualDisk -FriendlyName $StorageSpaceFriendlyName | Get-PhysicalDisk);
    Return $BackingPhysicalDisks;  
}

function Test-PsRemoting
{
<#
.SYNOPSIS
    Check if PsRemoting is enabled on remote computer.
.DESCRIPTION
    Cluster related functionalities requires the PsRemoting policy to be 
    enabled in remote computer. This utility function sends a simple 
    command to the remote computer and check the output to see if 
    the remote node fulfills this requirements.
.EXAMPLE
    Test-PsRemoting -ComputerName 'Node01'
.INPUTTYPE
    String
.RETURNVALUE
    Bool
#>
    param(
        [Parameter(Mandatory = $true)]
        $ComputerName
    )
    
    try
    {
        $result = Invoke-Command -ErrorAction "Stop" -ComputerName $ComputerName { 1 }
    }
    catch
    {
        Write-Verbose $_
        return $false
    }
    $true
}    

function CheckForServerSKU
{
<#
.SYNOPSIS
    Check for Server SKU. Return $True if run on Server.
.DESCRIPTION
    Some cmdlets can only run on server SKU, and some have different behaviors
    on different SKU's. This utility function helps us to know the SKU of the 
    node which as the scripts running on.
.EXAMPLE
    CheckForServerSKU
.RETURNVALUE
    Bool
#>
    if ((gwmi win32_operatingsystem).ProductType -gt 1)
    {
        $IsWindowsServer = $True
    }
    else
    {
        $IsWindowsServer = $False
    }
    return $IsWindowsServer
}  

################################################
#                Main Functions                #
################################################

#.ExternalHelp StorageSpaces.psm1-help.xml
function Get-SpacesProvider
{
    Get-StorageProvider -Name "Storage Spaces Management Provider";
}

#.ExternalHelp StorageSpaces.psm1-help.xml
function Get-SpacesSubsystem
{
    # Returns the StorageSubsystem object for Storage Spaces for use with other commands.
    Get-StorageSubSystem -Model "Storage Spaces";
}

#.ExternalHelp StorageSpaces.psm1-help.xml
function Get-SpacesPhysicalDisk
{
    [CmdletBinding(DefaultParameterSetName="None")]
    param(
    [parameter(Mandatory=$False,
               Position=0)]
    [Switch]
    $OnlyListAvailable,

    [parameter(Mandatory=$False,
               Position=1)]
    [ValidateSet("SAS", "iSCSI", "SATA", "USB")]
    [System.String]
    $BusType,
    
    [parameter(Mandatory=$True,
               ParameterSetName='ByComputerList',
               Position=2)]
    [System.String[]]
    $ServerToCompare,
    
    [parameter(Mandatory=$True, 
               ParameterSetName='ByClusterFriendlyName',
               Position=2)]           
    [System.String]
    $ClusterFriendlyName,
    
    [parameter(Mandatory=$False,
               Position=3)]
    [ValidateRange(1,256)]
    [int]
    $Throttle = 8   
    )

    $ScriptToExecute = 
    {
        Param(
            $OnlyListAvailable,
            $BusType
        )
        $Subsystem = Get-StorageSubSystem -Model "Storage Spaces"
        
        # By default, return all physical disks from the spaces subsystem
        $PhysicalDisks = @(Get-PhysicalDisk -StorageSubSystem $Subsystem)

        # If -OnlyListAvailable is specified, return only the available Physical Disks for pool creation.
        if ($OnlyListAvailable -eq $True)
        {
            $PhysicalDisks = @($PhysicalDisks | Where-Object {$_.CanPool -eq $true})
        }
        
        # If -BusType Was specified, only return physical disks of that bustype.
        if (![String]::IsNullOrEmpty($BusType))
        {
            $PhysicalDisks = @($PhysicalDisks | Where-Object {$_.Bustype -eq $BusType})
        }

        return $PhysicalDisks
    }
    
    # We always need local disks information.
    # Invoking command without server parameter is much faster.
    $LocalDisks = @(Invoke-Command -ScriptBlock $ScriptToExecute -ArgumentList $OnlyListAvailable,$BusType)
    if ($LocalDisks -eq $null)
    {
        Write-Error $SCStringTable.RSDNotObtained
        Return $null
    }
    
    # See where the nodes are from
    $NodesType = $null
    if ($ServerToCompare -ne $null -AND $ServerToCompare.Count -gt 0)
    {
        $NodesType = 'ByComputerList'
    }
    elseif (![String]::IsNullOrEmpty($ClusterFriendlyName))
    {
        $NodesType = 'ByClusterFriendlyName'
    }
    else
    {
        Return $LocalDisks
    }
    
    # Now obtain a list of nodes from the cluster
    if ($NodesType -eq 'ByClusterFriendlyName')
    {
        #Import-Module FailoverClusters
        $Nodes = Get-ClusterNode -Cluster $ClusterFriendlyName
        if ($Nodes -eq $null)
        {
            Write-Error "Unable to retrieve node list from cluster with friendly name $($ClusterFriendlyName)";
            Return $null
        }
        
        foreach ($Node in $Nodes)
        {
            $ServerToCompare += $Node.Name
        }
    }

    # Add domain support    
    $Domain = (gwmi Win32_ComputerSystem).Domain   
    [System.String[]] $ServerToCompareWithDomain = $null

    foreach ($Server in $ServerToCompare)
    { 
        if ($Server -ne 'LocalHost') 
        {
            $ServerToCompareWithDomain += $Server+'.'+$Domain
        }
        else
        {
            $ServerToCompareWithDomain += $Server
        }
    }
    
    # Test to see if Ps Remoting is enabled on each node
    foreach ($Node in $ServerToCompareWithDomain)
    {
        if(!(Test-PsRemoting -ComputerName $Node))
        {
            Write-Error $($SCStringTable.RemoteNotEnabled -f $Node, "Enable-PSRemoting")
            Return $null
        }
    }

    # When cluster information is presented, run the script on each servers, assuming all priviledges have been granted.
    $RemoteDisks = @(Invoke-Command -Throttle $Throttle -ComputerName $ServerToCompareWithDomain -ScriptBlock $ScriptToExecute  -ArgumentList $OnlyListAvailable,$BusType)
    if ($RemoteDisks -eq $null)
    {
        Write-Error $SCStringTable.RSDNotObtained
        Return $null
    }
    
    # Obtain a list of all the common disks
    # We don't distinguish localhost and local computer's name. Users should avoid this situation.
    $CommonRemoteDisks = $RemoteDisks | Group-Object UniqueId -AsHashTable
    $CommonLocalDisks = @($LocalDisks | Where-Object{$CommonRemoteDisks[$_.UniqueId].Count -eq $ServerToCompareWithDomain.Count})

    Return $CommonLocalDisks

    
}

#.ExternalHelp StorageSpaces.psm1-help.xml
function New-SpacesPool
{
    [CmdletBinding(ConfirmImpact="High")]
    param(

    [parameter(Mandatory=$true,
               Position=0)]
    [System.String]
    $FriendlyName,

    [Parameter(Mandatory=$true,
               ValueFromPipeline=$true,
               ValueFromPipelineByPropertyName=$true,
               ParameterSetName='ByDiskArray',
               Position=1)]
    [System.Object[]]
    $PhysicalDisks,
    
    [parameter(Mandatory=$true,
               ParameterSetName='ByLocalStorage',
               Position=1)]
    [ValidateRange(3,100)]
    [System.Int32]
    $NumberofPhysicalDiskstoUse,

    [parameter(Mandatory=$false,
               Position=2)]
    [ValidateRange(1,10)]
    [System.Int32]
    $NumberOfHotsparesToUse
    )
    
    # Process block will be executed once for each pipeline object, so we accumulate and put disk array into $DisksToUse.
    
    PROCESS
    {
         if ($PhysicalDisks)
        {
            $DisksToUse += $PhysicalDisks;
        }       
    }

    END
    {
        $SubSystem = Get-SpacesSubsystem;
        
        if ($DisksToUse)
        {
            if (@($DisksToUse).Count -lt ($NumberOfHotsparesToUse + 3))
            {
                Write-Error $SCStringTable.MinNumOfPD;
                break;
            }
            $DisksToUse = @($DisksToUse);
        }
        else
        {
            # Check to see if the total of used physical disks is greater than 100.
            if ($NumberOfPhysicalDisksToUse -gt 100)
            {
                Write-Error $SCStringTable.MaxNumOfPD;
                break;
            }
            
            # It's required to have at least 3 physical disks in the clustered pool
            if (($NumberOfPhysicalDisksToUse - $NumberOfHotsparesToUse) -lt 3)
            {
                Write-Error $SCStringTable.MinNumOfPD
                break;
            }

            # Locate the Storage Subsystem object for Windows Storage spaces to use as an input for Storage Pool creation.
            $DisksTemp = @(Get-PhysicalDisk -StorageSubsystem $Subsystem -CanPool $True);

            if ($DisksTemp.Count -lt $NumberOfPhysicalDisksToUse)
            {
                Write-Error $SCStringTable.NotEnoughPhysicalDisk
                break;
            }

            $DisksToUse = ($DisksTemp[0..($NumberofPhysicalDiskstoUse -1)]);
        }

        # Create the Storage Pool by utilizing the $DiskstoUse and $Subsystem variables created previously.
        Write-Verbose $SCStringTable.CreatePool;

        if ($NumberOfHotsparesToUse -eq 0)
        {
            $Pool = New-StoragePool -InputObject $Subsystem -FriendlyName $Friendlyname -PhysicalDisks $DisksToUse;
        }
        else
        {
            # Use the Physical Disks minus the number of hotspares to create the pool.
            $PhysicalDisksForPool = ($DisksToUse[0..($DisksToUse.Count-1-$NumberOfHotsparesToUse)]);

            # Use the remaining Physical Disks in the array for hotspares.
            $HotSparePDObjects    = ($DisksToUse[-$NumberOfHotsparesToUse..-1]);

            $CreatedStoragePool = New-StoragePool -InputObject $Subsystem -FriendlyName $Friendlyname -PhysicalDisks $PhysicalDisksForPool;
            $CreatedStoragePool | Add-PhysicalDisk -PhysicalDisks $HotSparePDObjects -Usage HotSpare;
            
            #Refresh pool information
            $Pool = Get-StoragePool -FriendlyName $Friendlyname
        }
    
        $Pool
    }
}

#.ExternalHelp StorageSpaces.psm1-help.xml
Function Get-SpacesVolume
{
    param(  
    [parameter(Mandatory=$false,
               Position=0)]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $SpaceFriendlyName,
    
    [parameter(Mandatory=$False,
               Position=1)]
    [Switch]
    $Cluster
    )
    
    # The following script block inputs space object and returns $StorageSpaces object.
    # In case of cluster, it will be executed remotely.
    $ScriptToExecute = 
    {
        param( $VirtualDisk )
        

        if ($VirtualDisk -eq $null)
        {
            Write-Error "Virtual disk parameter cannot be null to execute ScriptToExecute."
            return $null
        }

        $StorageSpaces = New-Object Object
        
        # The input parameter is an incomplete space object if the space clustered. Now obtain the full information on the owner node.
        $Space = Get-VirtualDisk -UniqueId  $VirtualDisk.UniqueId
        if ($Space)
        {
            $StorageSpaces | Add-Member "OperationalStatus"     -Value $Space.OperationalStatus     -MemberType NoteProperty;
            $StorageSpaces | Add-Member "HealthStatus"          -Value $Space.HealthStatus          -MemberType NoteProperty;
        }
        else
        {
            Write-Warning "Failed to obtain full information on the owner node for space $($VirtualDisk.FriendlyName)."
        }        
        
        $Diskobj       = Get-Disk -VirtualDisk $VirtualDisk -ErrorAction "silentlycontinue"
        if ($Diskobj -eq $null)
        {
            Write-Warning "No disk is found on the space $($VirtualDisk.FriendlyName). This is expected for Cluster Shared Volumes."
        }
        else
        {
            $StorageSpaces | Add-Member "DiskUniqueID"  -Value $DiskObj.UniqueID    -MemberType NoteProperty;        
            
            $Volumeobj     = Get-Partition -Disk $DiskObj -ErrorAction "silentlycontinue" | Where{$_.Type -eq "Basic"} | Get-Volume -erroraction "silentlycontinue"
            if ($Volumeobj -eq $null)
            {
                Write-Warning "No volume is found on the disk $($VirtualDisk.FriendlyName)."
            }
            else
            {
                $StorageSpaces | Add-Member "DriveLetter"       -Value $VolumeObj.DriveLetter      -MemberType NoteProperty;
                $StorageSpaces | Add-Member "VolumeSize"        -Value $VolumeObj.Size             -MemberType NoteProperty;
                $StorageSpaces | Add-Member "SizeRemaining"     -Value $VolumeObj.SizeRemaining    -MemberType NoteProperty;
                $StorageSpaces | Add-Member "VolumeObjectID"    -Value $VolumeObj.ObjectID         -MemberType NoteProperty;
                $StorageSpaces | Add-Member "FileSystem"        -Value $VolumeObj.FileSystem       -MemberType NoteProperty;
            }
        }
        
        $Backdisks   = $VirtualDisk | Get-PhysicalDisk | ForEach-Object {$_.FriendlyName}
        $StorageSpaces | Add-Member "BackingPhysicalDisks"  -Value $BackDisks   -MemberType NoteProperty;

        return $StorageSpaces
    }
    
    
    # Obtain all the local spaces conforming the criteria.
    if ([String]::IsNullOrEmpty($SpaceFriendlyName))
    {
        $Space = Get-VirtualDisk -StorageSubsystem (Get-SpacesSubsystem)
    }
    else
    {
        $Space = Get-VirtualDisk -FriendlyName $SpaceFriendlyName
    }
    if ($Space -eq $null)
    {
        Write-Verbose $SCStringTable.NoSpaceFound
        Break
    }

    # For each space, returns their information. 
    # In case that this space belongs to a cluster, return information from its owner node.
    foreach ($Object in $Space)
    {
        # Collect pool information about the space object passed.
        $Pool = Get-StoragePool -VirtualDisk $Object
        if ($Pool -eq $null)
        {
            Write-Error $SCStringTable.CannotObtainPool
            return
        }
        
        # Check if we need to handle cluster information
        if ($Cluster)
        {
            if (($Pool.IsClustered) -and ((CheckForServerSKU) -eq $True))
            {
                #Import-Module FailoverClusters
                
                try
                {   
                    $ClusterNodes = Get-ClusterNode -ErrorAction "Stop"
                    
                    # Check if every cluster node has enabled remote management
                    $Domain = (gwmi Win32_ComputerSystem).Domain
                    foreach ($Node in $ClusterNodes)
                    {
                        if (!(Test-PsRemoting -ComputerName ($Node.Name+'.'+$Domain)))
                        {
                            Write-Error $($SCStringTable.EnableRemote -f "Enable-PSRemoting", $($Node.Name))
                            return
                        }
                    }
                    
                    # Find the CSV information
                    $CSVInfo = Get-ClusterCSVFromStorageSpace -VirtualDisk $Object -ErrorAction "Stop"
                    if ($CSVInfo -eq $null)
                    {
                        # If New-SpacesVolume is called without CreateClusterSharedVolume switch, we'll come here. It's OK to go ahead without CSV information.
                        Write-Warning "Null information of CSV is obtained. Space with friendly name $($Object.FriendlyName) is not a cluster shared volume."
                    }
                    
                    # Find the pool owner
                    $PoolOwner = Get-ClusterPoolOwner -StoragePool $Pool -ErrorAction "Stop"
                    if ($PoolOwner -eq $null)
                    {
                        Write-Error $SCStringTable.NullPoolOwnerInfo
                        Continue
                    }

                    # Execute $ScriptToExecute on the owner node remotely to collect information, even though local host is the owner.
                    $StorageSpaces = Invoke-Command -ComputerName ($PoolOwner.ClusterOwnerNode+'.'+$Domain) -ScriptBlock $ScriptToExecute -ArgumentList $Object -ErrorAction "Stop"
                    if ($StorageSpaces -eq $null)
                    {
                        Write-Error "Invoke-Command "
                        Write-Error $($SCStringTable.OnNodeNull -f $($($PoolOwner.ClusterOwnerNode)+'.'+$Domain))
                        Continue
                    }
                    
                    # We need to provide Cluster Related information in the existing object.
                    if ($CSVInfo -ne $null)
                    {
                        $StorageSpaces | Add-Member "ClusterCSVResourceName"         -Value $CSVInfo.Name            -MemberType NoteProperty;
                        $StorageSpaces | Add-Member "ClusterResourceState"           -Value $CSVInfo.State           -MemberType NoteProperty;
                        $StorageSpaces | Add-Member "CurrentClusterNodeOwner"        -Value $CSVInfo.OwnerNode.Name  -MemberType NoteProperty;
                    }
                }
                catch
                {
                    Write-Verbose $_
                    Continue
                }
            }            
            else 
            {
                # When -Cluster is on, we don't return non-clustered space information.
                Continue
            }      
        }
        else
        {
            # When -Cluster is off, only return local space information.
            if ($Pool.IsClustered)
            {
                Write-Warning "Please run again with -Cluster switch to obtain information of clustered space with friendly name $($Object.FriendlyName)."
                Continue
            }
            else
            {
                $StorageSpaces = Invoke-Command -ScriptBlock $ScriptToExecute -ArgumentList $Object
                if ($StorageSpaces -eq $null)
                {
                    Write-Error "Invoke-Command "
                    Write-Error $SCStringTable.LocallyNull
                    Continue
                }
            }
        }        
        
        # Append local information here.
        $StorageSpaces | Add-Member "PoolFriendlyName"               -Value $Pool.FriendlyName          -MemberType NoteProperty;
        $StorageSpaces | Add-Member "SpaceFriendlyName"              -Value $Object.FriendlyName        -MemberType NoteProperty;
        $StorageSpaces | Add-Member "StorageSpaceUniqueID"           -Value $Object.UniqueID            -MemberType NoteProperty;
        $StorageSpaces | Add-Member "IsManualAttach"                 -Value $Object.IsManualAttach      -MemberType Noteproperty;
        $StorageSpaces | Add-Member "DetachedReason"                 -Value $Object.DetachedReason      -MemberType Noteproperty; 
        $StorageSpaces | Add-Member "SpaceUsageAlertPercentage"      -Value $Pool.ThinProvisioningAlertThresholds   -MemberType NoteProperty;
        
        # Return storage space object
        $StorageSpaces
    }
}

#.ExternalHelp StorageSpaces.psm1-help.xml
function New-SpacesVolume
{
    [CmdletBinding(
        SupportsShouldProcess=$True,
        ConfirmImpact="High"
    )]

    param(
    [parameter(Mandatory=$true,
               Position=0)]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $StoragePoolFriendlyName,

    [parameter(Mandatory=$true,
               Position=1)]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $SpaceFriendlyName,

    [parameter(Mandatory=$true,
               Position=2)]
    [ValidateRange(1073741824,69268158808064)]
    [System.String]
    $Size,

    [parameter(Mandatory=$true,
               Position=3)]
    [ValidateSet("Simple", "Mirror", "Parity")]
    [System.String]
    $ResiliencyType,

    [parameter(Mandatory=$True,
               Position=4)]
    [ValidateSet('Fixed', 'Thin')]
    [System.String]
    $ProvisioningType,
    
    [parameter(
        Mandatory=$False,
        ValueFromPipeline=$true,
        ValueFromPipelineByPropertyName=$true,
        Position=5)]
    [ValidateNotNullOrEmpty()]
    [System.Char]
    $DriveLetterToUse,
    
    [parameter(Mandatory=$False,
               Position=6)]
    [Switch]
    $MaximumColumnCount,

    [parameter(Mandatory=$False,
               Position=7)]
    [System.UInt64]
    $InterleaveBytes,
    
    [parameter(Mandatory=$False,
               Position=8)]
    [ValidateSet('4KB', '8KB', '16KB', '32KB', '64KB')]
    [System.String]
    $ClusterSize,
    
    [parameter(Mandatory=$False,
               Position=9)]
    [Switch]
    $CreateClusterSharedVolume,
    
    [parameter(Mandatory=$False,
               Position=10)]
    [ValidateSet('NTFS', 'ReFS')]
    [System.String]
    $FileSystem    
    )

    # Verify parameters format first
    if (![String]::IsNullOrEmpty($DriveLetterToUse))
    {
        # This parameter doesn't have ':' ending. We expect the input is from Get-AvailableDriveLetter.
        $UsedDriveLetters = @(Get-Volume | % { "$([char]$_.DriveLetter)"}) + @(Get-WmiObject -Class Win32_MappedLogicalDisk|%{$([char]$_.DeviceID.Trim(':'))});
        if ($UsedDriveLetters | Where{$_ -eq $DriveLetterToUse})
        {
            Write-Error "Parameter DriveLetterToUse=$($DriveLetterToUse) is not valid. It's already in use."
            Return
        }
    }
    
    $Pool = Get-StoragePool -FriendlyName $StoragePoolFriendlyName;
    if ($Pool -eq $null)
    {
        Write-Error $($SCStringTable.NameNotFound -f $StoragePoolFriendlyName)
        Return
    }

    $IsPoolClustered = ($Pool.IsClustered) -and ((CheckForServerSKU) -eq $True)
    
    if ($IsPoolClustered -and ($ProvisioningType -eq "Thin"))
    {
        Write-Error $($SCStringTable.ProvisioningTypeClustered -f "FIXED")
        Return
    }

    if ($CreateClusterSharedVolume)
    {
        if ($FileSystem -eq 'ReFS')
        {
            Write-Error "Cluster Shared Volume cannot be formatted with ReFS."
            Return
        }
        if (!$IsPoolClustered)
        {
            Write-Error "Cluster Shared Volume can only be created in a clustered pool."
            Return
        }
    }
    
    # If the pool that we are operating on is clustered, we should move cluster resource owner to current node
    if ($IsPoolClustered)
    {
        #Import-Module FailoverClusters

        try
        {
            $ErrorActionPreference = "Stop"
        
            # Check if every cluster node has enabled remote management
            $Domain = (gwmi Win32_ComputerSystem).Domain
            $ClusterNodes = Get-ClusterNode
            foreach ($Node in $ClusterNodes)
            {
                if (!(Test-PsRemoting -ComputerName ($Node.Name+'.'+$Domain)))
                {
                    Write-Error $($SCStringTable.EnableRemote -f "Enable-PSRemoting", $($Node.Name))
                    Return
                }
            }
            
            # Find the pool owner
            $PoolOwner = Get-ClusterPoolOwner -StoragePool $Pool
            $CurrentNode = (gwmi Win32_ComputerSystem).Name
        
            # If current node is not the cluster resource owner, move the ownership here.
            if ($PoolOwner.ClusterOwnerNode -ne $CurrentNode)
            {
                if ($PSCmdlet.ShouldProcess( "Cluster $($PoolOwner.ClusterResourceName)", "Move cluster"))
                {
                    # Move the ownership
                    $ClusterRes = Get-ClusterResource -Name $PoolOwner.ClusterResourceName
                    Move-ClusterGroup -Name $ClusterRes.OwnerGroup.Name -Node $CurrentNode | Out-Null
                }
                else
                {
                    Return
                }
            }
        }
        catch
        {
            Write-Verbose $_
            Return        
        }
        
    }

    # Now that current node is the cluster resource owner, we can operate locally.
    try
    {    
        $ErrorActionPreference = "Stop"
        
        $ColumnParam = $null;
        if ($MaximumColumnCount)
        {
            # Check how many physical disks are used for data store
            $DataPDCount = @(Get-PhysicalDisk -StoragePool $Pool | Where {$_.Usage -eq 'Auto-Select'}).Length;
            
            [System.UInt16] $NumberOfColumns = 1;
            switch ($ResiliencyType)
            {
                "Simple" 
                    {
                        $NumberOfColumns = $DataPDCount;
                        break;
                    }
                "Mirror"
                    {
                        $NumberOfColumns = $DataPDCount / 2;
                        if ($NumberOfColumns -eq 0)
                        {
                            Write-Error "Mirrored space should have at least 2 physical disks."
                            Return
                        }
                        break;
                    } 
                "Parity" 
                    {
                        $NumberOfColumns = 8;
                        if ($DataPDCount -lt 8)
                        {
                            $NumberOfColumns = $DataPDCount;
                        }
                        break;
                    }
            }
            
            $ColumnParam = ' -NumberOfColumns ' + $NumberOfColumns;
        }
        
        $InterleaveParam = $null;
        if ($InterleaveBytes)
        {
            $InterleaveParam = ' -Interleave ' + $InterleaveBytes
        }
    
        Write-Verbose $SCStringTable.CreateSpace
        $NewSpaceCmd = 'New-VirtualDisk -InputObject $Pool' + " -FriendlyName $SpaceFriendlyName -Size $size -ResiliencySettingName $ResiliencyType -ProvisioningType $ProvisioningType $ColumnParam $InterleaveParam";
        Write-Verbose "Executing cmdlet: $NewSpaceCmd"
        $Space = Invoke-Expression -Command $NewSpaceCmd;

        # Without this sleep statement, it can't find the virtual disk because it appears to query before creation completes.
        
        Write-Verbose $SCStringTable.RetreiveObject;
        Start-Sleep -Seconds 10;
        $Disk = Get-Disk -VirtualDisk $Space;

        Write-Verbose $SCStringTable.InitDiskCreatePar;
        Initialize-Disk -InputObject $Disk;
        $Part = New-Partition   -InputObject $Disk -UseMaximumSize;
        write-verbose $SCStringTable.RetreiveCreatedObject
        Start-Sleep -Seconds 5;

        $Part = Get-Partition -DiskId $Part.DiskId -Offset $Part.Offset;
        $Volume =  Get-Volume -Partition $Part;

        $ClusterSizeParam = $null;
        if ($ClusterSize)
        {
            $ClusterSizeParam = ' -ClusterSize (' + $ClusterSize + ')';
        }
        
        # If file system is not designated, use NTFS by default.
        if ([String]::IsNullOrEmpty($FileSystem))
        {
            $FileSystem = 'Ntfs'
        }
        
        Write-Verbose $SCStringTable.FormatVolume;
        $FormatVolumeCmd = '$Volume' + "|Format-Volume -NewFileSystemLabel $SpaceFriendlyName -FileSystem $FileSystem $ClusterSizeParam" + ' -Confirm:$False'
        Write-Verbose "Executing cmdlet: $FormatVolumeCmd"
        Invoke-Expression -Command $FormatVolumeCmd | Out-Null;
        
        if (![String]::IsNullOrEmpty($DriveLetterToUse))
        {
            Add-PartitionAccessPath -InputObject $Part -AccessPath $($DriveLetterToUse+':');
        }
        else
        {
            Add-PartitionAccessPath -InputObject $Part -AssignDriveLetter;
        }
    }
    catch
    {
        Write-Verbose $_
        Return  
    }
    
    # If the pool is clustered, and we are instructed to do so, add the new space object to cluster shared volume. 
    # Then, return the information of the newly created space.
    if ($IsPoolClustered)
    {
        if ($CreateClusterSharedVolume)
        {
            Get-ClusterAvailableDisk -Disk $Disk | Add-ClusterDisk | Add-ClusterSharedVolume | Out-Null
        }
        Get-SpacesVolume -SpaceFriendlyName $SpaceFriendlyName -Cluster
    }
    else
    {
        Get-SpacesVolume -SpaceFriendlyName $SpaceFriendlyName
    }
}

#.ExternalHelp StorageSpaces.psm1-help.xml
function Get-SpacesPool
{
     param(
     [parameter(Mandatory=$False)]
     [System.String]
     $StoragePoolFriendlyName)

     $Subsystem = Get-SpacesSubsystem

     if([String]::IsNullOrEmpty($StoragePoolFriendlyName))
     {
        Get-StoragePool -StorageSubsystem $Subsystem
     }
     else
     {
        Get-StoragePool -StorageSubsystem $Subsystem | Where-object {$_.FriendlyName -eq $StoragePoolFriendlyName}
     }
}

#.ExternalHelp StorageSpaces.psm1-help.xml
function Resize-SpacesVolume
{
    [CmdletBinding(
        SupportsShouldProcess=$True,
        ConfirmImpact="Medium"
    )]

    param(
        [parameter(Mandatory=$true,
                   Position=0)]   
        [ValidateNotNullOrEmpty()]
        [System.String]    
        $SpaceFriendlyName,
        
        [parameter(Mandatory=$true,
                   Position=1)]
        [ValidateRange(1073741824,69268158808064)]
        [System.String]
        $NewSize,

        [parameter(Mandatory=$false,
                   Position=2)]   
        [ValidateNotNullOrEmpty()]
        [System.String]    
        $StoragePoolFriendlyName
    )
    
    # The following script block inputs space object and new size, and then resize the space.
    # In case of cluster, this script will be executed remotely, and the space should have been put into maintenance mode.
    $ScriptToExecute = 
    {
        param( 
            $VirtualDisk,
            $SizeToExtend
            )
        
        # One virtual disk may have multiple partitions, but this cmdlet only addresses one partition with basic type
        $Disk =  Get-Disk -VirtualDisk $VirtualDisk
        if ($Disk -eq $null)
        {
            Write-Error "Windows disk is not found in the given space."
            return
        }
        
        $Partitions = @(Get-Partition -Disk $Disk | Where-Object{$_.Type -eq "Basic"})
        if ($Partitions.Count -ne 1)
        {
            Write-Error "This cmdlet can only deal with virtual disks with one basic partition on it.  Nothing is resized."
            return
        }
        
        Resize-VirtualDisk -InputObject $VirtualDisk -Size $SizeToExtend
        Write-Verbose "Virtual disk has been resized."
        
        # We have to refresh everything
        Update-Disk -InputObject $Disk
        $Disk =  Get-Disk -Number $Disk.Number
        $Partitions = @(Get-Partition -Disk $Disk | Where-Object{$_.Type -eq "Basic"})
        $PartitionSizeRange = $Partitions[0] | Get-PartitionSupportedSize
        Write-Verbose "Maximum available partition size is $($PartitionSizeRange.SizeMax)."
        
        Resize-Partition -InputObject $Partitions[0] -Size $PartitionSizeRange.SizeMax

        Write-Verbose "Partition on virtual disk has been resized."

        return
    }
    
    # Get all the virtual disks confine to the criteria
    if (![String]::IsNullOrEmpty($StoragePoolFriendlyName))
    {
        $Pool = Get-StoragePool -FriendlyName $StoragePoolFriendlyName
        $VirtualDisks = Get-VirtualDisk -StoragePool $Pool
    }
    else
    {
        $VirtualDisks = Get-VirtualDisk
    }
    $VirtualDisks = @($VirtualDisks | Where-Object{$_.FriendlyName -eq $SpaceFriendlyName})

    # This cmdlet can treat only one virtual disk
    if ($VirtualDisks.Count -ne 1)
    {
        Write-Error $SCStringTable.OneObjectOnly
        Break
    }
    
    # This cmdlet only allows to expand the size.
    if ([UInt64]$NewSize -le $VirtualDisks[0].Size)
    {
        Write-Error $SCStringTable.ExpandOnly
        Break
    }    
    
    if ($Pool -eq $null)
    {
        $Pool = Get-StoragePool -VirtualDisk $VirtualDisks[0]
    }
    
    $IsPoolClustered = ($Pool.IsClustered) -and ((gwmi win32_operatingsystem).ProductType -gt 1)
    
    # If this pool is clustered, let its owner node to handle this request
    if ($IsPoolClustered)
    {
        #Import-Module FailoverClusters
        try
        {
            $ErrorActionPreference = "Stop"
            $Domain = (gwmi Win32_ComputerSystem).Domain
            
            # Check if every cluster node has enabled remote management
            $ClusterNodes = Get-ClusterNode
            foreach ($Node in $ClusterNodes)
            {
                if (!(Test-PsRemoting -ComputerName ($Node.Name+'.'+$Domain)))
                {
                    Write-Error $($SCStringTable.EnableRemote -f "Enable-PSRemoting", $($Node.Name))
                    return
                }
            }
            
            # Get CSV info
            $CSVInfo = Get-ClusterCSVFromStorageSpace -VirtualDisk $VirtualDisks[0]
            if ($CSVInfo -eq $null)
            {
                Write-Error "Null information of CSV is obtained. Space with friendly name $($VirtualDisks[0].FriendlyName) is not a cluster shared volume."
                return
            }
            
            # Find the pool owner
            $PoolOwner = Get-ClusterPoolOwner -StoragePool $Pool
            if ($PoolOwner -eq $null)
            {
                Write-Error $SCStringTable.NullPoolOwnerInfo
                return
            }
            
            if ($PSCmdlet.ShouldProcess( "Cluster $($PoolOwner.ClusterResourceName)", "Move cluster"))
            {

                # If the pool and space resources are not on the same node, move the pool resources to the owner node.
                if ($CSVInfo.OwnerNode.Name -ne $PoolOwner.ClusterOwnerNode)
                {
                    $ClusterRes = Get-ClusterResource -Name $PoolOwner.ClusterResourceName
                    Move-ClusterGroup -Name $ClusterRes.OwnerGroup.Name -Node $CSVInfo.OwnerNode.Name | out-null
                }
                
                # Put the space in maintenance mode
                Suspend-ClusterResource -InputObject $CSVInfo | out-null
                
                # Execute $ScriptToExecute on the owner node remotely, even though local host is the owner.
                Write-Verbose $SCStringTable.ResizeSpaceRemotely
                Invoke-Command -ComputerName ($CSVInfo.OwnerNode.Name+'.'+$Domain) -ScriptBlock $ScriptToExecute -ArgumentList $VirtualDisks[0],$NewSize
                Write-Verbose $SCStringTable.RSRFinished
            }
            else
            {
                return
            }
        }
        catch
        {
            Write-Verbose $_
            return
        }
        finally
        {
            # Resume the space from maintenance mode
            if ($CSVInfo)
            {
                Resume-ClusterResource -InputObject $CSVInfo | out-null
            }
        }
    }
    else
    {
        # If the space is not clustered, or not server SKU, we can do this operation locally.
        Invoke-Command -ScriptBlock $ScriptToExecute -ArgumentList $VirtualDisks[0],$NewSize
    }
    
    # Return the operation results.
    Write-Verbose $SCStringTable.ObtainSpaceAfterResize
    if ($IsPoolClustered)
    {
        $ResizedSpace = @(Get-SpacesVolume -SpaceFriendlyName $SpaceFriendlyName -Cluster)
    }
    else
    {
        $ResizedSpace = @(Get-SpacesVolume -SpaceFriendlyName $SpaceFriendlyName)
    }
    
    if ($ResizedSpace.Count -ne 1)
    {
        $ResizedSpace = $ResizedSpace | Where{$_.PoolFriendlyName -eq $Pool.FriendlyName}
    }
    
    $ResizedSpace
}

#.ExternalHelp StorageSpaces.psm1-help.xml
function Get-SpacesConfiguration
{
    param(
    [parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $StoragePoolFriendlyName)

    ########
    # MAIN #
    ########
    
    $FullSpaceDetail = $Null;
    $SpacesConfigOBJ = $Null;
    $Space = $Null;
      
    # Store the Storage Pool object in $PoolOBJ for later use in this function.;
    $PoolOBJ        = Get-StoragePool -FriendlyName $StoragePoolFriendlyName;
    if($PoolOBJ -eq $null)
    {
        Write-Error $SCStringTable.NoNameMatch
        Break
    }
    $SpaceObj       = Get-VirtualDisk -StoragePool $PoolObj;
    $PDObj          = Get-PhysicalDisk -StoragePool $PoolObj;

    # Check to see if this is a Server SKU AND if the pool is clustered before attempting to import the failover clusters module,
    # as this will fail on client SKU's. (Prouduct Type 1 is client, type 2 is Server and it appears 3 is datacenter);
    $IsPoolClustered = ((CheckForServerSKU) -eq $True) -and ($PoolObj.IsClustered);
    
    ##########################
    # Basic Pool Information #
    ##########################

    # Create a new output object, and add basic details;
    $SpacesConfigOBJ  = New-Object Object;
    $SpacesConfigOBJ  | Add-Member "StoragePoolFriendlyName" -Value $StoragePoolFriendlyName                -MemberType NoteProperty;
    $SpacesConfigOBJ  | Add-Member "HealthStatus"            -Value $PoolOBJ.HealthStatus                   -MemberType NoteProperty;
    $SpacesConfigOBJ  | Add-Member "IsReadOnly"              -Value $PoolOBJ.IsReadonly                     -MemberType NoteProperty;
    $SpacesConfigOBJ  | Add-Member "IsClusteredStoragePool"  -Value $PoolOBJ.IsClustered                    -MemberType NoteProperty;
    if ($IsPoolClustered)
    {
        #Import-Module FailoverClusters;
        $ClusterPoolOwner    = Get-ClusterPoolOwner -StoragePool $PoolObj;
        $SpacesConfigOBJ  | Add-Member "ClusterResourceName"     -Value $ClusterPoolOwner.ClusterResourceName   -MemberType NoteProperty;
        $SpacesConfigOBJ  | Add-Member "ClusterOwnerNode"        -Value $ClusterPoolOwner.ClusterOwnerNode      -MemberType NoteProperty;
        $SpacesConfigOBJ  | Add-Member "ClusterResourceState"    -Value $ClusterPoolOwner.ClusterResourceState  -MemberType NoteProperty;
    }

    #############################
    # Detailed Pool Information #
    #############################
    
    # Collect information about the pool;
    [System.Int64]$Allocated = $PoolObj.AllocatedSize;
    [System.Int64]$Total     = $PoolObj.Size;

    #Compute FreeSpace to GB
    [System.Int64] $PoolFreeTemp = ($PoolObj.Size - $PoolObj.AllocatedSize);
    [System.Int64] $PoolFree = ($PoolFreeTemp / 1GB);

    #Compute Freespace percentage
    $PoolFreePercent = (($PoolObj.AllocatedSize / $PoolObj.Size) * 100);
    $PoolUsedPercent = ([Math]::Round($PoolFreePercent, 2));
    $PoolFreeRemainingPercent = (100 - $PoolUsedPercent);

    #Assemble data for prompt
    $PoolName      = $PoolObj.FriendlyName;
    $PoolHealth    = $PoolObj.HealthStatus
    $PoolOpStatus  = $PoolObj.OperationalStatus;
    $SpaceCount    = @($SpaceOBJ).Count;
    [System.String]$AlertPercent = $PoolObj.ThinProvisioningAlertThresholds[0];
    $AlertPercent               = ($AlertPercent + " %");
    
    $PDCount             = @($PDObj).Count;
    $UnhealthyPD         = @($PDObj | Where-object {$_.HealthStatus -ne "Healthy"}).count;
    $UnhealthySpaces     = @($SpaceOBJ | Where-Object {$_.HealthStatus -ne "Healthy"}).count;

    # Add the details collected to the output object
    $SpacesConfigOBJ | Add-Member "ThinProvisionAlertThreshold"    -Value $AlertPercent              -MemberType NoteProperty;
    $SpacesConfigOBJ | Add-Member "StoragePoolFreeGigabytes"       -Value $PoolFree                  -MemberType NoteProperty;
    $SpacesConfigOBJ | Add-Member "StoragePoolUsedSpacePercent"    -Value $PoolUsedPercent           -MemberType NoteProperty;
    $SpacesConfigOBJ | Add-Member "StoragePoolFreeSpacePercent"    -Value $PoolFreeRemainingPercent  -MemberType NoteProperty;
    $SpacesConfigOBJ | Add-Member "OperationalStatus"              -Value $PoolOpStatus              -MemberType NoteProperty;
    $SpacesConfigOBJ | Add-Member "NumberofPhysicalDisksInPool"    -Value $PDcount                   -MemberType NoteProperty;
    $SpacesConfigOBJ | Add-Member "NumberofStorageSpacesInPool"    -Value $SpaceCount                -MemberType NoteProperty;
    $SpacesConfigOBJ | Add-Member "NumberofUnhealthyPhysicalDisks" -Value $UnhealthyPD               -MemberType NoteProperty;
    $SpacesConfigOBJ | Add-Member "NumberofUnhealthyStorageSpaces" -Value $UnhealthySpaces           -MemberType NoteProperty;
    
    # Return the SpacesConfigOBJ with the detailsbefore proceeeding to per-space full details.
    $SpacesConfigOBJ

    ##########################################
    # Information of each space in this pool #
    ##########################################
    
    foreach ($Space in $SpaceOBJ)
    {
        $FullSpaceDetail = New-Object Object;
        
        # If the pool is clustered, we should get space information from its owner node
        if ($IsPoolClustered)
        {
            $FullSpaceDetail = Get-SpacesVolume -SpaceFriendlyName $Space.FriendlyName -Cluster;
        }
        else
        {
            $FullSpaceDetail = Get-SpacesVolume -SpaceFriendlyName $Space.FriendlyName;
        }
        
        # It's possible that Get-SpacesVolume returns multiple spaces having same name from different pools
        if (@($FullSpaceDetail).Count -gt 1)
        {
            $FullSpaceDetail = $FullSpaceDetail | Where{$_.PoolFriendlyName -eq $StoragePoolFriendlyName};
        }
        
        $FullSpaceDetail
    }
    
}

#.ExternalHelp StorageSpaces.psm1-help.xml
Function Test-SpacesConfiguration
{
    param(
        [parameter(Mandatory=$true,
                   Position=0,
                   ParameterSetName='ByName')]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $StoragePoolFriendlyName,

        [parameter(Mandatory=$True,
                   Position=0,  
                   ParameterSetName='ByPool')]
        [Microsoft.Management.Infrastructure.CimInstance]
        [PSTypeName("Microsoft.Management.Infrastructure.CimInstance#MSFT_StoragePool")]
        $StoragePool,
        
        [parameter(Mandatory=$False,
                   Position=1)]
        [Switch]
        $Passthru
    )
    
    # Force a cache update to ensure we have the most recent state before querying the health status.
    $Subsystem = Get-SpacesSubsystem
    Update-StorageProviderCache -DiscoveryLevel Full -StorageSubSystem $SubSystem
    Update-HostStorageCache

    # Check to see if we already have a pool object to avoid re-query to the API.
    if (![String]::IsNullOrEmpty($StoragePoolFriendlyName))
    {
        $PoolObJ = Get-StoragePool -Friendlyname $StoragePoolFriendlyName;
    }
    else
    {
        $PoolObJ = $StoragePool;
    }    
    
    if ($PoolObJ -eq $null)
    {
        Write-Error $SCStringTable.PoolNotFound
        Return $false
    }
    
    ###################
    # Pool Collection #
    ###################
    Write-Verbose $SCStringTable.ProcessPool; 

    if (($PoolObJ.HealthStatus -ne "Healthy") -or ($PoolObJ.OperationalStatus -ne "OK"))
    {
        Write-Warning $SCStringTable.PoolUnhealthy
        
        if ($Passthru)
        {
            $PoolHealthObj  = New-Object Object
            $PoolHealthObj  | Add-Member "StoragePoolFriendlyName"        -Value $PoolObj.FriendlyName                  -MemberType NoteProperty;  
            $PoolHealthObj  | Add-Member "StoragePoolHealthStatus"        -Value $PoolObj.HealthStatus                  -MemberType NoteProperty; 
            $PoolHealthObj  | Add-Member "StoragePoolOperationalStatus"   -Value $PoolObJ.OperationalStatus             -MemberType NoteProperty; 
            $PoolHealthObj  | Add-Member "StoragePoolUniqueID"            -Value $PoolObJ.UniqueID                      -MemberType NoteProperty; 
            $PoolHealthObj  | Add-Member "StoragePoolIsReadOnly"          -Value $PoolObJ.IsReadOnly                    -MemberType NoteProperty;

            $PoolHealthObj
        }
        else
        {
            Return $false
        }
    }
    else
    {
        # If pool is healthy, it means all the spaces and disks are healthy. No need to do further check.
        Write-Host $SCStringTable.AllHealthy
        Return $true
    }
    
    # $Passthru should be true if we reach here.

    ####################
    # Space Collection #
    ####################
    Write-Verbose $SCStringTable.CollectSpace;
    
    $IsPoolClustered = ((gwmi win32_operatingsystem).ProductType -gt 1)  -and ((($PoolObJ.IsClustered) -eq $True));
    
    $SpacesObj = Get-VirtualDisk -StoragePool $PoolObJ
    foreach ($Object in $SpacesObj)
    {
        $Space = Get-SpacesVolume -SpaceFriendlyName $Object.FriendlyName -Cluster: $IsPoolClustered;
        if (($Space.HealthStatus -ne "Healthy") -or ($Space.OperationalStatus -ne "OK"))
        {
            # Determine if the Space is detached, and whether it appears to be clustered.            
            $SpaceIsDetached = ($Space.IsManualAttach -eq $true) -and ($Space.DetachedReason -ne "None");
            
            $SpaceHealthObj = New-Object Object
            $SpaceHealthObj | Add-Member "StorageSpaceFriendlyName"        -Value $Space.SpaceFriendlyName      -MemberType NoteProperty;
            $SpaceHealthObj | Add-Member "StorageSpaceHealthStatus"        -Value $Space.HealthStatus           -MemberType NoteProperty;
            $SpaceHealthObj | Add-Member "StorageSpaceOperationalStatus"   -Value $Space.OperationalStatus      -MemberType NoteProperty;
            $SpaceHealthObj | Add-Member "StorageSpaceUniqueID"            -Value $Space.StorageSpaceUniqueID   -MemberType NoteProperty;
            $SpaceHealthObj | Add-Member "SpaceIsDetached"                 -Value $SpaceIsDetached              -MemberType NoteProperty;
            
            $SpaceHealthObj
        }
    }

    ############################
    # Physical Disk Collection #
    ############################
    Write-Verbose $SCStringTable.CollectPhysicalDisk

    $PDObj = Get-PhysicalDisk -StoragePool ($PoolObJ)
    foreach ($PhysicalDisk in $PDObj)
    {
        if (($PhysicalDisk.HealthStatus -ne "Healthy") -or ($PhysicalDisk.OperationalStatus -ne "OK"))
        {
            $PDHealthObj    = New-Object Object
            $PDHealthObj | Add-Member "PhysicalDiskFriendlyName"        -Value $PhysicalDisk.FriendlyName           -MemberType NoteProperty
            $PDHealthObj | Add-Member "PhysicalDiskHealthStatus"        -Value $PhysicalDisk.HealthStatus           -MemberType NoteProperty 
            $PDHealthObj | Add-Member "PhysicalDiskOperationalStatus"   -Value $PhysicalDisk.OperationalStatus      -MemberType NoteProperty
            $PDHealthObj | Add-Member "PhysicalDiskUniqueID"            -Value $PhysicalDisk.UniqueID               -MemberType NoteProperty
            
            $PDHealthObj
        }
    }
    
    Return $false
}

#.ExternalHelp StorageSpaces.psm1-help.xml
Function Repair-SpacesConfiguration
{

    [CmdletBinding(
        SupportsShouldProcess=$False)]
    param()
    
    # Collect a list of all pools which are not clustered, and not primordial from the Storage Spaces Subsystem.
    write-Verbose "Collection Storage Pool information..."
    $RepairablePools =@(Get-StorageSubSystem -Model *space* | Get-StoragePool -IsPrimordial $False | ? IsClustered -eq $False)
    $NumberRepairablePools = ($RepairablePools).Count

    # Make sure we have pools that are able to be repaired
    if ($NumberRepairablePools -eq "0")
    {
        Write-Error "No non-clustered pools which can be repaired were found" -ErrorAction Stop
    }
    
    # Using the list of repairable pools, get a list of all Storage Spaces.
    Write-Verbose "Collecting Storage Space information..."
    $AllSpaces =@($RepairablePools | Get-VirtualDisk)

    # Check and repair all Read-Only Storage Pools.
    foreach ($StoragePool in $RepairablePools)
    {
        if ($StoragePool.IsReadOnly -eq $True)
        {
            Write-Warning "The selected pool is currently Read-Only, Change the Pool to read/write to allow repairs?" -WarningAction Inquire
            $StoragePool | Set-StoragePool -IsReadOnly $False
        }
    }

    # Check for and repair all manual attach Storage Spaces.
    foreach ($StorageSpace in $AllSpaces)
    {
        if ($StorageSpace.IsManualAttach -eq $True)
        {
            $Name =""
            $Name = $StorageSpace.FriendlyName
            Write-Warning "The Storage Space named $Name is configured to attach manually. Change to Automatic and connect the Storage Space?" -WarningAction Inquire
            $StorageSpace | Set-VirtualDisk -IsManualAttach $False
            $StorageSpace | Connect-VirtualDisk
        }
    }

    # Request repairs for all Storage Spaces across all non-clustered pools
    Write-Verbose "Requesting repairs of all Storage Spaces on all pools"
    $AllSpaces | Repair-VirtualDisk

    # Don't show status if there are not any active repair jobs.
    if (((Get-StorageJob | ? JobState -eq "Running").count) -eq "0")
    {
        Write-Warning "There are no active repair jobs. Exiting" -ErrorAction Stop
    }

    # Compute and display progress for repair jobs.
    if ((Get-StorageJob) -ne $Null)
    {
        # Enter a do-while loop to update repair progress every 2 seconds, as long as their are active repair jobs.
        # Note: This can take a long time if replacing a physical disk.

        do 
        {
            # Store the percent complete for the running repair job.
            $PercentComplete = ((Get-StorageJob | ? JobState -eq "Running").PercentComplete)

            # Need to force $NumJobsRemaining to always be an array so that it reports 1 when there is 1 job remaining.
            $NumJobsRemaining =@((Get-StorageJob | ? JobState -ne "Running").Count)

            # If there are no other jobs remaining, use the word "no" for the number of remaining jobs.
            if (!$NumJobsRemaining)
                {
                    $RemainingJobNumber="No"
                }
            else
                {
                    $RemainingJobNumber = $NumJobsRemaining
                }
            # Display proggress indication
            Write-Progress -Activity "Repairs of the current Storage Space are $PercentComplete percent complete" -PercentComplete $PercentComplete -Status "$NumJobsRemaining addtional repair job(s) remain."
            Start-Sleep -Seconds 2
        }
        while ((Get-StorageJob) -ne $Null)
    }

    # Update the cache so that we have a consistent view of the storage before re-checking the status
    Write-Verbose "Updating cache..."
    Update-HostStorageCache
    Update-StorageProviderCache -DiscoveryLevel Full
     
     # Now that repairs were requested for all Storage Spaces that were not Healthy or InService, we need to refresh the state of these Storage Spaces
     # And re-check their current status.
     $ResultList = ($AllSpaces | Get-VirtualDisk)
     
    foreach ($StorageSpace in $Resultlist)
    {
        # If the Space is not healthy, and not still performing repairs, surface an error message.
        If ($StorageSpace.HealthStatus -ne "Healthy")
        {
            $Name = ""
            $Name = $StorageSpace.FriendlyName
            Write-Error "The Storage Space named $Name is still not healthy and not being repaired, try adding additional physical disks to the pool and try again" -ErrorAction Stop    
        }
    }
}  

#.ExternalHelp StorageSpaces.psm1-help.xml
function Enable-StorageSpacesMpioSupport
{
    # Block running on Client SKUs
    if ((CheckForServerSKU) -eq $False)
    {
        write-Error $SCStringTable.ServerRequired;
        break;
    }

    #Check MPIO Installation State, and Install if not already present
    if (((Get-WindowsOptionalFeature  -Online -FeatureName "MultipathIo").State) -ne "Enabled")
    {
        write-verbose $SCStringTable.InstallMPIO
        Enable-WindowsOptionalFeature -Online -FeatureName "MultiPathIo";
    }
    # Import the MPIO Module
    Import-Module MPIO;

    write-verbose $SCStringTable.EnableAutoClaiming;
    Enable-MSDSMAutomaticClaim -BusType "SAS";

    write-verbose $SCStringTable.SetRoundRobin
    Set-MSDSMGlobalDefaultLoadBalancePolicy -Policy "RR";

    $Result = Get-StorageSpacesMPIOConfiguration
    Return $Result
}

#.ExternalHelp StorageSpaces.psm1-help.xml
function Disable-StorageSpacesMpioSupport
{
    # Block running on Client SKUs
    if ((CheckForServerSKU) -eq $False)
    {
        write-Error $SCStringTable.ServerRequired;
        break;
    }
    
    # Import the MPIO Module
    Import-Module MPIO;

    Disable-MSDSMAutomaticClaim -BusType "SAS";

   $Result = Get-StorageSpacesMpioConfiguration
   Return $Result

}

#.ExternalHelp StorageSpaces.psm1-help.xml
function Get-StorageSpacesMpioConfiguration
{
    # Block running on Client SKUs
    if ((CheckForServerSKU) -eq $False)
    {
        write-Error $SCStringTable.ServerMPIORequired;
        break;
    }
    
    # Import the MPIO Module;
    Import-Module MPIO;

    # Collect required data
    $ClaimState = Get-MSDSMAutomaticClaimSettings;
    $LBPolicy   = Get-MSDSMGlobalDefaultLoadBalancePolicy;

    #Populate values for display
    if ($ClaimState.Sas -eq "True")
    {
        $SASClaimed = $True
    }
    else 
    {
        $SASClaimed = $False
    }
     
    if (($LBPolicy -eq "RR") -and ($SASClaimed -eq $True))
    {
        $OptimalPolicy   = $True
        [String]$PolicyToDisplay = "RR"
    }
    else
    {
        $OptimalPolicy   = $False
        [String]$PolicyToDisplay = $LBPolicy
    }

    # Assemble information for the Output object
    $MPIOSpace = New-Object Object
    $MPIOSpace | Add-Member "SASClaimedByMpio"               -Value $SasClaimed                 -MemberType NoteProperty;
    $MPIOSpace | Add-Member "LBPolicy"                       -Value $PolicyToDisplay            -MemberType NoteProperty;
    $MPIOSpace | Add-Member "PolicyOptimalForSpaces"         -Value $OptimalPolicy              -MemberType NoteProperty;

    return $MPIOSpace | FT -autosize
}

#.ExternalHelp StorageSpaces.psm1-help.xml
function Get-AvailableDriveLetter
{
    param(
    [parameter(Mandatory=$False)]
    [Switch]
    $ReturnFirstLetterOnly)

    $CurentUserPriv = [Security.Principal.WindowsIdentity]::GetCurrent()
    $IsElevated = (New-Object Security.Principal.WindowsPrincipal $CurentUserPriv).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)

    If ($IsElevated -eq $False)
    {
        Write-Error "This command must be run from an elevated PowerShell Window" -ErrorAction Stop
    } 

    #Collect a list of mapped network drives.
    $MappedDrives =@((Get-ChildItem "HKCU:\Network" | Get-ItemProperty).Pschildname)

    #Collect a list of all volumes that have drive letters
    $VolumeDriveLetters=@(Get-Volume | % { "$([char]$_.DriveLetter)"})

    # Get all available drive letters, and store in a temporary variable.
    If ($MappedDrives -ne $Null)
    {
        $UsedDriveLetters =@( @($VolumeDriveLetters) + @($MappedDrives))
    }
    Else 
    {
        $UsedDriveLetters =$VolumeDriveLetters
    }
                
    $TempDriveLetters =@(Compare-Object -DifferenceObject $UsedDriveLetters -ReferenceObject $( 67..90 | % { "$([char]$_)" } ) | ? { $_.SideIndicator -eq '<=' } | % { $_.InputObject })

    # For completeness, sort the output alphabetically
    $AvailableDriveLetter = ($TempDriveLetters | Sort-Object)

    if ($ReturnFirstLetterOnly -eq $true)
    {
        $TempDriveLetters[0]
    }
    else
    {
        $TempDriveLetters
    }
}

#.ExternalHelp StorageSpaces.psm1-help.xml
Function Get-SpacesPoolPhysicalDiskHWCounter
{
    [CmdletBinding(
        SupportsShouldProcess=$False
    )]
    param(  
    [parameter(Mandatory=$True)]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $StoragePoolFriendlyName
    )

    $Pool      = Get-StoragePool -FriendlyName $StoragePoolFriendlyName
    $PoolDisks = $Pool | Get-PhysicalDisk

    foreach ($PhysicalDisk in $PoolDisks)
    {
        $ReliablityData = $PhysicalDisk | Get-StorageReliabilityCounter

        # Assemble the output object 
        $PDRelibilityObj = New-Object "Object"
        $PDRelibilityObj | Add-Member "PhysicalDiskFriendlyName"  -Value $PhysicalDisk.FriendlyName       -MemberType NoteProperty;
        $PDRelibilityObj | Add-Member "PhysicalDiskUniqueID"      -Value $PhysicalDisk.UniqueId           -MemberType NoteProperty;
        $PDRelibilityObj | Add-Member "CurrentTemperatureCelsius" -Value $ReliablityData.Temperature      -MemberType NoteProperty;
        $PDRelibilityObj | Add-Member "PowerOnHours"              -Value $ReliablityData.PowerOnHours     -MemberType NoteProperty;
        $PDRelibilityObj | Add-Member "ReadErrorsTotal"           -Value $ReliablityData.ReadErrorsTotal  -MemberType NoteProperty;
        $PDRelibilityObj | Add-Member "WriteErrorsTotal"          -Value $ReliablityData.WriteErrorsTotal -MemberType NoteProperty;
        $PDRelibilityObj | Add-Member "ReadLatencyMax"            -Value $ReliablityData.ReadLatencyMax   -MemberType NoteProperty;
        $PDRelibilityObj | Add-Member "WriteLatencyMax"           -Value $ReliablityData.WriteLatencyMax  -MemberType NoteProperty;
  
       $PDRelibilityObj;
    }
}

#.ExternalHelp StorageSpaces.psm1-help.xml
Function New-StorageSpacesEventLog 
{
    [CmdletBinding(
        SupportsShouldProcess=$False
    )]
    param()

    # Author: Tobias Klima
    # Organization: Microsoft
    # Last Updated: July 25, 2012

    $JobName = "StorageSpaces Event Monitor"
    $LogName = "StorageSpaces Events"
    $Script_Path = "C:\Windows\System32\WindowsPowerShell\v1.0\Modules\StorageSpaces\Notification_Script.ps1"

    $CurrentPolicy = Get-ExecutionPolicy

    if ($CurrentPolicy -eq "Restricted")
    {
        Write-Error "The PowerShell execution policy must be set to either RemoteSigned or Unrestricted to enable logging of events" -ErrorAction Stop
    }

    # Test if the path to the script file is valid
    if(!(Test-Path $Script_Path))
    {
        Write-Host "The script file NotificationScript.ps1 cannot be found at location:" $Script_Path -ForegroundColor Red
        Write-Host "Exiting ..."

        return
    }

    if ((Get-ScheduledJob -Name "StorageSpaces Event Monitor" -ErrorAction SilentlyContinue) -ne $Null)
    {
        Write-Warning "The scheduled job" $JobName "already exists. In case of issues, uninstall and re-install the script." 
        return
    }

    if ((Get-EventLog * | ? Log -eq "StorageSpaces Event Log" -ErrorAction SilentlyContinue) -ne $Null)
    {
        Write-warning "The log with name" $LogName "already exists. In case of issues, uninstall and re-install the script." 
        return
    }

    # Definte the two job triggers that will start the registered job.
    $JobTriggers = @((New-JobTrigger -AtStartup -RandomDelay 0:01),(New-JobTrigger -Daily -At (Get-Date).AddMinutes(30)))

    # Register a new Job to run at system start-up
    Register-ScheduledJob -FilePath $Script_Path -Name $JobName -Trigger $JobTriggers 

    # Create a new classic event log
    New-EventLog -LogName $LogName -Source $LogName -ErrorAction SilentlyContinue

    Write-Warning "Installation successful, reboot required."
}

#.ExternalHelp StorageSpaces.psm1-help.xml
Function Remove-StorageSpacesEventLog 
{
    [CmdletBinding(
        SupportsShouldProcess=$False
    )]
    param()
    $JobName = "StorageSpaces Event Monitor"
    $LogName = "StorageSpaces Events"

    Write-Warning "Warning, the contents of the StorageSpaces Event Log will be removed." -WarningAction Inquire

    # Check if the uninstall switch is toggled. If yes, unregister the job and delete the log.
    Unregister-ScheduledJob -Name $JobName 
    Start-Sleep -Seconds 5
    Remove-EventLog -LogName $LogName 

    Write-Host "Job unregistered and StorageSpaces event log removed.... uninstall complete." -ForegroundColor Yellow
}

################################################
#                Export CMDlets                #
################################################

Export-ModuleMember Get-SpacesPhysicalDisk
Export-ModuleMember Get-SpacesPool
Export-ModuleMember New-SpacesPool
Export-ModuleMember Get-SpacesVolume
Export-ModuleMember New-SpacesVolume
Export-ModuleMember Get-SpacesConfiguration
Export-ModuleMember Resize-SpacesVolume
Export-ModuleMember Test-SpacesConfiguration
Export-ModuleMember Repair-SpacesConfiguration
Export-ModuleMember Enable-StorageSpacesMpioSupport
Export-ModuleMember Disable-StorageSpacesMpioSupport
Export-ModuleMember Get-SpacesProvider
Export-ModuleMember Get-SpacesSubsystem
Export-ModuleMember Get-StorageSpacesMpioConfiguration
Export-ModuleMember Get-AvailableDriveLetter
Export-ModuleMember Get-SpacesPoolPhysicalDiskHWCounter
Export-ModuleMember New-StorageSpacesEventLog
Export-ModuleMember Remove-StorageSpacesEventLog

