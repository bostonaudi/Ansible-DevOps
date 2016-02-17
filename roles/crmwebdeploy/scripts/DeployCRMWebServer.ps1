[CmdletBinding()]
param
(
    [Parameter(Mandatory=$true)][string]$buildDropLocation, 
    [Parameter(Mandatory=$true)][string]$SQLInstance,
    [Parameter(Mandatory=$true)][string]$databaseName,
    [string]$databaseKey = "EnterpriseAutomation",
    [string]$ReportInstance = "",
    [string]$Product = "Phoenix",
    [string]$AGListener = ""
)

$libraryVersion = "\\ptlserver9\CrmPowershell\DEBUG\CRMManifest.psd1"
Write-Host "Loading CRM Library from $libraryVersion"
Import-Module $libraryVersion

$Global:ScriptRoot = "c:\buildscripts"

if ($AGListener -ne "") { $SQLInstance = $AGListener}

<# Master list of steps for all deployment for CRM Automation

  0)  Determine if patch build
  1)  Kill anything lingering on the agent (chrome, IE, IIS)
  2)  Setup lab user on the SQL server
  3)  Reset SQL Server instance?
  4)  Load SQL DB?
  5)  Install the application
  6)  Setup Address Validation
  7)  Load Reports onto the Report Server
  8)  Setup BBPS
  9)  Copy Brand Options file
 10)  Create a snapshot of the Database

#>

$currentUser = [Environment]::UserDomainName + "\" + [Environment]::UserName
Write-Host "Currently running as $currentUser"

# -- Determine if patch build --
$isPatchBuild = $buildDropLocation.Contains("Patches")
if ($isPatchBuild) {
    $patchDropLocation = $buildDropLocation
    $buildDropLocation = $patchDropLocation.Substring(0, $patchDropLocation.IndexOf("Patches") - 1)
    
    Write-Host "Installing build from $buildDropLocation"
    Write-Host "Installing patch from $patchDropLocation"
}

# Set all parameters for the installation
$vDir = "bbappfx_$Product"
$baseInstallDir = "d:\sites\$Product"

$addressValSrv = "SC1AddValSrv.pdnt.blackbaud.com"

$reportServiceUrl = "http://$ReportInstance/reportserver"
$webServiceUrl = "http://localhost/$vDir/AppFxWebService.asmx"

$brandingFile = "$PSScriptRoot\brandoptions.xml"
$brandFileDropLocation = "$baseInstallDir\vroot\browser\brand\current"

# -- Install the application -- 
Write-Host "Installing Build from $buildDropLocation to $baseInstallDir"
Install-CRMBuild -prodName $vDir -sourceDir $buildDropLocation -baseInstallDir $baseInstallDir

if ($isPatchBuild) {
    Write-Host "Installing Patch from $patchDropLocation"
    Install-CRMPatch -patchDir $patchDropLocation -baseInstallDir $baseInstallDir
}

Write-Host "Changing web.config, regenerating the encryption key."
Set-CRMDatabaseEntry -installDir $baseInstallDir -DatabaseName $databaseName -SQLInstance $SQLInstance -databaseKey $databaseKey 

# -- Setup Address Validation --
Write-Host "Setting up Address Validation Services to point at $addressValSrv"
Set-CRMAddressValidationService -AddressValidationMachineIpAddress (Get-CRMIPAddressForHostName $addressValSrv) -BaseInstallDir $baseInstallDir

if ($ReportInstance.Length -gt 0) {
    # -- Load Reports onto the Report Server --
    Write-Host "Setting up reporting services on $ReportInstance"
    Set-CRMReportServer -installDir $baseInstallDir -databaseName $databaseName -databaseServer $SQLInstance -reportFolder $databaseName -reportServiceHost $ReportInstance -reportServiceURL $reportServiceUrl  -deleteRootFolderList
    Publish-CRMReports -installDir $baseInstallDir -databaseKey $databaseKey -webServiceUrl $webServiceUrl -loadAllReports
}

# -- Copy Brand Options file --
# Currently, we assume the build definition is going to grab this file and put it in the scripts folder. We should fix this one day
Write-Host "Branding application as CRM"
if (test-path $brandingFile) {
    xcopy $brandingFile $brandFileDropLocation /e /y /r
} else {
    Write-Host "No branding file found, skipping copy."
}
