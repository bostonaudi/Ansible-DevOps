param ([string]$path)


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

echo "received $path"

$user = 'pdnt\automagic'
$pass = ConvertTo-SecureString -String "Research6" -AsPlainText -Force
$creds = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList ($user, $pass)
$computername = "sc1ansagt01.pdnt.blackbaud.com"

$scriptBlock = {
    param($path)
    echo "inside script block path: $path"
    dir $path
}

Invoke-CRMCommand -ComputerName $computername -Credential $creds -Authentication CredSSP -ArgumentList $path -Scriptblock $scriptBlock


