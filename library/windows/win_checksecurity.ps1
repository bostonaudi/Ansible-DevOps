#!powershell
# This file is part of Ansible
#
# Copyright 2014, Trond Hindenes <trond@hindenes.com>
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

Set-Attr $result "name" $(([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).Identity.Name)
Set-Attr $result "Authtype" $(([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).Identity.AuthenticationType)
Set-Attr $result "IsAuthenticated" $(([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).Identity.IsAuthenticated)

function Invoke-CRMCommand{
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

$scriptblock ="
If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] ""Administrator""))
{
    Set-Attr $result ""msg"" ""You are not Administrator!""
}
else {
    Set-Attr $result ""msg"" ""I am Administrator!""
}"

Invoke-CRMCommand -Scriptblock $scriptblock -
Exit-Json $result;