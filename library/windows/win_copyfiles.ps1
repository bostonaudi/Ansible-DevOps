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

#debug
#$params = New-Object PSObject;
#Set-Attr $params "srcFolder" "\\tfs-bldfs\builds\DEV\CRM_Integration\5.0.92.0\Installer"
#Set-Attr $params "destFolder" "c:\testfolder"
#Set-Attr $params "filename" "BlackbaudInstaller.exe"


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

$result = New-Object PSObject;

Set-Attr $result "changed" $false;

$srcFolder = Get-Attr -obj $params -name "srcFolder" -default "" -failifempty $true
Set-Attr $result "srcFolder" $srcFolder

$destFolder = Get-Attr -obj $params -name "destFolder" -default $FALSE -failifempty $true
Set-Attr $result "destFolder" $destFolder

$user = 'pdnt\automagic'
$password = ConvertTo-SecureString -String "Research6" -AsPlainText -Force
$credentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList ($user, $password)

if (test-path "P:") {
    Remove-PSDrive -Name P
}

if (!(test-path $destFolder)) {
    New-Item $destFolder -type directory
}

# get the parent folder so we can map it
$option = [System.StringSplitOptions]::RemoveEmptyEntries
$rootmap = "\\" + [string]::join("\",$srcFolder.Split("\")[2..3])
$count = $srcFolder.Split("\", $option).count + 1
$remainder = [string]::join("\", $srcFolder.Split("\")[4..$count])

New-PSDrive -Name P -PSProvider FileSystem -Root $rootmap -Credential $credentials -persist

Start-Sleep -s 1

if (!(test-path "P:")) {
    Fail-Json $result "New-PSDrive failed!"
}

$mappedPath = [io.path]::combine("P:\", $remainder)
Set-Attr $result "fullSrc" $mappedPath

if (!(test-path $mappedPath)) {
    Fail-Json $result "$mappedPath does not exist!"
}

if ((Get-Item $mappedPath) -is [System.IO.DirectoryInfo]) {
    [boolean]$upgrade = [System.IO.Directory]::Exists($destFolder)
    if ($upgrade) {
        Copy-CRMMirrorSourceAndTarget -source $mappedPath -target $destFolder -exclusions $null
    } else {
        Copy-SourceToTarget -source $mappedPath -target $destFolder -exclusions $null
    }
}
else {
    Copy-Item "$mappedPath" -Destination $destFolder -Force
}

Remove-PSDrive -Name P

Set-Attr $result "changed" $true;
Exit-Json $result;

