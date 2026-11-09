function Get-ITSettingsCatalogPolicy {
    <#
    .SYNOPSIS
        Gets Intune settings catalog policies (configurationPolicies), optionally with their settings.

    .DESCRIPTION
        Returns the settings catalog policies (also endpoint security policies built on the
        settings catalog) with displayName, Platform and settingCount. -IncludeSetting reads
        each policy with its settings ($expand=settings) and adds a flat SettingList
        (SettingDefinitionId, Value) for quick reading; the raw 'settings' stay on the object.

    .PARAMETER Name
        Policy name. Wildcards allowed.

    .PARAMETER Id
        Policy ID(s).

    .PARAMETER Platform
        Only policies for this platform.

    .PARAMETER IncludeSetting
        Read the configured settings of each policy (one extra Graph call per policy).

    .PARAMETER IncludeAssignment
        Also read the assignments of each policy (one extra Graph call per policy).

    .EXAMPLE
        Get-ITSettingsCatalogPolicy -Platform Windows

    .EXAMPLE
        Get-ITSettingsCatalogPolicy -Name 'Win - Edge*' -IncludeSetting | Select-Object -ExpandProperty SettingList

        Every configured setting with its value.

    .OUTPUTS
        IntuneToolkit.SettingsCatalogPolicy

    .NOTES
        Graph permission : DeviceManagementConfiguration.Read.All
        Graph endpoint   : GET /deviceManagement/configurationPolicies
        API version      : beta (not available in v1.0)

    .LINK
        https://learn.microsoft.com/graph/api/resources/intune-deviceconfigv2-devicemanagementconfigurationpolicy?view=graph-rest-beta
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    [OutputType('IntuneToolkit.SettingsCatalogPolicy')]
    param(
        [Parameter(ParameterSetName = 'ByName', Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ById', ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Id,

        [ValidateSet('Windows', 'macOS', 'iOS', 'Android', 'Linux')]
        [string]$Platform,

        [switch]$IncludeSetting,

        [switch]$IncludeAssignment
    )

    begin {
        $info = Get-ITPolicyTypeInfo -PolicyType SettingsCatalog
        Assert-ITGraphConnection -RequiredScope $info.ReadScope
    }

    process {
        $params = @{ TypeInfo = $info; IncludeAssignment = $IncludeAssignment }
        if ($PSCmdlet.ParameterSetName -eq 'ById') { $params['Id'] = $Id } elseif ($Name) { $params['Name'] = $Name }
        $platformFilter = $Platform
        $policies = @(Get-ITIntuneObject @params | Where-Object { -not $platformFilter -or $_.Platform -eq $platformFilter })

        foreach ($policy in $policies) {
            if ($IncludeSetting) {
                $settings = @()
                try {
                    $settings = @(Invoke-ITGraphRequest -Uri ('{0}/{1}/settings' -f $info.Path, $policy.id) -ApiVersion 'beta' -All)
                }
                catch {
                    Write-Error -ErrorRecord $_
                }
                Add-Member -InputObject $policy -NotePropertyName 'settings' -NotePropertyValue $settings -Force
                $list = foreach ($setting in $settings) {
                    if (-not $setting.PSObject.Properties['settingInstance']) { continue }
                    ConvertTo-ITSettingList -SettingInstance $setting.settingInstance
                }
                Add-Member -InputObject $policy -NotePropertyName 'SettingList' -NotePropertyValue @($list) -Force
            }
            $policy
        }
    }
}
