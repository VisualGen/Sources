function Get-ITCompliancePolicy {
    <#
    .SYNOPSIS
        Gets Intune device compliance policies.

    .DESCRIPTION
        Returns the compliance policies with Platform (Windows, iOS, Android, macOS, ...) and
        ObjectType (the Graph type, e.g. windows10CompliancePolicy). -IncludeAssignment adds the
        included/excluded groups. The objects carry PolicyType 'Compliance' and pipe into
        Get-/Add-/Remove-ITPolicyAssignment, Get-ITDeviceComplianceStatus and Export-ITPolicy.

    .PARAMETER Name
        Policy display name. Wildcards allowed.

    .PARAMETER Id
        Policy ID(s).

    .PARAMETER Platform
        Only policies for this platform.

    .PARAMETER IncludeAssignment
        Also read the assignments of each policy (one extra Graph call per policy).

    .PARAMETER ApiVersion
        Graph API version. Default: v1.0 ('beta' returns more properties).

    .EXAMPLE
        Get-ITCompliancePolicy

    .EXAMPLE
        Get-ITCompliancePolicy -Platform Windows -IncludeAssignment |
            Select-Object displayName, @{ n = 'Groups'; e = { $_.Assignments.Count } }

    .EXAMPLE
        Get-ITCompliancePolicy -Name 'Win - Baseline*' | Get-ITDeviceComplianceStatus -Status noncompliant

        Devices that fail a specific policy.

    .OUTPUTS
        IntuneToolkit.CompliancePolicy

    .NOTES
        Graph permission : DeviceManagementConfiguration.Read.All
        Graph endpoint   : GET /deviceManagement/deviceCompliancePolicies
        API version      : v1.0 (default) or beta

    .LINK
        https://learn.microsoft.com/graph/api/intune-deviceconfig-devicecompliancepolicy-list
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    [OutputType('IntuneToolkit.CompliancePolicy')]
    param(
        [Parameter(ParameterSetName = 'ByName', Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ById', ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Id,

        [ValidateSet('Windows', 'Windows8', 'macOS', 'iOS', 'Android', 'Linux')]
        [string]$Platform,

        [switch]$IncludeAssignment,

        [ValidateSet('v1.0', 'beta')]
        [string]$ApiVersion = 'v1.0'
    )

    begin {
        $info = Get-ITPolicyTypeInfo -PolicyType Compliance
        Assert-ITGraphConnection -RequiredScope $info.ReadScope
    }

    process {
        $params = @{ TypeInfo = $info; ApiVersion = $ApiVersion; IncludeAssignment = $IncludeAssignment }
        if ($PSCmdlet.ParameterSetName -eq 'ById') { $params['Id'] = $Id } elseif ($Name) { $params['Name'] = $Name }
        $platformFilter = $Platform
        Get-ITIntuneObject @params | Where-Object { -not $platformFilter -or $_.Platform -eq $platformFilter }
    }
}
