#!powershell
# This file is part of Ansible
#
# Ansible is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Ansible is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Ansible.  If not, see <http://www.gnu.org/licenses/>.

# WANT_JSON
# POWERSHELL_COMMON

$params = Parse-Args $args;

$result = New-Object PSObject;

Set-Attr $result "changed" $false;

$baseInstallDir = Get-Attr -obj $params -name "baseInstallDir" -default "" -failifempty $true
Set-Attr $result "baseInstallDir" $baseInstallDir

$SQLInstance = Get-Attr -obj $params -name "SQLInstance" -default $env:computername
Set-Attr $result "SQLInstance" $SQLInstance


# load this from somewhere?
Function Create-CRMDatabaseSnapshot {
    [cmdletbinding()]
    Param
    (
        [string]$database,
        [string]$snapshotname,
		[string]$SQLInstance = '(LOCAL)',
        [switch]$overwrite,
        [PSObject]$result
    )
    # This needs to probably not rely on the lower level calling this script.
    Add-Type -Path '.\Assemblies\Blackbaud.AppFx.Platform.Automation.dll'

    $snapshotClass = New-Object Blackbaud.AppFx.Platform.Automation.SQLServer.SQLServerSnapshot($SQLInstance, $database)

    try {
        if ($overwrite.IsPresent) {
            $snapshotClass.DeleteSnapshot($snapshotname)
        }

        [void]$snapshotClass.CreateSnapshot($snapshotname)
    }
    catch [System.Exception] {
        Fail-Json $result "Could not create snapshot. `n`t Reason: $Error"
        #throw "Could not create snapshot. `n`t Reason: $Error"
    }
}

Function Add-CRMApplicationUser {
    [cmdletbinding()]
    Param
    (
        [string]$installDir = "",
        [string]$connectionString="",
        [string]$addUser="",
        [bool]$sysadmin=$true,
        [PSObject]$result
    )

    #Write-Host "Adding application user"

    $user = 'pdnt\automagic'
    $pass = ConvertTo-SecureString -String "Research6" -AsPlainText -Force
    $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList ($user, $pass)

    $scriptBlock = {
        param($installDir,$connectionString,$addUser,$sysadmin, $result)


        [string]$buildTasks = [System.IO.Path]::Combine($installDir, "MSBuild\Tasks\Blackbaud.AppFx.Platform.BuildTasks.dll")
        $asm = [System.Reflection.Assembly]::LoadFrom($buildTasks)

        $bt = New-Object Blackbaud.AppFx.Platform.BuildTasks.AddApplicationUser

        $bt.ConnectString = $connectionString
        $bt.UserName = $addUser
        $bt.IsSysAdmin = $sysadmin
        $bt.CheckForExistingUser = $true

        [boolean]$passed = $bt.Execute()

        if (!$passed)
        {
            Fail-Json $result "Application user add failed for user $addUser"
            #throw 'Application user add failed.'
        }
    }
    Invoke-Command -ComputerName $env:computername -Credential $Credential -ScriptBlock $scriptBlock -Authentication Default -ArgumentList $installDir,$connectionString,$addUser,$sysadmin,$result
}

Function Regenerate-CRMEncryptionKey {
    [cmdletbinding()]
    Param
    (
        [string]$installDir = "",
        [string]$connectionString="",
        [string]$encryptionKey="Bl@ckb@udEnterpr1s3R0x!!",
        [PSObject]$result
    )

    $user = 'pdnt\automagic'
    $pass = ConvertTo-SecureString -String "Research6" -AsPlainText -Force
    $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList ($user, $pass)

    $scriptBlock = {
        param($installDir,$connectionString,$encryptionKey,$result)

        [string]$buildTasks = [System.IO.Path]::Combine($installDir, "MSBuild\Tasks\Blackbaud.AppFx.Platform.BuildTasks.dll")
        $asm = [System.Reflection.Assembly]::LoadFrom($buildTasks)

        $bt = New-Object Blackbaud.AppFx.Platform.BuildTasks.RecreateEncryption

        $bt.NewEncryptionKeyPassword = $encryptionKey
        $bt.SQLConnectString = $connectionString

        [boolean]$passed = $bt.Execute()

        if (!$passed)
        {
            Fail-Json $result "Encryption Key regeneration failed."
            #throw 'Encryption Key regeneration failed.'
        }
        Invoke-Command -ComputerName $env:computername -Credential $Credential -ScriptBlock $scriptBlock -Authentication Default -ArgumentList $installDir,$connectionString,$encryptionKey,$result
    }
}

