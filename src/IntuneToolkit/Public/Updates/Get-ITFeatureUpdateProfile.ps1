function Get-ITFeatureUpdateProfile {
    <#
    .SYNOPSIS
        Gets Windows feature update profiles (target Windows version).

    .DESCRIPTION
        Returns the feature update profiles with featureUpdateVersion (e.g. 'Windows 11, version 24H2'),
        rollout settings and endOfSupportDate. DaysToEndOfSupport is added for the monthly
        report (negative = already out of support).

    .PARAMETER Name
        Profile display name. Wildcards allowed.

    .PARAMETER Id
        Profile ID(s).

    .PARAMETER IncludeAssignment
        Also read the assignments.

    .EXAMPLE
        Get-ITFeatureUpdateProfile | Select-Object displayName, featureUpdateVersion, DaysToEndOfSupport

    .OUTPUTS
        IntuneToolkit.FeatureUpdateProfile

    .NOTES
        Graph permission : DeviceManagementConfiguration.Read.All
        Graph endpoint   : GET /deviceManagement/windowsFeatureUpdateProfiles
        API version      : beta

    .LINK
        Get-ITUpdateRing
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    [OutputType('IntuneToolkit.FeatureUpdateProfile')]
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
        $info = Get-ITPolicyTypeInfo -PolicyType FeatureUpdate
        Assert-ITGraphConnection -RequiredScope $info.ReadScope
    }

    process {
        $params = @{ TypeInfo = $info; IncludeAssignment = $IncludeAssignment }
        if ($PSCmdlet.ParameterSetName -eq 'ById') { $params['Id'] = $Id } elseif ($Name) { $params['Name'] = $Name }
        foreach ($item in @(Get-ITIntuneObject @params)) {
            $days = $null
            if ($item.PSObject.Properties['endOfSupportDate'] -and $item.endOfSupportDate) {
                $end = [datetime]::MinValue
                if ([datetime]::TryParse([string]$item.endOfSupportDate, [ref]$end)) { $days = [int][math]::Floor(($end - (Get-Date)).TotalDays) }
            }
            Add-Member -InputObject $item -NotePropertyName 'DaysToEndOfSupport' -NotePropertyValue $days -Force
            $item
        }
    }
}
