# Builds the two programs with the C# compiler that is part of Windows, so there is
# nothing to install first:
#
#   bin\WindowsDebloater.exe        the program people start; it runs the scripts in src
#   bin\WindowsDebloaterSetup.exe   the installer, with the program and src packed inside
#
#   powershell -ExecutionPolicy Bypass -File scripts\build-exe.ps1
#
# The version comes from src\version.txt.
#
#   -Sign    also code-sign both programs and the scripts packed into the installer,
#            with the certificate chosen by scripts\set-code-signing.ps1. Only a
#            release does this; everything builds and runs the same without it.

param([switch]$Sign)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$bin = Join-Path $root 'bin'
$obj = Join-Path $bin 'obj'
$version = (Get-Content -LiteralPath (Join-Path $root 'src\version.txt') -Raw).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw "src\version.txt should hold a version such as 1.2.3, not '$version'." }
# The year of the copyright line is the one the licence gives.
$year = [regex]::Match([IO.File]::ReadAllText((Join-Path $root 'LICENSE.md')), 'Copyright \S+ (\d{4}) Coursion Studio').Groups[1].Value
if (-not $year) { throw 'LICENSE.md has no copyright line with a year.' }

$framework = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
$csc = Join-Path $framework 'csc.exe'
$wpf = Join-Path $framework 'WPF'
if (-not (Test-Path -LiteralPath $csc)) { throw "The C# compiler was not found at $csc." }
# Windows PowerShell itself, which the program runs the scripts with.
$automation = [psobject].Assembly.Location
$icon = Join-Path $root 'src\ui\icon.ico'
$manifest = Join-Path $root 'exe\app.manifest'

$signing = $null
if ($Sign) {
    . (Join-Path $PSScriptRoot 'CodeSigning.ps1')
    $signing = Get-CodeSigningSetup
    if (-not $signing) { throw 'No signing certificate has been chosen. Run scripts\set-code-signing.ps1 first.' }
}

if (Test-Path -LiteralPath $obj) { Remove-Item -LiteralPath $obj -Recurse -Force }
[void](New-Item -ItemType Directory -Force -Path $obj)

# The name and version Windows shows for a program: in its Properties, in Task Manager
# and in the list of installed apps.
function New-VersionFile {
    param([string]$Path, [string]$Title, [string]$Description)
    $lines = @(
        'using System.Reflection;',
        ('[assembly: AssemblyTitle("{0}")]' -f $Title),
        ('[assembly: AssemblyDescription("{0}")]' -f $Description),
        '[assembly: AssemblyProduct("Windows Debloater")]',
        '[assembly: AssemblyCompany("Coursion Studio")]',
        ('[assembly: AssemblyCopyright("Copyright \u00A9 {0} Coursion Studio. Released under the MIT licence.")]' -f $year),
        ('[assembly: AssemblyVersion("{0}.0")]' -f $version),
        ('[assembly: AssemblyFileVersion("{0}.0")]' -f $version),
        ('[assembly: AssemblyInformationalVersion("{0}")]' -f $version)
    )
    [IO.File]::WriteAllText($Path, ($lines -join "`n") + "`n", (New-Object Text.UTF8Encoding($false)))
}

function Invoke-Compiler {
    param([string]$Out, [string[]]$Arguments)
    if (Test-Path -LiteralPath $Out) { Remove-Item -LiteralPath $Out -Force }
    $output = & $csc /nologo /target:winexe /optimize+ /platform:anycpu /warnaserror+ "/out:$Out" "/win32icon:$icon" "/win32manifest:$manifest" @Arguments
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $Out)) {
        throw ("Building {0} failed:`n{1}" -f (Split-Path -Leaf $Out), ($output -join "`n"))
    }
}

# ---------------------------------------------------------------- The program

