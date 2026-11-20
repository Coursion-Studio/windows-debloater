# Builds what a release carries, into dist\:
#
#   WindowsDebloaterSetup-<version>.exe   the installer
#   WindowsDebloater-<version>.zip        the same program to unpack and run, nothing installed
#   and a .sha256 file next to each, for checking a download
#   update.json                           what installed copies read to learn of this version:
#                                         where the installer is, its SHA-256, and a signature
#
#   powershell -ExecutionPolicy Bypass -File scripts\build-release.ps1
#
# The version comes from src\version.txt. Run test\Run-Tests.ps1 first.
#
# Signing needs the private half of the update key, which scripts\new-update-key.ps1
# made once: %APPDATA%\Coursion\keys\windows-debloater-update.xml. All five files go
# onto the release; update.json has to keep exactly that name.
#
# That signature is for the tool's own update check. Code signing is a second, separate
# one, the one Windows itself reads: when a certificate has been chosen with
# scripts\set-code-signing.ps1, both programs and the scripts they ship with are signed
# with it, and the release is refused if that does not work. -Unsigned builds a release
# without it on purpose.

param([switch]$Unsigned)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$version = (Get-Content -LiteralPath (Join-Path $root 'src\version.txt') -Raw).Trim()
$dist = Join-Path $root 'dist'
$name = "WindowsDebloater-$version"
$stage = Join-Path $dist $name
$zip = Join-Path $dist ($name + '.zip')
$setup = Join-Path $dist "WindowsDebloaterSetup-$version.exe"
$feedPath = Join-Path $dist 'update.json'
$keyFile = Join-Path $env:APPDATA 'Coursion\keys\windows-debloater-update.xml'
if (-not (Test-Path -LiteralPath $keyFile)) {
    throw "The update signing key was not found at $keyFile. Restore it from your backup. A new key would not do: copies that are already installed only accept the old one."
}

. (Join-Path $PSScriptRoot 'CodeSigning.ps1')
$signing = $null
if (-not $Unsigned) { $signing = Get-CodeSigningSetup }

if ($signing) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'build-exe.ps1') -Sign
} else {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'build-exe.ps1')
}
if ($LASTEXITCODE -ne 0) { throw 'Building the programs failed.' }

