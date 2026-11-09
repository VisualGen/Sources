#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Get-Module IntuneToolkit | Remove-Module -Force
    Import-Module (Join-Path $root 'src\IntuneToolkit\IntuneToolkit.psd1') -Force
}

AfterAll {
    Get-Module IntuneToolkit | Remove-Module -Force
}

Describe 'Invoke-ITGraphRequest' {
    BeforeEach {
        InModuleScope IntuneToolkit {
            $script:ITConfig.DefaultApiVersion = 'v1.0'
            $script:ITConfig.MaxRetry = 3
            $script:ITConfig.RetryDelaySeconds = 1
        }
        Mock -ModuleName IntuneToolkit Start-Sleep { }
    }

    Context 'URI building' {
        BeforeEach {
            Mock -ModuleName IntuneToolkit Send-ITGraphRequest { [pscustomobject]@{ id = '1' } }
        }

        It 'prefixes relative URIs with base URI and default version' {
            InModuleScope IntuneToolkit { Invoke-ITGraphRequest -Uri '/deviceManagement/managedDevices/1' } | Out-Null
            Should -Invoke -ModuleName IntuneToolkit Send-ITGraphRequest -Times 1 -ParameterFilter {
                $Uri -eq 'https://graph.microsoft.com/v1.0/deviceManagement/managedDevices/1' -and $Method -eq 'GET'
            }
        }

        It 'honours -ApiVersion beta' {
            InModuleScope IntuneToolkit { Invoke-ITGraphRequest -Uri 'deviceManagement' -ApiVersion beta } | Out-Null
            Should -Invoke -ModuleName IntuneToolkit Send-ITGraphRequest -Times 1 -ParameterFilter {
                $Uri -eq 'https://graph.microsoft.com/beta/deviceManagement'
            }
        }

        It 'uses the module default API version' {
            InModuleScope IntuneToolkit {
                $script:ITConfig.DefaultApiVersion = 'beta'
                Invoke-ITGraphRequest -Uri 'deviceManagement'
            } | Out-Null
            Should -Invoke -ModuleName IntuneToolkit Send-ITGraphRequest -Times 1 -ParameterFilter { $Uri -like '*/beta/*' }
        }

        It 'passes absolute URIs unchanged' {
            InModuleScope IntuneToolkit { Invoke-ITGraphRequest -Uri 'https://graph.microsoft.com/beta/x?$top=1' } | Out-Null
            Should -Invoke -ModuleName IntuneToolkit Send-ITGraphRequest -Times 1 -ParameterFilter { $Uri -eq 'https://graph.microsoft.com/beta/x?$top=1' }
        }

        It 'serialises object bodies to JSON with full depth' {
            InModuleScope IntuneToolkit {
                Invoke-ITGraphRequest -Uri 'x' -Method POST -Body @{ a = @{ b = @{ c = @{ d = 'deep' } } } }
            } | Out-Null
            Should -Invoke -ModuleName IntuneToolkit Send-ITGraphRequest -Times 1 -ParameterFilter {
                $Method -eq 'POST' -and $Body -eq '{"a":{"b":{"c":{"d":"deep"}}}}'
            }
        }
    }

    Context 'Response handling and paging' {
        It 'returns a single object as-is (even when it has a value property)' {
            Mock -ModuleName IntuneToolkit Send-ITGraphRequest { [pscustomobject]@{ id = '1'; value = 'x' } }
            $r = @(InModuleScope IntuneToolkit { Invoke-ITGraphRequest -Uri 'x' })
            $r.Count | Should -Be 1
            $r[0].id | Should -Be '1'
        }

        It 'unrolls collection responses' {
            Mock -ModuleName IntuneToolkit Send-ITGraphRequest {
                [pscustomobject]@{ '@odata.context' = 'ctx'; value = @([pscustomobject]@{ id = 'a' }, [pscustomobject]@{ id = 'b' }) }
            }
            $r = @(InModuleScope IntuneToolkit { Invoke-ITGraphRequest -Uri 'x' })
            $r.id | Should -Be @('a', 'b')
        }

        It 'returns nothing for an empty collection' {
            Mock -ModuleName IntuneToolkit Send-ITGraphRequest { [pscustomobject]@{ '@odata.context' = 'ctx'; value = @() } }
            @(InModuleScope IntuneToolkit { Invoke-ITGraphRequest -Uri 'x' }).Count | Should -Be 0
        }

        It 'follows @odata.nextLink with -All' {
            Mock -ModuleName IntuneToolkit Send-ITGraphRequest -ParameterFilter { $Uri -notlike '*page2*' } {
                [pscustomobject]@{ value = @([pscustomobject]@{ id = 'a' }); '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/x?page2' }
            }
            Mock -ModuleName IntuneToolkit Send-ITGraphRequest -ParameterFilter { $Uri -like '*page2*' } {
                [pscustomobject]@{ value = @([pscustomobject]@{ id = 'b' }) }
            }
            $r = @(InModuleScope IntuneToolkit { Invoke-ITGraphRequest -Uri 'x' -All })
            $r.id | Should -Be @('a', 'b')
            Should -Invoke -ModuleName IntuneToolkit Send-ITGraphRequest -Times 2 -Exactly
        }

        It 'returns only the first page without -All' {
            Mock -ModuleName IntuneToolkit Send-ITGraphRequest {
                [pscustomobject]@{ value = @([pscustomobject]@{ id = 'a' }); '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/x?page2' }
            }
            $r = @(InModuleScope IntuneToolkit { Invoke-ITGraphRequest -Uri 'x' })
            $r.id | Should -Be @('a')
            Should -Invoke -ModuleName IntuneToolkit Send-ITGraphRequest -Times 1 -Exactly
        }
    }

    Context 'Throttling and errors' {
        It 'retries on HTTP 429 using Retry-After and then succeeds' {
            $script:calls = 0
            Mock -ModuleName IntuneToolkit Send-ITGraphRequest {
                $script:calls++
                if ($script:calls -lt 3) { throw 'throttled' }
                [pscustomobject]@{ id = 'ok' }
            }
            Mock -ModuleName IntuneToolkit Get-ITGraphErrorInfo { [pscustomobject]@{ StatusCode = 429; RetryAfter = 7; Code = 'TooManyRequests'; Message = 'throttled' } }

            $r = InModuleScope IntuneToolkit { Invoke-ITGraphRequest -Uri 'x' -WarningAction SilentlyContinue }
            $r.id | Should -Be 'ok'
            Should -Invoke -ModuleName IntuneToolkit Send-ITGraphRequest -Times 3 -Exactly
            Should -Invoke -ModuleName IntuneToolkit Start-Sleep -Times 2 -Exactly -ParameterFilter { $Seconds -eq 7 }
        }

        It 'retries on HTTP 503 and gives up after MaxRetry' {
            Mock -ModuleName IntuneToolkit Send-ITGraphRequest { throw 'unavailable' }
            Mock -ModuleName IntuneToolkit Get-ITGraphErrorInfo { [pscustomobject]@{ StatusCode = 503; RetryAfter = $null; Code = 'ServiceUnavailable'; Message = 'down' } }

            { InModuleScope IntuneToolkit { Invoke-ITGraphRequest -Uri 'x' -WarningAction SilentlyContinue } } |
                Should -Throw -ExpectedMessage '*HTTP 503*ServiceUnavailable*down*'
            Should -Invoke -ModuleName IntuneToolkit Send-ITGraphRequest -Times 4 -Exactly   # 1 + MaxRetry(3)
        }

        It 'does not retry on HTTP 501 (Not Implemented is permanent)' {
            Mock -ModuleName IntuneToolkit Send-ITGraphRequest { throw 'not supported' }
            Mock -ModuleName IntuneToolkit Get-ITGraphErrorInfo { [pscustomobject]@{ StatusCode = 501; RetryAfter = $null; Code = 'NotSupported'; Message = 'not supported' } }

            { InModuleScope IntuneToolkit { Invoke-ITGraphRequest -Uri 'x' } } | Should -Throw -ExpectedMessage '*HTTP 501*NotSupported*'
            Should -Invoke -ModuleName IntuneToolkit Send-ITGraphRequest -Times 1 -Exactly
            Should -Invoke -ModuleName IntuneToolkit Start-Sleep -Times 0 -Exactly
        }

        It 'does not retry on HTTP 404' {
            Mock -ModuleName IntuneToolkit Send-ITGraphRequest { throw 'missing' }
            Mock -ModuleName IntuneToolkit Get-ITGraphErrorInfo { [pscustomobject]@{ StatusCode = 404; RetryAfter = $null; Code = 'ResourceNotFound'; Message = 'not found' } }

            $err = $null
            try { InModuleScope IntuneToolkit { Invoke-ITGraphRequest -Uri 'x' } } catch { $err = $_ }
            $err | Should -Not -BeNullOrEmpty
            $err.FullyQualifiedErrorId | Should -BeLike 'IntuneToolkit.GraphRequestFailed*'
            Should -Invoke -ModuleName IntuneToolkit Send-ITGraphRequest -Times 1 -Exactly
            Should -Invoke -ModuleName IntuneToolkit Start-Sleep -Times 0 -Exactly
        }
    }
}

