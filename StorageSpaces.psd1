###########################################################################
# Created by:   Bruce Langworthy                                          #
# Organization: Microsoft                                                 #
#-------------------------------------------------------------------------#
# Module Manifest                                                         #
#-------------------------------------------------------------------------#
# Module Name: StorageSpaces                                              #
###########################################################################
@{

# Script module or binary module file associated with this manifest
ModuleToProcess = '.\StorageSpaces.psm1'

# Version number of this module.
ModuleVersion = '1.0.0.0'

# ID used to uniquely identify this module
GUID = 'd84e3c43-eea6-471e-ad89-68beae6f1482'

# Author of this module
Author = 'Microsoft Corporation'

# Company or vendor of this module
CompanyName = 'Microsoft Corporation'

# Copyright statement for this module
Copyright = '(c) Microsoft Corporation. All rights reserved.'

# Description of the functionality provided by this module
Description = 'Provides management of Storage Spaces via Windows PowerShell'

# Minimum version of the Windows PowerShell engine required by this module
PowerShellVersion = '3.0'

# Name of the Windows PowerShell host required by this module
PowerShellHostName = ''

# Minimum version of the Windows PowerShell host required by this module
PowerShellHostVersion = ''

# Processor architecture (None, X86, Amd64, IA64) required by this module
ProcessorArchitecture = 'None'

# Modules that must be imported into the global environment prior to importing
# this module
RequiredModules = @('Storage')

# Assemblies that must be loaded prior to importing this module
RequiredAssemblies = @()

# Script files (.ps1) that are run in the caller's environment prior to
# importing this module
ScriptsToProcess = @()

# Type files (.ps1xml) to be loaded when importing this module
TypesToProcess = @()

# Format files (.ps1xml) to be loaded when importing this module
FormatsToProcess = @()

# Modules to import as nested modules of the module specified in
# ModuleToProcess
NestedModules = @()

# Functions to export from this module
FunctionsToExport = '*'

# Cmdlets to export from this module
CmdletsToExport = '*'

# Variables to export from this module
VariablesToExport = '*'

# Aliases to export from this module
AliasesToExport = '*'

# List of all modules packaged with this module
ModuleList = @()

# List of all files packaged with this module
FileList = @()

# Private data to pass to the module specified in ModuleToProcess
PrivateData = ''

# Help link for updatable help
HelpInfoURI = "http://go.microsoft.com/fwlink/p/?LinkID=237119"

}