# Checked again here, on the very files that go out.
if ($signing) {
    foreach ($program in 'WindowsDebloater.exe', 'WindowsDebloaterSetup.exe') {
        $problem = Get-CodeSignatureProblem -Path (Join-Path $root ('bin\' + $program)) -Thumbprint $signing.Thumbprint -RequireTimestamp
        if ($problem) { throw "$program cannot be released: $problem." }
    }
}

if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
foreach ($old in $zip, $setup, ($zip + '.sha256'), ($setup + '.sha256'), $feedPath) {
    if (Test-Path -LiteralPath $old) { Remove-Item -LiteralPath $old -Force }
}
[void](New-Item -ItemType Directory -Force -Path $stage)

# ---------------------------------------------------------------- The zip

Copy-Item -LiteralPath (Join-Path $root 'bin\WindowsDebloater.exe') -Destination $stage
foreach ($file in 'README.md', 'LICENSE.md', 'PRIVACY.md', 'CHANGELOG.md') {
    Copy-Item -LiteralPath (Join-Path $root $file) -Destination $stage
}
Copy-Item -LiteralPath (Join-Path $root 'src') -Destination $stage -Recurse
if ($signing) {
    $count = Add-ScriptSignatures -Folder (Join-Path $stage 'src') -Certificate $signing.Thumbprint -Timestamp $signing.Timestamp
    Write-Host "Signed the $count scripts in the zip."
}
# Of docs, only the list of changes goes along. The banner, the film and the pictures
# are several times the size of the program, so they stay on the project page, and the
# zip's copy of the README shows them from there.
[void](New-Item -ItemType Directory -Force -Path (Join-Path $stage 'docs'))
Copy-Item -LiteralPath (Join-Path $root 'docs\changes.md') -Destination (Join-Path $stage 'docs')
$readmePath = Join-Path $stage 'README.md'
$readme = [IO.File]::ReadAllText($readmePath)
$readme = $readme.Replace('src="docs/', 'src="https://raw.githubusercontent.com/Coursion-Studio/windows-debloater/main/docs/')
[IO.File]::WriteAllText($readmePath, $readme, (New-Object Text.UTF8Encoding($false)))

Compress-Archive -Path $stage -DestinationPath $zip
Remove-Item -LiteralPath $stage -Recurse -Force

# ---------------------------------------------------------------- The installer

Copy-Item -LiteralPath (Join-Path $root 'bin\WindowsDebloaterSetup.exe') -Destination $setup

Write-Host ''
foreach ($file in $setup, $zip) {
    $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
    $leaf = Split-Path -Leaf $file
    # The form sha256sum reads: the hash, two spaces, the file name.
    [IO.File]::WriteAllText(($file + '.sha256'), "$hash  $leaf", (New-Object Text.ASCIIEncoding))
    Write-Host ("{0}`n   {1:N0} bytes   SHA256 {2}" -f $file, (Get-Item -LiteralPath $file).Length, $hash)
}

# ---------------------------------------------------------------- The update feed

# The installer's bytes are signed with the private key. Installed copies check that
# signature with the public half they carry (src\update-key.xml) before they run it.
$bytes = [IO.File]::ReadAllBytes($setup)
$rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider -ArgumentList (New-Object System.Security.Cryptography.CspParameters 24)
try {
    $rsa.PersistKeyInCsp = $false
    $rsa.FromXmlString([IO.File]::ReadAllText($keyFile))
    $signature = [Convert]::ToBase64String($rsa.SignData($bytes, 'SHA256'))
} finally { $rsa.Dispose() }

# A signature the shipped key does not accept would be refused by every installed copy,
# so that is found out here and not after publishing.
$check = New-Object System.Security.Cryptography.RSACryptoServiceProvider -ArgumentList (New-Object System.Security.Cryptography.CspParameters 24)
try {
    $check.PersistKeyInCsp = $false
    $check.FromXmlString([IO.File]::ReadAllText((Join-Path $root 'src\update-key.xml')))
    if (-not $check.VerifyData($bytes, 'SHA256', [Convert]::FromBase64String($signature))) {
        throw 'The signing key on this PC is not the one src\update-key.xml belongs to.'
    }
} finally { $check.Dispose() }

# What is new: the points under this version's heading in CHANGELOG.md, a line each.
$notes = @()
$inSection = $false
foreach ($line in [IO.File]::ReadAllLines((Join-Path $root 'CHANGELOG.md'))) {
    if ($line -match '^## ') { if ($inSection) { break }; $inSection = $line -match ('^## ' + [regex]::Escape($version) + '\b'); continue }
    if (-not $inSection) { continue }
    if ($line -match '^- (.*)') { $notes += $Matches[1] }
    elseif ($line -match '^\s+(\S.*)' -and $notes.Count) { $notes[-1] = $notes[-1] + ' ' + $Matches[1] }
}
$notes = @($notes | ForEach-Object { $_ -replace '\*\*', '' -replace '`', '' })
if ($notes.Count -eq 0) { throw "CHANGELOG.md has no points under a heading for $version." }

$feed = [ordered]@{
    version   = $version
    published = (Get-Date -Format 'yyyy-MM-dd')
    url       = "https://github.com/Coursion-Studio/windows-debloater/releases/download/v$version/" + (Split-Path -Leaf $setup)
    sha256    = (Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash.ToLowerInvariant()
    signature = $signature
    size      = $bytes.Length
    notes     = @($notes)
}
[IO.File]::WriteAllText($feedPath, ($feed | ConvertTo-Json -Depth 3), (New-Object Text.UTF8Encoding($false)))
Write-Host ("{0}`n   version {1}, signed, {2} notes" -f $feedPath, $version, $notes.Count)

Write-Host ''
if ($signing) {
    $signer = (Get-AuthenticodeSignature -LiteralPath $setup).SignerCertificate.Subject
    Write-Host "Code-signed by: $signer"
} else {
    Write-Host 'Not code-signed: Windows will call the publisher unknown.'
    Write-Host 'Once there is a certificate, scripts\set-code-signing.ps1 chooses it and releases are signed from then on.'
}
