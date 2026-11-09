function Import-ITPolicy {
    <#
    .SYNOPSIS
        Restores policies from Export-ITPolicy JSON files, in the same or another tenant.

    .DESCRIPTION
        Creates a NEW object from each export file (an existing object is never overwritten).
        Read-only properties are removed first. An object with the same name and type that
        already exists is skipped (Status 'Exists') unless -AllowDuplicate is used, so a
        restore can be re-run safely.
        Cross-tenant: scope tags are removed (they do not exist in the target tenant) and
        assignments are NOT applied (group IDs differ). In the source tenant -IncludeAssignment
        re-applies the exported assignments.
        Settings that Graph never exports (passwords, keys, certificates) must be re-entered.

    .PARAMETER Path
        Export file(s) or folder(s). Folders are searched recursively for *.json.
        Binds from FullName / Path (Get-ChildItem, Export-ITPolicy output).

    .PARAMETER NamePrefix
        Text put in front of every imported name, e.g. 'Restored - '.

    .PARAMETER NameSuffix
        Text appended to every imported name, e.g. ' (copy)'.

    .PARAMETER IncludeAssignment
        Re-apply the exported assignments (only when importing into the tenant the export came from).

    .PARAMETER AllowDuplicate
        Create the object even when one with the same name already exists.

    .EXAMPLE
        Import-ITPolicy -Path 'D:\IntuneBackup\2026-11-01\SettingsCatalog' -WhatIf

        Show what would be created.

    .EXAMPLE
        Import-ITPolicy -Path .\Backup\Compliance\Win-Baseline__1a2b.json -NamePrefix 'Restored - ' -IncludeAssignment

    .EXAMPLE
        Export-ITPolicy -Path .\Copy -PolicyType SettingsCatalog -Name 'Win - *'
        Connect-ITGraph -TenantId 'contoso-test.onmicrosoft.com' -Scopes 'DeviceManagementConfiguration.ReadWrite.All'
        Import-ITPolicy -Path .\Copy

        Copy policies from production to a test tenant.

    .OUTPUTS
        IntuneToolkit.PolicyImportResult

    .NOTES
        Graph permission : DeviceManagementConfiguration.ReadWrite.All
        Graph endpoint   : POST /{collection}, POST /{collection}/{id}/assign
        API version      : beta

    .LINK
        Export-ITPolicy
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType('IntuneToolkit.PolicyImportResult')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Path,

        [string]$NamePrefix = '',

        [string]$NameSuffix = '',

        [switch]$IncludeAssignment,

        [switch]$AllowDuplicate
    )

    begin {
        Assert-ITGraphConnection -RequiredScope 'DeviceManagementConfiguration.ReadWrite.All'
        $context = Get-MgContext
        $currentTenant = $null
        if ($context) { $currentTenant = [string]$context.TenantId }
        $nameCache = @{}
    }

    process {
        $files = foreach ($item in $Path) {
            if (Test-Path -LiteralPath $item -PathType Container) {
                Get-ChildItem -LiteralPath $item -Filter '*.json' -Recurse -File
            }
            elseif (Test-Path -LiteralPath $item -PathType Leaf) {
                Get-Item -LiteralPath $item
            }
            else {
                Write-Error -Message "Path not found: $item" -Category ObjectNotFound -TargetObject $item
            }
        }

        foreach ($file in @($files | Where-Object { $_ })) {
            $result = [ordered]@{
                PSTypeName = 'IntuneToolkit.PolicyImportResult'
                PolicyType = $null; DisplayName = $null; SourceId = $null; NewId = $null
                Status     = 'Failed'; Message = $null; Path = $file.FullName
            }
            try {
                $doc = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                if (-not $doc.PSObject.Properties['IntuneToolkit'] -or -not $doc.PSObject.Properties['Object']) {
                    throw 'Not an IntuneToolkit export file (IntuneToolkit/Object sections missing).'
                }
                $meta = $doc.IntuneToolkit
                $type = [string]$meta.PolicyType
                $info = Get-ITPolicyTypeInfo -PolicyType $type
                $result.PolicyType = $type
                $result.SourceId   = $meta.SourceId

                $sameTenant = $currentTenant -and ([string]$meta.TenantId -eq $currentTenant)
                $newName = '{0}{1}{2}' -f $NamePrefix, [string]$meta.DisplayName, $NameSuffix
                $result.DisplayName = $newName

                if (-not $AllowDuplicate) {
                    if (-not $nameCache.ContainsKey($type)) {
                        $nameCache[$type] = @(Get-ITIntuneObject -TypeInfo $info | ForEach-Object { [string]$_.displayName })
                    }
                    if ($nameCache[$type] -contains $newName) {
                        $result.Status  = 'Exists'
                        $result.Message = 'An object with this name already exists (use -AllowDuplicate or -NamePrefix).'
                        [pscustomobject]$result
                        continue
                    }
                }

                $body = ConvertTo-ITImportBody -PolicyType $type -Object $doc.Object -NewName $newName -RemoveScopeTag:(-not $sameTenant)

                if (-not $PSCmdlet.ShouldProcess("$type '$newName'", 'Create from backup')) {
                    $result.Status = 'WhatIf'
                    [pscustomobject]$result
                    continue
                }

                $created = Invoke-ITGraphRequest -Uri $info.Path -Method POST -Body $body -ApiVersion 'beta'
                $result.NewId  = $created.id
                $result.Status = 'Created'
                if ($nameCache.ContainsKey($type)) { $nameCache[$type] += $newName }
                Write-ITLog -Message ('Imported {0} {1} as {2}' -f $type, $meta.SourceId, $created.id)

                $exported = @()
                if ($doc.PSObject.Properties['Assignments']) { $exported = @($doc.Assignments | Where-Object { $_ }) }
                if ($IncludeAssignment -and $exported.Count) {
                    if (-not $sameTenant) {
                        $result.Message = 'Assignments not applied: the export is from another tenant (group IDs differ).'
                    }
                    else {
                        $add = foreach ($a in $exported) {
                            $h = @{}
                            foreach ($p in $a.PSObject.Properties) {
                                if (@('id', 'source', 'sourceId') -notcontains $p.Name -and $p.Name -notlike '*@odata.context') { $h[$p.Name] = $p.Value }
                            }
                            $h
                        }
                        $count = Send-ITAssignmentSet -TypeInfo $info -Id $created.id -Add @($add)
                        $result.Message = '{0} assignment(s) applied.' -f $count
                    }
                }
            }
            catch {
                $result.Message = $_.Exception.Message
                Write-Error -ErrorRecord $_
            }
            [pscustomobject]$result
        }
    }
}
