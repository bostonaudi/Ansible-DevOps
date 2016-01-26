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

$vrootdir = Get-Attr -obj $params -name "vrootdir" -default "" -failifempty $true
Set-Attr $result "vrootdir" $vrootdir

$vdirname = Get-Attr -obj $params -name "vdirname" -default "" -failifempty $true
Set-Attr $result "vdirname" $vdirname

$apppool = Get-Attr -obj $params -name "apppool" -default "" -failifempty $true
Set-Attr $result "apppool" $apppool


Function Install-CRMIISWebSite {
    [cmdletbinding()]
    Param
    (
        [string]$vRootTargetDir,
        [string]$virtualDir="",
        [string]$appPool="DefaultAppPool",
        [string]$site="Default Web Site",
        [int]$port=80,
        [ValidateSet("High","Medium","Low","None")][string]$logging="Medium"
    )

    Import-Module WebAdministration

    $apppoolpath = $("IIS:\AppPools\" + $appPool)
    $sitepath = $("IIS:\Sites\" + $site)
    $virtualdirpath = $($sitepath + "\" + $virtualDir.replace("/","\"))

    [boolean]$apppoolexists = Test-Path $apppoolpath
    [boolean]$siteexists = Test-Path $sitepath
    [boolean]$virtualdirexists = Test-Path $virtualdirpath

    if (!$apppoolexists) {
        New-Item $apppoolpath
        Set-ItemProperty $apppoolpath -name ManagedRuntimeVersion -value v4.0
        #changing to network service (identity 2)
        #$apppoolpath.processModel.identityType = "NetworkService"
        Set-ItemProperty $apppoolpath -name ProcessModel.IdentityType -value 2
    }

    if (! $siteexists) {
        New-Item $sitepath -physicalPath $("c:\" + $site) -bindings @{protocol="http";bindingInformation=$(":" + $port + ":")}
        Set-ItemProperty $sitepath -name applicationPool -value DefaultAppPool
    }

    #if (! $virtualdirexists) {
    [string[]]$virDirParts = $virtualDir.Split('\/')
    [string] $group;
    [string] $prevGroup;
    foreach($val in $virDirParts) {
        $prevGroup = $group;
        $group = $($group + "\" + $val)
        if (! [String]::IsNullOrEmpty($prevGroup) ) {
            [boolean]$virtualdirexists = Test-Path $($sitepath + "\" + $group)
            if (! $virtualdirexists) {
                New-Item $($sitepath + "\" + $group) -physicalPath $("C:\Inetpub\wwwroot\" + $prevGroup) -type VirtualDirectory -force
            }
        }
    }

    [void](New-Item $virtualdirpath -physicalPath $vRootTargetDir -type Application -force)
    Set-ItemProperty $virtualdirpath -name applicationPool -value $appPool
    #}
}

Install-CRMIISWebSite -vRootTargetDir $vrootdir -virtualDir $vdirname -appPool $apppool
Set-Attr $result "changed" $true;
Exit-Json $result;