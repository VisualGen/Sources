Import-Module .\src\IntuneToolkit\IntuneToolkit.psd1

Start-ITLog

try {
    Connect-ITGraph -UseBrowser

    Get-ITManagedDevice | Export-ITReport -Path "$env:TEMP\ITManagedDevice.html"
    $status = 'Success'
}
catch { $status = "Failed: $($_.Exception.Message)"; throw }

finally { Stop-ITLog -Status $status }      # also closes the log when the script fails

Disconnect-ITGraph -Force

Remove-Module IntuneToolkit


