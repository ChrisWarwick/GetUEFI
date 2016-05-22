<#

The function in this module determines the underlying system firmware (BIOS) type - either UEFI or Legacy BIOS.

The function can use one of three methods to determine the firmware type:

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

Chris Warwick, @cjwarwickps,  September 2013.   (This version, November 2015)
chrisjwarwick.wordpress.com

See all my PS Gallery modules:   Find-Module | Where Author -match 'Chris Warwick'

#>

#Requires -Version 2

#region Helper Functions

# The folowing function works on all Windows versions:

<#
.Synopsis
   Determines underlying firmware (BIOS) type and return an object describing the Firmware.
.DESCRIPTION
   This function seraches the windows Setup log file (setupact.log in the \Windows\Panther folder)
   to determine whether setup identified a UEFI environment or a legacy BIOS.
.EXAMPLE
   Get-LogFileFirmwareType  # Returns custom object describing firmware
.OUTPUTS
   'FirmwareType', object describing firmware type
.FUNCTIONALITY
   Determines underlying system firmware type
#>
Function Get-LogFileFirmwareType {
[OutputType('FirmwareType')]
Param()

    # Template object to return, modified below...
    $FirmwareType = [PsCustomObject]@{
        PsTypeName   = 'FirmwareType'
        IsUEFI       = $False
        IsBIOS       = $False
        Undetermined = $True
        FirmwareType = 'Undetermined'   # Set to 'BIOs' or 'UEFI' when found
    }

    # Extract the firmware type from the 'setupact.log' file - see what bios type was detected (EFI or BIOS) at install time

    $Panther = "$Env:windir\Panther\setupact.log"
    If (Test-Path -Path $Panther -PathType Leaf) {

        $FirmwareString = (Select-String 'Detected boot environment:' $Panther -AllMatches ).Line -replace '.*:\s+'

        Switch -Regex ($FirmwareString) {

            '^BIOS$'  {$FirmwareType.IsBIOS = $True
                       $FirmwareType.Undetermined = $False
                       $FirmwareType.FirmwareType = 'BIOS'
                      }
            '^U?EFI$' {$FirmwareType.IsUEFI = $True
                       $FirmwareType.Undetermined = $False
                       $FirmwareType.FirmwareType = 'UEFI'
                      }
            Default   {Break}      # Can't determine f/w type, just return the 'Undetermined' object defined above
        }
    }
    
    $FirmwareType
}




<#
(Windows 7/Server 2008R2 or above)
Use the GetFirmwareEnvironmentVariable Win32 API.

