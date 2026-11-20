# Makes the pictures of the README: docs\banner.png and everything in docs\img.
#
#   powershell -ExecutionPolicy Bypass -File scripts\build-pictures.ps1
#
# Nothing is taken from the screen. The window walks through itself off screen in demo
# mode, which changes nothing on the PC, and draws each stage at twice its size with
# the corners and the shadow a window has on a desktop. The setup window draws its own
# pages the same way. The banner is put together here, from the app icon, a few words
# and the picture of the overview.
#
#   -Keep    leave the working folder in TEMP afterwards, to look at the other pictures

param([switch]$Keep)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$docs = Join-Path $root 'docs'
$pictures = Join-Path $docs 'img'
$work = Join-Path $env:TEMP 'WindowsDebloater-pictures'
if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
[void](New-Item -ItemType Directory -Force -Path $work)
[void](New-Item -ItemType Directory -Force -Path $pictures)

# ---------------------------------------------------------------- The window

Write-Host 'Walking through the window...'
$walk = Join-Path $work 'walk'
$savedData = $env:DEBLOATER_DATA
$savedShots = $env:DEBLOATER_SHOTS
$env:DEBLOATER_DATA = Join-Path $work 'data'
$env:DEBLOATER_SHOTS = 'readme'
try {
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $root 'src\Debloater.ps1') + '" -Demo -Lang en -Theme dark -SelfTest "' + $walk + '"'
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WindowStyle Hidden -PassThru
    if (-not $process.WaitForExit(600000)) { throw 'The walk through the window did not finish.' }
} finally {
    $env:DEBLOATER_DATA = $savedData
    $env:DEBLOATER_SHOTS = $savedShots
}
$report = Get-Content -LiteralPath (Join-Path $walk 'selftest.json') -Raw | ConvertFrom-Json
if (-not $report.ok) { throw ('The walk through the window failed: ' + $report.error) }

# Which stage of the walk becomes which picture of the README.
$stages = [ordered]@{
    'home.png'         = 'home.png'
    'page-apps.png'    = 'apps.png'
    'confirm.png'      = 'confirm.png'
    'progress.png'     = 'progress.png'
    'home-done.png'    = 'home-done.png'
    'undo-confirm.png' = 'revert.png'
    'update.png'       = 'update.png'
}
foreach ($stage in $stages.Keys) {
    Copy-Item -LiteralPath (Join-Path $walk $stage) -Destination (Join-Path $pictures $stages[$stage]) -Force
}

# ---------------------------------------------------------------- The setup window

Write-Host 'Drawing the setup window...'
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'build-exe.ps1') | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Building the programs failed.' }
$setupShots = Join-Path $work 'setup'
$arguments = '"/shots=' + $setupShots + '" /lang=en "/sandbox=' + (Join-Path $work 'box') + '"'
$process = Start-Process -FilePath (Join-Path $root 'bin\WindowsDebloaterSetup.exe') -ArgumentList $arguments -PassThru
if (-not $process.WaitForExit(120000) -or $process.ExitCode -ne 0) { throw 'Drawing the setup window failed; see %TEMP%\WindowsDebloaterSetup.log.' }
Copy-Item -LiteralPath (Join-Path $setupShots 'setup-install.png') -Destination (Join-Path $pictures 'setup.png') -Force
Copy-Item -LiteralPath (Join-Path $setupShots 'setup-done-not-opened.png') -Destination (Join-Path $pictures 'setup-done.png') -Force

# ---------------------------------------------------------------- The banner

Write-Host 'Drawing the banner...'
Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase

