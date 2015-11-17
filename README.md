# Get-FirmwareType
Chris Warwick, @cjwarwickps, November 2015

The function in this module determines the underlying system firmware (BIOS) type - either UEFI or Legacy BIOS.

Script Structure
----------------

This Get-FirmwareType function uses three techniques (in helper functions) to determine the underlying machine firmware type, either checking the firmware type recorded by Windows setup or using one of two Win32 APIs that are called from PowerShell through a compiled (Add-Type) class using P/Invoke.

1. The first method relies on the fact that Windows setup detects the firmware type as a part of the Windows installation routine and records its findings in the setupact.log file in the \Windows\Panther folder.  It's a trivial task to use Select-String to extract the relevant line from this file and to pick off the (U)EFI or BIOS keyword it contains.  This technique should work on all versions on Windows.
   
2. For Windows 7/Server 2008R2 and above, the GetFirmwareEnvironmentVariable Win32 API (designed to extract firmware environment variables) can be used.  This API is not supported on non-UEFI firmware and will fail in a predictable way when called - this will identify a legacy BIOS.  On UEFI firmware, the API can be called with dummy parameters, and while it will still fail the resulting error code will be different from the legacy BIOS case.

3. For Windows 8/Server 2012 and above there's a more elegant solution in the form of the GetFirmwareType() API.  This returns an enum (integer) indicating the underlying firmware type.

Get-FirmwareType will use one of the above methods based on the version of the Windows OS. Alternatively, the method can be explicitly selected using the -QueryType parameter.

Refer to further notes in the script about the Win32 APIs being used here.
   

Script Help
-----------
````

<#
.Synopsis
    This cmdlet determines the underlying system firmware (BIOS) type - either UEFI or Legacy BIOS.
.Description
    This cmdlet determines the underlying system firmware (BIOS) type - either UEFI or Legacy BIOS.

    The function will use one of three methods to determine the firmware type:

    The first method relies on the fact that Windows setup detects the firmware type as a part of the Windows installation
    routine and records its findings in the setupact.log file in the \Windows\Panther folder.  It's a trivial task to use
    Select-String to extract the relevant line from this file and to pick off the (U)EFI or BIOS keyword it contains.
    
    To do a proper job there are two choices; both involve using Win32 APIs which we call from PowerShell through a compiled
    (Add-Type) class using P/Invoke.
    
    For Windows 7/Server 2008R2 and above, the GetFirmwareEnvironmentVariable Win32 API (designed to extract firmware environment
    variables) can be used.  This API is not supported on non-UEFI firmware and will fail in a predictable way when called - this 
    will identify a legacy BIOS.  On UEFI firmware, the API can be called with dummy parameters, and while it will still fail 
    (probably!) the resulting error code will be different from the legacy BIOS case.
    
    For Windows 8/Server 2012 and above there's a more elegant solution in the form of the GetFirmwareType() API.  This
    returns an enum (integer) indicating the underlying firmware type.
.Example
    Get-FirmwareType
    Determines the firmware type of the current machine using the most appropriate technique based on OS version
.Example
    Get-FirmwareType -Auto
    Determines the firmware type of the current machine using the most appropriate technique based on OS version
.Example
    Get-FirmwareType -SetupLog
    Determines the firmware type of the current machine by reading the Setup log file
.Example
    Get-FirmwareType -GetFirmwareType
    Determines the firmware type of the current machine by using the GetFirmwareType() API call. (Windows 8+ only)
.Inputs
    None
.Outputs
    ['FirmwareType'] PS Custom object describing the machine firmware type
.Parameter QueryType
    Use this parameter to force a particular query type (if not specified this will default to 'Auto')
    Valid values are: 
     SetupLog - look for the machine firmware type in the Windows Setup log file
     GetFirmwareEnvironmentVariable - uses the GetFirmwareEnvironmentVariable Win32 API call (Windows 7/Server 208R2 and above)
     GetFirmwareType - uses the GetFirmwareType Win32 API call (Windows 8/Server 2012R2 and above)
     Auto - uses the most appropriate technique depending on the underlying OS version
.Notes
    Can only run against the local machine currently
.Functionality
    Determine the firmware type of the current machine
#>


````

Sample Output
-------------


````

PS:> Get-FirmwareType

IsUEFI IsBIOS Undetermined FirmwareType
------ ------ ------------ ------------
 False   True        False BIOS        


PS:> # The function can also be used to test for a particular firmware type:
PS:> (Get-FirmwareType).IsBios
True


````

Version History:
---------------

 V1.0 (Original Published Version)
  - Initial release to the PowerShell Gallery 

 V0.1-0.9 Dev versions

Other Modules:
------------
See all my other PS Gallery modules: 

````
  Find-Module | Where Author -match 'Chris Warwick'
````
