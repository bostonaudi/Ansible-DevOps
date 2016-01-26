Function Update-Chrome {

    $ComputerName = $env:COMPUTERNAME

    $user = 'pdnt\automagic'
    $pass = ConvertTo-SecureString -String "Research6" -AsPlainText -Force

    $creds = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList ($user, $pass)

    $session = New-PSSession -ComputerName $ComputerName -Credential $creds -Authentication credssp

    Invoke-Command -Session $session -ScriptBlock {
        import-module "\\ptlserver9\CrmPowershell\RELEASE\CRMManifest.psd1"
        Install-CRMLatestChromeDriver
    }
}


Update-Chrome
