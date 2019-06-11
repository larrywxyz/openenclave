﻿Import-Module Hyper-V

### -----------------------------------
### Constants
### -----------------------------------

$VM_MEMORY_SETTINGS_GUID = "4764334d-e001-4176-82ee-5594ec9b530e"

Set-StrictMode -Version 5

$ErrorActionPreference = "Stop"
$InformationPreference = "Continue"

### -----------------------------------
### Strings
### -----------------------------------

Data Strings {
    # culture="en-US"
    ConvertFrom-StringData @'
    ERR_NO_MEM_SETTING_DATA_OBJECT = Could not retrieve the Memory Setting Data object for VM '{0}' from WMI.
    ERR_NO_VMM = Could not retrieve the instance of the Virtual System Management Service from WMI.
    ERR_VM_STATE = The VM '{0}' must be Off before its SGX settings may be modified.
    ERR_NO_SETTINGS_TO_MODIFY = Specify at least one SGX setting to modify.
    ERR_NO_SGX_MEM_TO_ENABLE = To enable SGX, some SGX EPC memory is required (-SgxSize).
    ERR_COULD_NOT_MODIFY_SETTINGS = Could not modify SGX settings for VM '{0}' via WMI with error value '{1}'.

    WARN_GEN2_TITLE = The VM '{0}' is not a Generation 2 or later VM.
    WARN_GEN2_TEXT = > Enabling SGX may not work.

    WARN_SECURE_BOOT_TITLE = The VM '{0}' has Secure Boot on.
    WARN_SECURE_BOOT_TEXT = > If you plan on running Linux, you will have to sign your Intel SGX kernel module with a custom Secure Boot key.

    WARN_CHECKPOINT_TITLE = The VM '{0}' has checkpoints enabled.
    WARN_CHECKPOINT_TEXT = > Enabling SGX may cause the VM to not start.
'@
}

# Import localized strings.
Import-LocalizedData Strings -FileName VirtualMachineSgxSettings.Strings.psd1 -ErrorAction SilentlyContinue

### -----------------------------------
### Classes
### -----------------------------------

Class VirtualMachineSgx {
    [bool] $IsSgxEnabled;
    [UInt64] $SgxSize;
    [String] $SgxLaunchControlDefault;
    [UInt32] $SgxLaunchControlMode;

    VirtualMachineSgx([System.Management.ManagementObject] $VmSgx) {
        $This.IsSgxEnabled = $VmSgx.SgxEnabled;
        $This.SgxSize = $VmSgx.SgxSize;
        $This.SgxLaunchControlDefault = $VmSgx.SgxLaunchControlDefault;
        $This.SgxLaunchControlMode = $VmSgx.SgxLaunchControlMode;
    }
}

### -----------------------------------
### Helper Functions
### -----------------------------------

Function Get-VMSgxMemorySettingData([Microsoft.HyperV.PowerShell.VirtualMachine] $Vm) {
    $Mem = Get-WmiObject -Namespace root/virtualization/v2 -Class Msvm_MemorySettingData |
    Where-Object { $_.InstanceId -eq "Microsoft:$($Vm.Id)\$VM_MEMORY_SETTINGS_GUID" }

    If (!$Mem) {
        Write-Error ($Strings.ERR_NO_MEM_SETTING_DATA_OBJECT -f $Vm.Name)
    }

    Return $Mem
}

Function Get-VMSgxManagementService() {
    $Svc = Get-WmiObject -Namespace root/virtualization/v2 -Class Msvm_VirtualSystemManagementService |
    Where-Object {
        ($_.CreationClassName -eq "Msvm_VirtualSystemManagementService") -and
        ($_.Name -eq "vmms") -and
        ($_.SystemCreationClassName -eq "Msvm_ComputerSystem") -and
        ($_.SystemName -eq $env:COMPUTERNAME)
    }

    If (!$Svc) {
        Write-Error $Strings.ERR_NO_VMM
    }

    return $Svc
}

### -----------------------------------
### Get-VMSgx Cmdlet
### -----------------------------------

