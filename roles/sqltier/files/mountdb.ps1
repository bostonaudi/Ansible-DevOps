#!powershell
# This file is part of Ansible
#
# Copyright 2014, Chris Hoffman <choffman@chathamfinancial.com>
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

# Handle params
$params = Parse-Args $args;

$result = New-Object PSObject;
Set-Attr $result "changed" $false;
Set-Attr $result "Output" "Nothing"

If (-not $params.name.sqlinstance)
{
    Fail-Json $result "missing required arguments: name"
}
If (-not $params.name.databasename)
{
    Fail-Json $result "missing required arguments: name"
}
If (-not $params.name.databasepath)
{
    Fail-Json $result "missing required arguments: name"
}

Function Restore-CRMDatabase {
    [cmdletbinding()]
    Param 
    (
        [string]$databaseName,
        [string]$SQLInstance,
        [string]$databasePath,
        [PSObject]$result
    ) 

    $ComputerName = $env:COMPUTERNAME

    $logFile = $databaseName + "_load.log"

    $sqlCmdfile = ".\LoadDatabase.sql"

    if (!Test-Path $sqlCmdfile)
    {
        Fail-Json $result "SQL file $sqlCmdfile was not found!"
    }

    SQLCMD -S $SQLInstance -i $sqlCmdfile -v bakLocation="$databasePath" databasename="$databaseName" computername="$ComputerName" > $logFile

    [boolean]$loadFailed = [string]::IsNullOrWhiteSpace((Get-Content $logFile | Select-String "RESTORE DATABASE successfully processed" -SimpleMatch))

    if ($loadFailed) {
        Fail-Json $result "Database could not be loaded. See '$logFile' for more details"
    }
    Set-Attr $result "changed" $true
}

Restore-CRMDatabase -databasename $params.name.databasename -sqlinstance $params.name.sqlinstance -databasepath $params.name.databasepath -result $result


Set-Attr $result "Output" "Database mounted"
Exit-Json $result;
