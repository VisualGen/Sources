function Resume-ITUpdateRing {
    <#
    .SYNOPSIS
        Resumes paused quality and/or feature updates of a Windows update ring.

    .DESCRIPTION
        Clears qualityUpdatesPaused / featureUpdatesPaused on the ring.

    .PARAMETER Id
        Update ring ID(s). Binds from Get-ITUpdateRing objects.

    .PARAMETER UpdateType
        Quality (default), Feature or Both.

    .EXAMPLE
        Get-ITUpdateRing | Where-Object qualityUpdatesPaused | Resume-ITUpdateRing -WhatIf

    .OUTPUTS
        IntuneToolkit.UpdateRing

    .NOTES
        Graph permission : DeviceManagementConfiguration.ReadWrite.All
        Graph endpoint   : PATCH /deviceManagement/deviceConfigurations/{id}
        API version      : beta

    .LINK
        Suspend-ITUpdateRing
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType('IntuneToolkit.UpdateRing')]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Id,

        [ValidateSet('Quality', 'Feature', 'Both')]
        [string]$UpdateType = 'Quality'
    )

    begin {
        Assert-ITGraphConnection -RequiredScope 'DeviceManagementConfiguration.ReadWrite.All'
    }

    process {
        $info = Get-ITPolicyTypeInfo -PolicyType UpdateRing
        foreach ($ringId in $Id) {
            $ring = @(Get-ITIntuneObject -TypeInfo $info -Id $ringId)
            if (-not $ring.Count) {
                Write-Error -Message "Update ring $ringId not found (or it is not a Windows update ring)." -Category ObjectNotFound -TargetObject $ringId
                continue
            }
            $label = "Update ring '{0}' ({1})" -f $ring[0].displayName, $ringId
            if ($PSCmdlet.ShouldProcess($label, ('Resume {0} updates' -f $UpdateType.ToLower()))) {
                try { Send-ITUpdateRingPause -Id $ringId -UpdateType $UpdateType -Paused $false }
                catch { Write-Error -ErrorRecord $_ }
            }
        }
    }
}
