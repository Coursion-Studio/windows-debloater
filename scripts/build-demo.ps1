# Makes docs\demo.gif, the film at the top of the README.
#
#   powershell -ExecutionPolicy Bypass -File scripts\build-demo.ps1
#
# It opens the real window off screen in demo mode, which changes nothing on the PC,
# presses Debloat the way a person would and films the window while it works. Then
# scripts\demo\Film.cs draws a made-up desktop around those frames and writes the GIF.
# Nothing is recorded from the real screen.
#
#   -Keep             leave the footage in the temporary folder afterwards (about 500 MB)
#   -Reuse            use footage that was kept instead of filming again, and keep it
#   -Stills "1,5,12"  also save single frames of the film at these seconds, to look at
#   -Out <file>       write the GIF somewhere else

param([switch]$Keep, [switch]$Reuse, [string]$Stills, [string]$Out)

$root = Split-Path -Parent $PSScriptRoot
$src = Join-Path $root 'src'
$work = Join-Path $env:TEMP 'WindowsDebloater-demo'
$rawPath = Join-Path $work 'footage.raw'
$notesPath = Join-Path $work 'footage.json'
if (-not $Out) { $Out = Join-Path $root 'docs\demo.gif' }

# The window is filmed at three quarters of its size, which is how large it is in the film.
$filmScale = 0.75

