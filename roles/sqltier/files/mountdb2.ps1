#!powershell
# <license>

# WANT_JSON
# POWERSHELL_COMMON

# code goes here, reading in stdin as JSON and outputting JSON

$params = Parse-Args $args;

$sqlinstance = Get-Attr $params "sqlinstance" $FALSE;
if ($sqlinstance -eq $FALSE)
{
    Fail-Json $result "missing required arguments: name"
}

$databasename = Get-Attr $params "databasename" $FALSE;
if ($databasename -eq $FALSE)
{
    Fail-Json $result "missing required arguments: name"
}

$databasepath = Get-Attr $params "databasepath" $FALSE;
if ($databasepath -eq $FALSE)
{
    Fail-Json $result "missing required arguments: name"
}

$result = New-Object psobject @{
    output = ""
    changed = $false
};

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

Restore-CRMDatabase -databasename $databasename -sqlinstance $sqlinstance -databasepath $databasepath -result $result

Set-Attr $result "Output" "Database mounted"

Exit-Json $result;
