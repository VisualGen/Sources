function Resolve-ITDirectoryObject {
    <#
    .SYNOPSIS
        Internal: turns a user, group or device reference into { Id, DisplayName, ObjectType }.

    .DESCRIPTION
        Accepted input:
          - a UPN ('jane@contoso.com')                       -> user
          - an object ID (user, group, device)                -> tried as user, group, device
          - an Entra device ID (deviceId / azureADDeviceId)   -> device
          - an exact group or device display name             -> group, then device (must be unique)
          - objects from IntuneToolkit: groups, group members, managed devices (azureADDeviceId),
            Autopilot devices (azureActiveDirectoryDeviceId), or any object with @odata.type + id.
        Results are cached in -Cache (key = input text) so a long pipeline does not repeat lookups.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$InputObject,

        [hashtable]$Cache
    )

    $guidPattern = '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$'
    $emptyGuid   = '00000000-0000-0000-0000-000000000000'
    $isNotFound  = { param($err) $err.Exception.Message -match 'HTTP 404|Request_ResourceNotFound|ResourceNotFound' }

    $make = {
        param($Id, $DisplayName, $ObjectType)
        [pscustomobject]@{ Id = [string]$Id; DisplayName = [string]$DisplayName; ObjectType = $ObjectType }
    }

    $findDevice = {
        param([string]$DeviceId)
        if ($DeviceId -eq $emptyGuid) { throw 'The device is not registered in Entra ID (empty device ID).' }
        $uri = New-ITGraphUri -Path 'devices' -Filter ("deviceId eq '{0}'" -f $DeviceId) -Select 'id', 'displayName'
        $hit = @(Invoke-ITGraphRequest -Uri $uri -ApiVersion 'v1.0')
        if ($hit.Count -eq 0) { throw "No Entra ID device with device ID '$DeviceId'." }
        & $make $hit[0].id $hit[0].displayName 'Device'
    }

    # --- Objects ----------------------------------------------------------------
    if ($InputObject -isnot [string]) {
        $o = $InputObject
        $names = @($o.PSObject.TypeNames)
        $prop  = { param($n) if ($o.PSObject.Properties[$n]) { $o.$n } else { $null } }

        if ($names -contains 'IntuneToolkit.Group') {
            return (& $make $o.id $o.displayName 'Group')
        }
        if ($names -contains 'IntuneToolkit.GroupMember' -and (& $prop 'MemberType')) {
            return (& $make $o.id $o.displayName $o.MemberType)
        }
        $type = Get-ITDirectoryObjectType -InputObject $o
        if ($type -ne 'Other' -and (& $prop 'id')) {
            return (& $make $o.id (& $prop 'displayName') $type)
        }
        $aadId = & $prop 'azureADDeviceId'
        if (-not $aadId) { $aadId = & $prop 'azureActiveDirectoryDeviceId' }
        if ($aadId) { return (& $findDevice ([string]$aadId)) }

        $upn = & $prop 'userPrincipalName'
        if ($upn) { $InputObject = [string]$upn }
        elseif (& $prop 'id') { $InputObject = [string]$o.id }
        else { throw 'Cannot resolve the input object: it has no id, userPrincipalName or device ID.' }
    }

    # --- Text -------------------------------------------------------------------
    $text = ([string]$InputObject).Trim()
    if (-not $text) { throw 'Empty member reference.' }
    if ($Cache -and $Cache.ContainsKey($text)) { return $Cache[$text] }

    $result = $null
    if ($text -like '*@*') {
        $u = Invoke-ITGraphRequest -Uri (New-ITGraphUri -Path ('users/{0}' -f [uri]::EscapeDataString($text)) -Select 'id', 'displayName') -ApiVersion 'v1.0'
        $result = & $make $u.id $u.displayName 'User'
    }
    elseif ($text -match $guidPattern) {
        foreach ($kind in @(@('users', 'User'), @('groups', 'Group'), @('devices', 'Device'))) {
            try {
                $hit = Invoke-ITGraphRequest -Uri (New-ITGraphUri -Path ('{0}/{1}' -f $kind[0], $text) -Select 'id', 'displayName') -ApiVersion 'v1.0'
                $result = & $make $hit.id $hit.displayName $kind[1]
                break
            }
            catch {
                if (-not (& $isNotFound $_)) { throw }
            }
        }
        if (-not $result) {
            try { $result = & $findDevice $text }
            catch { throw "No user, group or device found with ID '$text'." }
        }
    }
    else {
        $odataName = ConvertTo-ITODataString $text
        $groups = @(Invoke-ITGraphRequest -Uri (New-ITGraphUri -Path 'groups' -Filter ("displayName eq '{0}'" -f $odataName) -Select 'id', 'displayName') -ApiVersion 'v1.0' -All)
        if ($groups.Count -gt 1) { throw "$($groups.Count) groups are named '$text'. Use the object ID instead." }
        if ($groups.Count -eq 1) {
            $result = & $make $groups[0].id $groups[0].displayName 'Group'
        }
        else {
            $devices = @(Invoke-ITGraphRequest -Uri (New-ITGraphUri -Path 'devices' -Filter ("displayName eq '{0}'" -f $odataName) -Select 'id', 'displayName') -ApiVersion 'v1.0' -All)
            if ($devices.Count -gt 1) { throw "$($devices.Count) Entra ID devices are named '$text'. Use the object ID instead." }
            if ($devices.Count -eq 0) { throw "No group or device named '$text'. Use a UPN for users." }
            $result = & $make $devices[0].id $devices[0].displayName 'Device'
        }
    }

    if ($Cache) { $Cache[$text] = $result }
    $result
}