<#
    .SYNOPSIS
        Retrieves the Hyper-V virtualization settings for Intel Software Guard
        Extensions (SGX).

    .Description
        Intel Software Guard Extensions (SGX) provide developers the ability to
        run code inside a Trusted Execution Environment (TEE) known as an
        enclave. Hyper-V allows system administrators to virtualize SGX
        resources and expose this ability to guests on an SGX-capable host.
        This function retrieves the settings for SGX virtualization for the
        given virtual machine:

        - IsSgxEnabled: Whether SGX virtualization is enabled for the given
            virtual machine.
        - SgxSize: The size, in MB, of the host's SGX EPC memory the given
            virtual machine is allowed to use.
        - SgxLaunchControlDefault: The default SGX Launch Control Mode for the
            given virtual machine, if the host supports Flexible Launch Control
            (FLC) mode.
        - SgxLaunchControlMode: The current SGX Launch Control Mode for the
            given virtual machine, if the host supports Flexible Launch Control
            (FLC) mode.

    .Parameter VmName
        Name of the virtual machine for which to retrieve the SGX
        virtualization settings.

    .Parameter Vm
        The virtual machine object for which to retrieve the SGX
        virtualization settings.

    .Example
        To retrieve the settings for SGX virtualization for a virtual machine
        by name, do:

        Get-VMSgx -VmName MySGXVm

        You can also write:

        Get-VMSgx MySgxVM

    .Link
        https://openenclave.io/
#>
Function Get-VMSgx {
    [CmdletBinding()]
    Param
    (
        # Name of the VM to get the SGX settings for.
        [Parameter(Mandatory = $True, ParameterSetName = "ByName", Position = 0)]
        [ValidateNotNullOrEmpty()]
        [String]$VmName,

        # VM to get the SGX settings for.
        [Parameter(Mandatory = $True, ParameterSetName = "ByObject", Position = 0)]
        [ValidateNotNull()]
        [Microsoft.HyperV.PowerShell.VirtualMachine]$Vm
    )

    Process {
        If (!$Vm) {
            $Vm = Get-VM $VmName
        }

        $Mem = Get-VMSgxMemorySettingData $Vm
        Return [VirtualMachineSgx]::New($Mem)
    }
}

### -----------------------------------
### Set-VMSgx Cmdlet
### -----------------------------------

<#
    .SYNOPSIS
        Modifies the Hyper-V virtualization settings for Intel Software Guard
        Extensions (SGX).

    .Description
        Intel Software Guard Extensions (SGX) provide developers the ability to
        run code inside a Trusted Execution Environment (TEE) known as an
        enclave. Hyper-V allows system administrators to virtualize SGX
        resources and expose this ability to guests on an SGX-capable host.
        This function modifies the settings for SGX virtualization for the
        given virtual machine and then retrieves the same from Hyper-V:

        - IsSgxEnabled: Whether SGX virtualization is enabled for the given
            virtual machine.
        - SgxSize: The size, in MB, of the host's SGX EPC memory the given
            virtual machine is allowed to use.
        - SgxLaunchControlDefault: The default SGX Launch Control Mode for the
            given virtual machine, if the host supports Flexible Launch Control
            (FLC) mode.
        - SgxLaunchControlMode: The current SGX Launch Control Mode for the
            given virtual machine, if the host supports Flexible Launch Control
            (FLC) mode.

    .Parameter VmName
        Name of the virtual machine for which to modify the SGX virtualization
        settings.

    .Parameter Vm
        The virtual machine object for which to modify the SGX virtualization
        settings.

    .Parameter IsSgxEnabled
        Whether SGX virtualization is enabled for the given virtual machine.

    .Parameter SgxSize
        The size, in MB, of the host's SGX EPC memory the given virtual machine
        is allowed to use.

    .Parameter SgxLaunchControlDefault
        The default SGX Launch Control Mode for the given virtual machine, if
        the host supports Flexible Launch Control (FLC) mode.

    .Parameter SgxLaunchControlMode
        The current SGX Launch Control Mode for the given virtual machine, if
        the host supports Flexible Launch Control (FLC) mode.

    .Example
        To enable SGX virtualization on a virtual machine by name and set its
        SGX EPC memory size to 32M, do:

        Set-VMSgx -VmName MySgxVM -IsSgxEnabled $True -SgxSize 32

        You may also write:

        Set-VMSgx MySgxVM $True 32

    .Example
        To disable SGX virtualization on a virtual machine by name, do:

        Set-VMSgx -VmName MySgxVM -IsSgxEnabled $False -SgxSize 0

        Alternately:

        Set-VMSgx MySgxVM $False 0

    .Link
        https://openenclave.io/
