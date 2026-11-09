@{
    Severity     = @('Error', 'Warning', 'Information')

    ExcludeRules = @(
        # Write-ITLog intentionally uses Write-Verbose; template uses placeholder verb.
        'PSUseApprovedVerbs'   # enforced instead by Tests\Module.Tests.ps1 (templates excluded)
    )

    Rules        = @{
        # Fail on any syntax / command that does not exist in Windows PowerShell 5.1
        PSUseCompatibleSyntax   = @{
            Enable         = $true
            TargetVersions = @('5.1')
        }
        PSUseCompatibleCmdlets  = @{
            Compatibility = @('desktop-5.1.14393.206-windows')
        }
        PSUseCompatibleCommands = @{
            Enable         = $true
            TargetProfiles = @('win-48_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework')
            IgnoreCommands = @('Connect-MgGraph', 'Disconnect-MgGraph', 'Get-MgContext', 'Invoke-MgGraphRequest')
        }
        PSPlaceOpenBrace        = @{ Enable = $true; OnSameLine = $true; NewLineAfter = $true; IgnoreOneLineBlock = $true }
        # Stroustrup style: '}' then 'else' / 'catch' on the next line
        PSPlaceCloseBrace       = @{ Enable = $true; NoEmptyLineBefore = $false; IgnoreOneLineBlock = $true; NewLineAfter = $true }
        PSUseConsistentIndentation = @{ Enable = $true; IndentationSize = 4; Kind = 'space' }
        PSAvoidUsingCmdletAliases  = @{ Enable = $true }
    }
}