function New-Color { param([string]$Hex) return [Windows.Media.ColorConverter]::ConvertFromString($Hex) }
function New-Fill { param([string]$Hex) return (New-Object Windows.Media.SolidColorBrush((New-Color $Hex))) }
function New-Face {
    param([string]$Weight = 'Normal')
    $family = New-Object Windows.Media.FontFamily('Segoe UI Variable Display, Segoe UI')
    return (New-Object Windows.Media.Typeface($family, [Windows.FontStyles]::Normal, [Windows.FontWeights]::$Weight, [Windows.FontStretches]::Normal))
}
function New-Words {
    param([string]$Text, [double]$Size, $Brush, [string]$Weight = 'Normal', [double]$MaxWidth = 0)
    $words = New-Object Windows.Media.FormattedText($Text, [Globalization.CultureInfo]::GetCultureInfo('en-US'),
        [Windows.FlowDirection]::LeftToRight, (New-Face $Weight), $Size, $Brush, [double]1)
    if ($MaxWidth -gt 0) { $words.MaxTextWidth = $MaxWidth }
    return $words
}
function Open-Picture {
    param([string]$Path)
    $stream = [IO.File]::OpenRead($Path)
    try {
        return [Windows.Media.Imaging.BitmapFrame]::Create($stream, [Windows.Media.Imaging.BitmapCreateOptions]::None, [Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
    } finally { $stream.Dispose() }
}

$width = 2560
$height = 1040
$whole = New-Object Windows.Rect(0, 0, $width, $height)
$visual = New-Object Windows.Media.DrawingVisual
[Windows.Media.RenderOptions]::SetBitmapScalingMode($visual, [Windows.Media.BitmapScalingMode]::HighQuality)
$draw = $visual.RenderOpen()

# The ground: the warm ink of the window, with its one light in the top left corner
# and a fainter one, in the pink the icon ends in, low on the left.
$ground = New-Object Windows.Media.LinearGradientBrush((New-Color '#18151A'), (New-Color '#0B0A0C'), [double]90)
$draw.DrawRectangle($ground, $null, $whole)
foreach ($light in @(@(220, -160, 1350, '#3DFF7A59'), @(420, 1220, 1050, '#2AE04A8B'), @(2380, 420, 950, '#12FF7A59'))) {
    $glow = New-Object Windows.Media.RadialGradientBrush
    $glow.MappingMode = [Windows.Media.BrushMappingMode]::Absolute
    $glow.Center = New-Object Windows.Point($light[0], $light[1])
    $glow.GradientOrigin = $glow.Center
    $glow.RadiusX = $light[2]
    $glow.RadiusY = $light[2]
    $glow.GradientStops.Add((New-Object Windows.Media.GradientStop((New-Color $light[3]), 0)))
    $glow.GradientStops.Add((New-Object Windows.Media.GradientStop((New-Color '#00FF7A59'), 1)))
    $draw.DrawRectangle($glow, $null, $whole)
}

# Left: the icon, the name, what it is for, and the three things worth knowing.
$left = 150
$column = 1010
$iconStream = [IO.File]::OpenRead((Join-Path $root 'src\ui\icon.ico'))
try {
    $decoder = New-Object Windows.Media.Imaging.IconBitmapDecoder($iconStream, 'None', 'OnLoad')
    $icon = $decoder.Frames | Sort-Object PixelWidth -Descending | Select-Object -First 1
} finally { $iconStream.Dispose() }
$halo = New-Object Windows.Media.RadialGradientBrush
$halo.MappingMode = [Windows.Media.BrushMappingMode]::Absolute
$halo.Center = New-Object Windows.Point(($left + 88), 238)
$halo.GradientOrigin = $halo.Center
$halo.RadiusX = 250
$halo.RadiusY = 250
$halo.GradientStops.Add((New-Object Windows.Media.GradientStop((New-Color '#59FF7A59'), 0)))
$halo.GradientStops.Add((New-Object Windows.Media.GradientStop((New-Color '#00FF7A59'), 1)))
$draw.DrawRectangle($halo, $null, $whole)
$draw.DrawImage($icon, (New-Object Windows.Rect($left, 150, 176, 176)))

# The name is as large as the column lets it be.
$size = 150
do {
    $size -= 2
    $name = New-Words 'Windows Debloater' $size (New-Fill '#FFFFFF') 'Bold'
} while ($name.Width -gt $column -and $size -gt 60)
$top = 392
$draw.DrawText($name, (New-Object Windows.Point(($left - 4), $top)))
$top += $name.Height - 6

$blend = New-Object Windows.Media.LinearGradientBrush((New-Color '#FF8A66'), (New-Color '#E04A8B'), [double]0)
$blend.MappingMode = [Windows.Media.BrushMappingMode]::Absolute
$blend.StartPoint = New-Object Windows.Point($left, 0)
$blend.EndPoint = New-Object Windows.Point(($left + 470), 0)
$sub = New-Words 'for Windows 11' 62 $blend 'SemiBold'
$draw.DrawText($sub, (New-Object Windows.Point($left, $top)))
$top += $sub.Height + 26

$say = New-Words 'Remove the apps nobody asked for and switch off ads and suggestions.' 40 (New-Fill '#B8B3B0') 'Normal' 880
$say.LineHeight = 56
$draw.DrawText($say, (New-Object Windows.Point($left, $top)))
$top += $say.Height + 44

# A pill in the accent, as the Debloat button is, and two quieter ones beside it.
$at = $left
foreach ($chip in @(@('One button', $true), @('You confirm first', $false), @('Revert puts it back', $false))) {
    $ink = '#F5F3F2'
    if ($chip[1]) { $ink = '#FFFFFF' }
    $label = New-Words $chip[0] 30 (New-Fill $ink) 'SemiBold'
    $box = New-Object Windows.Rect($at, $top, ($label.Width + 52), 62)
    if ($chip[1]) {
        $fill = New-Object Windows.Media.LinearGradientBrush((New-Color '#FF8A66'), (New-Color '#F2643F'), [double]90)
        $draw.DrawRoundedRectangle($fill, (New-Object Windows.Media.Pen((New-Fill '#61FF7A59'), 2)), $box, 16, 16)
    } else {
        $draw.DrawRoundedRectangle((New-Fill '#14FFFFFF'), (New-Object Windows.Media.Pen((New-Fill '#30FFFFFF'), 2)), $box, 16, 16)
    }
    $draw.DrawText($label, (New-Object Windows.Point(($at + 26), ($top + (62 - $label.Height) / 2 - 1))))
    $at += $box.Width + 16
}

# Right: the overview itself, at its real size, shadow and all.
$overview = Open-Picture (Join-Path $pictures 'home.png')
$shownWidth = $overview.PixelWidth / 2
$shownHeight = $overview.PixelHeight / 2
$draw.DrawImage($overview, (New-Object Windows.Rect(($width - $shownWidth - 34), (($height - $shownHeight) / 2), $shownWidth, $shownHeight)))
$draw.Close()

$banner = New-Object Windows.Media.Imaging.RenderTargetBitmap($width, $height, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
$banner.Render($visual)
$encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($banner))
$stream = [IO.File]::Create((Join-Path $docs 'banner.png'))
try { $encoder.Save($stream) } finally { $stream.Dispose() }

Write-Host ''
foreach ($file in @(Get-Item -LiteralPath (Join-Path $docs 'banner.png')) + @(Get-ChildItem -LiteralPath $pictures -File | Sort-Object Name)) {
    Write-Host ('{0,8:N0} KB  {1}' -f ($file.Length / 1KB), $file.FullName.Substring($root.Length + 1))
}
if (-not $Keep) { Remove-Item -LiteralPath $work -Recurse -Force }
