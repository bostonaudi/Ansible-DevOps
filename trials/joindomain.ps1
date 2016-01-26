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

# code

$result = New-Object psobject @{
    output = New-Object psobject
    changed = $false
};

$cred = (New-Object System.Management.Automation.PSCredential("addme", (ConvertTo-SecureString "addme" -AsPlainText -Force)))

Add-Computer -Credential $cred -DomainName "pdnt.blackbaud.com" -OUPath "OU=NoGreetPopup,DC=pdnt,DC=blackbaud,DC=com" -Force -Restart

Set-Attr $result.output "Name" "added to pdnt"

Exit-Json $result;
