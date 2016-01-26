[CmdletBinding()]
param
(
    [Parameter(Mandatory=$true)][string]$buildDropLocation,
    [Parameter(Mandatory=$true)][string]$SQLInstance,
    [Parameter(Mandatory=$true)][string]$databasePath,
    [string]$databaseKey = "EnterpriseAutomation",
    [string]$ReportInstance = "",
    [string]$Product = "Phoenix"
)

import-module "c:\buildscripts\Library\CRMManifest.psd1"

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
#>

if ($buildDropLocation.Contains("/")) {
    $buildDropLocation = $buildDropLocation.replace("/", "\")
}

if ($databasePath.Contains("/")) {
    $databasePath = $databasePath.replace("/", "\")
}

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
$baseInstallDir = "c:\Infinity\$Product"

$databaseName = $env:COMPUTERNAME
$ConnectionString ="Data Source=$SQLInstance;Initial Catalog=$databaseName;Integrated Security=SSPI;"

$addressValSrv = $CRM_AddressValServer

$reportServiceUrl = "http://$ReportInstance/reportserver"
$webServiceUrl = "http://localhost/$vDir/AppFxWebService.asmx"

$brandingFile = "$PSScriptRoot\brandoptions.xml"
$brandFileDropLocation = "$baseInstallDir\bbappfx\vroot\browser\brand\current"

# Database compatability. Normally 110.
$compatLevel = "110"

# Why is this a thing? How is the agent NOT running as Automagic right now?
#Write-Host 'Changing the Lab Agent Service account to run as PDNT\Automagic'
#Set-LabServiceUser

# -- Load SQL DB --

# Attach and prep the DB - assumption is database coming from a parameter
Write-Host "Loading database $databaseName from backup $databasePath"
Restore-CRMDatabase -databaseName $databaseName -SQLInstance $SQLInstance -databasePath $databasePath

# Setup lab user on the SQL server
Write-Host "Adding system user to database $databaseName"
Add-CRMSystemUser -databaseName $databaseName -SQLInstance $SQLInstance

# -- Install the application --
Write-Host "Installing Build from $buildDropLocation to $baseInstallDir"
Install-CRMBuild -prodName $vDir -sourceDir $buildDropLocation -baseInstallDir $baseInstallDir

if ($isPatchBuild) {
    Write-Host "Installing Patch from $patchDropLocation"
    Install-CRMPatch -patchDir $patchDropLocation -baseInstallDir $baseInstallDir
}

Write-Host "Changing web.config, regenerating the encryption key."
Set-CRMDatabaseEntry -installDir $baseInstallDir -connectionString $ConnectionString -databaseKey $databaseKey
Set-CRMEncryptionKey -installDir $baseInstallDir -connectionString $ConnectionString
Update-CRMRevisions -installDir $baseInstallDir -connectionString $ConnectionString

# -- Setup Address Validation --
Write-Host "Setting up Address Validation Services to point at $addressValSrv"
Set-CRMAddressValidationService -AddressValidationMachineIpAddress (Get-CRMIPAddressForHostName $addressValSrv) -BaseInstallDir $baseInstallDir

if ($ReportInstance.Length -gt 0) {
    # -- Load Reports onto the Report Server --
    Write-Host "Setting up reporting services on $ReportInstance"
    Set-CRMReportServer -installDir $baseInstallDir -databaseName $databaseName -databaseServer $SQLInstance -reportFolder $databaseName -reportServiceHost $ReportInstance -reportServiceURL $reportServiceUrl  -deleteRootFolderList -createInternalUser
    Publish-CRMReports -installDir $baseInstallDir -databaseKey $databaseKey -webServiceUrl $webServiceUrl -loadAllReports
}

# -- Setup BBPS --
Write-Host "Adding BBPS account to $databaseName on $SQLInstance"
Add-CRMBBPSAccount -databaseName $databaseName -SQLInstance $SQLInstance

# -- Copy Brand Options file --
# Currently, we assume the build definition is going to grab this file and put it in the scripts folder. We should fix this one day
Write-Host "Branding application as CRM"
if (test-path $brandingFile) {
    xcopy $brandingFile $brandFileDropLocation /e /y /r
} else {
    Write-Host "No branding file found, skipping copy."
}
