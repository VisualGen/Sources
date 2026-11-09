function Verb-ITNoun {
    <#
    .SYNOPSIS
        One line: what the function does.

    .DESCRIPTION
        Two to five lines: behaviour, filters, what is returned, side effects.

    .PARAMETER Id
        Intune object ID. Accepts pipeline input by property name (id / Id).

    .PARAMETER ApiVersion
        Graph API version ('v1.0' or 'beta'). Default: module setting (Get-ITConfiguration).

    .EXAMPLE
        Verb-ITNoun -Id '00000000-0000-0000-0000-000000000000'

        Explain what this example does.

    .EXAMPLE
        Get-ITSomething | Verb-ITNoun -WhatIf

        Pipeline example.

    .OUTPUTS
        IntuneToolkit.Noun

    .NOTES
        Graph permission : DeviceManagementXxx.Read.All
        Graph endpoint   : GET /deviceManagement/xxx/{id}
        API version      : v1.0

    .LINK
        https://learn.microsoft.com/graph/api/resources/intune-graph-overview
    #>

    # ---- Rules (delete this block in real functions) -------------------------
    # * File name = function name; place under Public\<Area>\.
    # * Approved verb only (Get-Verb). Noun = 'IT' + singular PascalCase noun.
    # * State-changing verbs (New/Set/Remove/Add/Invoke...) need SupportsShouldProcess;
    #   destructive ones also ConfirmImpact = 'High'.
    # * Call Assert-ITGraphConnection first; talk to Graph ONLY via Invoke-ITGraphRequest.
    # * Return objects (ConvertTo-ITObject), never Write-Host / formatted text.
    # * Windows PowerShell 5.1 syntax only: no ?:, ??, ?., && / ||, -Parallel.
    # * Variable names are case-insensitive: a local $days overwrites parameter -Days
    #   (and breaks its validation). Never reuse a parameter name for a local variable.
    # * Single quotes in OData values: ConvertTo-ITODataString. Build URIs with New-ITGraphUri.
    # * 'switch' runs EVERY matching case: end each case with 'break' when patterns overlap.
    # * Every wait/poll loop needs a hard iteration cap, not only a time check.
    # * Tests: a GET via Invoke-ITGraphRequest usually has no -Method, so filter with { -not $Method }.
    # * Inside the module $Error is the MODULE's own (empty) list: read the session's with $global:Error.
    # * Do not add log calls for the script user: Write-ITLog goes to the file set by Start-ITLog automatically.
    # * Tests: '<Name>' in an It/Describe title is a Pester template - avoid angle brackets in titles.
    # * Tests: in a Mock BODY (not a ParameterFilter) a parameter that was not passed is undefined under
    #   StrictMode (the build sets it): use  if (Test-Path variable:Method) { ... }.
    # * Tests: in -like, '?' is a wildcard - 'groups?*' also matches 'groups/x'. Use 'groups[?]*'.
    # * Help: a line in the help block that starts with '.word' is read as a help keyword and breaks
    #   the whole help (e.g. '.csv - ...'). Start such lines with a word.
    # * Policies/apps: reuse Get-ITPolicyTypeInfo + Get-ITIntuneObject + Invoke-ITAssignmentChange
    #   instead of new list/assign code; /assign REPLACES all assignments.
    # * Add Tests\Public\<Area>\Verb-ITNoun.Tests.ps1 and a CHANGELOG entry.
    # ---------------------------------------------------------------------------

    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType('IntuneToolkit.Noun')]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string]$Id,

        [ValidateSet('v1.0', 'beta')]
        [string]$ApiVersion = $script:ITConfig.DefaultApiVersion
    )

    begin {
        Assert-ITGraphConnection -RequiredScope 'DeviceManagementXxx.ReadWrite.All'
    }

    process {
        $uri = "deviceManagement/xxx/$Id"

        if ($PSCmdlet.ShouldProcess($Id, 'Describe the action')) {
            Invoke-ITGraphRequest -Uri $uri -Method GET -ApiVersion $ApiVersion |
                ConvertTo-ITObject -TypeName 'Noun'
        }
    }
}
