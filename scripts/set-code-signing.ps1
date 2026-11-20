# Chooses the certificate that signs the programs of a release. Run it once, after
# the certificate has arrived, with the token plugged in or the cloud signing app
# signed in.
#
#   powershell -ExecutionPolicy Bypass -File scripts\set-code-signing.ps1
#
# It lists the code-signing certificates Windows can see for you. With exactly one,
# that is the one; with several, it asks for -Thumbprint. The choice is saved to
# %APPDATA%\Coursion\keys\code-signing.json, outside this folder, where every Coursion
# app's release script finds it. It holds no secret: only which certificate, and which
# server puts the time on a signature.
#
#   -Thumbprint <40 hex digits>   choose this one
#   -Timestamp <address>          use this time server instead of the usual one
#   -Remove                       forget the choice; releases are unsigned again

param([string]$Thumbprint, [string]$Timestamp, [switch]$Remove)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'CodeSigning.ps1')

if ($Remove) {
    if (Test-Path -LiteralPath $script:CodeSigningFile) { Remove-Item -LiteralPath $script:CodeSigningFile -Force }
    Write-Host 'No certificate is chosen now. Releases will not be code-signed.'
    return
}

$found = @(Get-CodeSigningCertificates)
if ($found.Count -eq 0) {
    throw 'Windows sees no code-signing certificate of yours. Plug in the token, or sign in to the cloud signing app (SimplySign Desktop for a Certum cloud certificate), and run this again.'
}
Write-Host 'Code-signing certificates:'
foreach ($certificate in $found) {
    Write-Host ('  {0}  until {1:yyyy-MM-dd}  {2}' -f $certificate.Thumbprint, $certificate.NotAfter, $certificate.Subject)
}

$wanted = ($Thumbprint -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()
if ($wanted) {
    $chosen = $found | Where-Object { $_.Thumbprint -eq $wanted } | Select-Object -First 1
    if (-not $chosen) { throw "None of them has the thumbprint $wanted." }
} elseif ($found.Count -eq 1) {
    $chosen = $found[0]
} else {
    throw 'There are several. Run this again with -Thumbprint and the one you mean.'
}

# The authority that issued the certificate runs a time server for it. Any trusted
# one will do; this is just the natural default.
if (-not $Timestamp) {
    $Timestamp = 'http://timestamp.digicert.com'
    if ($chosen.Issuer -match 'Certum') { $Timestamp = 'http://time.certum.pl' }
    elseif ($chosen.Issuer -match 'Sectigo|COMODO') { $Timestamp = 'http://timestamp.sectigo.com' }
    elseif ($chosen.Issuer -match 'SSL\.com') { $Timestamp = 'http://ts.ssl.com' }
}

[void](New-Item -ItemType Directory -Force -Path (Split-Path -Parent $script:CodeSigningFile))
$setup = [ordered]@{ thumbprint = $chosen.Thumbprint; subject = $chosen.Subject; timestamp = $Timestamp }
[IO.File]::WriteAllText($script:CodeSigningFile, ($setup | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))

Write-Host ''
Write-Host ('Chosen:      {0}' -f $chosen.Subject)
Write-Host ('Time server: {0}' -f $Timestamp)
Write-Host ('Saved to:    {0}' -f $script:CodeSigningFile)
if (-not (Find-SignTool)) {
    Write-Host ''
    Write-Host 'Microsoft''s signtool was not found, so Windows PowerShell''s own signing will be used.'
    Write-Host 'Installing the Windows SDK''s "Signing Tools" gives the build the tool it prefers.'
}
