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

Function Clean-TestController {
    [cmdletbinding()]
    Param ($result)

    # For each user folder, look for VSEQT.
    $userDirs = Get-ChildItem -Path "$env:USERPROFILE\.."

    foreach ($dir in $userDirs) {
        $expectedPath = [System.IO.Path]::Combine($dir.FullName, "AppData\Local\VSEQT")
    
        # if found, delete entire contents - force delete, skip on locks    
        if (Test-Path -Path $expectedPath) {
            Write-Verbose "$expectedPath Exists. Deleting contents"

            Remove-Item -Path "$expectedPath\*" -Recurse -Force -ErrorAction SilentlyContinue
            Set-Attr $result "changed" $true;
        }
    }
}


$params = Parse-Args $args;

$result = New-Object PSObject;
Set-Attr $result "changed" $false;

Clean-TestController -result $result

Exit-Json $result;
