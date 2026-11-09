function Get-ITScript {
    <#
    .SYNOPSIS
        Gets Intune PowerShell platform scripts (Devices > Scripts), optionally with the script text.

    .DESCRIPTION
        Returns the device management scripts with run settings (runAsAccount, runAs32Bit,
        enforceSignatureCheck, fileName). -IncludeContent reads each script by ID and adds
        ScriptText (decoded). Results pipe into Get-ITScriptRunState, Export-ITScript and
        Add-/Remove-ITPolicyAssignment.

    .PARAMETER Name
        Script display name. Wildcards allowed.

    .PARAMETER Id
        Script ID(s).

    .PARAMETER IncludeContent
        Add ScriptText (one extra Graph call per script).

    .PARAMETER IncludeAssignment
        Also read the assignments of each script.

    .EXAMPLE
        Get-ITScript

    .EXAMPLE
        Get-ITScript -Name 'Set-*' -IncludeContent | Select-Object displayName, ScriptText

    .EXAMPLE
        Get-ITScript -IncludeAssignment | Where-Object { -not $_.Assignments } | Select-Object displayName

        Scripts that are not assigned.

    .OUTPUTS
        IntuneToolkit.Script

    .NOTES
        Graph permission : DeviceManagementConfiguration.Read.All
        Graph endpoint   : GET /deviceManagement/deviceManagementScripts
        API version      : beta (not available in v1.0)

    .LINK
        Export-ITScript
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    [OutputType('IntuneToolkit.Script')]
    param(
        [Parameter(ParameterSetName = 'ByName', Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ById', ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Id,

        [switch]$IncludeContent,

        [switch]$IncludeAssignment
    )

    begin {
        $info = Get-ITPolicyTypeInfo -PolicyType Script
        Assert-ITGraphConnection -RequiredScope $info.ReadScope
    }

    process {
        $params = @{ TypeInfo = $info; IncludeAssignment = $IncludeAssignment }
        if ($PSCmdlet.ParameterSetName -eq 'ById') { $params['Id'] = $Id } elseif ($Name) { $params['Name'] = $Name }

        foreach ($item in @(Get-ITIntuneObject @params)) {
            if ($IncludeContent) {
                $content = $null
                if ($item.PSObject.Properties['scriptContent'] -and $item.scriptContent) {
                    $content = $item.scriptContent
                }
                else {
                    try {
                        $full = Invoke-ITGraphRequest -Uri ('{0}/{1}' -f $info.Path, $item.id) -ApiVersion 'beta'
                        if ($full.PSObject.Properties['scriptContent']) { $content = $full.scriptContent }
                    }
                    catch {
                        Write-Error -ErrorRecord $_
                    }
                }
                Add-Member -InputObject $item -NotePropertyName 'ScriptText' -NotePropertyValue (ConvertFrom-ITBase64 $content) -Force
            }
            $item
        }
    }
}
