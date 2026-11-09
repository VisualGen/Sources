function ConvertTo-ITFlatHashtable {
    <#
    .SYNOPSIS
        Internal: flattens an object tree to 'path' = 'value' pairs for comparison.

    .DESCRIPTION
        Nested objects become 'parent.child', array items 'list[0].name'. Arrays of plain
        values are kept as one comma-separated value (order-insensitive: sorted).
        Settings catalog 'settings' are flattened by settingDefinitionId (not by position),
        so a re-ordered policy does not show as changed. Keys in -Ignore are skipped at any
        level. Depth-capped at 30.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowNull()]
        [object]$InputObject,

        [string]$Prefix = '',

        [string[]]$Ignore = @(),

        [hashtable]$Result = @{},

        [int]$Depth = 0
    )

    if ($Depth -gt 30) { $Result[$Prefix] = '<too deep>'; return $Result }

    if ($null -eq $InputObject) {
        if ($Prefix) { $Result[$Prefix] = $null }
        return $Result
    }

    $isScalar = $InputObject -is [string] -or $InputObject -is [ValueType]
    if ($isScalar) {
        # Dates come back as DateTime or as ISO strings depending on the JSON reader: normalise
        $value = $InputObject
        if ($value -is [string] -and $value -match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}') {
            $parsed = [datetime]::MinValue
            if ([datetime]::TryParse($value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$parsed)) { $value = $parsed }
        }
        if ($value -is [datetime]) {
            $value = $value.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
        }
        elseif ($value -is [bool]) {
            $value = ([string]$value).ToLowerInvariant()
        }
        $Result[$Prefix] = [string]$value
        return $Result
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $InputObject = [pscustomobject]$InputObject
    }

    if ($InputObject -is [System.Collections.IEnumerable]) {
        $items = @($InputObject)
        if (-not $items.Count) { $Result[$Prefix] = ''; return $Result }
        $allScalar = -not @($items | Where-Object { $null -ne $_ -and -not ($_ -is [string] -or $_ -is [ValueType]) }).Count
        if ($allScalar) {
            $Result[$Prefix] = (@($items | ForEach-Object { [string]$_ }) | Sort-Object) -join ','
            return $Result
        }
        $leaf = $Prefix
        if ($leaf -match '\.') { $leaf = $leaf.Substring($leaf.LastIndexOf('.') + 1) }
        if ($leaf -eq 'settings') {
            foreach ($row in @($items | Where-Object { $_ -and $_.PSObject.Properties['settingInstance'] } | ForEach-Object { ConvertTo-ITSettingList -SettingInstance $_.settingInstance })) {
                $key = 'setting:{0}' -f $row.SettingDefinitionId
                $n = 1
                while ($Result.ContainsKey($key)) { $n++; $key = 'setting:{0}#{1}' -f $row.SettingDefinitionId, $n }
                $Result[$key] = [string]$row.Value
            }
            return $Result
        }
        for ($i = 0; $i -lt $items.Count; $i++) {
            $null = ConvertTo-ITFlatHashtable -InputObject $items[$i] -Prefix ('{0}[{1}]' -f $Prefix, $i) -Ignore $Ignore -Result $Result -Depth ($Depth + 1)
        }
        return $Result
    }

    foreach ($prop in $InputObject.PSObject.Properties) {
        if ($Ignore -contains $prop.Name) { continue }
        $key = $prop.Name
        if ($Prefix) { $key = '{0}.{1}' -f $Prefix, $prop.Name }
        $null = ConvertTo-ITFlatHashtable -InputObject $prop.Value -Prefix $key -Ignore $Ignore -Result $Result -Depth ($Depth + 1)
    }
    $Result
}
