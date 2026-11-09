function Get-ITUpdateRing {
    <#
    .SYNOPSIS
        Gets Windows Update for Business update rings.

    .DESCRIPTION
        Returns the update rings (windowsUpdateForBusinessConfiguration profiles) with their
        deferral periods, deadlines and pause state (qualityUpdatesPaused,
        featureUpdatesPaused). Results pipe into Suspend-/Resume-ITUpdateRing and the
        assignment commands.

    .PARAMETER Name
        Ring display name. Wildcards allowed.

    .PARAMETER Id
        Ring ID(s).

    .PARAMETER IncludeAssignment
        Also read the assignments.

    .EXAMPLE
        Get-ITUpdateRing

    .EXAMPLE
        Get-ITUpdateRing | Select-Object displayName, qualityUpdatesDeferralPeriodInDays, featureUpdatesDeferralPeriodInDays, qualityUpdatesPaused

    .OUTPUTS
        IntuneToolkit.UpdateRing

    .NOTES
        Graph permission : DeviceManagementConfiguration.Read.All
        Graph endpoint   : GET /deviceManagement/deviceConfigurations (type windowsUpdateForBusinessConfiguration)
        API version      : beta

    .LINK
        Suspend-ITUpdateRing
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    [OutputType('IntuneToolkit.UpdateRing')]
    param(
        [Parameter(ParameterSetName = 'ByName', Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ById', ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Id,

        [switch]$IncludeAssignment
    )

    begin {
        $info = Get-ITPolicyTypeInfo -PolicyType UpdateRing
        Assert-ITGraphConnection -RequiredScope $info.ReadScope
    }

    process {
        $params = @{ TypeInfo = $info; IncludeAssignment = $IncludeAssignment }
        if ($PSCmdlet.ParameterSetName -eq 'ById') { $params['Id'] = $Id } elseif ($Name) { $params['Name'] = $Name }
        Get-ITIntuneObject @params
    }
}
