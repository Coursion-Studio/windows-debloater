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
# Releases are built by GitHub Actions (.github\workflows\release.yml), not on a PC,
# so that every published file comes from the public source. The workflow uses:
#
#   -Prebuilt   package bin\ and src\ as they are, without building the programs
#               again. The workflow builds them itself and has them code-signed
#               first, so rebuilding here would throw the signatures away.
#   -NoFeed     leave update.json out. It is signed with the private half of the
#               update key, which only the maintainer has and which never goes to
#               GitHub. scripts\write-update-feed.ps1 adds it on the maintainer's
#               PC afterwards. See CODE_SIGNING_POLICY.md.
#
# Without -NoFeed, signing the feed needs that key, which scripts\new-update-key.ps1
# made once: %APPDATA%\Coursion\keys\windows-debloater-update.xml. update.json has
# to keep exactly that name on the release.

param([switch]$Prebuilt, [switch]$NoFeed)

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
if (-not $NoFeed -and -not (Test-Path -LiteralPath $keyFile)) {
    throw "The update signing key was not found at $keyFile. Restore it from your backup. A new key would not do: copies that are already installed only accept the old one. (-NoFeed builds the release without update.json.)"
}

if ($Prebuilt) {
    foreach ($program in 'WindowsDebloater.exe', 'WindowsDebloaterSetup.exe') {
        if (-not (Test-Path -LiteralPath (Join-Path $root ('bin\' + $program)))) { throw "-Prebuilt packages bin\$program, and it is not there. Run scripts\build-exe.ps1 first." }
    }
} else {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'build-exe.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Building the programs failed.' }
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

if ($NoFeed) {
    Write-Host ''
    Write-Host 'No update.json: scripts\write-update-feed.ps1 adds it on the maintainer''s PC.'
} else {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'write-update-feed.ps1') -Installer $setup -Out $feedPath
    if ($LASTEXITCODE -ne 0) { throw 'Signing the update feed failed.' }
}

$signature = Get-AuthenticodeSignature -LiteralPath $setup
Write-Host ''
if ($signature.SignerCertificate) {
    Write-Host ('Code-signed by: {0} ({1})' -f $signature.SignerCertificate.Subject, $signature.Status)
} else {
    Write-Host 'Not code-signed: Windows will call the publisher unknown.'
}
