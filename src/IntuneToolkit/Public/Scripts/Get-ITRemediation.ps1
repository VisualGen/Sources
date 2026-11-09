function Get-ITRemediation {
    <#
    .SYNOPSIS
        Gets Intune remediations (proactive remediations / device health scripts).

    .DESCRIPTION
        Returns the remediation script packages with publisher, run settings and IsBuiltIn
        (Microsoft-published scripts). -IncludeContent adds DetectionScriptText and
        RemediationScriptText. Results pipe into Get-ITRemediationResult,
        Invoke-ITRemediationOnDemand (-RemediationId), Export-ITScript and the assignment commands.

    .PARAMETER Name
        Remediation display name. Wildcards allowed.

    .PARAMETER Id
        Remediation ID(s).

    .PARAMETER ExcludeBuiltIn
        Hide the scripts published by Microsoft.

    .PARAMETER IncludeContent
        Add the decoded detection and remediation script text (one extra call per remediation).

    .PARAMETER IncludeAssignment
        Also read the assignments.

    .EXAMPLE
        Get-ITRemediation -ExcludeBuiltIn

    .EXAMPLE
        Get-ITRemediation -Name 'Fix-WindowsUpdate' -IncludeContent | Select-Object -ExpandProperty DetectionScriptText

    .OUTPUTS
        IntuneToolkit.Remediation

    .NOTES
        Graph permission : DeviceManagementConfiguration.Read.All
        Graph endpoint   : GET /deviceManagement/deviceHealthScripts
        API version      : beta (not available in v1.0)
        Licence          : Windows Enterprise E3/E5 or equivalent

    .LINK
        Get-ITRemediationResult
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    [OutputType('IntuneToolkit.Remediation')]
    param(
        [Parameter(ParameterSetName = 'ByName', Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ById', ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Id,

        [switch]$ExcludeBuiltIn,

        [switch]$IncludeContent,

        [switch]$IncludeAssignment
    )

    begin {
        $info = Get-ITPolicyTypeInfo -PolicyType Remediation
        Assert-ITGraphConnection -RequiredScope $info.ReadScope
    }

    process {
        $params = @{ TypeInfo = $info; IncludeAssignment = $IncludeAssignment }
        if ($PSCmdlet.ParameterSetName -eq 'ById') { $params['Id'] = $Id } elseif ($Name) { $params['Name'] = $Name }

        foreach ($item in @(Get-ITIntuneObject @params)) {
            $builtIn = [bool]($item.PSObject.Properties['isGlobalScript'] -and $item.isGlobalScript)
            if ($ExcludeBuiltIn -and $builtIn) { continue }
            Add-Member -InputObject $item -NotePropertyName 'IsBuiltIn' -NotePropertyValue $builtIn -Force

            if ($IncludeContent) {
                $full = $item
                if (-not ($item.PSObject.Properties['detectionScriptContent'] -and $item.detectionScriptContent)) {
                    try { $full = Invoke-ITGraphRequest -Uri ('{0}/{1}' -f $info.Path, $item.id) -ApiVersion 'beta' }
                    catch { Write-Error -ErrorRecord $_ }
                }
                $detect = $null; $fix = $null
                if ($full.PSObject.Properties['detectionScriptContent']) { $detect = $full.detectionScriptContent }
                if ($full.PSObject.Properties['remediationScriptContent']) { $fix = $full.remediationScriptContent }
                Add-Member -InputObject $item -NotePropertyName 'DetectionScriptText' -NotePropertyValue (ConvertFrom-ITBase64 $detect) -Force
                Add-Member -InputObject $item -NotePropertyName 'RemediationScriptText' -NotePropertyValue (ConvertFrom-ITBase64 $fix) -Force
            }
            $item
        }
    }
}
