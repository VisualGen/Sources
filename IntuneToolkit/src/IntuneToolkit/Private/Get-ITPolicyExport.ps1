function Get-ITPolicyExport {
    <#
    .SYNOPSIS
        Internal: reads one Intune object completely and returns the export document (ordered hashtable).

    .DESCRIPTION
        Used by Export-ITPolicy (written to JSON) and Compare-ITPolicy (compared with a backup).
        Document layout (SchemaVersion 1):
          IntuneToolkit : PolicyType, SchemaVersion, ExportedAt, TenantId, SourceId, DisplayName, ModuleVersion
          Object        : the Graph object (beta) incl. settings (settings catalog),
                          scheduledActionsForRule (compliance) and scriptContent (scripts)
          Assignments   : the raw assignments
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$TypeInfo,

        [Parameter(Mandatory)]
        [string]$Id
    )

    $uri = New-ITGraphUri -Path ('{0}/{1}' -f $TypeInfo.Path, $Id) -Expand $TypeInfo.ExportExpand
    $object = Invoke-ITGraphRequest -Uri $uri -ApiVersion 'beta'

    if ($TypeInfo.PolicyType -eq 'SettingsCatalog') {
        # Separate call with paging: $expand=settings may truncate large policies
        $settings = @(Invoke-ITGraphRequest -Uri ('{0}/{1}/settings' -f $TypeInfo.Path, $Id) -ApiVersion 'beta' -All)
        Add-Member -InputObject $object -NotePropertyName 'settings' -NotePropertyValue $settings -Force
    }

    foreach ($prop in @($object.PSObject.Properties | Where-Object { $_.Name -like '*@odata.*' -and $_.Name -ne '@odata.type' })) {
        $object.PSObject.Properties.Remove($prop.Name)
    }

    $assignments = @()
    try {
        $assignments = @(Get-ITAssignment -Path ('{0}/{1}' -f $TypeInfo.Path, $Id) -ApiVersion 'beta' -Raw)
    }
    catch {
        Write-Warning -Message ('{0} {1}: assignments not read: {2}' -f $TypeInfo.PolicyType, $Id, $_.Exception.Message)
    }

    $nameProp = $TypeInfo.NameProperty
    $displayName = $null
    if ($object.PSObject.Properties[$nameProp]) { $displayName = $object.$nameProp }

    $tenantId = $null
    $context = Get-MgContext
    if ($context) { $tenantId = $context.TenantId }

    $moduleVersion = $null
    if ($MyInvocation.MyCommand.Module) { $moduleVersion = [string]$MyInvocation.MyCommand.Module.Version }

    [ordered]@{
        IntuneToolkit = [ordered]@{
            PolicyType    = $TypeInfo.PolicyType
            SchemaVersion = 1
            ExportedAt    = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            TenantId      = $tenantId
            SourceId      = $Id
            DisplayName   = $displayName
            ModuleVersion = $moduleVersion
        }
        Object        = $object
        Assignments   = $assignments
    }
}