Function Get-ItemGroupAsArray {
    [cmdletbinding()]
    Param
    (
        $itemGroup
    )

    $retval = @()

    foreach($val in $itemGroup) {
       $retval += $val.Include
    }

    return $retval
}

Function Get-CRMDatabaseAssemblies {
    [cmdletbinding()]
    Param
    (
        $platformOptionsXml,
        $productOptionsXml
    )

    [string[]]$platformassemblies = Get-ItemGroupAsArray $platformOptionsXml.Project.SelectNodes("//*[name() = 'ItemGroup']/*[name()='DatabaseAssemblies']")
    [string[]]$productassemblies = Get-ItemGroupAsArray $productOptionsXml.Project.SelectNodes("//*[name() = 'ItemGroup']/*[name()='DatabaseAssemblies']")

    return ($platformassemblies + $productassemblies) -notlike ""
}

Function Get-CRMServiceRevisions {
    [cmdletbinding()]
    Param
    (
        $platformOptionsXml,
        $productOptionsXml
    )

    [string[]]$platformrevisions = Get-ItemGroupAsArray $platformOptionsXml.Project.SelectNodes("//*[name() = 'ItemGroup']/*[name()='ServiceRevisions']")
    [string[]]$productrevisions = Get-ItemGroupAsArray $productOptionsXml.Project.SelectNodes("//*[name() = 'ItemGroup']/*[name()='ServiceRevisions']")

    return $platformrevisions + $productrevisions -notlike ""
}

Function Run-CRMRevisions {
    [cmdletbinding()]
    Param
    (
        [string]$installDir,
        [string]$connectionString,
        [PSObject]$result
    )

    $user = 'pdnt\automagic'
    $pass = ConvertTo-SecureString -String "Research6" -AsPlainText -Force
    $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList ($user, $pass)

    $scriptBlock = {
        param($installDir,$connectionString,$result)

        [string]$platformMSBuildPath = [System.IO.Path]::Combine($installDir, "MSBuild")
        [string]$vrootPath = [System.IO.Path]::Combine($installDir, "vroot")
        [string]$binPath = [System.IO.Path]::Combine($vrootPath, "bin")
        [string]$productOptionsPath = [System.IO.Path]::Combine($platformMSBuildPath, "ProductOptions")
        [string]$platfile = [System.IO.Path]::Combine($platformMSBuildPath,"BlackbaudPlatform.xml")
        [string]$prodfile = [System.IO.Path]::Combine($productOptionsPath,"ProductOptions.xml")

        [xml]$platformOptionsXml = Get-Content $platfile
        [xml]$productOptionsXml = Get-Content $prodfile

        [string]$buildTasks = [System.IO.Path]::Combine($installDir, "MSBuild\Tasks\Blackbaud.AppFx.Platform.BuildTasks.dll")

        $buildUtilDll = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.Build.Utilities")
        $buildTasksDll = [System.Reflection.Assembly]::LoadFrom($buildTasks)

        #Read databaseassemblies and servicerevisions from xml files in platformoptions
        #Read the same based on the product passed in

        [string[]]$databaseAssemblies = Get-CRMDatabaseAssemblies $platformOptionsXml $productOptionsXml
        [string[]]$serviceRevisions = Get-CRMServiceRevisions $platformOptionsXml $productOptionsXml

        $serviceRevisionsItems = @()

        foreach ($i in $serviceRevisions) {
           $i = [System.IO.Path]::Combine($platformMsBuildPath, $i)
           $serviceRevisionsItems += New-Object Microsoft.Build.Utilities.TaskItem($i)
        }

        for ($i=0; $i -le $databaseAssemblies.Count - 1; $i++) {
           $databaseAssemblies[$i] = [System.IO.Path]::Combine($platformMSBuildPath, $databaseAssemblies[$i])
        }

        $goodAssemblies = $databaseAssemblies | where { [System.IO.File]::Exists($_ )} | sort -Unique

        $bt = New-Object Blackbaud.AppFx.Platform.BuildTasks.RunServiceRevisions

        $bt.SQLConnectString = $connectionString
        $bt.CatalogAssembliesPath = $binPath
        $bt.SqlClrAssemblies = $goodAssemblies
        $bt.RevisionsAssemblies = $serviceRevisionsItems
        [boolean]$passed = $bt.Execute()

        if (!$passed)
        {
            Fail-Json $result "Revisions failed!"
        }
    }
    Invoke-Command -ComputerName $env:computername -Credential $Credential -ScriptBlock $scriptBlock -Authentication Default -ArgumentList $installDir,$connectionString,$result
}

