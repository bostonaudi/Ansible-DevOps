<# SQL Server Prep and Revisions process
# This script:
    1. copies the build to the server
    2. Copies the test database to the server
    3. Mounts the test database, runs revisions and whatever else it needs (encryption etc.)
    4. Backs the database up
    5. Restore the database into n copies

    Author: JH

Usage:
    This script should be run in the build definition for the SQL Server Role, that role will need to be assigned in the MTM test rig
#>

[CmdletBinding()]
param
(
    [Parameter(Mandatory=$true)][string]$buildDropLocation,
    [Parameter(Mandatory=$true)][string[]]$databases,
    [Parameter(Mandatory=$true)][string]$databasePath,
    [string]$SQLInstance=$env:COMPUTERNAME,
    [string]$ReportInstance=""
)

$Global:ScriptRoot = "C:\BuildScripts"

import-module "$Global:ScriptRoot\Library\CRMManifest.psd1"

import-module "sqlps" -DisableNameChecking

# pass the builds with linux format forward slashes, then convert back for Windows
if ($buildDropLocation.Contains("/")) {
    $buildDropLocation = $buildDropLocation.replace("/", "\")
}

if ($databasePath.Contains("/")) {
    $databasePath = $databasePath.replace("/", "\")
}

$Product = "bbec"
$vDir = "bbappfx_$Product"
$baseInstallDir = "c:\Infinity\$Product"
$databaseKey = "CRM_Enterprise"

$databaseName = $env:COMPUTERNAME

# Report Services setup
$reportServiceUrl = "http://$ReportInstance/reportserver"
$webServiceUrl = "http://localhost/$vDir/AppFxWebService.asmx"

$ConnectionString ="Data Source=$SQLInstance;Initial Catalog=$databaseName;Integrated Security=SSPI;"

# -- Determine if patch build --
$isPatchBuild = $buildDropLocation.Contains("Patches")
if ($isPatchBuild) {
    $patchDropLocation = $buildDropLocation
    $buildDropLocation = $patchDropLocation.Substring(0, $patchDropLocation.IndexOf("Patches") - 1)

    echo "Installing build from $buildDropLocation"
    echo "Installing patch from $patchDropLocation"
}


# Attach and prep the DB - assumption is database coming from a parameter
echo "Loading database $databaseName from backup $databasePath"
Restore-CRMDatabase -databaseName $databaseName -SQLInstance $SQLInstance -databasePath $databasePath

# -- Install the application to the SQL box so we can run revisions locally--
echo "Installing Build from $buildDropLocation to $baseInstallDir"
Install-CRMComponents -sourceDir $buildDropLocation -destDir $baseInstallDir

if ($isPatchBuild) {
    echo "Installing Patch from $patchDropLocation"
    Install-CRMPatch -patchDir $patchDropLocation -baseInstallDir $baseInstallDir
}

#Set-CRMEncryptionKey -installDir $baseInstallDir -connectionString $ConnectionString
Update-CRMRevisions -installDir $baseInstallDir -connectionString $ConnectionString

#After Revisions, back up the database, then restore N copies for each agent
$tmpBakFile = join-path "d:\" $($databaseName + ".bak")

Backup-SqlDatabase -ServerInstance $SQLInstance -Database $databaseName -BackupAction Database -BackupFile $tmpBakFile -Initialize

# Get the back up path
#[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO') | out-null
#$s = New-Object ('Microsoft.SqlServer.Management.Smo.Server') "LOCALHOST"
#$backPath = $($s.Settings.BackupDirectory)

$appuserFile = "$Global:ScriptRoot\data\crmappusers.txt"

ForEach ($db in $databases)
{
    echo "DB: $db"
    # split is to get simple name
    if ($db -contains ".") {
        $db=$db.Split(".")[0]
    }

    Restore-CRMDatabase -databaseName $db -SQLInstance $SQLInstance -databasePath $tmpBakFile -ComputerName $db

    if ($ReportInstance.Length -gt 0) {
        # -- Load Reports onto the Report Server --
        Set-CRMReportServer -installDir $baseInstallDir -databaseName $db -databaseServer $SQLInstance -reportFolder $db -reportServiceHost $ReportInstance -reportServiceURL $reportServiceUrl -deleteRootFolderList
        Publish-CRMReports -installDir $baseInstallDir -databaseKey $databaseKey -webServiceUrl $webServiceUrl -loadAllReports
    }

    if (Test-Path ($appuserFile)) {
        $ConStr = "Data Source=$SQLInstance;Initial Catalog=$db;Integrated Security=SSPI;"
        $content = Get-Content $appuserFile
        foreach ($user in $content)
        {
            $user = $user.split("`t")[0]
            echo "adding appuser $user"
            try {
                Add-CRMApplicationUser -installDir $baseInstallDir -connectionString $ConStr -sysadmin $true -addUser $user
            }
            catch {
                echo "User $user could not be added!"
            }
        }
    }
}

