[CmdletBinding()]
param($configFile, $srcPath)


$user = 'pdnt\automagic'
$pass = ConvertTo-SecureString -String "Research6" -AsPlainText -Force
$creds = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList ($user, $pass)

Function installSQL
{
    [CmdletBinding()]
    param($configFile, $srcPath)

    $user = 'pdnt\automagic'
    $pass = ConvertTo-SecureString -String "Research6" -AsPlainText -Force
    $creds = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList ($user, $pass)

    [scriptblock]$scriptBlock =
    {
        param($configFile, $srcPath)
        Import-Module \\ptlserver9\CrmPowershell\DEBUG\CRMManifest.psd1

        $setup = Join-Path $srcPath "setup.exe"
        $config = Join-Path $srcPath $configFile
        $mediaPath = Join-Path $srcPath "\x64\Setup"

        & $setup /action=install /installmediapath=$mediaPath /ConfigurationFile=$configFile /Q /IAcceptSQLServerLicenseTerms

    }
    Invoke-Command -ComputerName $env:ComputerName -ScriptBlock $scriptBlock -Authentication Default -Credential $creds -ArgumentList $configFile,$srcPath

}

installSQL -configFile $configFile -srcPath $srcPath