# This should probably be .NET code, given how complicated this seems.
Function Set-CRMDatabaseEntry {
    [cmdletbinding()]
    Param
    (
        [string]$installDir,
        [string]$databaseKey,
        [string]$connectionString
    )

    #Write-Host "InstallDir: $installDir"
    #Write-Host "DatabaseKey: $databaseKey"
    #Write-Host "ConnectionString: $connectionString"
    $scriptblock = {
        $asm = [System.Reflection.Assembly]::LoadWithPartialName("System.Web")
        $asm = [System.Reflection.Assembly]::LoadWithPartialName("System.Configuration")

        [string]$dummyVirtualPath = "/MyApp"
        [string]$webconfigpath = [System.IO.Path]::Combine($installDir, "vroot")

        [System.Console]::WriteLine("Mapping virtual directory")

        $map = New-Object System.Web.Configuration.WebConfigurationFileMap

        $virtualDirMapping = New-Object System.Web.Configuration.VirtualDirectoryMapping($webconfigPath,$true, "web.config")

        $map.VirtualDirectories.Add($dummyVirtualPath, $virtualDirMapping)

        $webconfig = [System.Web.Configuration.WebConfigurationManager]::OpenMappedWebConfiguration($map, $dummyVirtualPath)

        $appSettings = $webconfig.AppSettings

        $redblistKey = "REDBList"

        $dbKeyPlusSemiColon = $databaseKey + ";"


        if ($appSettings.Settings[$redblistKey] -eq $null) {
            $appSettings.Settings.Add($redblistKey, $databaseKey)
        }
        elseif ($appSettings.Settings[$redblistKey].Value -ne $datbaseKey -and ! [System.String]::Copy($appSettings.Settings[$redblistkey].Value).Split(";").Contains($databaseKey) ) {
            $appSettings.Settings[$redblistKey].Value = $dbKeyPlusSemiColon + $appSettings.Settings[$redblistKey].Value
        }

    #Write-Host "Adding connection string to ConnectionStrings"

        $connectionStrings = $webconfig.ConnectionStrings.ConnectionStrings

        if ($connectionStrings.Item($databaseKey) -eq $null) {
            $newConnection = New-Object System.Configuration.ConnectionStringSettings($databaseKey, $connectionString)
        $connectionStrings.Add($newConnection)
        }
        else {
            $connectionStrings[$databaseKey].ConnectionString = $connectionString
        }

    #Write-Host "Saving web.config changes"

        $webconfig.Save([System.Configuration.ConfigurationSaveMode]::Modified)
    }
    $user = 'pdnt\automagic'
    $password = ConvertTo-SecureString -String "Research6" -AsPlainText -Force
    $creds = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList ($user, $password)

    Invoke-CRMCommand -Scriptblock $scriptblock -Credential $creds -Authentication Default
}

Function Restore-CRMDatabase {
    [cmdletbinding()]
    Param
    (
        [string]$databaseName,
        [string]$SQLInstance,
        [string]$databasePath,
        [string]$ComputerName = $env:COMPUTERNAME,
        [PSObject]$result
    )

    $logFile = $databaseName + "_load.log"
    SQLCMD -S $SQLInstance -i "c:\buildscripts\SQLScripts\LoadDatabase.sql" -v bakLocation="$databasePath" databasename="$databaseName" computername="$ComputerName" > $logFile

    [boolean]$loadFailed = [string]::IsNullOrWhiteSpace((Get-Content $logFile | Select-String "RESTORE DATABASE successfully processed" -SimpleMatch))

    if ($loadFailed) {
        Fail-Json $result "Database could not be loaded. See '$logFile' for more details"
        #Throw "Database could not be loaded. See '$logFile' for more details"
    }
}

