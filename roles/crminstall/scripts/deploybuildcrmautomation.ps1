[CmdletBinding()]
param
(
    [Parameter(Mandatory=$true)][string]$buildDropLocation,
    [Parameter(Mandatory=$true)][string]$SQLInstance,
    [Parameter(Mandatory=$true)][string]$databasePath,
    [string]$ReportInstance = ""
)

#$buildDropLocation = "\\tfs-bldfs\builds\DEV\CRM_Integration\5.0.110.0"
#$SQLInstance = "sc1test2sqlsrv"
#$databasePath = "\\ptlservernas3\DBrepository\Infinity\Firebird\Enterprise\SQLServerCompatBackups\BBInfinity_4.0_SP2_Compat110.bak"
#$databasePath = "\\tfs-bldfs\builds\DEV\CRM_Integration\5.0.110.0\database\BBInfinity.bak"


$Global:ScriptRoot = "c:\buildscripts"

import-module "$Global:ScriptRoot\Library\CRMManifest.psd1" -force

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


# -- Determine if patch build --
$isPatchBuild = $buildDropLocation.Contains("Patches")
if ($isPatchBuild) {
    $patchDropLocation = $buildDropLocation
    $buildDropLocation = $patchDropLocation.Substring(0, $patchDropLocation.IndexOf("Patches") - 1)

    Write-Host "Installing build from $buildDropLocation"
    Write-Host "Installing patch from $patchDropLocation"
}

# Set all parameters for the installation
$Product = "Phoenix"
$vDir = "bbappfx_$Product"
$baseInstallDir = "c:\Infinity\$Product"

$databaseKey = "EnterpriseAutomation"
$databaseName = $env:COMPUTERNAME
$ConnectionString ='Data Source=' + $SQLInstance + ';Initial Catalog=' + $databaseName + ';Integrated Security=SSPI;'

$addressValSrv = $CRM_AddressValServer

$reportServiceUrl = "http://$ReportInstance/reportserver"
$webServiceUrl = "http://localhost/$vDir/AppFxWebService.asmx"

$brandingFile = "$PSScriptRoot\brandoptions.xml"
$brandFileDropLocation = "$baseInstallDir\vroot\browser\brand\current"

# Database compatability. Normally 110.
$compatLevel = "110"

#SQL Prep
$uncpath=$baseInstallDir.Replace(":", "$") # replaces the ":" with a "$" in a local path (e.g. C:\temp => C$\temp)
$SQLPath = "\\" + $SQLInstance + "\" + $uncpath
Install-CRMComponents -sourceDir $buildDropLocation -destDir $SQLPath


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
    Set-CRMReportServer -installDir $baseInstallDir -databaseName $databaseName -databaseServer $SQLInstance -reportFolder $databaseName -reportServiceHost $ReportInstance -reportServiceURL $reportServiceUrl  -deleteRootFolderList
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

# -- Create a snapshot of the Database --
Write-Host "Creating/Overwriting Snapshot of $databaseName"
$snapName = $databaseName + "_Automation"
Add-CRMDatabaseSnapshot -database $databaseName -snapshotname $snapName -SQLInstance $SQLInstance -overwrite
