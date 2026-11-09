function Get-ITEnrollmentConfiguration {
    <#
    .SYNOPSIS
        Internal: reads all device enrollment configurations and adds ConfigurationType / IsDefault.

    .DESCRIPTION
        Restrictions, device limits, Enrollment Status Pages and Windows Hello settings all live in
        /deviceManagement/deviceEnrollmentConfigurations and are told apart by '@odata.type'.
        Uses beta: v1.0 does not return the per-platform restriction configurations.
        Output is sorted the way the Intune portal evaluates them: by priority, defaults last.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string[]]$ConfigurationType,

        [string]$Name,

        [switch]$IncludeAssignment
    )

    $typeMap = @{
        'deviceEnrollmentPlatformRestrictionsConfiguration'     = 'PlatformRestrictions'
        'deviceEnrollmentPlatformRestrictionConfiguration'      = 'PlatformRestriction'
        'deviceEnrollmentLimitConfiguration'                    = 'DeviceLimit'
        'windows10EnrollmentCompletionPageConfiguration'        = 'EnrollmentStatusPage'
        'deviceEnrollmentWindowsHelloForBusinessConfiguration'  = 'WindowsHelloForBusiness'
        'deviceComanagementAuthorityConfiguration'              = 'CoManagementAuthority'
        'windowsRestoreDeviceEnrollmentConfiguration'           = 'WindowsRestore'
    }

    $basePath = 'deviceManagement/deviceEnrollmentConfigurations'
    $configs = @(Invoke-ITGraphRequest -Uri $basePath -ApiVersion 'beta' -All)

    $result = foreach ($config in $configs) {
        $odataType = ''
        if ($config.PSObject.Properties['@odata.type']) { $odataType = ([string]$config.'@odata.type') -replace '^#microsoft\.graph\.', '' }
        $friendly = $typeMap[$odataType]
        if (-not $friendly) { $friendly = $odataType }

        if ($ConfigurationType -and ($ConfigurationType -notcontains $friendly)) { continue }
        if ($Name -and ($config.displayName -notlike $Name)) { continue }

        $isDefault = ([string]$config.id) -match '_Default'
        Add-Member -InputObject $config -NotePropertyName 'ConfigurationType' -NotePropertyValue $friendly -Force
        Add-Member -InputObject $config -NotePropertyName 'IsDefault' -NotePropertyValue $isDefault -Force

        if ($IncludeAssignment) {
            $assignments = @()
            try {
                $assignments = @(Get-ITAssignment -Path ('{0}/{1}' -f $basePath, $config.id) -ApiVersion 'beta')
            }
            catch {
                Write-Error -ErrorRecord $_
            }
            Add-Member -InputObject $config -NotePropertyName 'Assignments' -NotePropertyValue $assignments -Force
        }
        $config
    }

    $result | Sort-Object -Property @{ Expression = { [int]$_.IsDefault } }, @{ Expression = { if ($_.PSObject.Properties['priority']) { [int]$_.priority } else { 0 } } }
}
