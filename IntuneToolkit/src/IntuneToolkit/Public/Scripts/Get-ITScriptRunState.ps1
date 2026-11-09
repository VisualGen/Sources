function Get-ITScriptRunState {
    <#
    .SYNOPSIS
        Gets the per-device result of an Intune platform script.

    .DESCRIPTION
        Returns one row per device: DeviceName, RunState (success, fail, pending, ...),
        ResultMessage (script output), ErrorCode, ErrorDescription, LastStateUpdateDateTime.
        -FailedOnly keeps rows with RunState 'fail' or 'error'.

    .PARAMETER Id
        Script ID. Binds from the id of Get-ITScript objects.

    .PARAMETER FailedOnly
        Only devices where the script failed.

    .EXAMPLE
        Get-ITScript -Name 'Set-TimeZone' | Get-ITScriptRunState

    .EXAMPLE
        Get-ITScript | Get-ITScriptRunState -FailedOnly | Select-Object ScriptName, DeviceName, ErrorCode, ResultMessage

    .OUTPUTS
        IntuneToolkit.ScriptRunState

    .NOTES
        Graph permission : DeviceManagementConfiguration.Read.All (+ DeviceManagementManagedDevices.Read.All for device names)
        Graph endpoint   : GET /deviceManagement/deviceManagementScripts/{id}/deviceRunStates?$expand=managedDevice
        API version      : beta

    .LINK
        Get-ITScript
    #>
    [CmdletBinding()]
    [OutputType('IntuneToolkit.ScriptRunState')]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string]$Id,

        [switch]$FailedOnly
    )

    begin {
        Assert-ITGraphConnection -RequiredScope 'DeviceManagementConfiguration.Read.All'
        $get = { param($o, $n) if ($o -and $o.PSObject.Properties[$n]) { $o.$n } else { $null } }
    }

    process {
        $scriptName = $null
        if ($_ -and $_.PSObject.Properties['displayName']) { $scriptName = $_.displayName }

        try {
            $uri = New-ITGraphUri -Path ('deviceManagement/deviceManagementScripts/{0}/deviceRunStates' -f $Id) -Expand 'managedDevice($select=id,deviceName,userPrincipalName)'
            $states = Invoke-ITGraphRequest -Uri $uri -ApiVersion 'beta' -All
        }
        catch {
            Write-Error -ErrorRecord $_
            return
        }

        foreach ($state in @($states | Where-Object { $_ })) {
            $runState = [string](& $get $state 'runState')
            if ($FailedOnly -and @('fail', 'error') -notcontains $runState) { continue }
            $device = & $get $state 'managedDevice'
            [pscustomobject]@{
                PSTypeName              = 'IntuneToolkit.ScriptRunState'
                ScriptId                = $Id
                ScriptName              = $scriptName
                DeviceId                = & $get $device 'id'
                DeviceName              = & $get $device 'deviceName'
                UserPrincipalName       = & $get $device 'userPrincipalName'
                RunState                = $runState
                ResultMessage           = & $get $state 'resultMessage'
                ErrorCode               = & $get $state 'errorCode'
                ErrorDescription        = & $get $state 'errorDescription'
                LastStateUpdateDateTime = & $get $state 'lastStateUpdateDateTime'
            }
        }
    }
}
