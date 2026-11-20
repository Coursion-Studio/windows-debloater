# Draws the app icon and writes src\ui\icon.ico. The icon is drawn from shapes here, so
# there is no source image to keep in the repository.
#
#   powershell -ExecutionPolicy Bypass -File scripts\build-icon.ps1
#
# -Path writes the icon somewhere else, to look at it before replacing the real one.

param([string]$Path)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase
$root = Split-Path -Parent $PSScriptRoot
$target = Join-Path $root 'src\ui\icon.ico'
if ($Path) { $target = $Path }

# The app's mark: four app tiles, three solid and one only an outline, as if it had
# just been taken out. It sits on Coursion's signature gradient, the same mark the top
# bar of the window shows.
function New-IconPng {
    param([int]$Size)
    $visual = New-Object Windows.Media.DrawingVisual
    $context = $visual.RenderOpen()
    $from = [Windows.Media.ColorConverter]::ConvertFromString('#FF8A66')
    $to = [Windows.Media.ColorConverter]::ConvertFromString('#E04A8B')
    $brush = New-Object Windows.Media.LinearGradientBrush($from, $to, 45.0)
    $radius = $Size * 0.26
    $context.DrawRoundedRectangle($brush, $null, (New-Object Windows.Rect(0, 0, $Size, $Size)), $radius, $radius)

    # The mark is drawn in a box of 20 units; scale it to 58% of the icon and centre it.
    $scale = $Size * 0.58 / 20
    $offset = ($Size - 20 * $scale) / 2
    $transform = New-Object Windows.Media.TransformGroup
    $transform.Children.Add((New-Object Windows.Media.ScaleTransform($scale, $scale)))
    $transform.Children.Add((New-Object Windows.Media.TranslateTransform($offset, $offset)))
    $context.PushTransform($transform)
    $white = [Windows.Media.Brushes]::White
    foreach ($corner in @(@(1, 1), @(1, 11.4), @(11.4, 11.4))) {
        $context.DrawRoundedRectangle($white, $null, (New-Object Windows.Rect($corner[0], $corner[1], 7.6, 7.6)), 2.2, 2.2)
    }
    $outline = New-Object Windows.Media.Pen((New-Object Windows.Media.SolidColorBrush([Windows.Media.Color]::FromArgb(200, 255, 255, 255))), 1.5)
    $context.DrawRoundedRectangle($null, $outline, (New-Object Windows.Rect(12.15, 1.75, 6.1, 6.1)), 1.8, 1.8)
    $context.Pop()
    $context.Close()
    $bitmap = New-Object Windows.Media.Imaging.RenderTargetBitmap($Size, $Size, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($visual)
    $encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream = New-Object IO.MemoryStream
    $encoder.Save($stream)
    return ,$stream.ToArray()
}

$sizes = @(16, 24, 32, 48, 64, 128, 256)
$images = @()
foreach ($size in $sizes) { $images += ,(New-IconPng $size) }

# An .ico file is a small directory followed by the images; PNG images are allowed.
$file = New-Object IO.MemoryStream
$writer = New-Object IO.BinaryWriter($file)
$writer.Write([uint16]0)
$writer.Write([uint16]1)
$writer.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $dimension = $sizes[$i]
    if ($dimension -ge 256) { $dimension = 0 }
    $writer.Write([byte]$dimension)
    $writer.Write([byte]$dimension)
    $writer.Write([byte]0)
    $writer.Write([byte]0)
    $writer.Write([uint16]1)
    $writer.Write([uint16]32)
    $writer.Write([uint32]$images[$i].Length)
    $writer.Write([uint32]$offset)
    $offset += $images[$i].Length
}
foreach ($image in $images) { $writer.Write([byte[]]$image) }
$writer.Flush()
[IO.File]::WriteAllBytes($target, $file.ToArray())
Write-Host ("Wrote {0} ({1:N0} bytes, {2} sizes)" -f $target, (Get-Item -LiteralPath $target).Length, $sizes.Count)
