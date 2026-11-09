function ConvertTo-ITSettingList {
    <#
    .SYNOPSIS
        Internal: flattens a settings catalog settingInstance tree to SettingDefinitionId / Value rows.

    .DESCRIPTION
        Handles choice, simple, simple collection, choice collection and group collection
        instances and walks their children recursively (depth-capped at 20).
        Choice values are returned as the option ID (e.g. 'device_vendor_msft_..._1').
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$SettingInstance,

        [int]$Depth = 0
    )

    if ($Depth -gt 20 -or $null -eq $SettingInstance) { return }
    $has = { param($o, $n) $null -ne $o -and [bool]$o.PSObject.Properties[$n] }

    $definitionId = $null
    if (& $has $SettingInstance 'settingDefinitionId') { $definitionId = $SettingInstance.settingDefinitionId }

    $children = @()
    $value = $null

    if (& $has $SettingInstance 'choiceSettingValue') {
        $choice = $SettingInstance.choiceSettingValue
        if (& $has $choice 'value') { $value = $choice.value }
        if (& $has $choice 'children') { $children += @($choice.children) }
    }
    elseif (& $has $SettingInstance 'simpleSettingValue') {
        $simple = $SettingInstance.simpleSettingValue
        if (& $has $simple 'value') { $value = $simple.value }
    }
    elseif (& $has $SettingInstance 'simpleSettingCollectionValue') {
        $value = @($SettingInstance.simpleSettingCollectionValue | Where-Object { $_ } | ForEach-Object { $_.value }) -join '; '
    }
    elseif (& $has $SettingInstance 'choiceSettingCollectionValue') {
        $values = foreach ($entry in @($SettingInstance.choiceSettingCollectionValue | Where-Object { $_ })) {
            if (& $has $entry 'children') { $children += @($entry.children) }
            $entry.value
        }
        $value = @($values) -join '; '
    }
    elseif (& $has $SettingInstance 'groupSettingCollectionValue') {
        foreach ($group in @($SettingInstance.groupSettingCollectionValue | Where-Object { $_ })) {
            if (& $has $group 'children') { $children += @($group.children) }
        }
    }

    if ($null -ne $value) {
        [pscustomobject]@{
            PSTypeName          = 'IntuneToolkit.SettingValue'
            SettingDefinitionId = $definitionId
            Value               = $value
        }
    }
    foreach ($child in @($children | Where-Object { $_ })) {
        ConvertTo-ITSettingList -SettingInstance $child -Depth ($Depth + 1)
    }
}
