function Add-ITAppAssignment {
    <#
    .SYNOPSIS
        Assigns an Intune app to a group, all devices or all users as required, available or uninstall.

    .DESCRIPTION
        Adds ONE target and keeps the existing assignments. A target that already exists is
        reported as 'Unchanged' (change the intent by removing it first). Exclusions use -Exclude
        (no intent needed). Win32 apps can get delivery options with -Notification and
        -DeliveryOptimizationPriority.

    .PARAMETER Id
        App ID. Binds from the id of Get-ITApp objects.

    .PARAMETER Intent
        required, available, uninstall or availableWithoutEnrollment.

    .PARAMETER GroupId
        Entra group object ID.

    .PARAMETER Exclude
        Exclude the group.

    .PARAMETER AllDevices
        Assign to all devices.

    .PARAMETER AllUsers
        Assign to all licensed users.

    .PARAMETER FilterId
        Assignment filter ID (Get-ITAssignmentFilter). Not allowed on exclusions.

    .PARAMETER FilterType
        'include' (default) or 'exclude'.

    .PARAMETER Notification
        Win32 / WinGet apps: end-user notifications (showAll, showReboot, hideAll).

    .PARAMETER DeliveryOptimizationPriority
        Win32 apps: notConfigured (background) or foreground.

    .EXAMPLE
        Get-ITApp -Name '7-Zip' | Add-ITAppAssignment -Intent required -GroupId $pilotGroup -WhatIf

    .EXAMPLE
        Get-ITApp -Name 'Company Portal' | Add-ITAppAssignment -Intent available -AllUsers

    .EXAMPLE
        Add-ITAppAssignment -Id $appId -GroupId $kioskGroup -Exclude

    .OUTPUTS
        IntuneToolkit.AssignmentChange

    .NOTES
        Graph permission : DeviceManagementApps.ReadWrite.All
        Graph endpoint   : GET /deviceAppManagement/mobileApps/{id}/assignments, POST /deviceAppManagement/mobileApps/{id}/assign
        API version      : beta

    .LINK
        Remove-ITAppAssignment
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'Group')]
    [OutputType('IntuneToolkit.AssignmentChange')]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string]$Id,

        [Parameter(ParameterSetName = 'Group')]
        [Parameter(Mandatory, ParameterSetName = 'AllDevices')]
        [Parameter(Mandatory, ParameterSetName = 'AllUsers')]
        [ValidateSet('required', 'available', 'uninstall', 'availableWithoutEnrollment')]
        [string]$Intent,

        [Parameter(Mandatory, ParameterSetName = 'Group')]
        [ValidateNotNullOrEmpty()]
        [string]$GroupId,

        [Parameter(ParameterSetName = 'Group')]
        [switch]$Exclude,

        [Parameter(Mandatory, ParameterSetName = 'AllDevices')]
        [switch]$AllDevices,

        [Parameter(Mandatory, ParameterSetName = 'AllUsers')]
        [switch]$AllUsers,

        [ValidateNotNullOrEmpty()]
        [string]$FilterId,

        [ValidateSet('include', 'exclude')]
        [string]$FilterType = 'include',

        [ValidateSet('showAll', 'showReboot', 'hideAll')]
        [string]$Notification,

        [ValidateSet('notConfigured', 'foreground')]
        [string]$DeliveryOptimizationPriority
    )

    begin {
        $info = Get-ITPolicyTypeInfo -PolicyType App
        Assert-ITGraphConnection -RequiredScope $info.WriteScope
    }

    process {
        if ($AllDevices) { $target = 'AllDevices' }
        elseif ($AllUsers) { $target = 'AllUsers' }
        elseif ($Exclude) { $target = 'Exclude' }
        else { $target = 'Include' }
        if ($target -ne 'Exclude' -and -not $Intent) {
            Write-Error -Message '-Intent is required (required, available, uninstall) unless -Exclude is used.' -Category InvalidArgument
            return
        }

        $objectName = $null
        $appType = $null
        if ($_ -and $_.PSObject.Properties['displayName']) { $objectName = $_.displayName }
        if ($_ -and $_.PSObject.Properties['ObjectType']) { $appType = [string]$_.ObjectType }

        $assignIntent = $Intent
        if ($target -eq 'Exclude') { $assignIntent = 'required' }   # Graph needs an intent; ignored for exclusions
        $extra = @{ '@odata.type' = '#microsoft.graph.mobileAppAssignment'; intent = $assignIntent }

        if ($Notification -or $DeliveryOptimizationPriority) {
            # WinGet (new Store) apps have their own settings type without delivery optimization
            if ($appType -eq 'winGetApp') {
                $settings = @{ '@odata.type' = '#microsoft.graph.winGetAppAssignmentSettings' }
            }
            else {
                $settings = @{ '@odata.type' = '#microsoft.graph.win32LobAppAssignmentSettings' }
                if ($DeliveryOptimizationPriority) { $settings['deliveryOptimizationPriority'] = $DeliveryOptimizationPriority }
            }
            if ($Notification) { $settings['notifications'] = $Notification }
            $extra['settings'] = $settings
        }

        $label = '{0} {1}' -f $Intent, $target
        if ($GroupId) { $label = '{0} group {1}' -f $label, $GroupId }
        $what = 'App {0}' -f $(if ($objectName) { "'$objectName' ($Id)" } else { $Id })
        if ($PSCmdlet.ShouldProcess($what, "Add assignment: $label")) {
            Invoke-ITAssignmentChange -TypeInfo $info -Id $Id -ObjectName $objectName -Mode Add -Intent $target -GroupId $GroupId `
                -FilterId $FilterId -FilterType $FilterType -Extra $extra
        }
    }
}