From MSDN (http://msdn.microsoft.com/en-ca/library/windows/desktop/ms724325%28v=vs.85%29.aspx):

"Firmware variables are not supported on a legacy BIOS-based system. The GetFirmwareEnvironmentVariable function will 
always fail on a legacy BIOS-based system, or if Windows was installed using legacy BIOS on a system that supports both 
legacy BIOS and UEFI. 

"To identify these conditions, call the function with a dummy firmware environment name such as an empty string ("") for 
the lpName parameter and a dummy GUID such as "{00000000-0000-0000-0000-000000000000}" for the lpGuid parameter. 
On a legacy BIOS-based system, or on a system that supports both legacy BIOS and UEFI where Windows was installed using 
legacy BIOS, the function will fail with ERROR_INVALID_FUNCTION. On a UEFI-based system, the function will fail with 
an error specific to the firmware, such as ERROR_NOACCESS, to indicate that the dummy GUID namespace does not exist."


From PowerShell, we can call the API via P/Invoke from a compiled C# class using Add-Type.  In Win32 any resulting
API error is retrieved using GetLastError(), however, this is not reliable in .Net (see 
blogs.msdn.com/b/adam_nathan/archive/2003/04/25/56643.aspx), instead we mark the pInvoke signature for 
GetFirmwareEnvironmentVariableA with SetLastError=true and use Marshal.GetLastWin32Error()

Note: The GetFirmwareEnvironmentVariable API requires the SE_SYSTEM_ENVIRONMENT_NAME privilege.  In the Security 
Policy editor this equates to "User Rights Assignment": "Modify firmware environment values" and is granted to 
Administrators by default.  Because we don't actually read any variables this permission appears to be optional.

#>


<#
.Synopsis
   Determines underlying firmware (BIOS) type and return an object describing the Firmware.
.DESCRIPTION
   This function uses a complied Win32 API call to determine the underlying system firmware type.
.EXAMPLE
   Get-FirmwareEnvironmentVariableAPI  # Returns custom object describing firmware
.OUTPUTS
   'FirmwareType', object describing firmware type
.FUNCTIONALITY
   Determines underlying system firmware type
#>
Function Get-FirmwareEnvironmentVariableAPI {
[OutputType('FirmwareType')]
Param()

# Wrap the 'GetFirmwareEnvironmentVariableA' API...
Add-Type -Language CSharp -TypeDefinition @'

    using System;
    using System.Runtime.InteropServices;

    public class CheckUEFI
    {
        [DllImport("kernel32.dll", SetLastError=true)]
        static extern UInt32 
        GetFirmwareEnvironmentVariableA(string lpName, string lpGuid, IntPtr pBuffer, UInt32 nSize);

        const int ERROR_INVALID_FUNCTION = 1; 

        public static bool IsUEFI()
        {
            // Try to call the GetFirmwareEnvironmentVariable API.  This is invalid on legacy BIOS.

            GetFirmwareEnvironmentVariableA("","{00000000-0000-0000-0000-000000000000}",IntPtr.Zero,0);

            if (Marshal.GetLastWin32Error() == ERROR_INVALID_FUNCTION)

                return false;     // API not supported (INVALID_FUNCTION); this is a legacy BIOS

            else

                return true;      // Call to API is supported.  This is UEFI.
        }
    }
'@


    # Call API and return result

    If ([CheckUEFI]::IsUEFI()) {
        [PsCustomObject]@{
            PsTypeName   = 'FirmwareType'
            IsUEFI       = $True
            IsBIOS       = $False
            Undetermined = $False
            FirmwareType = 'UEFI' 
        }
    }
    else {
        [PsCustomObject]@{
            PsTypeName   = 'FirmwareType'
            IsUEFI       = $False
            IsBIOS       = $True
            Undetermined = $False
            FirmwareType = 'BIOS'   
        }
    }    
}



<#
(Windows 8/Server 2012 or above)

Use GetFirmwareTtype() Win32 API.

In Windows 8/Server 2012 and above there's an API that directly returns the firmware type and doesn't rely on a hack.
GetFirmwareType() in kernel32.dll (http://msdn.microsoft.com/en-us/windows/desktop/hh848321%28v=vs.85%29.aspx) returns 
a pointer to a FirmwareType enum that defines the following:

typedef enum _FIRMWARE_TYPE { 
  FirmwareTypeUnknown  = 0,
  FirmwareTypeBios     = 1,
  FirmwareTypeUefi     = 2,
  FirmwareTypeMax      = 3
} FIRMWARE_TYPE, *PFIRMWARE_TYPE;

Once again, this API call can be called in .Net via P/Invoke.  

#>


<#
.Synopsis
   Determines underlying firmware (BIOS) type and return an object describing the Firmware.
.DESCRIPTION
   This function uses a complied Win32 API call to determine the underlying system firmware type.
.EXAMPLE
   Get-FirmwareEnvironmentVariableAPI  # Returns custom object describing firmware
.OUTPUTS
   'FirmwareType', object describing firmware type
.FUNCTIONALITY
   Determines underlying system firmware type
#>
Function Get-FirmwareTypeAPI {
[OutputType('FirmwareType')]
Param()

# Wrap the 'GetFirmwareType' API...
Add-Type -Language CSharp -TypeDefinition @'

    using System;
    using System.Runtime.InteropServices;

    public class FirmwareType
    {
        [DllImport("kernel32.dll")]
        static extern bool GetFirmwareType(ref uint FirmwareType);

        public static uint GetFirmwareType()
        {
            uint firmwaretype = 0;
            if (GetFirmwareType(ref firmwaretype))
                return firmwaretype;
            else
                return 0;   // API call failed, just return 'unknown'
        }
    }
'@

    # Template object, modified below...
    $FirmwareType = [PsCustomObject]@{
        PsTypeName   = 'FirmwareType'
        IsUEFI       = $False
        IsBIOS       = $False
        Undetermined = $True
        FirmwareType = 'Undetermined'   # Set to 'BIOs' or 'UEFI' when found
    }

    Switch ([FirmwareType]::GetFirmwareType()) {

        0 {Break}      # Can't determine f/w type, just return the 'Undetermined' object defined above
        1  {$FirmwareType.IsBIOS = $True
            $FirmwareType.Undetermined = $False
            $FirmwareType.FirmwareType = 'BIOS'
           }
        2  {$FirmwareType.IsUEFI = $True
            $FirmwareType.Undetermined = $False
            $FirmwareType.FirmwareType = 'UEFI'
           }
    }
    
    $FirmwareType
}



# Determine the version of the host OS
# Windows 7,   Server 2008R2  -> 6.1.x
# Windows 8,   Server 2012    -> 6.2.x
# Windows 8.1, Server 2012R2  -> 6.3.x
# Windows 10,  Server 2016    -> 10.0.x

Function Get-OSVersion {
[OutputType([System.Version])]
Param()
    [System.Version](Get-WmiObject -Query 'Select Version from WIN32_OperatingSystem').Version
}


#endregion Helper Functions

# -------------------------------------------------------------------------------------------------------


# The following function wraps the helper functions above.  If the 'QueryType' parameter isn't specified
# the function will determine the most appropriate technique based on the current OS version


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

Function Get-FirmwareType {
[CmdletBinding()]
[OutputType('FirmwareType')]
Param(
    [Parameter()]
    [ValidateSet(
        'SetupLog',
        'GetFirmwareEnvironmentVariable',
        'GetFirmwareType',
        'Auto'
    )]
    [String]$QueryType='Auto'
)

    # Convert the 'Auto' query type into one of the three supported types based on OS Version:

    If ($QueryType -eq 'Auto') {
        
        Switch (Get-OSVersion) { 
            {$_ -ge [System.Version]'6.2.0.0'} {
                Write-Verbose "OS Version $_, Windows 8.0, Server 2012 or above -> Using GetFirmwareType() API."
                $QueryType = 'GetFirmwareType'
                Break
            }

            {$_ -ge [System.Version]'6.1.0.0'} {
                Write-Verbose "OS Version $_, Windows 7, Server 2008R2 or above -> Using GetFirmwareEnvironmentVariable() API."
                $QueryType = 'GetFirmwareEnvironmentVariable'
                Break
            }
            Default {
                Write-Verbose "OS Version $_, Windows Vista, Server 2008 or below -> Using $Env:windir\Panther\setupact.log file."
                $QueryType = 'SetupLog'
                Break
            }
        }
    }

    
    # Determine the Firmware type using the specified method...

    Switch ($QueryType) {

        GetFirmwareType {
            Get-FirmwareTypeAPI
        }
        
        GetFirmwareEnvironmentVariable {
            Get-FirmwareEnvironmentVariableAPI
        }
   
        SetupLog {
            Get-LogFileFirmwareType
        }
    }
}


# An electron is pulled-up for speeding. The policeman says, “Sir, do you realise you were travelling at 130mph?” The electron says, “Oh great, now I’m lost.”
