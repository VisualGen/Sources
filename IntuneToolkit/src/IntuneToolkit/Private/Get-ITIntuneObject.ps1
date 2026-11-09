function Get-ITIntuneObject {
    <#
    .SYNOPSIS
        Internal: shared list/get logic for policies, profiles, scripts and apps.

    .DESCRIPTION
        - By Id: one GET per ID (errors are non-terminating so the rest continues).
        - Otherwise: the whole collection with paging, then -Name (wildcard) locally.
        - Keeps only objects of TypeInfo.ODataType when that is set (update rings).
        - Adds PolicyType (so the result pipes into Get/Add/Remove-ITPolicyAssignment),
          ObjectType (@odata.type without the namespace) and Platform.
        - -IncludeAssignment adds Assignments (flat Get-ITAssignment objects).
        - -Expand is passed to Graph ($expand), e.g. 'settings' for the settings catalog.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$TypeInfo,

        [string]$Name,

        [string[]]$Id,

        [switch]$IncludeAssignment,

        [ValidateSet('v1.0', 'beta')]
        [string]$ApiVersion = $TypeInfo.ApiVersion,

        [string]$Expand,

        [string]$Filter
    )

    $basePath = $TypeInfo.Path
    $nameProp = $TypeInfo.NameProperty

    if ($Id) {
        $items = foreach ($objectId in $Id) {
            try {
                $uri = New-ITGraphUri -Path ('{0}/{1}' -f $basePath, $objectId) -Expand $Expand
                Invoke-ITGraphRequest -Uri $uri -ApiVersion $ApiVersion
            }
            catch {
                Write-Error -ErrorRecord $_
            }
        }
    }
    else {
        $uri = New-ITGraphUri -Path $basePath -Expand $Expand -Filter $Filter
        $items = Invoke-ITGraphRequest -Uri $uri -ApiVersion $ApiVersion -All
        if ($Name) {
            $items = $items | Where-Object { $_.PSObject.Properties[$nameProp] -and $_.$nameProp -like $Name }
        }
    }

    foreach ($item in @($items | Where-Object { $_ })) {
        $odataType = ''
        if ($item.PSObject.Properties['@odata.type']) { $odataType = [string]$item.'@odata.type' }
        if ($TypeInfo.ODataType -and $odataType -ne $TypeInfo.ODataType) { continue }

        Add-Member -InputObject $item -NotePropertyName 'PolicyType' -NotePropertyValue $TypeInfo.PolicyType -Force
        Add-Member -InputObject $item -NotePropertyName 'ObjectType' -NotePropertyValue ($odataType -replace '^#microsoft\.graph\.', '') -Force
        Add-Member -InputObject $item -NotePropertyName 'Platform' -NotePropertyValue (Get-ITPlatform -InputObject $item) -Force

        # Uniform display name (settings catalog uses 'name')
        if ($nameProp -ne 'displayName' -and -not $item.PSObject.Properties['displayName'] -and $item.PSObject.Properties[$nameProp]) {
            Add-Member -InputObject $item -NotePropertyName 'displayName' -NotePropertyValue $item.$nameProp -Force
        }

        if ($IncludeAssignment) {
            $assignments = @()
            try {
                $assignments = @(Get-ITAssignment -Path ('{0}/{1}' -f $basePath, $item.id) -ApiVersion 'beta')
            }
            catch {
                Write-Error -ErrorRecord $_
            }
            Add-Member -InputObject $item -NotePropertyName 'Assignments' -NotePropertyValue $assignments -Force
        }
        $item | ConvertTo-ITObject -TypeName $TypeInfo.TypeName
    }
}
