# More info
More info about VisualGen [here](https://www.visualgen.net).

# Disclaimer
All the information in this repository is for educational purposes only. The author of the repository is not responsible for any misuse of the information. All the scripts have been created for educational purposes.

```PowerShell
<# .SYNOPSIS
    Provision a page templates.

.DESCRIPTION
    You need to have the latest version of PnP PowerShell

    Provision a single page template to a SharePoint Online site collection.

.PARAMETER SiteCollection
    Specifies the URL of the SharePoint Online Site Collection.

.PARAMETER PageName
    Specifies the name of the new page template.

.EXAMPLE
    PS> .\add_spopagetemplate.ps1 -SiteCollection "https://contoso.sharepoint.com" -PageName "Contoso Page Template"
  
#>

param ([Parameter(Mandatory)]$SiteCollection,[Parameter(Mandatory)]$PageName)

# Variables
$LogFileName = "add_spopagetemplates_" + $(get-date -f filedatetime) + ".txt"

#####################
Start-Transcript -Path .\logs\$LogFileName -NoClobber 

Connect-PnPOnline -Url $SiteCollection -Interactive

Add-PnPPage -Name $PageName -HeaderLayoutType FullWidthImage -PromoteAs Template -Publish

Disconnect-PnPOnline

#####################
Stop-Transcript
```
