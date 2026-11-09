function Wait-ITContentFileState {
    <#
    .SYNOPSIS
        Internal: polls an app content file until its uploadState reaches the success state.

    .DESCRIPTION
        Polls every -IntervalSeconds, at most -MaxPoll times (hard cap). Throws when the
        failure state (or any '*Failed' / '*TimedOut' state) is reported or the cap is reached.
        Returns the last content file object.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter(Mandatory)]
        [string]$SuccessState,

        [Parameter(Mandatory)]
        [string]$FailureState,

        [int]$IntervalSeconds = 5,

        [int]$MaxPoll = 60
    )

    for ($poll = 1; $poll -le $MaxPoll; $poll++) {
        $file = Invoke-ITGraphRequest -Uri $Uri -ApiVersion 'beta'
        $state = ''
        if ($file -and $file.PSObject.Properties['uploadState']) { $state = [string]$file.uploadState }
        if ($state -eq $SuccessState) { return $file }
        if ($state -eq $FailureState -or $state -like '*Failed' -or $state -like '*TimedOut') {
            throw "App content upload failed: state '$state'."
        }
        Write-Verbose -Message "Content file state '$state' - waiting for '$SuccessState' ($poll/$MaxPoll)."
        Start-Sleep -Seconds $IntervalSeconds
    }
    throw "App content upload: '$SuccessState' not reached after $MaxPoll checks."
}
