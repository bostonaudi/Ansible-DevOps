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

$buildDropLocation = Get-Attr -obj $params -name "buildDropLocation" -default "" -failifempty $true
Set-Attr $result "buildDropLocation" $buildDropLocation

$SQLInstance = Get-Attr -obj $params -name "SQLInstance" -default "" -failifempty $true
Set-Attr $result "SQLInstance" $SQLInstance

$databasePath = Get-Attr -obj $params -name "databasePath" -default "" -failifempty $true
Set-Attr $result "databasePath" $databasePath

$ReportInstance = Get-Attr -obj $params -name "ReportInstance" -default $null
Set-Attr $result "ReportInstance" $ReportInstance

$result = New-Object PSObject;

Set-Attr $result "changed" $false;

import-module "\\sc1jumpbox.pdnt.blackbaud.com\CRMPowershell\library\CRMManifest.psd1"


<# Master list of steps for all deployment for CRM Automation

  0)  Determine if patch build
  1)  Kill anything lingering on the agent (chrome, IE, IIS)
  2)  Setup lab user on the SQL server
  3)  Reset SQL Server instance?
  4)  Load SQL DB?
  5)  Install the application
  6)  Setup Address Validation
  7)  Load Reports onto the Report Server
  8)  Setup BBPS
  9)  Copy Brand Options file
 10)  Create a snapshot of the Database

#>

# -- Determine if patch build --
$isPatchBuild = $buildDropLocation.Contains("Patches")
if ($isPatchBuild) {
    $patchDropLocation = $buildDropLocation
    $buildDropLocation = $patchDropLocation.Substring(0, $patchDropLocation.IndexOf("Patches") - 1)

    Write-Host "Installing build from $buildDropLocation"
    Write-Host "Installing patch from $patchDropLocation"
}

# Set all parameters for the installation
$Product = "Phoenix"
$vDir = "bbappfx_$Product"
$baseInstallDir = "c:\Infinity\$Product"

$databaseKey = "EnterpriseAutomation"
$databaseName = $env:COMPUTERNAME
$ConnectionString ="Data Source=$SQLInstance;Initial Catalog=$databaseName;Integrated Security=SSPI;"

$addressValSrv = $CRM_AddressValServer

$reportServiceUrl = "http://$ReportInstance/reportserver"
$webServiceUrl = "http://localhost/$vDir/AppFxWebService.asmx"

$brandingFile = "$PSScriptRoot\brandoptions.xml"
$brandFileDropLocation = "$baseInstallDir\bbappfx\vroot\browser\brand\current"

# Database compatability. Normally 110.
$compatLevel = "110"

# Why is this a thing? How is the agent NOT running as Automagic right now?
#Write-Host 'Changing the Lab Agent Service account to run as PDNT\Automagic'
#Set-LabServiceUser

# -- Load SQL DB --

# Attach and prep the DB - assumption is database coming from a parameter
Write-Host "Loading database $databaseName from backup $databasePath"
Restore-CRMDatabase -databaseName $databaseName -SQLInstance $SQLInstance -databasePath $databasePath

# Setup lab user on the SQL server
Write-Host "Adding system user to database $databaseName"
Add-CRMSystemUser -databaseName $databaseName -SQLInstance $SQLInstance

# -- Install the application --
Write-Host "Installing Build from $buildDropLocation to $baseInstallDir"
Install-CRMBuild -prodName $vDir -sourceDir $buildDropLocation -baseInstallDir $baseInstallDir

if ($isPatchBuild) {
    Write-Host "Installing Patch from $patchDropLocation"
    Install-CRMPatch -patchDir $patchDropLocation -baseInstallDir $baseInstallDir
}

Write-Host "Changing web.config, regenerating the encryption key."
Set-CRMDatabaseEntry -installDir $baseInstallDir -connectionString $ConnectionString -databaseKey $databaseKey
Set-CRMEncryptionKey -installDir $baseInstallDir -connectionString $ConnectionString
Update-CRMRevisions -installDir $baseInstallDir -connectionString $ConnectionString

# -- Setup Address Validation --
Write-Host "Setting up Address Validation Services to point at $addressValSrv"
Set-CRMAddressValidationService -AddressValidationMachineIpAddress (Get-CRMIPAddressForHostName $addressValSrv) -BaseInstallDir $baseInstallDir

if ($ReportInstance.Length -gt 0) {
    # -- Load Reports onto the Report Server --
    Write-Host "Setting up reporting services on $ReportInstance"
    Set-CRMReportServer -installDir $baseInstallDir -databaseName $databaseName -databaseServer $SQLInstance -reportFolder $databaseName -reportServiceHost $ReportInstance -reportServiceURL $reportServiceUrl  -deleteRootFolderList
    Publish-CRMReports -installDir $baseInstallDir -databaseKey $databaseKey -webServiceUrl $webServiceUrl -loadAllReports
}

