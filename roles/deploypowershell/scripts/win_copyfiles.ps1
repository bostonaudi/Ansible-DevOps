param
(
    [string]$srcFolder,
    [string]$destFolder,
    [string]$user,
    [string]$pass
)

$scriptblock = {
    param
    (
        [string]$srcFolder,
        [string]$destFolder
    )

    Function Copy-SourceToTarget {
        [cmdletbinding()]
        Param
        (
            [string]$source,
            [string]$target,
            [string]$exclusions
        )

        [string]$tempLog = [System.IO.Path]::GetTempFileName()

        if ([String]::IsNullOrEmpty($exclusions)) {
            robocopy $source $target /S /MT /NFL /NDL /NJH /NJS /NC /NS /NP /log:$tempLog
        }
        else {
            robocopy $source $target /S /MT /NFL /NDL /NJH /NJS /NC /NS /NP /XF $exclusions /log:$tempLog
        }
    }

    Function Copy-CRMMirrorSourceAndTarget {
        [cmdletbinding()]
        Param
        (
            [string]$source,
            [string]$target,
            [string]$exclusions
        )

        [string]$tempLog = [System.IO.Path]::GetTempFileName()

        if ([String]::IsNullOrEmpty($exclusions)) {
            robocopy $source $target /MIR /MT /NFL /NDL /NJH /NJS /NC /NS /NP /log:$tempLog
        }
        else {
            Write-Host "With exclusions"
            robocopy $source $target /MIR /MT /NFL /NDL /NJH /NJS /NC /NS /NP /XF $exclusions /log:$tempLog
        }
    }

    if ((Get-Item $srcFolder) -is [System.IO.DirectoryInfo]) {
        [boolean]$upgrade = [System.IO.Directory]::Exists($destFolder)
        if ($upgrade) {
            Copy-CRMMirrorSourceAndTarget -source $srcFolder -target $destFolder -exclusions $null
        } else {
            Copy-SourceToTarget -source $srcFolder -target $destFolder -exclusions $null
        }
    }
    else {
        Copy-Item "$srcFolder" -Destination $destFolder -Force
    }
}


$secpasswd = ConvertTo-SecureString $pass -AsPlainText -Force
$creds = New-Object System.Management.Automation.PSCredential ($user, $secpasswd)

$session = New-PSSession -ComputerName $env:Computername -Credential $creds -Authentication Credssp

Invoke-Command -Session $session -ScriptBlock $scriptblock -ArgumentList $srcFolder,$destFolder

