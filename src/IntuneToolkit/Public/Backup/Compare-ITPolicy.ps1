function Compare-ITPolicy {
    <#
    .SYNOPSIS
        Compares Export-ITPolicy backups with the current tenant (configuration drift).

    .DESCRIPTION
        For every export file the matching tenant object is read (by the exported ID, or by
        name with -MatchByName, e.g. after a tenant-to-tenant copy) and both are flattened to
        property paths. One row is returned per difference:
          Changed         - the value differs
          OnlyInBackup    - property set in the backup, missing in the tenant
          OnlyInTenant    - property set in the tenant, missing in the backup
          MissingInTenant - the whole object no longer exists
        Settings catalog settings are compared by setting definition ID; assignments are
        compared too (assignments.*). Timestamps, IDs and version are ignored.
        No output = no drift.

    .PARAMETER Path
        Export file(s) or folder(s) (searched recursively). Binds from FullName / Path.

    .PARAMETER MatchByName
        Find the tenant object by type + name instead of by ID.

    .PARAMETER ExcludeAssignment
        Do not compare assignments.

    .EXAMPLE
        Compare-ITPolicy -Path 'D:\IntuneBackup\2026-11-01'

        What changed since the last monthly backup.

    .EXAMPLE
        Compare-ITPolicy -Path .\Baseline\SettingsCatalog -MatchByName | Export-ITReport -Path .\drift.html -Title 'Drift'

    .OUTPUTS
        IntuneToolkit.PolicyDifference

    .NOTES
        Graph permission : DeviceManagementConfiguration.Read.All
        Graph endpoint   : GET /{collection}/{id} (+ /settings, /assignments)
        API version      : beta

    .LINK
        Export-ITPolicy
    #>
    [CmdletBinding()]
    [OutputType('IntuneToolkit.PolicyDifference')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Path,

        [switch]$MatchByName,

        [switch]$ExcludeAssignment
    )

    begin {
        Assert-ITGraphConnection -RequiredScope 'DeviceManagementConfiguration.Read.All'
        $ignore = @('id', 'createdDateTime', 'lastModifiedDateTime', 'version', 'settingCount', 'creationSource',
            'isAssigned', 'priorityMetaData', 'sourceId', 'source', '@odata.context', 'settingDefinitions')
        $listCache = @{}
    }

    process {
        $files = foreach ($item in $Path) {
            if (Test-Path -LiteralPath $item -PathType Container) { Get-ChildItem -LiteralPath $item -Filter '*.json' -Recurse -File }
            elseif (Test-Path -LiteralPath $item -PathType Leaf) { Get-Item -LiteralPath $item }
            else { Write-Error -Message "Path not found: $item" -Category ObjectNotFound -TargetObject $item }
        }

        foreach ($file in @($files | Where-Object { $_ })) {
            try {
                $backup = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                if (-not $backup.PSObject.Properties['IntuneToolkit']) { throw 'Not an IntuneToolkit export file.' }
                $meta = $backup.IntuneToolkit
                $type = [string]$meta.PolicyType
                $info = Get-ITPolicyTypeInfo -PolicyType $type
                $name = [string]$meta.DisplayName

                $tenantId = [string]$meta.SourceId
                if ($MatchByName) {
                    if (-not $listCache.ContainsKey($type)) { $listCache[$type] = @(Get-ITIntuneObject -TypeInfo $info) }
                    $hit = @($listCache[$type] | Where-Object { [string]$_.displayName -eq $name })
                    $tenantId = $null
                    if ($hit.Count) { $tenantId = $hit[0].id }
                    if ($hit.Count -gt 1) { Write-Warning -Message "$type '$name': $($hit.Count) objects with this name, comparing the first." }
                }

                $current = $null
                if ($tenantId) {
                    try {
                        $current = Get-ITPolicyExport -TypeInfo $info -Id $tenantId
                    }
                    catch {
                        if ($_.Exception.Message -notmatch 'HTTP 404|HTTP 400') { throw }
                    }
                }

                $row = { param($prop, $change, $old, $new)
                    [pscustomobject]@{
                        PSTypeName  = 'IntuneToolkit.PolicyDifference'
                        PolicyType  = $type
                        DisplayName = $name
                        Property    = $prop
                        Change      = $change
                        BackupValue = $old
                        TenantValue = $new
                        TenantId    = $tenantId
                        Path        = $file.FullName
                    }
                }

                if (-not $current) {
                    & $row '(object)' 'MissingInTenant' $meta.SourceId $null
                    continue
                }

                $left  = ConvertTo-ITFlatHashtable -InputObject $backup.Object -Ignore $ignore -Result @{}
                $right = ConvertTo-ITFlatHashtable -InputObject ([pscustomobject]$current.Object) -Ignore $ignore -Result @{}
                if (-not $ExcludeAssignment) {
                    $leftAssign = @()
                    if ($backup.PSObject.Properties['Assignments']) { $leftAssign = @($backup.Assignments | Where-Object { $_ } | ForEach-Object { $_.target }) }
                    $rightAssign = @($current.Assignments | Where-Object { $_ } | ForEach-Object { $_.target })
                    $null = ConvertTo-ITFlatHashtable -InputObject (ConvertTo-ITAssignmentKey $leftAssign) -Prefix 'assignments' -Result $left
                    $null = ConvertTo-ITFlatHashtable -InputObject (ConvertTo-ITAssignmentKey $rightAssign) -Prefix 'assignments' -Result $right
                }

                foreach ($key in @($left.Keys + $right.Keys | Sort-Object -Unique)) {
                    $inLeft = $left.ContainsKey($key)
                    $inRight = $right.ContainsKey($key)
                    if ($inLeft -and $inRight) {
                        if ([string]$left[$key] -cne [string]$right[$key]) { & $row $key 'Changed' $left[$key] $right[$key] }
                    }
                    elseif ($inLeft) {
                        if ([string]$left[$key] -ne '') { & $row $key 'OnlyInBackup' $left[$key] $null }
                    }
                    elseif ([string]$right[$key] -ne '') {
                        & $row $key 'OnlyInTenant' $null $right[$key]
                    }
                }
            }
            catch {
                Write-Error -ErrorRecord $_
            }
        }
    }
}
