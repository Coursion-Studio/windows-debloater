# Writes update.json, the file installed copies read to learn of a new version: where
# the installer is, its SHA-256, the points from CHANGELOG.md, and a signature over the
# installer's bytes made with the private half of the update key.
#
# That key is the one thing a release needs that does not go to GitHub. It stays on
# the maintainer's PC, at %APPDATA%\Coursion\keys\windows-debloater-update.xml
# (scripts\new-update-key.ps1 made it once), so this is the one step of a release that
# runs there and not in GitHub Actions. See CODE_SIGNING_POLICY.md.
#
# After the release workflow has built a draft release for a tag:
#
#   powershell -ExecutionPolicy Bypass -File scripts\write-update-feed.ps1 -Tag v1.2.3
#
#   downloads the installer from that draft release, checks it against the .sha256 the
#   workflow published with it, signs it, and uploads update.json to the same release.
#   Publishing the draft stays a separate, deliberate step:
#
#   gh release edit v1.2.3 --repo Coursion-Studio/windows-debloater --draft=false
#
# scripts\build-release.ps1 also uses it, with -Installer and -Out, when a release is
# built on the PC.
#
# Run it from a checkout of the tag, so that src\version.txt and CHANGELOG.md are the
# ones the release was built from.

param([string]$Tag, [string]$Installer, [string]$Out)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$repo = 'Coursion-Studio/windows-debloater'
$version = (Get-Content -LiteralPath (Join-Path $root 'src\version.txt') -Raw).Trim()
$keyFile = Join-Path $env:APPDATA 'Coursion\keys\windows-debloater-update.xml'
if (-not (Test-Path -LiteralPath $keyFile)) {
    throw "The update signing key was not found at $keyFile. Restore it from your backup. A new key would not do: copies that are already installed only accept the old one."
}
if (-not $Tag -and -not $Installer) { throw 'Say which release: -Tag v1.2.3, or -Installer and the path of the installer.' }

$upload = $false
if ($Tag) {
    if ($Tag -ne "v$version") { throw "src\version.txt says $version, so this checkout is not the one $Tag was built from. Check out $Tag first." }
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'This needs the GitHub CLI, gh, signed in to an account that can edit the releases.' }
    $download = Join-Path $root 'dist\from-github'
    if (Test-Path -LiteralPath $download) { Remove-Item -LiteralPath $download -Recurse -Force }
    [void](New-Item -ItemType Directory -Force -Path $download)
    $leaf = "WindowsDebloaterSetup-$version.exe"
    & gh release download $Tag --repo $repo --dir $download --pattern $leaf --pattern ($leaf + '.sha256')
    if ($LASTEXITCODE -ne 0) { throw "Downloading $leaf from the $Tag release failed." }
    $Installer = Join-Path $download $leaf
    $published = ([IO.File]::ReadAllText($Installer + '.sha256').Trim() -split '\s+')[0].ToLowerInvariant()
    $actual = (Get-FileHash -LiteralPath $Installer -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($published -ne $actual) { throw "The downloaded installer does not match the SHA-256 published with it ($actual, not $published)." }
    if (-not $Out) { $Out = Join-Path $download 'update.json' }
    $upload = $true
}
if (-not $Out) { $Out = Join-Path $root 'dist\update.json' }
if (-not (Test-Path -LiteralPath $Installer)) { throw "There is no installer at $Installer." }
$Installer = (Resolve-Path -LiteralPath $Installer).Path

# The installer's bytes are signed with the private key. Installed copies check that
# signature with the public half they carry (src\update-key.xml) before they run it.
$bytes = [IO.File]::ReadAllBytes($Installer)
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
    url       = "https://github.com/$repo/releases/download/v$version/WindowsDebloaterSetup-$version.exe"
    sha256    = (Get-FileHash -LiteralPath $Installer -Algorithm SHA256).Hash.ToLowerInvariant()
    signature = $signature
    size      = $bytes.Length
    notes     = @($notes)
}
[void](New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Out))
[IO.File]::WriteAllText($Out, ($feed | ConvertTo-Json -Depth 3), (New-Object Text.UTF8Encoding($false)))
Write-Host ("{0}`n   version {1}, signed, {2} notes" -f $Out, $version, $notes.Count)

if ($upload) {
    & gh release upload $Tag $Out --repo $repo --clobber
    if ($LASTEXITCODE -ne 0) { throw "Uploading update.json to the $Tag release failed." }
    Write-Host "Uploaded update.json to $Tag. The release is still a draft until you publish it:"
    Write-Host "   gh release edit $Tag --repo $repo --draft=false"
}