Describe 'Get-ITGraphErrorInfo' {
    It 'parses the Graph error body' {
        $info = InModuleScope IntuneToolkit {
            $record = New-Object System.Management.Automation.ErrorRecord (New-Object System.Exception 'raw'), 'id', 'NotSpecified', $null
            $record.ErrorDetails = New-Object System.Management.Automation.ErrorDetails '{"error":{"code":"Forbidden","message":"Insufficient privileges"}}'
            Get-ITGraphErrorInfo -ErrorRecord $record
        }
        $info.Code | Should -Be 'Forbidden'
        $info.Message | Should -Be 'Insufficient privileges'
        $info.StatusCode | Should -BeNullOrEmpty
    }

    It 'parses an Intune error whose JSON body is in Exception.Message with a nested JSON message' {
        $info = InModuleScope IntuneToolkit {
            $inner = @{
                _version = 3
                Message  = 'An error has occurred - Operation ID (for customer support): 00000000-0000-0000-0000-000000000000 - Activity ID: e6f16ceb-99a4-468e-a370-a270aecfa7f7 - Url: https://fef.msua06.manage.microsoft.com/DeviceFE/StatelessDeviceFEService/deviceManagement/managedDevices(%2700000000%27)?api-version=5025-09-25'
                CustomApiErrorPhrase = ''
            } | ConvertTo-Json -Compress
            $body = @{ error = @{ code = 'ResourceNotFound'; message = $inner; innerError = @{ 'request-id' = 'e6f16ceb-99a4-468e-a370-a270aecfa7f7'; date = '2026-11-08T12:15:01' } } } | ConvertTo-Json -Depth 5 -Compress
            $record = New-Object System.Management.Automation.ErrorRecord (New-Object System.Exception $body), 'id', 'NotSpecified', $null
            Get-ITGraphErrorInfo -ErrorRecord $record
        }
        $info.Code | Should -Be 'ResourceNotFound'
        $info.Message | Should -Be 'An error has occurred - Activity ID: e6f16ceb-99a4-468e-a370-a270aecfa7f7'
        $info.RequestId | Should -Be 'e6f16ceb-99a4-468e-a370-a270aecfa7f7'
    }

    It 'parses a JSON body prefixed by other text' {
        $info = InModuleScope IntuneToolkit {
            $record = New-Object System.Management.Automation.ErrorRecord (New-Object System.Exception 'GET https://x HTTP/1.1 403 Forbidden {"error":{"code":"Forbidden","message":"Application is not authorized"}}'), 'id', 'NotSpecified', $null
            Get-ITGraphErrorInfo -ErrorRecord $record
        }
        $info.Code | Should -Be 'Forbidden'
        $info.Message | Should -Be 'Application is not authorized'
    }

    It 'parses the body out of a full HTTP dump in ErrorDetails (braces in headers and trailing text)' {
        $info = InModuleScope IntuneToolkit {
            $dump = @(
                'GET https://graph.microsoft.com/v1.0/deviceManagement/managedDevices/0000 HTTP/1.1'
                'SdkVersion: graph-powershell/2.41.2, Graph-dotnet-v1/{x}'
                ''
                'HTTP/1.1 400 Bad Request'
                'Content-Type: application/json'
                ''
                '{"error":{"code":"BadRequest","message":"{\r\n  \"_version\": 3,\r\n  \"Message\": \"An error has occurred - Operation ID (for customer support): 00000000-0000-0000-0000-000000000000 - Activity ID: 1111 - Url: https://fef/x\",\r\n  \"HttpHeaders\": \"{}\"\r\n}","innerError":{"request-id":"2222","client-request-id":"2222"}}}'
                'trailing } text'
            ) -join "`r`n"
            $record = New-Object System.Management.Automation.ErrorRecord (New-Object System.Exception 'Response status code does not indicate success: BadRequest (Bad Request).'), 'id', 'NotSpecified', $null
            $record.ErrorDetails = New-Object System.Management.Automation.ErrorDetails $dump
            Get-ITGraphErrorInfo -ErrorRecord $record
        }
        $info.Code | Should -Be 'BadRequest'
        $info.Message | Should -Be 'An error has occurred - Activity ID: 1111'
        $info.RequestId | Should -Be '2222'
    }

    It 'uses the regex fallback when the JSON is truncated' {
        $info = InModuleScope IntuneToolkit {
            $record = New-Object System.Management.Automation.ErrorRecord (New-Object System.Exception 'x'), 'id', 'NotSpecified', $null
            $record.ErrorDetails = New-Object System.Management.Automation.ErrorDetails '{"error":{"code":"Forbidden","message":"No \"access\"","innerError":{"request-id":"3333"'
            Get-ITGraphErrorInfo -ErrorRecord $record
        }
        $info.Code | Should -Be 'Forbidden'
        $info.Message | Should -Be 'No "access"'
        $info.RequestId | Should -Be '3333'
    }

    It 'falls back to the exception message' {
        $info = InModuleScope IntuneToolkit {
            $record = New-Object System.Management.Automation.ErrorRecord (New-Object System.Exception 'network down'), 'id', 'NotSpecified', $null
            Get-ITGraphErrorInfo -ErrorRecord $record
        }
        $info.Message | Should -Be 'network down'
    }
}
