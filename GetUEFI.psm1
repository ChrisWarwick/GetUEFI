<#

This function determines the underlying system firmware (BIOS) type - either UEFI or Legacy BIOS.

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

Chris Warwick, @cjwarwickps,  September 2013
chrisjwarwick.wordpress.com

#>


#region Help Functions

Function Get-LogFileFirmwareType {

    # Extract the firmware type from the 'setupact.log' file 

    # Look in the setup logfile to see what bios type was detected (EFI or BIOS)
    (Select-String 'Detected boot environment' C:\Windows\Panther\setupact.log -AllMatches ).line -replace '.*:\s+'

}




<#
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

Function Get-FirmwareEnvironmentVariableAPI {

<#
.Synopsis
   Determines underlying firmware (BIOS) type and returns True for UEFI or False for legacy BIOS.
.DESCRIPTION
   This function uses a complied Win32 API call to determine the underlying system firmware type.
.EXAMPLE
   If (IsUEFI) { # System is running UEFI firmware... }
.OUTPUTS
   [Bool] True = UEFI Firmware; False = Legacy BIOS
.FUNCTIONALITY
   Determines underlying system firmware type
#>

[OutputType([Bool])]
Param ()

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


    [CheckUEFI]::IsUEFI()
}








<#

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

Once again, this API call can be called in .Net via P/Invoke.  Rather than defining an enum the function below 
just returns an unsigned int.

#>




# Windows 8/Server 2012 or above:


Function Get-FirmwareTypeAPI {

<#
.Synopsis
   Determines underlying firmware (BIOS) type and returns an integer indicating UEFI, Legacy BIOS or Unknown.
   Supported on Windows 8/Server 2012 or later
.DESCRIPTION
   This function uses a complied Win32 API call to determine the underlying system firmware type.
.EXAMPLE
   If (Get-BiosType -eq 2) { # System is running UEFI firmware... }
.EXAMPLE
    Switch (Get-BiosType) {
        1       {"Legacy BIOS"}
        2       {"UEFI"}
        Default {"Unknown"}
    }
.OUTPUTS
   Integer indicating firmware type (1 = Legacy BIOS, 2 = UEFI, Other = Unknown)
.FUNCTIONALITY
   Determines underlying system firmware type
#>

[OutputType([UInt32])]
Param()

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


    [FirmwareType]::GetFirmwareType()
}

#endregion Help Functions

# -------------------------------------------------------------------------------------------------------

# The follwoing function wraps the helper functions above.  If the 'QueryType' parameter isn't specified
# the function will determine the most appropriate technique based on the current OS version
Function Get-FirmwareType {
[CmdletBinding()]
[OutputType('FirmwareType')]
Param(
    [Parameter(Mandatory=$True)]
    [ValidateSet(
        'SetupLog',
        'GetFirmwareEnvironmentVariable',
        'GetFirmwareType',
        'Auto'
    )]
    [String]$QueryType='Auto'
)

    Switch ($QueryType) {
    
        Auto { # Todo: Determine OS level: -ge 8, -ge 7, -lt 7
        }
    
        SetupLog {
            # Look in the setup logfile to see what bios type was detected (EFI or BIOS)
            (Select-String 'Detected boot environment' C:\Windows\Panther\setupact.log -AllMatches ).line -replace '.*:\s+'
        }
    
    
    }

    [PsCustomObject]@{
        PsTypeName   = 'FirmwareType'
        IsUEFI       = $False
        IsBIOS       = $False
        Undetermined = $True
        BiosType     = 'Undetermined'
    }

}




# An electron is pulled-up for speeding. The policeman says, “Sir, do you realise you were travelling at 130mph?” The electron says, “Oh great, now I’m lost.”

