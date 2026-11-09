function Get-ITEnrollmentStatusPage {
    <#
    .SYNOPSIS
        Gets the Windows Enrollment Status Page (ESP) profiles.

    .DESCRIPTION
        Returns the ESP configurations in evaluation order (by priority, the built-in default
        last). Key properties: showInstallationProgress, installProgressTimeoutInMinutes,
        blockDeviceSetupRetryByUser, allowDeviceResetOnInstallFailure,
        trackInstallProgressForAutopilotOnly and selectedMobileAppIds (blocking apps).

    .PARAMETER Name
        Display name. Wildcards allowed.

    .PARAMETER IncludeAssignment
        Also read the group assignments of each ESP profile.

    .EXAMPLE
        Get-ITEnrollmentStatusPage

    .EXAMPLE
        Get-ITEnrollmentStatusPage |
            Select-Object displayName, priority, installProgressTimeoutInMinutes, @{ n = 'BlockingApps'; e = { @($_.selectedMobileAppIds).Count } }

        Timeout and number of blocking apps per ESP profile.

    .OUTPUTS
        IntuneToolkit.EnrollmentConfiguration

    .NOTES
        Graph permission : DeviceManagementServiceConfig.Read.All
        Graph endpoint   : GET /deviceManagement/deviceEnrollmentConfigurations
                           (type windows10EnrollmentCompletionPageConfiguration)
        API version      : beta

    .LINK
        https://learn.microsoft.com/graph/api/resources/intune-onboarding-windows10enrollmentcompletionpageconfiguration?view=graph-rest-beta
    #>
    [CmdletBinding()]
    [OutputType('IntuneToolkit.EnrollmentConfiguration')]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [switch]$IncludeAssignment
    )

    Assert-ITGraphConnection -RequiredScope 'DeviceManagementServiceConfig.Read.All'

    $params = @{ ConfigurationType = 'EnrollmentStatusPage'; IncludeAssignment = $IncludeAssignment }
    if ($Name) { $params['Name'] = $Name }

    Get-ITEnrollmentConfiguration @params | ConvertTo-ITObject -TypeName 'EnrollmentConfiguration'
}
