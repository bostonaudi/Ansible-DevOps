<# SQL Server Prep and Revisions process
This script:
    1. copies the build to the server
    2. Backs the target database up (compress), and msdb to preserve jobs
	3. If target database does not exist, copies the target database to the server, mounts, then revisions, otherwise just revisions
	4. If revisions fails, rollback

Usage:

#>

[CmdletBinding()]
param
(
    [Parameter(Mandatory=$true)][string]$buildDropLocation,
    [Parameter(Mandatory=$true)][string]$bakFilePath,
    [Parameter(Mandatory=$true)][string]$databaseName,
    [Parameter(Mandatory=$true)][string]$webservers
)

$buildDropLocation = $buildDropLocation.replace("/", "\")
$bakFilePath = $bakFilePath.replace("/", "\")

$scriptblock = {
param
(
    [Parameter(Mandatory=$true)][string]$buildDropLocation,
    [Parameter(Mandatory=$true)][string]$bakfilePath,
    [Parameter(Mandatory=$true)][string]$databaseName,
    [Parameter(Mandatory=$true)][string]$webservers

)
    Import-Module "\\ptlserver9\CrmPowershell\DEBUG\CRMManifest.psd1"
    Import-module "\\ptlserver9\CrmPowershell\sdo\Powershell\SDOManifest.psd1"


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

    if (!(Test-Path -Path $baseInstallDir)) {
        Write-Host "Creating folder $baseInstallDir"
        New-Item -Path $baseInstallDir -ItemType Directory | Out-Null
    }

    # -- Install the application --
    Write-Host "Installing Build from $buildDropLocation to $baseInstallDir"
    Install-CRMComponents -sourceDir $buildDropLocation -destDir $baseInstallDir

    if ($isPatchBuild) {
        Write-Host "Installing Patch from $patchDropLocation"
        Install-CRMPatch -patchDir $patchDropLocation -baseInstallDir $baseInstallDir
    }

    $instance = Get-SDOSQLServerInstances -ComputerName $env:COMPUTERNAME
    $databasepresent = $instance.ConnectionString | Get-SDOSQLServerDatabase -database $databaseName
    $primaryInstanceName = $($instance.Hostname + "\" + $instance.InstanceName  + "," + $instance.PortNumber)

    Write-Host "Starting database installation for db $databaseName"

    # does the target db already exist? If so, revision it, if not, mount it, prep it, do the usual stuff
    if ($databasepresent) {
    # just run revisions
        # back it up so can revert from revision failure
        Write-Host "Database $databaseName already present, only revisions will be run"
        Write-Host "Backing up database before revisions."
        $tmpBakFile = Backup-CRMSqlDatabase -SQLInstance $primaryInstanceName -DatabaseName $databaseName -Initialize

        try {
            Update-CRMRevisions -installDir $baseInstallDir -DatabaseName $databaseName -SQLInstance $primaryInstanceName
            }
        catch {
            write-host "Revisions failed, restoring from backup!"
            Restore-CRMDatabase -databaseName $databaseName -SQLInstance $primaryInstanceName -databasePath $tmpBakFile -ReplaceDatabase
            throw $_.Exception
        }
    }
    else {
        Write-Host "Database $databaseName not found, installing new db $databaseName"
        # Move database backup
        $localDbBackup = "$baseInstallDir\local.bak"
        Write-Host "Copying database backup from $bakFilePath to $localDbBackup"
        Copy-Item -Path $bakFilePath -Destination $localDbBackup -Force

        # Attach and prep the DB - assumption is database coming from a parameter
        Write-Host "Loading database $databaseName from backup $localDbBackup"
        Restore-CRMDatabase -databaseName $databaseName -SQLInstance $primaryInstanceName -databasePath $localDbBackup -ReplaceDatabase

         # set to full backup
        Set-CRMDBRecoveryModel -DatabaseName $databaseName -SQLInstance $primaryInstanceName -RecoveryModel 'Full'

        Write-Host "Updating encryption keys"
        Set-CRMEncryptionKey -installDir $baseInstallDir -DatabaseName $databaseName -SQLInstance $primaryInstanceName

        Write-Host "Running revisions"
        Update-CRMRevisions -installDir $baseInstallDir -DatabaseName $databaseName -SQLInstance $primaryInstanceName

        # -- Setup BBPS --
        Write-Host "Adding BBPS account to $databaseName on $primaryInstanceName"
        Add-CRMBBPSAccount -databaseName $databaseName -SQLInstance $primaryInstanceName

        # Setup lab user on the SQL server
        foreach ($webserver in $webservers.split(',')) {
            Write-Host "Adding $webserver to database $databaseName roles"
            Add-CRMSystemUser -databaseName $databaseName -SQLInstance $primaryInstanceName -ComputerName $webserver
        }

        # Setup lab user on the SQL server
        Write-Host "Adding Job User Role to $databaseName"
        Add-CRMJobUserRole -installDir $baseInstallDir -ComputerName $SQLInstance -DatabaseName $databaseName -SQLInstance $primaryInstanceName

        Write-Host "Adding Job User to $databaseName"
        Add-CRMJobUser -installDir $baseInstallDir -DatabaseName $databaseName -SQLInstance $primaryInstanceName

        Write-Host "Adding Proxy rights to system user"
        Add-CRMJobUserProxyRights -installDir $baseInstallDir -ComputerName $SQLInstance -DatabaseName $databaseName -SQLInstance $primaryInstanceName

        Write-Host "Installing new db $databaseName complete."

    }
}

$user = 'pdnt\automagic'
$pass = ConvertTo-SecureString -String "Research6" -AsPlainText -Force
$creds = New-Object System.Management.Automation.PSCredential ($user, $pass)

$session = New-PSSession -ComputerName $env:Computername -Credential $creds -Authentication Credssp

Invoke-Command -Session $session -ScriptBlock $scriptblock -ArgumentList $buildDropLocation,$bakFilePath,$databaseName,$webservers
