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

$sqlinstance = Get-Attr -obj $params -name "sqlinstance" -default $false -failifempty $true
Set-Attr $result "sqlinstance" $sqlinstance

$databasepath = Get-Attr -obj $params -name "databasepath" -default $false -failifempty $true
Set-Attr $result "databasepath" $databasepath

Function Restore-CRMDatabase {
    [cmdletbinding()]
    Param
    (
        [string]$SQLInstance,
        [string]$databasePath,
        [PSObject]$result
    )

    $ComputerName = $env:COMPUTERNAME

    $user = 'pdnt\automagic'
    $pass = ConvertTo-SecureString -String "Research6" -AsPlainText -Force

    $creds = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList ($user, $pass)

    $session = New-PSSession -ComputerName $SQLInstance -Credential $creds

    [boolean]$loadfailed = $true

    $resultObj =  [PSCustomObject]@{
        loadFailed = $true
        logFile = ""
    }

    $resultObj = Invoke-Command -Session $session -ScriptBlock {
        param($SQLInstance, $databasePath, $ComputerName)

        $resultObj =  [PSCustomObject]@{
            loadFailed = $true
            logFile = ""
            errmsg = ""
        }
        $sqlCmdfile = "c:\buildscripts\SQLScripts\LoadDatabase.sql"
        $logFile = $($env:TEMP + "\" + $ComputerName + "_load.log")
        $resultObj.logFile = $logFile
        if (!(Test-Path $sqlCmdfile))
        {
            $resultObj.errmsg = "SQL file $sqlCmdfile was not found!"
            $resultObj.loadFailed = $true
        }
        else
        {
            SQLCMD -S $SQLInstance -i $sqlCmdfile -o $logfile -v databaseName=$ComputerName bakLocation=$databasePath computerName=$ComputerName
            $resultObj.loadFailed = [string]::IsNullOrWhiteSpace((Get-Content $logFile | Select-String "RESTORE DATABASE successfully processed" -SimpleMatch))
        }
        Write-Output $resultObj
    } -ArgumentList $SQLInstance, $databasePath, $ComputerName

    if ($($resultObj.loadfailed)) {
        Fail-Json $result "Database could not be loaded: $($resultObj.errmsg) Also See $($resultObj.logFile) on $SQLInstance for more details: bakpath: $databasePath"
    }
    else {
        Set-Attr $result "changed" $true;
    }

}

Restore-CRMDatabase -sqlinstance $sqlinstance -databasepath $databasepath -result $result

Exit-Json $result;
