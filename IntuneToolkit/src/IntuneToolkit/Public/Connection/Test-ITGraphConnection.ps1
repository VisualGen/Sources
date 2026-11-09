function Test-ITGraphConnection {
    <#
    .SYNOPSIS
        Tests whether a Microsoft Graph session exists and holds the required permissions.

    .DESCRIPTION
        Returns $true when connected and every -RequiredScope is granted. A '*.ReadWrite.*' scope
        also satisfies the matching '*.Read.*' scope.
        For app-only sessions without readable roles the scope check is skipped (Verbose message).

    .PARAMETER RequiredScope
        One or more permissions that must be present, e.g. 'DeviceManagementManagedDevices.Read.All'.

    .PARAMETER Detailed
        Returns an object (Connected, AuthType, TenantId, MissingScopes) instead of a boolean.

    .EXAMPLE
        Test-ITGraphConnection

        $true if any Graph session exists.

    .EXAMPLE
        if (-not (Test-ITGraphConnection -RequiredScope 'DeviceManagementManagedDevices.PrivilegedOperations.All')) {
            Connect-ITGraph -Scopes 'DeviceManagementManagedDevices.PrivilegedOperations.All'
        }

        Reconnects only when the privileged device-action permission is missing.

    .EXAMPLE
        Test-ITGraphConnection -RequiredScope 'DeviceManagementApps.Read.All' -Detailed

        Shows which scopes are missing.

    .OUTPUTS
        System.Boolean, or IntuneToolkit.ConnectionTest with -Detailed.

    .NOTES
        Graph permission: none.

    .LINK
        Connect-ITGraph
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    [OutputType('IntuneToolkit.ConnectionTest')]
    param(
        [string[]]$RequiredScope,

        [switch]$Detailed
    )

    $mg = Get-ITMgContext
    $missing = New-Object -TypeName System.Collections.Generic.List[string]

    if ($mg) {
        $granted = @($mg.Scopes | Where-Object { $_ })
        if ($mg.AuthType -eq 'AppOnly' -and $granted.Count -eq 0) {
            Write-ITLog -Message 'App-only session without role information: scope check skipped.'
        }
        else {
            foreach ($scope in @($RequiredScope | Where-Object { $_ })) {
                $broader = $scope -replace '\.Read\.', '.ReadWrite.'
                if (($granted -notcontains $scope) -and ($granted -notcontains $broader)) {
                    $missing.Add($scope)
                }
            }
        }
    }

    if ($Detailed) {
        [pscustomobject]@{
            PSTypeName    = 'IntuneToolkit.ConnectionTest'
            Connected     = [bool]$mg
            AuthType      = $(if ($mg) { [string]$mg.AuthType } else { $null })
            TenantId      = $(if ($mg) { $mg.TenantId } else { $null })
            MissingScopes = $missing.ToArray()
        }
    }
    else {
        [bool]$mg -and $missing.Count -eq 0
    }
}
