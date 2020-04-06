# StorageSpaces
A PowerShell Module for managing Storage Spaces in Windows.
The StorageSpaces module is a PowerShell module which utilizes the Storage module for Windows PowerShell to provide a streamlined
management experience for Storage Spaces. 

This module provides the ability to easily manage Storage Spaces for single-machine deployments, as well as providing cluster-aware management when
using Storage Spaces in a Windows Failover Cluster.

 When using the StorageSpaces module, you can create a Storage Space and provision the disk in a single step, rather than using multiple cmdlets from the Storage module to do this same workflow in a granular fashion.
 

PowerShell
# Create a Mirror Storage Space that is thinly provisioned, and format a  
# volume on the Storage Space and use letter E on the new Volume. 
 
      New-SpacesVolume -StoragePoolFriendlyName Internal -SpaceFriendlyName  
      MirrorTest -Size (20GB) -ResiliencyType Mirror -ProvisioningType Thin - 
      DriveLetterToUse E  
 
 
# Create a detailed report on the Storage Spaces pool, Storage Spaces, an pool disks 
 
PS C:\WINDOWS\system32> Get-SpacesConfiguration -StoragePoolFriendlyName Backup 
 
 
StoragePoolFriendlyName        : Backup 
HealthStatus                   : Healthy 
IsReadOnly                     : False 
IsClusteredStoragePool         : False 
ThinProvisionAlertThreshold    : 70 % 
StoragePoolFreeGigabytes       : 4442 
StoragePoolUsedSpacePercent    : 60.25 
StoragePoolFreeSpacePercent    : 39.75 
OperationalStatus              : OK 
NumberofPhysicalDisksInPool    : 4 
NumberofStorageSpacesInPool    : 1 
NumberofUnhealthyPhysicalDisks : 0 
NumberofUnhealthyStorageSpaces : 0 
 
OperationalStatus         : OK 
HealthStatus              : Healthy 
DiskUniqueID              : D3568BF49705E211BE6D002522F8BB58 
DriveLetter               : Z 
VolumeSize                : 4947667034112 
SizeRemaining             : 1341698236416 
VolumeObjectID            : \\?\Volume{f48b56da-0597-11e2-be6d-002522f8bb58}\ 
FileSystem                : NTFS 
BackingPhysicalDisks      : {Added-JAN02013, Added-Jan2013(old drive), Added Jan 2012 (Old Drive2), Added-Jan2013-Old} 
PoolFriendlyName          : Backup 
SpaceFriendlyName         : USB-Backup 
StorageSpaceUniqueID      : D3568BF49705E211BE6D002522F8BB58 
IsManualAttach            : False 
DetachedReason            : None 
SpaceUsageAlertPercentage : {70} 
 
# Display information about the health of all pooled disks in a Storage Spaces pool, such as temperature,  read errors, and write errors 
 
PS C:\WINDOWS\system32> Get-SpacesPoolPhysicalDiskHWCounter -StoragePoolFriendlyName Backup  
 
 
PhysicalDiskFriendlyName  : Added Jan 2012 (Old Drive2) 
PhysicalDiskUniqueID      : USBSTOR\Disk&Ven_WDC_WD30&Prod_EZRX-00MMMB0&Rev_\DCA2969546FF&2:Bruce-PC 
CurrentTemperatureCelsius : 33 
PowerOnHours              : 4836 
ReadErrorsTotal           : 0 
WriteErrorsTotal          :  
ReadLatencyMax            : 445 
WriteLatencyMax           : 424 
 
PhysicalDiskFriendlyName  : Added-JAN02013 
PhysicalDiskUniqueID      : USBSTOR\Disk&Ven_WDC_WD30&Prod_EZRX-00MMMB0&Rev_\DCA2969546FF&0:Bruce-PC 
CurrentTemperatureCelsius : 32 
PowerOnHours              : 1756 
ReadErrorsTotal           : 0 
WriteErrorsTotal          :  
ReadLatencyMax            : 444 
WriteLatencyMax           : 429 
 
PhysicalDiskFriendlyName  : Added-Jan2013(old drive) 
PhysicalDiskUniqueID      : USBSTOR\Disk&Ven_WDC_WD30&Prod_EZRX-00MMMB0&Rev_\DCA2969546FF&1:Bruce-PC 
CurrentTemperatureCelsius : 33 
PowerOnHours              : 3002 
ReadErrorsTotal           : 0 
WriteErrorsTotal          :  
ReadLatencyMax            : 638 
WriteLatencyMax           : 862 
 
PhysicalDiskFriendlyName  : Added-Jan2013-Old 
PhysicalDiskUniqueID      : USBSTOR\Disk&Ven_WDC_WD30&Prod_EZRX-00MMMB0&Rev_\DCA2969546FF&3:Bruce-PC 
CurrentTemperatureCelsius : 34 
PowerOnHours              : 5427 
ReadErrorsTotal           : 0 
WriteErrorsTotal          :  
ReadLatencyMax            : 715 
WriteLatencyMax           : 426
