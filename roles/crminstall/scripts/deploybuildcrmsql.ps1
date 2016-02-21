<# SQL Server Prep and Revisions process
This script:
    1. copies the build to the server
    2. Copies the test database to the server
    3. Mounts the test database, runs revisions and whatever else it needs (encryption etc.)
    4. Backs the database up
    5. Restore the database into n copies (n = number of agent names provided)

Usage:
    This script should be run in the build definition for the SQL Server Role, that role will need to be assigned in the MTM test rig
#>

[CmdletBinding()]
param
(
    [Parameter(Mandatory=$true)][string]$buildDropLocation,
    [Parameter(Mandatory=$true)][string[]]$agents,
    [Parameter(Mandatory=$true)][string]$databasePath
)

# DEBUGGING
#$buildDropLocation = "\\tfs-bldfs\builds\DEV\CRM_Integration\5.0.112.0"
#$agents = "sc1test2ag0t1, sc1test2agt02"
#$databasePath = "$buildDropLocation\Database\BBInfinity.bak"

# END DEBUGGING
$libraryVersion = "\\ptlserver9\CrmPowershell\DEBUG\CRMManifest.psd1"
Write-Host "Loading CRM Library from $libraryVersion"
Import-Module $libraryVersion


$option = [System.StringSplitOptions]::RemoveEmptyEntries
$databases = $agents.split(",", $option)

$Global:ScriptRoot = "C:\BuildScripts"

# This machine is the SQL host
$SQLInstance = $env:COMPUTERNAME

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
$Product = "Phoenix"
$vDir = "bbappfx_$Product"
$baseInstallDir = "c:\Infinity\$Product"

$databaseName = $env:COMPUTERNAME

if (!(Test-Path -Path $baseInstallDir)) {
    Write-Host "Creating folder $baseInstallDir"
    New-Item -Path $baseInstallDir -ItemType Directory | Out-Null
}

# Move database backup
$localDbBackup = "$baseInstallDir\local.bak"
Write-Host "Copying database backup from $databasePath to $localDbBackup"
Copy-Item -Path $databasePath -Destination $localDbBackup -Force

# Attach and prep the DB - assumption is database coming from a parameter
Write-Host "Loading database $databaseName from backup $localDbBackup"
Restore-CRMDatabase -databaseName $databaseName -SQLInstance $SQLInstance -databasePath $localDbBackup -ReplaceDatabase

# -- Install the application --
Write-Host "Installing Build from $buildDropLocation to $baseInstallDir"
Install-CRMComponents -sourceDir $buildDropLocation -destDir $baseInstallDir

if ($isPatchBuild) {
    Write-Host "Installing Patch from $patchDropLocation"
    Install-CRMPatch -patchDir $patchDropLocation -baseInstallDir $baseInstallDir
}

Write-Host "Updating encryption keys"
Set-CRMEncryptionKey -installDir $baseInstallDir -DatabaseName $databaseName -SQLInstance $SQLInstance

Write-Host "Running revisions"
Update-CRMRevisions -installDir $baseInstallDir -DatabaseName $databaseName -SQLInstance $SQLInstance

# -- Setup BBPS --
Write-Host "Adding BBPS account to $databaseName on $SQLInstance"
Add-CRMBBPSAccount -databaseName $databaseName -SQLInstance $SQLInstance

#After Revisions, back up the database, then restore N copies
$tmpBakFile = Backup-CRMSqlDatabase -SQLInstance $SQLInstance -DatabaseName $databaseName -Initialize

foreach ($db in $databases) {
    $db = $db.Split(".")[0]
    Write-Host "Restoring: $db"
    Restore-CRMDatabase -databaseName $db -SQLInstance $SQLInstance -databasePath $tmpBakFile -ComputerName $db -ReplaceDatabase
    Set-CRMEncryptionKey -installDir $baseInstallDir -DatabaseName $db -SQLInstance $SQLInstance

    # Setup lab user on the SQL server
    Write-Host "Adding system user to database $db"
    Add-CRMSystemUser -databaseName $db -SQLInstance $SQLInstance -ComputerName $db

    # Setup lab user on the SQL server
    Write-Host "Adding Job User Role to $db"
    Add-CRMJobUserRole -installDir $baseInstallDir -ComputerName $db -DatabaseName $db -SQLInstance $SQLInstance

    Write-Host "Adding Job User to $db"
    Add-CRMJobUser -installDir $baseInstallDir -DatabaseName $db -SQLInstance $SQLInstance

    Write-Host "Adding Proxy rights to system user"
    Add-CRMJobUserProxyRights -installDir $baseInstallDir -ComputerName $db -DatabaseName $db -SQLInstance $SQLInstance

    Write-Host "Restore complete"
}

Remove-Item $tmpBakFile -Force