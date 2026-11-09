function Send-ITUpdateRingPause {
    <#
    .SYNOPSIS
        Internal: sets or clears the quality/feature pause of one update ring (PATCH) and returns the ring.

    .DESCRIPTION
        Used by Suspend-ITUpdateRing and Resume-ITUpdateRing, which handle ShouldProcess.
        Graph needs the @odata.type in a PATCH of a deviceConfiguration.
    #>
    [CmdletBinding()]
    [OutputType('IntuneToolkit.UpdateRing')]
    param(
        [Parameter(Mandatory)]
        [string]$Id,

        [Parameter(Mandatory)]
        [ValidateSet('Quality', 'Feature', 'Both')]
        [string]$UpdateType,

        [Parameter(Mandatory)]
        [bool]$Paused
    )

    $info = Get-ITPolicyTypeInfo -PolicyType UpdateRing
    $body = @{ '@odata.type' = $info.ODataType }
    if ($UpdateType -ne 'Feature') { $body['qualityUpdatesPaused'] = $Paused }
    if ($UpdateType -ne 'Quality') { $body['featureUpdatesPaused'] = $Paused }

    $null = Invoke-ITGraphRequest -Uri ('{0}/{1}' -f $info.Path, $Id) -Method PATCH -Body $body -ApiVersion 'beta'
    Write-ITLog -Message ('Update ring {0}: {1} updates paused = {2}' -f $Id, $UpdateType, $Paused)
    Get-ITIntuneObject -TypeInfo $info -Id $Id
}