#>
Function Set-VMSgx {
    [CmdletBinding()]
    Param
    (
        # Name of the VM to configure.
        [Parameter(Mandatory = $True, ParameterSetName = "ByName", Position = 0)]
        [ValidateNotNullOrEmpty()]
        [String]$VmName,

        # VM to configure.
        [Parameter(Mandatory = $True, ParameterSetName = "ByObject", Position = 0)]
        [ValidateNotNull()]
        [Microsoft.HyperV.PowerShell.VirtualMachine]$Vm,

        # Whether SGX is enabled in the VM.
        [Parameter(Position = 1)]
        [Bool]$IsSgxEnabled = $False,

        # Desired SGX EPC Memory Size for the VM (in MB).
        [Parameter(Position = 2)]
        [UInt64]$SgxSize = 0,

        # Desired default SGX Launch Control Mode for the VM.
        [Parameter(Position = 3)]
        [String]$SgxLaunchControlDefault = [String]::Empty,

        # Desired SGX Launch Control Mode for the VM.
        [Parameter(Position = 4)]
        [UInt32]$SgxLaunchControlMode = 0,

        # Ignore warnings.
        [Parameter()]
        [Switch]$Force
    )

    Process {
        # If the user passed a VM name, retrieve the VM object.
        If ($Null -eq $Vm) {
            $Vm = Get-VM $VmName
        }

        # If the VM is not Off, the function cannot proceed.
        If ($Vm.State -ne [Microsoft.HyperV.PowerShell.VMState]::Off) {
            Write-Error ($Strings.ERR_VM_STATE -f $Vm.Name)
        }

        # At the time of this writing, the following conditions hold:
        #
        # 1. SGX virtualization is only supported on Gen2 VMs:
        # 1.1. The Intel SGX driver is not yet merged into mainline Linux and must be compiled manually;
        #      For VMs with Secure Boot on, this means that the module must be signed with a custom key;
        #      Note: Only Gen2 VMs support Secure Boot.
        # 2. Checkpoints are not supported with SGX turned on.

        If (!$Force -and $IsSgxEnabled) {
            # Check VM generation.
            If ($Vm.Generation -lt 2) {
                Write-Warning ($Strings.WARN_GEN2_TITLE -f $Vm.Name)
                Write-Warning $Strings.WARN_GEN2_TEXT
            }

            # Check Secure Boot settings.
            If ($Vm.Generation -ge 2) {
                $Fw = $Vm | Get-VMFirmware

                If ($Fw.SecureBoot -eq [Microsoft.HyperV.PowerShell.OnOffState]::On) {
                    Write-Information ($Strings.WARN_SECURE_BOOT_TITLE -f $Vm.Name)
                    Write-Information $Strings.WARN_SECURE_BOOT_TEXT
                }
            }

            # Check Checkpoint settings.
            If ($Vm.CheckpointType -ne [Microsoft.HyperV.PowerShell.CheckpointType]::Disabled -and $IsSgxEnabled) {
                Write-Information ($Strings.WARN_CHECKPOINT_TITLE -f $Vm.Name)
                Write-Information $Strings.WARN_CHECKPOINT_TEXT
            }
        }

        # Fetch the settings for the VM.
        $Mem = Get-VMSgxMemorySettingData $Vm

        # Fetch the WMI interface to the VMM service.
        $Svc = Get-VMSgxManagementService

        # The function only changes settings when asked to, it does not assume
        # default values.
        $HasWorkToDo = $False

        # Enable/Disable SGX.
        If ($PSBoundParameters.ContainsKey('IsSgxEnabled')) {
            $Mem.SgxEnabled = $IsSgxEnabled
            $HasWorkToDo = $True
        }

        # SGX EPC size (in MB).
        If ($PSBoundParameters.ContainsKey('SgxSize')) {
            $Mem.SgxSize = $SgxSize
            $HasWorkToDo = $True
        }

        # Default FLC Mode.
        If ($PSBoundParameters.ContainsKey('SgxLaunchControlDefault')) {
            $Mem.SgxLaunchControlDefault = $SgxLaunchControlDefault
            $HasWorkToDo = $True
        }

        # FLC Mode.
        If ($PSBoundParameters.ContainsKey('SgxLaunchControlMode')) {
            $Mem.SgxLaunchControlMode = $SgxLaunchControlMode
            $HasWorkToDo = $True
        }

        # If no settings were passed to the cmdlet, bail out.
        If (!$HasWorkToDo) {
            Write-Error $Strings.ERR_NO_SETTINGS_TO_MODIFY
        }

        # Check that some memory was specified to enable SGX.
        If (!$Force -and $IsSgxEnabled -and ($SgxSize -eq 0)) {
            Write-Error $Strings.ERR_NO_SGX_MEM_TO_ENABLE
        }

        # Try to change the settings.
        $Ret = $Svc.ModifyResourceSettings($Mem.GetText(1))

        # Inform the user as to the result.
        If ($Ret.ReturnValue -ne 0) {
            Write-Error ($Strings.ERR_COULD_NOT_MODIFY_SETTINGS -f $Vm.Name, $Ret.ReturnValue)
        }

        # Write out the new values.
        Get-VMSgx -Vm $Vm
    }
}

Export-ModuleMember -Function Get-VMSgx, Set-VMSgx