$appExe = Join-Path $bin 'WindowsDebloater.exe'
$appVersion = Join-Path $obj 'AppVersion.cs'
New-VersionFile $appVersion 'Windows Debloater' 'A clean start for Windows 11'
Invoke-Compiler $appExe @("/r:$automation", '/r:System.dll', '/r:System.Core.dll', $appVersion, (Join-Path $root 'exe\WindowsDebloater.cs'))
# Signed before it goes into the installer, so that the copy that gets installed is
# signed as well.
if ($signing) { Add-CodeSignature -Path $appExe -Certificate $signing.Thumbprint -Timestamp $signing.Timestamp -Description 'Windows Debloater' }
Write-Host "Built $appExe"

# ---------------------------------------------------------------- The installer

$setupSources = @(Get-ChildItem -LiteralPath (Join-Path $root 'setup') -Filter '*.cs' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
if ($setupSources.Count -gt 0) {
    # What gets installed: the program, the scripts, and the few documents the window
    # links to. It travels inside the installer as one zip.
    $stage = Join-Path $obj 'payload'
    [void](New-Item -ItemType Directory -Force -Path (Join-Path $stage 'docs'))
    Copy-Item -LiteralPath $appExe -Destination $stage
    Copy-Item -LiteralPath (Join-Path $root 'src') -Destination $stage -Recurse
    # The copies that get installed, not the ones in src.
    if ($signing) { [void](Add-ScriptSignatures -Folder (Join-Path $stage 'src') -Certificate $signing.Thumbprint -Timestamp $signing.Timestamp) }
    Copy-Item -LiteralPath (Join-Path $root 'docs\changes.md') -Destination (Join-Path $stage 'docs')
    foreach ($file in 'LICENSE.md', 'PRIVACY.md') { Copy-Item -LiteralPath (Join-Path $root $file) -Destination $stage }
    $payload = Join-Path $obj 'payload.zip'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory($stage, $payload, [IO.Compression.CompressionLevel]::Optimal, $false)

    $setupExe = Join-Path $bin 'WindowsDebloaterSetup.exe'
    $setupVersion = Join-Path $obj 'SetupVersion.cs'
    New-VersionFile $setupVersion 'Windows Debloater Setup' 'Installs Windows Debloater'
    # The picture the setup window shows: the largest one in the app icon, as a PNG.
    Add-Type -AssemblyName PresentationCore, WindowsBase
    $picture = Join-Path $obj 'icon.png'
    $iconStream = [IO.File]::OpenRead($icon)
    try {
        $decoder = New-Object Windows.Media.Imaging.IconBitmapDecoder($iconStream, 'None', 'OnLoad')
        $largest = $decoder.Frames | Sort-Object PixelWidth -Descending | Select-Object -First 1
        $encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
        $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($largest))
        $pictureStream = [IO.File]::Create($picture)
        try { $encoder.Save($pictureStream) } finally { $pictureStream.Dispose() }
    } finally { $iconStream.Dispose() }

    $resources = @("/resource:$payload,payload.zip", "/resource:$picture,icon.png")
    foreach ($extra in @(Get-ChildItem -LiteralPath (Join-Path $root 'setup') -File -Filter '*.xaml')) {
        $resources += "/resource:$($extra.FullName),$($extra.Name)"
    }
    $references = @(
        "/r:$wpf\PresentationFramework.dll", "/r:$wpf\PresentationCore.dll", "/r:$wpf\WindowsBase.dll",
        '/r:System.Xaml.dll', '/r:System.dll', '/r:System.Core.dll', '/r:System.Xml.dll',
        '/r:System.IO.Compression.dll', '/r:System.IO.Compression.FileSystem.dll', '/r:System.Web.Extensions.dll'
    )
    Invoke-Compiler $setupExe ($references + $resources + @($setupVersion) + $setupSources)
    # The installer keeps a copy of itself next to the program as Uninstall.exe, so
    # signing it signs the uninstaller too.
    if ($signing) { Add-CodeSignature -Path $setupExe -Certificate $signing.Thumbprint -Timestamp $signing.Timestamp -Description 'Windows Debloater Setup' }
    Write-Host "Built $setupExe"
}

Remove-Item -LiteralPath $obj -Recurse -Force
