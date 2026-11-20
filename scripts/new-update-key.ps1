# Creates the key that signs Windows Debloater's updates. Run once, ever.
#
#   powershell -ExecutionPolicy Bypass -File scripts\new-update-key.ps1
#
# The private half is saved to %APPDATA%\Coursion\keys\windows-debloater-update.xml,
# outside this folder and never to be committed. Back it up somewhere safe: without it
# no update can be signed, and copies that are already installed would refuse every
# later version.
#
# The public half is written to src\update-key.xml, which ships with the tool. Every
# installer an update downloads has to carry a signature made with the private half,
# or it is not run.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$keyDir = Join-Path $env:APPDATA 'Coursion\keys'
$keyFile = Join-Path $keyDir 'windows-debloater-update.xml'
if (Test-Path -LiteralPath $keyFile) { throw "A key already exists at $keyFile. It is not overwritten." }
[void](New-Item -ItemType Directory -Force -Path $keyDir)

$rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider -ArgumentList 3072, (New-Object System.Security.Cryptography.CspParameters 24)
try {
    $rsa.PersistKeyInCsp = $false
    [IO.File]::WriteAllText($keyFile, $rsa.ToXmlString($true), (New-Object Text.ASCIIEncoding))
    [IO.File]::WriteAllText((Join-Path $root 'src\update-key.xml'), $rsa.ToXmlString($false) + "`n", (New-Object Text.ASCIIEncoding))
} finally { $rsa.Dispose() }

Write-Host "Private key: $keyFile"
Write-Host '             Back this file up and keep it secret.'
Write-Host 'Public key:  src\update-key.xml'