Function Add-SystemUser {
    [cmdletbinding()]
    Param
    (
        [string]$databaseName,
        [string]$SQLInstance,
        [string]$ComputerName = $env:COMPUTERNAME
    )

    $logFile = $databaseName + "_AddUser.log"
    SQLCMD -S $SQLInstance -i "c:\buildscripts\SQLScripts\AddUser.sql" -v databasename=$databaseName computername="$ComputerName" > $logFile
}

Function Load-ProductFlags {
    [cmdletbinding()]
    Param
    (
        [string]$databaseName,
        [string]$SQLInstance,
        [PSObject]$result
    )

    $logFile = $databaseName + "_productFlags.log"
    SQLCMD -S $SQLInstance -i "c:\buildscripts\SQLScripts\ProductFlags.SQL" -d $databaseName > $logFile

    [boolean]$errorFound = ![string]::IsNullOrWhiteSpace((Get-Content $logFile | Select-String "Unexpected error occurred" -SimpleMatch))

    if ($errorFound) {
        Fail-Json $result "Product flags could not be set correctly. See '$logFile' for more details"
        #Throw "Product flags could not be set correctly. See '$logFile' for more details"
    }
}

Function Grant-UserSqlRights {
    [cmdletbinding()]
    Param
    (
        [string]$SQLInstance,
        [string]$UserName
    )

    $logFile = "GrantUserRights.log"
    SQLCMD -S $SQLInstance -i "c:\buildscripts\SQLScripts\GrantUserRights.sql" -v userName="$UserName" > $logFile
}

Function Configure-ReportServer {
    [cmdletbinding()]
    Param
    (
        [string]$databaseName,
        [string]$databaseServer,
        [string]$reportFolder,
        [string]$reportServiceHost,
        [string]$reportServiceURL,
        [string]$installDir,

        [switch]$createInternalUser,
        [switch]$deleteRootFolderList,
        [PSObject]$result
    )

    Write-Verbose 'Configure Report Server'
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    Write-Verbose "Current User: $currentUser"

    [string]$buildTasks = [System.IO.Path]::Combine($installDir, "MSBuild\Tasks\Blackbaud.AppFx.Platform.BuildTasks.dll")

    $asm = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.Build.Utilities")
    $asm = [System.Reflection.Assembly]::LoadFrom($buildTasks)

    $bt = New-Object Blackbaud.AppFx.Platform.BuildTasks.ConfigureReportServer

    $bt.createInternalUser = $createInternalUser.IsPresent
	
	# use domain user, we can't have all machines uploading a local user with a different password all at once, set createinternaluser to false
    $bt.ReportServerUser = "pdnt\automagic"
    $bt.reportUserPassword = "Research6"

	$bt.database = $databaseName
    $bt.databaseServer = $databaseServer
    $bt.deleteRootFolderList = $deleteRootFolderList.IsPresent
    $bt.reportFolder = $reportFolder
    $bt.reportServiceHost = $reportServiceHost
    $bt.reportServiceURL = $reportServiceURL

    [boolean]$passed = $bt.Execute()

    if (!$passed)
    {
        Fail-Json $result "Report server configuration failed for $databaseServer."
        #throw "Report server configuration failed for $databaseServer."
    }
}

Function Load-Reports {
    [cmdletbinding()]
    Param (
        [string]$installDir,
        [string]$databaseKey,
        [string]$webServiceUrl,
        [switch]$loadAllReports,
        [PSObject]$result
    )

    [string]$buildTasks = [System.IO.Path]::Combine($installDir, "MSBuild\Tasks\Blackbaud.AppFx.Platform.BuildTasks.dll")
    $asm = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.Build.Utilities")
    $asm = [System.Reflection.Assembly]::LoadFrom($buildTasks)

    $bt = New-Object Blackbaud.AppFx.Platform.BuildTasks.LoadReports

    $bt.WebServiceDatabaseName = $databaseKey
    $bt.WebServiceUrl = $webServiceUrl

    if ($loadAllReports.IsPresent) {
        $bt.TryLoadingAllReports = $true
    }

	$bt.TreatWarningsAsErrors = $false
    [boolean]$passed = $bt.Execute()

    if (!$passed)
    {
        Fail-Json $result "Could not load reports to '$webServiceUrl'"
        #throw "Could not load reports to '$webServiceUrl'"
    }
}