if (-not ($Reuse -and (Test-Path -LiteralPath $rawPath) -and (Test-Path -LiteralPath $notesPath))) {
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
    [void](New-Item -ItemType Directory -Force -Path $work)

    # Even a demo run keeps a log of itself. It goes to the work folder, not into the
    # real history of this PC.
    $savedData = $env:DEBLOATER_DATA
    $env:DEBLOATER_DATA = Join-Path $work 'data'

    Import-Module (Join-Path $src 'Debloater.Engine.psm1') -Force -DisableNameChecking
    Initialize-DebloaterLanguage 'en'
    . (Join-Path $src 'Debloater.UI.ps1')

    $script:Shoot = @{
        Path = $rawPath; Width = [int](1140 * $filmScale); Height = [int](780 * $filmScale); Dpi = 96 * $filmScale
        Times = New-Object System.Collections.ArrayList; Marks = @(); Points = @()
        Stream = $null; Clock = $null; Bitmap = $null; Buffer = $null; Last = -1; Error = ''
        Summary = @(); Count = 0
    }

    # Takes one picture of the window as it is drawn at this moment, no more often than
    # twenty-five times a second, and keeps the window alive while it waits.
    function Save-FilmFrame {
        $shoot = $script:Shoot
        while ($shoot.Clock.Elapsed.TotalSeconds -lt $shoot.Last + 0.04) { Invoke-UiIdle; Start-Sleep -Milliseconds 4 }
        Invoke-UiIdle
        $shoot.Last = $shoot.Clock.Elapsed.TotalSeconds
        $shoot.Bitmap.Clear()
        $shoot.Bitmap.Render($script:Window.Content)
        $shoot.Bitmap.CopyPixels($shoot.Buffer, $shoot.Width * 4, 0)
        $shoot.Stream.Write($shoot.Buffer, 0, $shoot.Buffer.Length)
        [void]$shoot.Times.Add($shoot.Last)
    }

    # Films for a number of seconds, or until something has happened.
    function Start-Filming {
        param([double]$Seconds = 0, [scriptblock]$Until)
        $shoot = $script:Shoot
        $stop = $shoot.Clock.Elapsed.TotalSeconds + $Seconds
        $limit = $shoot.Clock.Elapsed.TotalSeconds + 120
        while ($true) {
            Save-FilmFrame
            if ($script:SelfTestError) { throw $script:SelfTestError }
            $now = $shoot.Clock.Elapsed.TotalSeconds
            if ($Until) {
                if (& $Until) { break }
                if ($now -gt $limit) { throw 'The run did not finish.' }
            } elseif ($now -ge $stop) { break }
        }
    }

    # Notes the moment, and where the middle of a button is in the filmed picture.
    function Add-FilmMark { $script:Shoot.Marks += $script:Shoot.Clock.Elapsed.TotalSeconds }
    function Add-FilmPoint {
        param($Element)
        $middle = New-Object Windows.Point(($Element.ActualWidth / 2), ($Element.ActualHeight / 2))
        $point = $Element.TranslatePoint($middle, $script:Window.Content)
        $script:Shoot.Points += ($point.X * $filmScale), ($point.Y * $filmScale)
    }

    # Shows a button the way it looks under the pointer, or pressed.
    function Set-FilmLook {
        param($Control, [string]$State)
        [void][Windows.VisualStateManager]::GoToState($Control, $State, $true)
    }

    # The pointer comes to rest on a button, presses it, and the button is clicked.
    function Invoke-FilmPress {
        param($Button)
        Add-FilmPoint $Button
        Set-FilmLook $Button 'MouseOver'
        Add-FilmMark
        Start-Filming 0.45
        Set-FilmLook $Button 'Pressed'
        Start-Filming 0.12
        Add-FilmMark
        Invoke-TestClick $Button
        Set-FilmLook $Button 'Normal'
    }

    # The window calls this once it has looked at the PC, where a test would start its
    # walk-through. Here it plays one run from the overview to the finished overview.
    function Invoke-DebloaterSelfTest {
        $shoot = $script:Shoot
        $ui = $script:Ui
        try {
            # It is the real window, so the film should not say "demo" or "dry run" on it.
            # The window shows the tag again whenever it changes page, so it is made
            # invisible instead of being taken away.
            $ui.ModeRow.Opacity = 0
            Wait-MotionSettled
            $shoot.Buffer = New-Object byte[] ($shoot.Width * $shoot.Height * 4)
            $shoot.Bitmap = New-Object Windows.Media.Imaging.RenderTargetBitmap($shoot.Width, $shoot.Height, $shoot.Dpi, $shoot.Dpi, [Windows.Media.PixelFormats]::Pbgra32)
            $shoot.Stream = [IO.File]::Create($shoot.Path)
            $shoot.Clock = [Diagnostics.Stopwatch]::StartNew()

            # The overview arrives: the rows one after another, the number counting up.
            $script:CurrentView = ''
            Show-Page 'home'
            Start-Filming 1.3
            Invoke-FilmPress $ui.BtnDebloat

            # The summary to confirm. Its lines are kept, to show again at the end of the film.
            $ui.ConfirmFine.Text = (T 'confirm.fine.backup') + ' ' + (T 'confirm.fine.admin')
            $shoot.Summary = @($ui.ConfirmRows.ItemsSource | ForEach-Object { [string]$_.Text })
            $shoot.Count = @(Get-SelectedIds).Count
            Start-Filming 1.05
            Invoke-FilmPress $ui.BtnConfirmGo

            # The run, to its end.
            $ui.ProgressIntro.Text = T 'progress.intro'
            Start-Filming -Until { $script:Mode -eq 'result' }
            Add-FilmMark
            Start-Filming 1.0
            Invoke-FilmPress $ui.BtnProgressDone

            # The overview afterwards.
            Start-Filming 2.0
            Add-FilmMark
        } catch {
            $shoot.Error = $_.Exception.Message + ' @ ' + $_.ScriptStackTrace
        } finally {
            if ($shoot.Stream) { $shoot.Stream.Dispose() }
        }
        if ($script:SelfTestError -and -not $shoot.Error) { $shoot.Error = [string]$script:SelfTestError }
        $script:Window.Close()
    }

    Write-Host 'Filming the window...'
    Show-DebloaterWindow -Demo -SelfTestDir $work -Theme dark
    $env:DEBLOATER_DATA = $savedData

    $shoot = $script:Shoot
    if ($shoot.Error) { throw ('Filming failed: ' + $shoot.Error) }
    if ($shoot.Marks.Count -ne 8 -or $shoot.Points.Count -ne 6) { throw 'Filming ended early.' }
    $notes = [pscustomobject]@{
        width = $shoot.Width; height = $shoot.Height
        times = @($shoot.Times); marks = @($shoot.Marks); points = @($shoot.Points)
        summary = @($shoot.Summary); count = [int]$shoot.Count
    }
    [IO.File]::WriteAllText($notesPath, ($notes | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding($false)))
    $seconds = [double]$shoot.Times[$shoot.Times.Count - 1]
    Write-Host ('Filmed {0} frames in {1:N1} s ({2:N1} a second).' -f $shoot.Times.Count, $seconds, ($shoot.Times.Count / $seconds))
}

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase, System.Xaml
if (-not ('Debloater.Demo.Film' -as [type])) {
    Add-Type -TypeDefinition (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'demo\Film.cs') -Raw -Encoding UTF8) `
        -ReferencedAssemblies PresentationCore, PresentationFramework, WindowsBase, System.Xaml, System.Core
}

$notes = Get-Content -LiteralPath $notesPath -Raw | ConvertFrom-Json
$footage = New-Object Debloater.Demo.Footage($rawPath, [int]$notes.width, [int]$notes.height, [double[]]@($notes.times))
try {
    $film = New-Object Debloater.Demo.Film($footage, [int]$notes.width, [int]$notes.height, [double[]]@($notes.marks), [double[]]@($notes.points))
    $film.Summary = [string[]]@($notes.summary)
    $film.Total = ('{0} changes. Revert puts them back.' -f $notes.count)
    Write-Host ('The film is {0:N1} s long, {1} frames.' -f $film.Duration, $film.FrameCount)
    foreach ($entry in @($Stills -split ',')) {
        if (-not $entry.Trim()) { continue }
        $second = [double]::Parse($entry.Trim(), [Globalization.CultureInfo]::InvariantCulture)
        $still = Join-Path $work ('still-{0:000.0}.png' -f $second)
        $film.SaveStill($second, $still)
        Write-Host "Saved $still"
    }
    Write-Host 'Drawing the film...'
    $film.Save($Out)
} finally {
    $footage.Dispose()
}
Write-Host ('Wrote {0} ({1:N0} KB)' -f $Out, ((Get-Item -LiteralPath $Out).Length / 1KB))
if (-not $Keep -and -not $Reuse) { Remove-Item -LiteralPath $work -Recurse -Force }
