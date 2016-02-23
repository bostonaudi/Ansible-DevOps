[CmdletBinding()]
param
(
    [Parameter(Mandatory=$true)][string]$hostname, 
    [Parameter(Mandatory=$true)][string]$configpath,
    [Parameter(Mandatory=$true)][string]$websitename
)

$configpath = $configpath.replace("/", "\")

$scriptblock = {
param
(
    [string]$hostname, 
    [string]$configpath,
    [string]$websitename

)

    import-module "\\ptlserver9\CrmPowershell\SDO\Powershell\SDOManifest.psd1"

    Initialize-SDOWebServer -ComputerName $hostname -ServerSetupConfigFilePath $configpath -WebSiteName $websitename
}

$user = 'pdnt\automagic'
$pass = ConvertTo-SecureString -String "Research6" -AsPlainText -Force
$creds = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList ($user, $pass)

$session = New-PSSession -ComputerName $env:Computername -Credential $creds -Authentication Credssp

Invoke-Command -Session $session -ScriptBlock $scriptblock -ArgumentList $hostname,$configpath,$websitename