Function Add-BBPSAccount {
    [cmdletbinding()]
    Param
    (
        [string]$databaseName,
        [string]$SQLInstance
    )

    $logFile = $databaseName + "_AddBBPSUser.log"
    SQLCMD -S $SQLInstance -i "c:\buildscripts\SQLScripts\AddBBPSAccount.sql" -v databasename=$databaseName > $logFile
}

Function Set-DbCompatLevel {
    [cmdletbinding()]
    Param
    (
        [string]$databaseName,
        [ValidateSet("80","90","100","110","120")]
        [string]$compatLevel="110"
    )

    $logFile = $databaseName + "_CompatLevel.log"
    SQLCMD -S $SQLInstance -i "c:\buildscripts\SQLScripts\SetDBCompat.sql" -v databasename=$databaseName compatLevel=$compatLevel > $logFile
}

Function Reenable-SqlIndexes {
    [cmdletbinding()]
    Param
    (
        [string]$databaseName
    )

    $logFile = $databaseName + "_ReenableIndexes.log"
    SQLCMD -S $SQLInstance -i "c:\buildscripts\SQLScripts\ReenableIndexes.sql" -d $databaseName > $logFile
}

function Invoke-CRMCommand {
    [CmdLetBinding()]
    param(
        [Parameter( Mandatory=$true)]
                    [scriptblock]$Scriptblock,

        [Parameter( Position=0)]
                    [string[]]$ComputerName='localhost',

        [object[]]$ArgumentList,


        [System.Management.Automation.Runspaces.AuthenticationMechanism]$Authentication = 'Default',

        [Parameter( ValueFromPipelineByPropertyName=$true)]
                    [PSCredential]$Credential =[pscredential]::Empty

    )

    #if you call invoke-command without a -ComputerName parameter for local execution, the debugger will step through each line of code defined in $scriptblock. If you specify the -ComputerName argument for local execution
    #it will not allow you to step into the scriptblock which can make debugging difficult.
    #By using this wrapper, you do not have to add the if-then logic to all of your cmdlets that rely on invoke-command

    If ($computerName.length -eq 1 -and ($computerName -eq 'LOCALHOST' -or $computerName -eq $env:COMPUTERNAME -or $computerName -eq '')) {
        #passing down results in invalid argument exception when credential set is empty. Probably only when option strict is set. Thus, need to branch code
        if ($Credential -eq [pscredential]::empty) {
            Invoke-Command -ScriptBlock $Scriptblock -ArgumentList $ArgumentList
        }
        else {
            Invoke-Command -ScriptBlock $Scriptblock -ArgumentList $ArgumentList -Authentication $Authentication -Credential $Credential
        }
    }
    else  {
        if ($Credential -eq [pscredential]::empty) {
            Invoke-Command -ComputerName $computerName -ScriptBlock $Scriptblock -ArgumentList $ArgumentList -Verbose:$VerbosePreference
        }
        else  {
            Invoke-Command -ComputerName $computerName -ScriptBlock $Scriptblock -ArgumentList $ArgumentList -Authentication $Authentication -Credential $Credential -Verbose:$VerbosePreference
        }
     }
}


$databaseName=$env:computername
$ConnectionString ="Data Source=$SQLInstance;Initial Catalog=$databaseName;Integrated Security=SSPI;"
Set-Attr $result "ConnectionStr" $ConnectionString
$databaseKey="BBInfinity"

Add-SystemUser -databaseName $databaseName -SQLInstance $SQLInstance

Set-CRMDatabaseEntry -installDir $baseInstallDir -connectionString $ConnectionString -databaseKey $databaseKey

Regenerate-CRMEncryptionKey -installDir $baseInstallDir -connectionString $ConnectionString -result $result

Run-CRMRevisions -installDir $baseInstallDir -connectionString $ConnectionString -result $result

Add-CRMApplicationUser -installDir $baseInstallDir -connectionString $ConnectionString -addUser "pdnt\automagic" -sysadmin $true -result $result
Add-CRMApplicationUser -installDir $baseInstallDir -connectionString $ConnectionString -addUser "pdnt\loadtestuser_1" -sysadmin $true -result $result

Set-Attr $result "changed" $true;
Exit-Json $result;
