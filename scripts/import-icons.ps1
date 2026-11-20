# Takes the page pictures from design\icons, crops each one to a centred square,
# shrinks it to 256 pixels and writes it to src\ui\icons, where the app picks it up.
# A page without a picture shows a plain box with a glyph instead.
#
#   powershell -ExecutionPolicy Bypass -File scripts\import-icons.ps1
#
# Expected file names: overview, apps, ads, edge, look, onedrive, history, settings.
# Use .png or .jpg files; Windows cannot read .webp without an extra codec.

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationCore, WindowsBase
$root = Split-Path -Parent $PSScriptRoot
$source = Join-Path $root 'design\icons'
$target = Join-Path $root 'src\ui\icons'
$names = @('overview', 'apps', 'ads', 'edge', 'look', 'onedrive', 'history', 'settings')
$size = 256

if (-not (Test-Path -LiteralPath $source)) {
    Write-Host "Nothing to import: $source does not exist."
    exit 0
}
[void](New-Item -ItemType Directory -Force -Path $target)

$imported = 0
foreach ($name in $names) {
    $file = $null
    foreach ($extension in '.png', '.jpg', '.jpeg') {
        $candidate = Join-Path $source ($name + $extension)
        if (Test-Path -LiteralPath $candidate) { $file = $candidate; break }
    }
    if (-not $file) { Write-Host ("missing   {0}" -f $name); continue }

    $bitmap = New-Object Windows.Media.Imaging.BitmapImage
    $bitmap.BeginInit()
    $bitmap.CacheOption = [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bitmap.UriSource = New-Object Uri($file)
    $bitmap.EndInit()

    # Centre crop to a square, then scale down.
    $side = [Math]::Min($bitmap.PixelWidth, $bitmap.PixelHeight)
    $x = [int](($bitmap.PixelWidth - $side) / 2)
    $y = [int](($bitmap.PixelHeight - $side) / 2)
    $cropped = New-Object Windows.Media.Imaging.CroppedBitmap($bitmap, (New-Object Windows.Int32Rect($x, $y, $side, $side)))
    $scale = $size / $side
    $scaled = New-Object Windows.Media.Imaging.TransformedBitmap($cropped, (New-Object Windows.Media.ScaleTransform($scale, $scale)))

    $encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($scaled))
    $stream = [IO.File]::Create((Join-Path $target ($name + '.png')))
    try { $encoder.Save($stream) } finally { $stream.Dispose() }
    Write-Host ("imported  {0}  ({1} x {2} -> {3} x {3})" -f $name, $bitmap.PixelWidth, $bitmap.PixelHeight, $size)
    $imported++
}
Write-Host ("{0} of {1} icons imported into {2}" -f $imported, $names.Count, $target)
