function ConvertTo-ITObject {
    <#
    .SYNOPSIS
        Internal: tags Graph objects with an IntuneToolkit type name and removes OData noise.

    .DESCRIPTION
        Adds 'IntuneToolkit.<TypeName>' at the top of PSObject.TypeNames so format files
        (.ps1xml) and pipeline binding can target our objects, and strips '@odata.context'
        style properties. '@odata.type' is kept because it identifies the Intune object subtype.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$TypeName
    )

    process {
        if ($null -eq $InputObject) { return }

        if ($InputObject -is [System.Collections.IDictionary]) {
            $InputObject = [pscustomobject]$InputObject
        }

        $odata = $InputObject.PSObject.Properties | Where-Object { $_.Name -like '@odata.*' -and $_.Name -ne '@odata.type' }
        $remove = @($odata | ForEach-Object { $_.Name })
        foreach ($name in $remove) { $InputObject.PSObject.Properties.Remove($name) }

        $fullName = "IntuneToolkit.$TypeName"
        if ($InputObject.PSObject.TypeNames[0] -ne $fullName) {
            $InputObject.PSObject.TypeNames.Insert(0, $fullName)
        }
        $InputObject
    }
}