# -- Setup BBPS --
Write-Host "Adding BBPS account to $databaseName on $SQLInstance"
Add-CRMBBPSAccount -databaseName $databaseName -SQLInstance $SQLInstance

# -- Copy Brand Options file --
# Currently, we assume the build definition is going to grab this file and put it in the scripts folder. We should fix this one day
Write-Host "Branding application as CRM"
if (test-path $brandingFile) {
    xcopy $brandingFile $brandFileDropLocation /e /y /r
} else {
    Write-Host "No branding file found, skipping copy."
}

# -- Create a snapshot of the Database --
Write-Host "Creating/Overwriting Snapshot of $databaseName"
$snapName = $databaseName + "_Automation"
Add-CRMDatabaseSnapshot -database $databaseName -snapshotname $snapName -SQLInstance $SQLInstance -overwrite

Set-Attr $result "changed" $true;
Exit-Json $result;


# SIG # Begin signature block
# MIIQXAYJKoZIhvcNAQcCoIIQTTCCEEkCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUHYEuKXG2NXviKhn6n+UZlVtA
# tSqgggvZMIIDPDCCAiigAwIBAgIQ3Ie1GSoICLZFaJCpbx3+ejAJBgUrDgMCHQUA
# MCkxJzAlBgNVBAMTHkNSTSBQb3dlclNoZWxsIExvY2FsIENlcnQgUm9vdDAeFw0x
# NTA4MDMxNzMxMjRaFw0zOTEyMzEyMzU5NTlaMB4xHDAaBgNVBAMTE0NSTSBQb3dl
# clNoZWxsIFVzZXIwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDJiiKE
# UOilslGYP0PZ2AvK3AvbTk7DiuKym2M/QFYyElaHjphKeLAAyaqULZ+MujLP5GL8
# riSHOx69b26ukWQlxxBOQqkmwLlEVmFTMmvKc4qv6akIcZVfQj6i2x0NteEKTJci
# fEYNi0GYhedCA83Rd8JY+9DM1XWpF4cnXKr9EcQ+ytphf0VKRaG5f0tj88C8sDwe
# vsIjIs1ocK8LoPCPnlEjAOcKUd9fCVIBT6g9XDLooLtOVb+ZTYT95D2PW4eiczkW
# 7QTT5XQZks0mKAXwvqb39FLfuWqCAep2cBWxu6TQtfGr63wRtJDurs1M0sPZYd/h
# CZfI9qDw/6+zMnQBAgMBAAGjczBxMBMGA1UdJQQMMAoGCCsGAQUFBwMDMFoGA1Ud
# AQRTMFGAEMxeeTYumBu4s5eBxSLieSahKzApMScwJQYDVQQDEx5DUk0gUG93ZXJT
# aGVsbCBMb2NhbCBDZXJ0IFJvb3SCEGnVSo6abe+nTa3jVV8vlEkwCQYFKw4DAh0F
# AAOCAQEAO+OQoWOFANmqUc2PcIy8M/daMd4T7lS/1kVhn6d7NBMz9dDbeMZfxl03
# 0CazOGX1JUmQQ406FJ7Z2xiipA6s42xXgEn7eQpjrGH0d3Dv4t9tg/sySjM3IqT7
# bXmHrw3TDra1MgUqWy/B+0XTAWYCLbU4beHYdWJvHqufMKFXtTZguftRxMeidIrD
# 1CVnSHO1K9A/QnunAKhR9NHBB8HRK60+tYz0dOb7rpSn/XntM4HMRwcoYE7+hw5u
# wk94Upqsc4SpafPqPp0BQwq72KT2/tpkBwMOgj+2BES/nsfna5LDxYoHRUHtZQJN
# T1U8vHaQzJbotEc8z6/0RirplBrjazCCA+4wggNXoAMCAQICEH6T6/t8xk5Z6kua
# d9QG/DswDQYJKoZIhvcNAQEFBQAwgYsxCzAJBgNVBAYTAlpBMRUwEwYDVQQIEwxX
# ZXN0ZXJuIENhcGUxFDASBgNVBAcTC0R1cmJhbnZpbGxlMQ8wDQYDVQQKEwZUaGF3
# dGUxHTAbBgNVBAsTFFRoYXd0ZSBDZXJ0aWZpY2F0aW9uMR8wHQYDVQQDExZUaGF3
# dGUgVGltZXN0YW1waW5nIENBMB4XDTEyMTIyMTAwMDAwMFoXDTIwMTIzMDIzNTk1
# OVowXjELMAkGA1UEBhMCVVMxHTAbBgNVBAoTFFN5bWFudGVjIENvcnBvcmF0aW9u
# MTAwLgYDVQQDEydTeW1hbnRlYyBUaW1lIFN0YW1waW5nIFNlcnZpY2VzIENBIC0g
# RzIwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCxrLNJVEuXHBIK2CV5
# kSJXKm/cuCbEQ3Nrwr8uUFr7FMJ2jkMBJUO0oeJF9Oi3e8N0zCLXtJQAAvdN7b+0
# t0Qka81fRTvRRM5DEnMXgotptCvLmR6schsmTXEfsTHd+1FhAlOmqvVJLAV4RaUv
# ic7nmef+jOJXPz3GktxK+Hsz5HkK+/B1iEGc/8UDUZmq12yfk2mHZSmDhcJgFMTI
# yTsU2sCB8B8NdN6SIqvK9/t0fCfm90obf6fDni2uiuqm5qonFn1h95hxEbziUKFL
# 5V365Q6nLJ+qZSDT2JboyHylTkhE/xniRAeSC9dohIBdanhkRc1gRn5UwRN8xXnx
# ycFxAgMBAAGjgfowgfcwHQYDVR0OBBYEFF+a9W5czMx0mtTdfe8/2+xMgC7dMDIG
# CCsGAQUFBwEBBCYwJDAiBggrBgEFBQcwAYYWaHR0cDovL29jc3AudGhhd3RlLmNv
# bTASBgNVHRMBAf8ECDAGAQH/AgEAMD8GA1UdHwQ4MDYwNKAyoDCGLmh0dHA6Ly9j
# cmwudGhhd3RlLmNvbS9UaGF3dGVUaW1lc3RhbXBpbmdDQS5jcmwwEwYDVR0lBAww
# CgYIKwYBBQUHAwgwDgYDVR0PAQH/BAQDAgEGMCgGA1UdEQQhMB+kHTAbMRkwFwYD
# VQQDExBUaW1lU3RhbXAtMjA0OC0xMA0GCSqGSIb3DQEBBQUAA4GBAAMJm495739Z
# MKrvaLX64wkdu0+CBl03X6ZSnxaN6hySCURu9W3rWHww6PlpjSNzCxJvR6muORH4
# KrGbsBrDjutZlgCtzgxNstAxpghcKnr84nodV0yoZRjpeUBiJZZux8c3aoMhCI5B
# 6t3ZVz8dd0mHKhYGXqY4aiISo1EZg362MIIEozCCA4ugAwIBAgIQDs/0OMj+vzVu
# BNhqmBsaUDANBgkqhkiG9w0BAQUFADBeMQswCQYDVQQGEwJVUzEdMBsGA1UEChMU
# U3ltYW50ZWMgQ29ycG9yYXRpb24xMDAuBgNVBAMTJ1N5bWFudGVjIFRpbWUgU3Rh
# bXBpbmcgU2VydmljZXMgQ0EgLSBHMjAeFw0xMjEwMTgwMDAwMDBaFw0yMDEyMjky
# MzU5NTlaMGIxCzAJBgNVBAYTAlVTMR0wGwYDVQQKExRTeW1hbnRlYyBDb3Jwb3Jh
# dGlvbjE0MDIGA1UEAxMrU3ltYW50ZWMgVGltZSBTdGFtcGluZyBTZXJ2aWNlcyBT
# aWduZXIgLSBHNDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAKJjCzlE
# uLsjp0RJuw7/ofBhClOTsJjbrSwPSsVu/4Y8U1UPFc4EPyv9qZaW2b5heQtbyUyG
# duXgQ0sile7CK0PBn9hotI5AT+6FOLkRxSPyZFjwFTJvTlehroikAtcqHs1L4d1j
# 1ReJMluwXplaqJ0oUA4X7pbbYTtFUR3PElYLkkf8q672Zj1HrHBy55LnX80QucSD
# ZJQZvSWA4ejSIqXQugJ6oXeTW2XD7hd0vEGGKtwITIySjJEtnndEH2jWqHR32w5b
# MotWizO92WPISZ06xcXqMwvS8aMb9Iu+2bNXizveBKd6IrIkri7HcMW+ToMmCPsL
# valPmQjhEChyqs0CAwEAAaOCAVcwggFTMAwGA1UdEwEB/wQCMAAwFgYDVR0lAQH/
# BAwwCgYIKwYBBQUHAwgwDgYDVR0PAQH/BAQDAgeAMHMGCCsGAQUFBwEBBGcwZTAq
# BggrBgEFBQcwAYYeaHR0cDovL3RzLW9jc3Aud3Muc3ltYW50ZWMuY29tMDcGCCsG
# AQUFBzAChitodHRwOi8vdHMtYWlhLndzLnN5bWFudGVjLmNvbS90c3MtY2EtZzIu
# Y2VyMDwGA1UdHwQ1MDMwMaAvoC2GK2h0dHA6Ly90cy1jcmwud3Muc3ltYW50ZWMu
# Y29tL3Rzcy1jYS1nMi5jcmwwKAYDVR0RBCEwH6QdMBsxGTAXBgNVBAMTEFRpbWVT
# dGFtcC0yMDQ4LTIwHQYDVR0OBBYEFEbGaaMOShQe1UzaUmMXP142vA3mMB8GA1Ud
# IwQYMBaAFF+a9W5czMx0mtTdfe8/2+xMgC7dMA0GCSqGSIb3DQEBBQUAA4IBAQB4
# O7SRKgBM8I9iMDd4o4QnB28Yst4l3KDUlAOqhk4ln5pAAxzdzuN5yyFoBtq2MrRt
# v/QsJmMz5ElkbQ3mw2cO9wWkNWx8iRbG6bLfsundIMZxD82VdNy2XN69Nx9DeOZ4
# tc0oBCCjqvFLxIgpkQ6A0RH83Vx2bk9eDkVGQW4NsOo4mrE62glxEPwcebSAe6xp
# 9P2ctgwWK/F/Wwk9m1viFsoTgW0ALjgNqCmPLOGy9FqpAa8VnCwvSRvbIrvD/niU
# UcOGsYKIXfA9tFGheTMrLnu53CAJE3Hrahlbz+ilMFcsiUk/uc9/yb8+ImhjU5q9
# aXSsxR08f5Lgw7wc2AR1MYID7TCCA+kCAQEwPTApMScwJQYDVQQDEx5DUk0gUG93
# ZXJTaGVsbCBMb2NhbCBDZXJ0IFJvb3QCENyHtRkqCAi2RWiQqW8d/nowCQYFKw4D
# AhoFAKB4MBgGCisGAQQBgjcCAQwxCjAIoAKAAKECgAAwGQYJKoZIhvcNAQkDMQwG
# CisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwIwYJKoZI
# hvcNAQkEMRYEFKAT7Oi55NtMdkIEKAZqbKZceyqVMA0GCSqGSIb3DQEBAQUABIIB
# AILwGf4UroFtYGgpnJCS0CcXfdezl56y9UECbpCxZQWdJ5RExJNSXMvEAICbyRZ2
# VwwrN9LzLdQx/X7EmTJwaOzlbVvspBMch0OjgpyM9skBR0LqOGabNtyhheUsK5Ci
# vt72vNg6T/qJ8bTkUBEqd1tPZjGL6HC4NCIyW8WB20O63niJseo7b8vsu8QWjRzK
# 3CgLTwF5VoNlqAfGwG8U8KzasZfB3iQrHqzSSYCt0M+aoS24GW+avhI5tPnwKhbv
# 8SK8DHCiDW6KbJOHh/3c2ytZvBZyl/woWm7A55RuV9TkAyqKULs8EGy776oV6SDw
# uwkPHJ43DHhmz0sIonlUVzKhggILMIICBwYJKoZIhvcNAQkGMYIB+DCCAfQCAQEw
# cjBeMQswCQYDVQQGEwJVUzEdMBsGA1UEChMUU3ltYW50ZWMgQ29ycG9yYXRpb24x
# MDAuBgNVBAMTJ1N5bWFudGVjIFRpbWUgU3RhbXBpbmcgU2VydmljZXMgQ0EgLSBH
# MgIQDs/0OMj+vzVuBNhqmBsaUDAJBgUrDgMCGgUAoF0wGAYJKoZIhvcNAQkDMQsG
# CSqGSIb3DQEHATAcBgkqhkiG9w0BCQUxDxcNMTUwODA0MjAyMDA4WjAjBgkqhkiG
# 9w0BCQQxFgQUWLINhfoEFmxLPSYeX42jDzDqKwwwDQYJKoZIhvcNAQEBBQAEggEA
# EeLAfZ3g8jjza60iOAlLl/WkfJan485OKbsrBgbr69YzMxsqnYbjOzAy8Qaytz3n
# 7McZjScL2wBKkTHVRfR9n6GJ6LjX+Tgd77Mjt+Ya6VXEsYuWpZGOwwBZp05br3Ow
# A+G2p/lVLYSvqkTo5R1zgCl/n4MroJU37P1eXf7fL81XZr/QsbQyPwMHnJVemRvm
# xRqB/OQgEYmxO3wYa5c/vZG5B4sLvobOX6BKotXyTeo7kHZiS/9BcR3Rdfk/eP2s
# cyaoDHrTFUwbg3EcHl9H00JL43EzQjE/6dlnN7dvb2UXgowg4tLXerXtbmc08h65
# YnCj9k7EoQRIBWdjrWvCHw==
# SIG # End signature block
