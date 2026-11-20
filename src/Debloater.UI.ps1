# Debloater.UI.ps1
# The window. Dot-sourced by Debloater.ps1 after the engine module is loaded.
#
# The layout and every visual style live in ui\MainWindow.xaml, the things the screen
# shows are the small classes in ui\ViewModels.cs, and this file holds the behaviour.
# The window never changes the PC itself: it writes a plan and starts hidden worker
# processes (Invoke-DebloaterWorker in the engine), then shows their progress.
#
# How it is used: there is no sidebar. The overview lists the areas next to a panel
# with the one Debloat button, and History and Settings are two buttons in the top bar.
# The recommended changes are ticked when the window opens. Areas are for changing what
# is ticked. Debloat always applies everything ticked in every area, after one
# confirmation. While it runs, each area is a lane that fills up; afterwards the overview
# says what was done, until there is something to do again.
#
# How it looks follows the Coursion house style: warm ink, hairlines, and one accent
# that is kept for what can be pressed and what is selected. An area is told apart by
# its icon and its name, so nothing here gives an area a colour of its own.

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml
if (-not ('Debloater.Ui.ItemVm' -as [type])) {
    Add-Type -TypeDefinition (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'ui\ViewModels.cs') -Raw)
}
if (-not ('Debloater.Ui.Glide' -as [type])) {
    Add-Type -TypeDefinition (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'ui\Motion.cs') -Raw) `
        -ReferencedAssemblies PresentationFramework, PresentationCore, WindowsBase, System.Xaml
}

# The overview, the areas in the order they are listed, then History and Settings.
# File names the page's picture in ui\icons; the glyph stands in when it is missing.
$script:Pages = @(
    @{ Id = 'home';     Glyph = 0xEA99; Groups = @(); File = 'overview' },
    @{ Id = 'apps';     Glyph = 0xE71D; Groups = @('remove', 'optional', 'gaming'); File = 'apps' },
    @{ Id = 'ads';      Glyph = 0xE789; Groups = @('promoted', 'start', 'tips', 'privacy'); File = 'ads' },
    @{ Id = 'edge';     Glyph = 0xE774; Groups = @('edge', 'widgets'); File = 'edge' },
    @{ Id = 'look';     Glyph = 0xE771; Groups = @('lock', 'desktop'); File = 'look' },
    @{ Id = 'onedrive'; Glyph = 0xE753; Groups = @('onedrive'); File = 'onedrive' },
    @{ Id = 'history';  Glyph = 0xE81C; Groups = @(); File = 'history' },
    @{ Id = 'settings'; Glyph = 0xE713; Groups = @(); File = 'settings' }
)
$script:CategoryIds = @('apps', 'ads', 'edge', 'look', 'onedrive')
$script:ViewNames = @('ViewLoading', 'ViewHome', 'ViewList', 'ViewProgress', 'ViewResult', 'ViewHistory', 'ViewSettings')
$script:RepoUrl = 'https://github.com/Coursion-Studio/windows-debloater'

# The two themes. The values are Coursion's tokens: warm ink with a coral accent, and
# the same on warm paper. Text, lines and fills are all taken from the theme, so
# nothing is left white on white when it changes.
#   Window, BaseTop   the base of the window, a shade lighter at the top
#   CornerLight       the faint wash of the accent in the top left corner
#   RimHead           the bright end of the light that travels round the Debloat button
#   Brushes           every plain colour the layout asks for, by resource name
$script:Palettes = @{
    dark  = @{
        Window = '#0E0C10'; BaseTop = '#161418'; CornerLight = '#21FF7A59'; RimHead = '#FFFFFF'
        Brushes = @{
            Text = '#F5F3F2'; Text2 = '#B8B3B0'; Text3 = '#94FFFFFF'; Text4 = '#6BFFFFFF'
            Accent = '#FF7A59'; OnAccent = '#FFFFFF'; AccentText = '#FFB199'; Wash = '#21FF7A59'; Line = '#61FF7A59'
            Edge = '#24FFFFFF'; RuleFill = '#14FFFFFF'; CardFill = '#08FFFFFF'; ChipFill = '#12FFFFFF'; Chip2 = '#1FFFFFFF'
            Well = '#47000000'; Sheet = '#1B181D'; Dim = '#B8060507'
            SuccessFg = '#2ECC71'; SuccessBg = '#292ECC71'; SuccessLine = '#732ECC71'
            CautionFg = '#F5B041'; CautionBg = '#26F39C12'; CautionLine = '#66F39C12'
            DangerFg = '#F26B5C'; DangerBg = '#26E74C3C'; DangerLine = '#66E74C3C'
            BoxBorder = '#66FFFFFF'; ScrollThumb = '#2EFFFFFF'
        }
    }
    light = @{
        Window = '#F3EFEB'; BaseTop = '#FBF9F7'; CornerLight = '#2EFF7A59'; RimHead = '#FF4F1F'
        Brushes = @{
            Text = '#1B1719'; Text2 = '#5C5557'; Text3 = '#941B1719'; Text4 = '#701B1719'
            Accent = '#EB5A33'; OnAccent = '#FFFFFF'; AccentText = '#B93C17'; Wash = '#1FEB5A33'; Line = '#70EB5A33'
            Edge = '#291B1719'; RuleFill = '#171B1719'; CardFill = '#B3FFFFFF'; ChipFill = '#0F1B1719'; Chip2 = '#1C1B1719'
            Well = '#0D1B1719'; Sheet = '#FBF9F7'; Dim = '#851B1719'
            SuccessFg = '#1B8748'; SuccessBg = '#242ECC71'; SuccessLine = '#802ECC71'
            CautionFg = '#96590A'; CautionBg = '#2EF39C12'; CautionLine = '#80F39C12'
            DangerFg = '#B93226'; DangerBg = '#21E74C3C'; DangerLine = '#73E74C3C'
            BoxBorder = '#731B1719'; ScrollThumb = '#3D1B1719'
        }
    }
}
# The accent as a fill, lit from above, and Coursion's signature gradient for the app's mark.
$script:AccentFill = @('#FF8A66', '#F2643F')
$script:BrandFill = @('#FF8A66', '#E04A8B')

$script:Ui = @{}
$script:BrushConverter = New-Object Windows.Media.BrushConverter
$script:IconCache = @{}

# ================================================================ Small helpers

function Brush {
    param([string]$Color)
    $brush = $script:BrushConverter.ConvertFromString($Color)
    $brush.Freeze()
    return $brush
}

function ConvertTo-Color { param([string]$Hex) return [Windows.Media.ColorConverter]::ConvertFromString($Hex) }

# The same colour with an alpha value from 0 to 255, as "#AARRGGBB".
function Get-AlphaColor {
    param([string]$Hex, [int]$Alpha)
    $c = ConvertTo-Color $Hex
    return ('#{0:X2}{1:X2}{2:X2}{3:X2}' -f $Alpha, $c.R, $c.G, $c.B)
}

# Fills a brush with colour stops: spread evenly, or at the offsets given.
function Add-GradientStops {
    param($Brush, [string[]]$Colors, [double[]]$Offsets)
    for ($i = 0; $i -lt $Colors.Count; $i++) {
        $offset = [double]0
        if ($Offsets) { $offset = $Offsets[$i] }
        elseif ($Colors.Count -gt 1) { $offset = $i / ($Colors.Count - 1) }
        $Brush.GradientStops.Add((New-Object Windows.Media.GradientStop((ConvertTo-Color $Colors[$i]), $offset)))
    }
}

# A gradient along a line; the points are fractions of whatever it fills.
function New-Gradient {
    param([string[]]$Colors, [double]$X1 = 0, [double]$Y1 = 0, [double]$X2 = 1, [double]$Y2 = 1, [double[]]$Offsets)
    $brush = New-Object Windows.Media.LinearGradientBrush
    $brush.StartPoint = New-Object Windows.Point($X1, $Y1)
    $brush.EndPoint = New-Object Windows.Point($X2, $Y2)
    Add-GradientStops $brush $Colors $Offsets
    $brush.Freeze()
    return $brush
}

# A gradient that spreads out from the middle of whatever it fills.
function New-Radial {
    param([string[]]$Colors, [double[]]$Offsets)
    $brush = New-Object Windows.Media.RadialGradientBrush
    Add-GradientStops $brush $Colors $Offsets
    $brush.Freeze()
    return $brush
}

# The one light in the window: a faint wash of the accent that falls in from above the
# top left corner of the content. It is measured in the layout's own units, so it keeps
# its size however wide the window is; $Left is where the content starts, which is
# well inside a very wide window.
function New-CornerLight {
    param([string]$Color, [double]$Left = 0)
    $brush = New-Object Windows.Media.RadialGradientBrush
    $brush.MappingMode = [Windows.Media.BrushMappingMode]::Absolute
    $brush.Center = New-Object Windows.Point(($Left + 46), -47)
    $brush.GradientOrigin = $brush.Center
    $brush.RadiusX = 520
    $brush.RadiusY = 520
    Add-GradientStops $brush @($Color, (Get-AlphaColor $Color 0))
    $brush.Freeze()
    return $brush
}

# Values that come back from a PowerShell function carry a wrapper. A resource
# dictionary would store the wrapper itself, so hand it the bare object.
function Set-Resource {
    param([string]$Key, $Value)
    $script:Window.Resources[$Key] = $Value.PSObject.BaseObject
}

function Glyph { param([int]$Code) return [string][char]$Code }

function New-Collection { return ,(New-Object 'System.Collections.ObjectModel.ObservableCollection[object]') }

# Section labels are set in capitals, in the monospaced face. The language decides how
# a letter is capitalised: Turkish has a dotted capital I.
function Format-Caps {
    param([string]$Text)
    if (-not $Text) { return '' }
    $culture = [Globalization.CultureInfo]::InvariantCulture
    try { $culture = [Globalization.CultureInfo]::GetCultureInfo((Get-DebloaterLanguage)) } catch {}
    return $Text.ToUpper($culture)
}

function Get-Page { param([string]$Id) return ($script:Pages | Where-Object { $_.Id -eq $Id } | Select-Object -First 1) }

# A picture for an area, if one has been supplied in ui\icons. Without one the area
# shows a plain box with a glyph.
function Get-AreaIcon {
    param([string]$PageId)
    if ($script:IconCache.ContainsKey($PageId)) { return $script:IconCache[$PageId] }
    $image = $null
    $file = Join-Path $PSScriptRoot ('ui\icons\' + (Get-Page $PageId).File + '.png')
    if (Test-Path -LiteralPath $file) {
        try {
            $bitmap = New-Object Windows.Media.Imaging.BitmapImage
            $bitmap.BeginInit()
            $bitmap.CacheOption = [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $bitmap.DecodePixelWidth = 256
            $bitmap.UriSource = New-Object Uri($file)
            $bitmap.EndInit()
            $bitmap.Freeze()
            $image = $bitmap
        } catch {}
    }
    $script:IconCache[$PageId] = $image
    return $image
}

function Set-Button {
    param($Button, [string]$Text, [bool]$Enabled, [bool]$Visible)
    $Button.Content = $Text
    $Button.IsEnabled = $Enabled
    if ($Visible) { $Button.Visibility = 'Visible' } else { $Button.Visibility = 'Collapsed' }
}

function Invoke-Guarded {
    param([scriptblock]$Action)
    try { & $Action } catch { Show-DebloaterError $_ }
}

function Show-DebloaterError {
    param($ErrorRecord)
    $text = $ErrorRecord.Exception.Message + "`n`n" + $ErrorRecord.ScriptStackTrace
    try {
        $root = Get-DebloaterDataRoot
        [void](New-Item -ItemType Directory -Force -Path $root)
        Add-Content -LiteralPath (Join-Path $root 'error.log') -Value ((Get-Date).ToString('s') + ' ' + $text) -Encoding UTF8
    } catch {}
    if ($script:SelfTestDir) { $script:SelfTestError = $text; return }
    [void][Windows.MessageBox]::Show($script:Window, $text, (T 'error.title'), 'OK', 'Error')
}

# Something went wrong inside the window's own machinery rather than in a handler of
# ours: a storyboard that cannot find its target, for example. It is written to the
# log and shown once; without this the window could stop drawing with no word of why.
function Register-DebloaterFault {
    param($Exception)
    $text = [string]$Exception
    try {
        $root = Get-DebloaterDataRoot
        [void](New-Item -ItemType Directory -Force -Path $root)
        Add-Content -LiteralPath (Join-Path $root 'error.log') -Value ((Get-Date).ToString('s') + ' ' + $text) -Encoding UTF8
    } catch {}
    if ($script:SelfTestDir) {
        if (-not $script:SelfTestError) { $script:SelfTestError = $text }
        return
    }
    if ($script:FaultShown) { return }
    $script:FaultShown = $true
    [void][Windows.MessageBox]::Show($script:Window, $Exception.Message, (T 'error.title'), 'OK', 'Error')
}

function Invoke-UiIdle {
    $script:Window.Dispatcher.Invoke([Action] {}, [Windows.Threading.DispatcherPriority]::ContextIdle)
}

# Brings one view to the front. A view that was not showing arrives with a short rise.
function Show-View {
    param([string]$Name)
    $arriving = ($script:CurrentView -ne $Name)
    foreach ($view in $script:ViewNames) {
        if ($view -eq $Name) { $script:Ui[$view].Visibility = 'Visible' } else { $script:Ui[$view].Visibility = 'Collapsed' }
    }
    $script:CurrentView = $Name
    if ($arriving -and $Name -ne 'ViewLoading') { Start-Entrance $script:Ui[$Name] 0 280 10 }
    # Room for what the layout starts by itself when a page appears, such as ticks drawing in.
    Register-Motion 500
}

function Open-Path {
    param([string]$Path)
    if ($Path -and (Test-Path -LiteralPath $Path)) { Start-Process -FilePath 'explorer.exe' -ArgumentList ('"' + $Path + '"') }
}

# The licence that came with the tool, in Notepad; the copy on the project page when
# this one is missing.
function Open-Licence {
    $file = Get-DebloaterLicencePath
    if (Test-Path -LiteralPath $file) { Start-Process -FilePath 'notepad.exe' -ArgumentList ('"' + $file + '"') }
    else { Start-Process ($script:RepoUrl + '/blob/main/LICENSE.md') }
}
function Open-ChangesList {
    $file = Join-Path (Split-Path -Parent $PSScriptRoot) 'docs\changes.md'
    if (Test-Path -LiteralPath $file) { Start-Process -FilePath 'notepad.exe' -ArgumentList ('"' + $file + '"') }
    else { Start-Process ($script:RepoUrl + '/blob/main/docs/changes.md') }
}

# ================================================================ Motion
#
# Movement that is started from code goes through these helpers, so it can be switched
# off in one place ($script:Motion): Windows has a setting for people who do not want
# animations, and a PC that draws without a graphics card is too slow for them.
# Hover and press effects live in the layout file as visual states.

function New-Ease {
    param([string]$Kind)
    if ($Kind -eq 'back') { $ease = New-Object Windows.Media.Animation.BackEase; $ease.Amplitude = 0.45 }
    elseif ($Kind -eq 'quint') { $ease = New-Object Windows.Media.Animation.QuinticEase }
    else { $ease = New-Object Windows.Media.Animation.CubicEase }
    $ease.EasingMode = 'EaseOut'
    return $ease
}

# Remembers until when something is moving, so a screenshot can wait for it to settle.
function Register-Motion {
    param([double]$Milliseconds)
    $until = [DateTime]::UtcNow.AddMilliseconds($Milliseconds)
    if ($until -gt $script:MotionUntil) { $script:MotionUntil = $until }
}

# Moves one number of an element (opacity, an offset, a bar's value) to $To.
#   -From    start there instead of where it is now
#   -Delay   wait first, holding the start value
#   -Keep    $To is a new resting value: the property is set to it as well, so nothing
#            depends on the animation once it has finished
#   -Then    something to do when it has arrived
# Without -Keep the property returns to its own value at the end, which is what an
# entrance wants: it ends where the element belongs anyway.
function Start-Motion {
    param($Target, $Property, [double]$To, [double]$Milliseconds, $From = $null, [double]$Delay = 0, [string]$Ease = 'cubic', [switch]$Keep, [scriptblock]$Then)
    if (-not $Target) { return }
    if ($Keep -and $null -eq $From) { $From = [double]$Target.GetValue($Property) }
    if ($Keep) { $Target.SetValue($Property, $To) }
    if (-not $script:Motion) {
        $Target.BeginAnimation($Property, $null)
        if ($Then) { & $Then }
        return
    }

    $animation = New-Object Windows.Media.Animation.DoubleAnimationUsingKeyFrames
    $animation.FillBehavior = [Windows.Media.Animation.FillBehavior]::Stop
    if ($Then) { $animation.add_Completed($Then) }
    if ($null -ne $From) {
        $first = New-Object Windows.Media.Animation.DiscreteDoubleKeyFrame
        $first.Value = [double]$From
        $first.KeyTime = [Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::Zero)
        [void]$animation.KeyFrames.Add($first)
        if ($Delay -gt 0) {
            $hold = New-Object Windows.Media.Animation.DiscreteDoubleKeyFrame
            $hold.Value = [double]$From
            $hold.KeyTime = [Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromMilliseconds($Delay))
            [void]$animation.KeyFrames.Add($hold)
        }
    }
    $last = New-Object Windows.Media.Animation.EasingDoubleKeyFrame
    $last.Value = $To
    $last.KeyTime = [Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromMilliseconds($Delay + $Milliseconds))
    $last.EasingFunction = New-Ease $Ease
    [void]$animation.KeyFrames.Add($last)
    $Target.BeginAnimation($Property, $animation)
    Register-Motion ($Delay + $Milliseconds)
}

# An element's own offset, created the first time it is needed.
function Get-Offset {
    param($Element)
    $transform = $Element.RenderTransform
    if ($transform -isnot [Windows.Media.TranslateTransform] -or $transform.IsFrozen) {
        $transform = New-Object Windows.Media.TranslateTransform
        $Element.RenderTransform = $transform
    }
    return $transform
}

# An element's own scale, likewise. One that came out of a template is shared and
# cannot be animated directly, so it is replaced by a private one.
function Get-Scale {
    param($Element)
    $transform = $Element.RenderTransform
    if ($transform -isnot [Windows.Media.ScaleTransform] -or $transform.IsFrozen) {
        $transform = New-Object Windows.Media.ScaleTransform
        $Element.RenderTransform = $transform
    }
    return $transform
}

# A quick swell and back, to show that a number has just changed.
function Start-Bump {
    param($Element, [double]$From = 1.16)
    if (-not $Element -or -not $script:Motion) { return }
    $scale = Get-Scale $Element
    Start-Motion $scale ([Windows.Media.ScaleTransform]::ScaleXProperty) 1 300 -From $From -Ease 'back'
    Start-Motion $scale ([Windows.Media.ScaleTransform]::ScaleYProperty) 1 300 -From $From -Ease 'back'
}

# Something arrives: it fades in while rising a few pixels into its place.
function Start-Entrance {
    param($Element, [double]$Delay = 0, [double]$Milliseconds = 300, [double]$Rise = 14)
    if (-not $Element) { return }
    Start-Motion $Element ([Windows.UIElement]::OpacityProperty) 1 ($Milliseconds * 0.75) -From 0 -Delay $Delay
    if ($Rise -ne 0) {
        Start-Motion (Get-Offset $Element) ([Windows.Media.TranslateTransform]::YProperty) 0 $Milliseconds -From $Rise -Delay $Delay -Ease 'quint'
    }
}

# The items of a list arrive one after the other.
function Start-Cascade {
    param($ItemsControl, [double]$Delay = 0, [double]$Step = 45, [int]$Limit = 12, [double]$Rise = 16)
    if (-not $script:Motion -or -not $ItemsControl) { return }
    $ItemsControl.UpdateLayout()
    $count = [Math]::Min($Limit, $ItemsControl.Items.Count)
    for ($i = 0; $i -lt $count; $i++) {
        $container = $ItemsControl.ItemContainerGenerator.ContainerFromIndex($i)
        if ($container) { Start-Entrance $container ($Delay + $i * $Step) 340 $Rise }
    }
}

# Waits, with the window alive, until everything started above has come to rest.
function Wait-MotionSettled {
    while ([DateTime]::UtcNow -lt $script:MotionUntil.AddMilliseconds(60)) {
        Invoke-UiIdle
        Start-Sleep -Milliseconds 20
    }
    Invoke-UiIdle
}

# ================================================================ Theme

function Get-SystemTheme {
    $light = 1
    try { $light = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name AppsUseLightTheme -ErrorAction Stop).AppsUseLightTheme } catch {}
    if ($light -eq 0) { return 'dark' }
    return 'light'
}

function Set-UiTheme {
    param([string]$Theme)
    $script:Theme = $Theme
    $effective = $Theme
    if ($Theme -eq 'system') { $effective = Get-SystemTheme }
    $script:EffectiveTheme = $effective

    $palette = $script:Palettes[$effective]
    foreach ($key in $palette.Brushes.Keys) { Set-Resource $key (Brush $palette.Brushes[$key]) }
    $accent = $palette.Brushes.Accent
    Set-Resource 'BaseFill' (New-Gradient @($palette.BaseTop, $palette.Window) 0 0 0 1)
    Set-Resource 'CornerLight' (New-CornerLight $palette.CornerLight $script:LightLeft)
    Set-Resource 'AccentFill' (New-Gradient $script:AccentFill 0 0 0 1)
    Set-Resource 'Brand' (New-Gradient $script:BrandFill 0 0 1 1)
    # Around the Debloat button: the light that breathes behind it, and the band that
    # travels along its rim, faint at its tail and brightest just behind its head.
    Set-Resource 'AuraBrush' (New-Radial @((Get-AlphaColor $accent 205), (Get-AlphaColor $accent 82), (Get-AlphaColor $accent 0)) @(0, 0.58, 1))
    Set-Resource 'RimBrush' (New-Gradient @((Get-AlphaColor $accent 0), $accent, $palette.RimHead, $accent) 0 0 0 1 @(0, 0.5, 0.86, 1))
    $script:Window.Background = Brush $palette.Window
    Set-WindowLook
}

# A bigger window shows the same layout larger instead of stretching it thin: the
# design is for 1140 by 780, and everything grows with the window up to 1.6 times.
function Update-Zoom {
    $window = $script:Window
    $zoom = [Math]::Min([double]$window.ActualWidth / 1140, [double]$window.ActualHeight / 780)
    $zoom = [Math]::Max([double]1, [Math]::Min([double]1.6, $zoom))
    # In steps, so dragging the edge does not lay everything out anew for every pixel.
    $zoom = [Math]::Round($zoom * 40) / 40
    if ($zoom -ne $script:Zoom) {
        $script:Zoom = $zoom
        if ($zoom -eq 1) { $script:Ui.Root.LayoutTransform = $null }
        else { $script:Ui.Root.LayoutTransform = New-Object Windows.Media.ScaleTransform($zoom, $zoom) }
    }
    # The top bar keeps clear of the window's own three buttons. When the window is much
    # wider than the column of content, the column's edge is already clear of them.
    $width = [double]$window.ActualWidth / $zoom
    $side = [Math]::Max([double]0, ($width - 1480) / 2)
    $script:Ui.TopBar.Margin = New-Object Windows.Thickness(34, 8, [Math]::Max([double]34, 150 - $side), 0)
    # The light stays above the corner of the content, wherever that is.
    $left = [Math]::Round($side)
    if ($left -ne $script:LightLeft) {
        $script:LightLeft = $left
        Set-Resource 'CornerLight' (New-CornerLight $script:Palettes[$script:EffectiveTheme].CornerLight $left)
    }
}

# Rounded corners, and a frame to match the theme, where Windows offers them.
function Set-WindowLook {
    try {
        $handle = (New-Object Windows.Interop.WindowInteropHelper($script:Window)).Handle
        if ($handle -ne [IntPtr]::Zero) { [Debloater.Ui.Win32]::SetWindowLook($handle, ($script:EffectiveTheme -eq 'dark')) }
    } catch {}
}

# ================================================================ State and selection

# Takes a fresh look at the PC, with the window waiting. Start-StateScan is the one to
# use where the window is busy showing something.
function Update-State {
    Set-State (Get-DebloaterState -Catalog $script:Catalog -Demo:$script:Demo)
}

# Looks at the PC on another thread and hands over to $Then, on the window's own
# thread, when the answer is in. The scan takes a noticeable moment on a slow disk, and
# while it ran in place nothing in the window could move. If the other thread cannot
# be set up, or reports a problem, the scan is done in place after all.
function Start-StateScan {
    param([scriptblock]$Then)
    # A demo pretends, so there is nothing to look at.
    if ($script:Demo) { Update-State; & $Then; return }
    $shell = $null
    try {
        $shell = [powershell]::Create()
        [void]$shell.AddScript({
            param($ModulePath)
            Import-Module $ModulePath -Force
            $state = Get-DebloaterState -Catalog @(Get-DebloaterCatalog)
            $result = @{}
            foreach ($key in @($state.Keys)) { $result[[string]$key] = [string]$state[$key].State }
            $result
        }.ToString()).AddArgument((Join-Path $PSScriptRoot 'Debloater.Engine.psm1'))
        $handle = $shell.BeginInvoke()
    } catch {
        if ($shell) { $shell.Dispose() }
        Update-State
        & $Then
        return
    }
    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(40)
    $script:ScanJob = @{ Shell = $shell; Handle = $handle; Timer = $timer; Then = $Then }
    $timer.Add_Tick({
        Invoke-Guarded {
            $job = $script:ScanJob
            if (-not $job -or -not $job.Handle.IsCompleted) { return }
            $job.Timer.Stop()
            $script:ScanJob = $null
            $result = $null
            $failed = $false
            try { $result = @($job.Shell.EndInvoke($job.Handle))[0] } catch { $failed = $true }
            if ($job.Shell.HadErrors -or $result -isnot [hashtable]) { $failed = $true }
            $job.Shell.Dispose()
            if ($failed) {
                Update-State
            } else {
                $state = @{}
                foreach ($key in @($result.Keys)) { $state[$key] = [pscustomobject]@{ State = [string]$result[$key] } }
                Set-State $state
            }
            & $job.Then
        }
    })
    $timer.Start()
}

# Takes over a table of item id -> state as the current picture of the PC.
function Set-State {
    param($State)
    $script:State = $State
    foreach ($item in $script:Catalog) {
        if (-not $script:State.ContainsKey($item.Id)) { $script:State[$item.Id] = [pscustomobject]@{ State = 'absent' } }
    }
    if ($script:Demo) {
        # A demo changes nothing, so it remembers what it pretended to do: a removed
        # app is gone and an applied setting counts as done.
        foreach ($id in @($script:DemoDone.Keys)) {
            $item = $script:ById[$id]
            if (-not $item) { continue }
            $value = 'done'
            if (@($item.Packages).Count -gt 0) { $value = 'absent' }
            $script:State[$id] = [pscustomobject]@{ State = $value }
        }
    }
    foreach ($id in @($script:Selected.Keys)) {
        if (-not $script:State.ContainsKey($id) -or $script:State[$id].State -ne 'todo') { $script:Selected.Remove($id) }
    }
}

# A text with a number in it. Uses the "<key>.one" wording for exactly one.
function TN {
    param([string]$Key, [int]$Number)
    if ($Number -eq 1) { return (T ($Key + '.one')) }
    return (T $Key $Number)
}

# What earlier runs did on this PC: every item any of them got done ($script:AppliedIds),
# and the most recent run that has not been put back ($script:LastApplied). The first is
# how the overview knows which apps this tool removed, since an app that is gone looks
# the same as one that was never there. A demo keeps its own made-up record instead.
function Update-RunRecord {
    $script:AppliedIds = @{}
    if ($script:Demo) {
        foreach ($id in @($script:DemoDone.Keys)) { $script:AppliedIds[$id] = $true }
        return
    }
    $script:LastApplied = $null
    foreach ($run in @(Get-DebloaterRuns)) {
        if ($run.DryRun -or @($run.Done).Count -eq 0) { continue }
        foreach ($id in @($run.Done)) { $script:AppliedIds[[string]$id] = $true }
        if ($script:LastApplied -or $run.Undone) { continue }
        $when = $null
        try { $when = [datetime]::ParseExact($run.Created, 'yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture) } catch {}
        $script:LastApplied = @{ When = $when; Done = @($run.Done); Dir = $run.Dir; Undoable = ($run.UndoableUser + $run.UndoableAdmin); Session = $false }
    }
}

# True once nothing recommended is left: the overview then shows results, not a to-do list.
function Test-HomeFinished {
    return (@(Get-TodoItems | Where-Object { $_.Recommended }).Count -eq 0)
}

function Get-TodoItems {
    param([string]$PageId)
    return @($script:Catalog | Where-Object {
        $script:State[$_.Id].State -eq 'todo' -and (-not $PageId -or $_.Page -eq $PageId) })
}

function Get-SelectedIds {
    return @($script:Catalog |
        Where-Object { $script:Selected[$_.Id] -and $script:State[$_.Id].State -eq 'todo' } |
        ForEach-Object { $_.Id })
}

# Ticks or unticks items from code and refreshes whatever is on screen.
function Set-ItemsSelected {
    param($Items, [bool]$Value)
    foreach ($item in @($Items)) {
        if ($script:State[$item.Id].State -ne 'todo') { continue }
        if ($Value) { $script:Selected[$item.Id] = $true } else { $script:Selected.Remove($item.Id) }
        $vm = $script:PageVms[$item.Id]
        if ($vm) { $vm.SetSelectedQuietly($Value) }
    }
    Update-Chrome
    Update-Bars
}

# The starting point: every recommended change ticked, nothing optional.
function Reset-ToRecommended {
    $script:Selected = @{}
    foreach ($item in Get-TodoItems) {
        if ($item.Recommended) { $script:Selected[$item.Id] = $true }
        $vm = $script:PageVms[$item.Id]
        if ($vm) { $vm.SetSelectedQuietly([bool]$item.Recommended) }
    }
    Update-Chrome
    Update-Bars
}

function New-ItemVm {
    param($Item)
    $vm = New-Object Debloater.Ui.ItemVm
    $vm.Id = $Item.Id
    $vm.Title = Get-DebloaterItemTitle $Item
    $vm.Description = Get-DebloaterItemDescription $Item
    $vm.Details = Get-DebloaterItemDetails $Item
    $vm.NeedsAdmin = [bool](Test-DebloaterItemNeedsAdmin $Item)
    $vm.Recommended = [bool]$Item.Recommended
    $vm.AdminText = T 'badge.admin'
    $vm.RecommendedText = T 'badge.recommended'
    $vm.DetailsLabel = T 'item.details'
    $vm.StateText = T 'state.done'
    $vm.SetSelectedQuietly([bool]$script:Selected[$Item.Id])
    return $vm
}

# ================================================================ Top bar
#
# There is no sidebar. The rows on the overview lead to the areas, and the top bar
# holds the two pages that are not areas: History and Settings.

# One small object per page, holding its icon and its name for whatever shows them:
# the top bar buttons and the heading of each page.
function Build-Nav {
    $script:NavItems = New-Collection
    $script:NavById = @{}
    foreach ($page in $script:Pages) {
        $entry = New-Object Debloater.Ui.NavVm
        $entry.Id = $page.Id
        Set-AreaIcon $entry $page
        $script:NavItems.Add($entry)
        $script:NavById[$page.Id] = $entry
    }
    $script:Ui.BtnHistory.Content = $script:NavById['history'].PSObject.BaseObject
    $script:Ui.BtnSettings.Content = $script:NavById['settings'].PSObject.BaseObject
    # The Revert button of the finished overview is drawn the same way: a glyph and a word.
    $script:RevertLabel = New-Object Debloater.Ui.NavVm
    $script:RevertLabel.Glyph = Glyph 0xE7A7
    $script:Ui.BtnHomeUndo.Content = $script:RevertLabel.PSObject.BaseObject
}

# Texts that are not part of a single view: page names, the app's name, the mode tag.
function Update-Chrome {
    $ui = $script:Ui
    foreach ($entry in $script:NavItems) { $entry.Title = T ('nav.' + $entry.Id) }
    if ($script:RevertLabel) { $script:RevertLabel.Title = T 'btn.undo' }
    $ui.BrandName.Text = T 'app.name'
    $tag = ''
    if ($script:Demo) { $tag = T 'app.demo' } elseif ($script:DryRun) { $tag = T 'app.dryrun' }
    if ($tag) {
        $ui.ModeTag.Text = $tag
        $ui.ModeRow.Visibility = 'Visible'
    }
    Update-UpdatePill
}

# Marks the top bar button of the page that is open, if it has one.
function Select-NavEntry {
    param([string]$Id)
    if ($Id -eq 'history') { $script:Ui.BtnHistory.Tag = 'on' } else { $script:Ui.BtnHistory.Tag = '' }
    if ($Id -eq 'settings') { $script:Ui.BtnSettings.Tag = 'on' } else { $script:Ui.BtnSettings.Tag = '' }
}

# The top bar is out of reach while a question is open or a run is going.
function Set-NavEnabled {
    param([bool]$Enabled)
    $script:Ui.BtnHistory.IsEnabled = $Enabled
    $script:Ui.BtnSettings.IsEnabled = $Enabled
    $script:Ui.BtnUpdate.IsEnabled = $Enabled
}

# The text of the button that leads back to the overview.
function Get-BackText { return ([string][char]0x2039 + '  ' + (T 'btn.overview')) }

# ================================================================ Pages

function Show-Page {
    param([string]$Id)
    $script:CurrentPage = $Id
    $script:PageVms = @{}
    Select-NavEntry $Id
    switch ($Id) {
        'home'     { Build-Home; Show-View 'ViewHome'; Start-Cascade $script:Ui.HomeCards 60 45 8 10; Start-HomeCount }
        'history'  { Build-History; Show-View 'ViewHistory'; Start-Cascade $script:Ui.HistoryRuns 70 45 8 }
        'settings' { Build-Settings; Show-View 'ViewSettings' }
        default    {
            $script:Ui.SearchBox.Text = ''
            Build-List
            Show-View 'ViewList'
            $script:Ui.ListScroll.ScrollToTop()
            Start-Cascade $script:Ui.ListGroups 70 60 6
        }
    }
    Update-Chrome
    Update-Bars
}

# The number on the overview's panel counts up from nothing as the page arrives.
function Start-HomeCount {
    $block = $script:Ui.HomeCount
    $number = 0
    if (-not $script:Motion -or $block.Visibility -ne 'Visible') { return }
    if ([int]::TryParse([string]$block.Text, [ref]$number) -and $number -gt 1) {
        [Debloater.Ui.Counter]::Run($block, 0, $number, 620, 120)
        Register-Motion 900
    }
}

# The ring around the app's mark on the loading screen spreads out and fades, again
# and again, until the PC has been looked at.
function Start-LoadingPulse {
    if (-not $script:Motion) { return }
    $halo = $script:Ui.LoadingHalo
    $grow = New-Object Windows.Media.Animation.DoubleAnimation
    $grow.From = 1
    $grow.To = 1.9
    $grow.Duration = New-Object Windows.Duration([TimeSpan]::FromMilliseconds(1300))
    $grow.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
    $grow.EasingFunction = New-Ease 'cubic'
    $fade = $grow.Clone()
    $fade.From = 0.9
    $fade.To = 0
    $halo.RenderTransform.BeginAnimation([Windows.Media.ScaleTransform]::ScaleXProperty, $grow)
    $halo.RenderTransform.BeginAnimation([Windows.Media.ScaleTransform]::ScaleYProperty, $grow)
    $halo.BeginAnimation([Windows.UIElement]::OpacityProperty, $fade)
}

function Stop-LoadingPulse {
    $halo = $script:Ui.LoadingHalo
    $halo.RenderTransform.BeginAnimation([Windows.Media.ScaleTransform]::ScaleXProperty, $null)
    $halo.RenderTransform.BeginAnimation([Windows.Media.ScaleTransform]::ScaleYProperty, $null)
    $halo.BeginAnimation([Windows.UIElement]::OpacityProperty, $null)
}

# An area's picture, and the glyph that stands in for it when the file is missing.
function Set-AreaIcon {
    param($Vm, $Page)
    $Vm.Glyph = Glyph $Page.Glyph
    $Vm.Icon = Get-AreaIcon $Page.Id
}

# How many changes are in place, in one area or in all of them. For apps that is what
# this tool removed, since an app that is gone looks the same as one that was never
# there; for settings it is whatever is switched off, whoever did it.
function Get-AchievedCount {
    param([string]$PageId)
    $count = 0
    foreach ($item in $script:Catalog) {
        if ($PageId -and $item.Page -ne $PageId) { continue }
        $state = $script:State[$item.Id].State
        if ($state -eq 'todo') { continue }
        if (@($item.Packages).Count -gt 0) { if ($script:AppliedIds[$item.Id]) { $count++ } }
        # The Apps row counts apps only, so that it can say "removed".
        elseif ($PageId -eq 'apps') { continue }
        elseif ($state -eq 'done' -or $script:AppliedIds[$item.Id]) { $count++ }
    }
    return $count
}

# The overview's list: a row for each area that says what is in it, with how much of
# it is ticked in a box at the end. Once nothing recommended is left, the rows say what
# has been done instead.
function Build-Home {
    $ui = $script:Ui
    $finished = Test-HomeFinished
    $rows = New-Collection
    foreach ($id in $script:CategoryIds) {
        $todo = @(Get-TodoItems $id)
        $ticked = @($todo | Where-Object { $script:Selected[$_.Id] }).Count
        $recommended = @($todo | Where-Object { $_.Recommended }).Count
        $done = @($script:Catalog | Where-Object { $_.Page -eq $id -and $script:State[$_.Id].State -eq 'done' }).Count

        $row = New-Object Debloater.Ui.AreaVm
        $row.Id = $id
        $row.Title = T ('nav.' + $id)
        Set-AreaIcon $row (Get-Page $id)
        if ($finished) {
            # A result instead of a to-do: what is in place here, and what is still optional.
            $achieved = Get-AchievedCount $id
            if ($todo.Count -eq 0) {
                if ($achieved -eq 0) {
                    $row.Summary = T 'card.none'
                } else {
                    if ($id -eq 'onedrive') { $row.Summary = T 'card.fin.onedrive' }
                    else { $row.Summary = TN ('card.fin.' + $id) $achieved }
                    $row.Chip = T 'state.done'
                    $row.ChipKind = 'done'
                }
            } elseif ($ticked -gt 0) {
                $row.Summary = T 'card.fin.ticked' $ticked, $todo.Count
                $row.Chip = ('{0} / {1}' -f $ticked, $todo.Count)
            } else {
                if ($id -eq 'apps') { $row.Summary = TN 'card.fin.left.apps' $todo.Count }
                else { $row.Summary = TN 'card.fin.left' $todo.Count }
                if ($achieved -eq 0) {
                    $row.Chip = T 'card.fin.untouched'
                    $row.ChipKind = 'quiet'
                } else {
                    if ($id -eq 'apps') { $row.Chip = TN 'card.fin.count.apps' $achieved }
                    else { $row.Chip = TN 'card.fin.count' $achieved }
                    $row.ChipKind = 'done'
                }
            }
        } elseif ($todo.Count -gt 0) {
            $optional = $todo.Count - $recommended
            if ($optional -eq 0) { $row.Summary = T 'card.sub.recommended' $recommended }
            elseif ($recommended -eq 0) { $row.Summary = T 'card.sub.optional' $optional }
            else { $row.Summary = T 'card.sub' $recommended, $optional }
            $row.Chip = ('{0} / {1}' -f $ticked, $todo.Count)
            if ($ticked -eq 0) { $row.ChipKind = 'quiet' }
        } elseif ($done -gt 0) {
            $row.Summary = T 'card.clean'
            $row.Chip = T 'state.done'
            $row.ChipKind = 'done'
        } else {
            $row.Summary = T 'card.none'
        }
        $rows.Add($row)
    }
    $ui.HomeCards.ItemsSource = $rows
    $ui.HomeEyebrow.Text = Format-Caps (T 'home.eyebrow')
    $ui.BtnDebloat.Content = T 'btn.debloat'
    Update-Bars
}

function Build-List {
    $ui = $script:Ui
    $id = $script:CurrentPage
    $page = Get-Page $id
    $ui.ListTitle.Text = T ('nav.' + $id)
    $ui.ListIntro.Text = T ('page.' + $id + '.intro')
    $ui.ListOrb.Content = $script:NavById[$id].PSObject.BaseObject
    $ui.BtnBack.Content = Get-BackText
    $ui.SearchBox.Tag = T 'list.search'
    $ui.BtnSelectAll.Content = T 'list.selectall'
    $ui.BtnSelectNone.Content = T 'list.clear'
    $ui.BtnDebloatSmall.Content = T 'btn.debloat'

    $filter = ([string]$ui.SearchBox.Text).Trim()
    $script:PageVms = @{}
    $groups = New-Collection
    $shown = 0
    $pageTodo = 0
    foreach ($groupId in $page.Groups) {
        $items = @($script:Catalog | Where-Object { $_.Page -eq $id -and $_.Group -eq $groupId -and $script:State[$_.Id].State -eq 'todo' })
        $pageTodo += $items.Count
        $group = New-Object Debloater.Ui.GroupVm
        $group.Title = Format-Caps (T ('group.' + $id + '.' + $groupId))
        foreach ($item in $items) {
            $vm = New-ItemVm $item
            if ($filter -and ($vm.Title + ' ' + $vm.Description).IndexOf($filter, [StringComparison]::CurrentCultureIgnoreCase) -lt 0) { continue }
            $script:PageVms[$item.Id] = $vm
            $group.Items.Add($vm)
        }
        if ($group.Items.Count -eq 0) { continue }
        $group.CountText = [string]$group.Items.Count
        $groups.Add($group)
        $shown += $group.Items.Count
    }
    $ui.ListGroups.ItemsSource = $groups

    $doneItems = New-Collection
    foreach ($item in @($script:Catalog | Where-Object { $_.Page -eq $id -and $script:State[$_.Id].State -eq 'done' })) {
        $vm = New-ItemVm $item
        if ($filter -and $vm.Title.IndexOf($filter, [StringComparison]::CurrentCultureIgnoreCase) -lt 0) { continue }
        $doneItems.Add($vm)
    }
    $ui.DoneItems.ItemsSource = $doneItems
    if ($doneItems.Count -gt 0) {
        $ui.DoneLabel.Text = Format-Caps (T 'list.done' $doneItems.Count)
        $ui.DoneLabel.Visibility = 'Visible'
        $ui.DoneCard.Visibility = 'Visible'
    } else {
        $ui.DoneLabel.Visibility = 'Collapsed'
        $ui.DoneCard.Visibility = 'Collapsed'
    }

    # Empty states: nothing left to do on this page, or nothing matches the search.
    $background = [Windows.Controls.Border]::BackgroundProperty
    $border = [Windows.Controls.Border]::BorderBrushProperty
    $foreground = [Windows.Controls.TextBlock]::ForegroundProperty
    if ($shown -eq 0 -and $filter) {
        $ui.ListEmptyGlyph.Text = Glyph 0xE721
        $ui.ListEmptyBadge.SetResourceReference($background, 'ChipFill')
        $ui.ListEmptyBadge.SetResourceReference($border, 'RuleFill')
        $ui.ListEmptyGlyph.SetResourceReference($foreground, 'Text2')
        $ui.ListEmptyTitle.Text = T 'list.noresults'
        $ui.ListEmptyText.Text = ''
        if ($doneItems.Count -eq 0) { $ui.ListEmpty.Visibility = 'Visible' } else { $ui.ListEmpty.Visibility = 'Collapsed' }
    } elseif ($pageTodo -eq 0) {
        $ui.ListEmptyGlyph.Text = Glyph 0xE73E
        $ui.ListEmptyBadge.SetResourceReference($background, 'SuccessBg')
        $ui.ListEmptyBadge.SetResourceReference($border, 'SuccessLine')
        $ui.ListEmptyGlyph.SetResourceReference($foreground, 'SuccessFg')
        $ui.ListEmptyTitle.Text = T 'list.clean.title'
        $ui.ListEmptyText.Text = T 'page.empty'
        $ui.ListEmpty.Visibility = 'Visible'
    } else {
        $ui.ListEmpty.Visibility = 'Collapsed'
    }
    $ui.BtnSelectAll.IsEnabled = ($pageTodo -gt 0)
    $ui.BtnSelectNone.IsEnabled = ($pageTodo -gt 0)
}

function Get-UiCulture {
    try { return [Globalization.CultureInfo]::GetCultureInfo((Get-DebloaterLanguage)) } catch {}
    return [Globalization.CultureInfo]::InvariantCulture
}

# The heading of a finished overview: when the last run was and what it did. Says
# whether that run has settings that can still be put back.
function Update-HomeBanner {
    $ui = $script:Ui
    $last = $script:LastApplied
    if (-not $last) {
        $ui.HomeBannerTitle.Text = T 'home.title.clean'
        $ui.HomeBannerSub.Text = T 'home.done.sub.none'
        return $false
    }
    if (-not $last.When) { $ui.HomeBannerTitle.Text = T 'home.title.clean' }
    elseif ($last.When.Date -eq (Get-Date).Date) { $ui.HomeBannerTitle.Text = T 'home.done.today' ($last.When.ToString('HH:mm')) }
    else { $ui.HomeBannerTitle.Text = T 'home.done.on' ($last.When.ToString('d MMMM yyyy', (Get-UiCulture))) }
    $text = TN 'home.done.sub' @($last.Done).Count
    if ($last.Session) { $text += ' ' + (T 'home.done.restart') }
    $ui.HomeBannerSub.Text = $text
    # A dry run changed nothing, so it has nothing to put back. A demo pretends.
    return ($last.Undoable -gt 0 -and ($script:Demo -or -not $script:DryRun))
}

# The texts around the Debloat button, on the overview and on area pages.
function Update-Bars {
    $ui = $script:Ui
    if ($script:Mode -notin 'browse', 'confirm') { return }
    $todo = @(Get-TodoItems)
    $selected = @($todo | Where-Object { $script:Selected[$_.Id] })
    $count = $selected.Count
    $areas = @($selected | ForEach-Object { $_.Page } | Sort-Object -Unique).Count
    $recommended = @($todo | Where-Object { $_.Recommended })
    $optional = @($todo | Where-Object { -not $_.Recommended })

    if ($script:CurrentPage -eq 'home') {
        # Nothing recommended left: the heading says what was done instead of what to do.
        $finished = ($recommended.Count -eq 0)
        $undoable = $false
        if ($finished) {
            $undoable = [bool](Update-HomeBanner)
            $ui.HomeHead.Visibility = 'Collapsed'
            $ui.HomeBanner.Visibility = 'Visible'
        } else {
            $ui.HomeBanner.Visibility = 'Collapsed'
            $ui.HomeHead.Visibility = 'Visible'
            if ($todo.Count -eq 1) { $ui.HomeTitle.Text = T 'home.title.one' }
            else { $ui.HomeTitle.Text = T 'home.title.todo' $todo.Count }

            $onlyRecommended = ($count -eq $recommended.Count) -and (@($selected | Where-Object { -not $_.Recommended }).Count -eq 0)
            if ($count -eq 0) { $ui.HomeSub.Text = T 'home.sub.none' }
            elseif ($onlyRecommended) { $ui.HomeSub.Text = T 'home.sub.ticked' $count }
            else { $ui.HomeSub.Text = T 'home.sub.custom' $count }
        }

        # The panel: how much is ticked and the button that applies it. With nothing
        # recommended left and nothing ticked it rests: the number is what is in place,
        # and a tick stands where the button was.
        $resting = ($finished -and $count -eq 0)
        if ($resting) {
            $inPlace = Get-AchievedCount ''
            $ui.HomePanelLabel.Text = Format-Caps (T 'home.panel.done')
            if ($inPlace -gt 0) {
                $ui.HomeCount.Text = [string]$inPlace
                $ui.HomeCount.Visibility = 'Visible'
                # The number stands above these words, so they do not repeat it.
                if ($inPlace -eq 1) { $ui.HomeReady.Text = T 'home.inplace.one' } else { $ui.HomeReady.Text = T 'home.inplace' }
            } else {
                $ui.HomeCount.Visibility = 'Collapsed'
                $ui.HomeReady.Text = T 'home.done.sub.none'
            }
            if ($optional.Count -gt 0) { $ui.HomeReadySub.Text = TN 'home.done.ready.sub' $optional.Count }
            else { $ui.HomeReadySub.Text = T 'home.sub.clean' }
            $ui.BtnDebloat.Visibility = 'Collapsed'
            $ui.HomeMedal.Visibility = 'Visible'
            $script:HomeCountShown = -1
        } else {
            if ($count -eq 0) {
                $ui.HomePanelLabel.Text = Format-Caps (T 'home.panel.none')
                $ui.HomeReady.Text = T 'home.ready.none'
                $ui.HomeReadySub.Text = T 'home.ready.sub.none'
            } else {
                $ui.HomePanelLabel.Text = Format-Caps (T 'home.panel.ready')
                if ($count -eq 1) { $ui.HomeReady.Text = T 'home.ready.one' }
                elseif ($areas -eq 1) { $ui.HomeReady.Text = T 'home.ready.area' }
                else { $ui.HomeReady.Text = T 'home.ready' $areas }
                $ui.HomeReadySub.Text = T 'home.note'
            }
            $ui.HomeMedal.Visibility = 'Collapsed'
            $ui.HomeCount.Visibility = 'Visible'
            $ui.BtnDebloat.Visibility = 'Visible'
            if ($script:HomeCountShown -ne $count) {
                $ui.HomeCount.Text = [string]$count
                # A nudge when the number changes under the eyes, not when the page arrives.
                if ($script:HomeCountShown -ge 0 -and $script:CurrentView -eq 'ViewHome') { Start-Bump $ui.HomeCount 1.1 }
                $script:HomeCountShown = $count
            }
        }
        $ui.BtnDebloat.IsEnabled = ($count -gt 0)
        if ($resting -and $undoable) { $ui.BtnHomeUndo.Visibility = 'Visible' } else { $ui.BtnHomeUndo.Visibility = 'Collapsed' }

        if ($optional.Count -gt 0) {
            $ui.OptionalSwitch.Content = TN 'home.optional' $optional.Count
            $ui.OptionalSwitch.IsChecked = (@($optional | Where-Object { -not $script:Selected[$_.Id] }).Count -eq 0)
            $ui.OptionalSwitch.Visibility = 'Visible'
        } else {
            $ui.OptionalSwitch.Visibility = 'Collapsed'
        }
    } elseif ($script:CategoryIds -contains $script:CurrentPage) {
        $onPage = @($selected | Where-Object { $_.Page -eq $script:CurrentPage }).Count
        if ($count -eq 0) { $ui.BarTitle.Text = T 'home.ready.none' }
        elseif ($count -eq 1) { $ui.BarTitle.Text = T 'bar.selected.one' }
        else { $ui.BarTitle.Text = T 'bar.selected' $count }
        $ui.BarSub.Text = T 'bar.page' $onPage
        $ui.BtnDebloatSmall.IsEnabled = ($count -gt 0)
    }
}

# ================================================================ Confirmation

function Show-Confirm {
    $selected = @(Get-SelectedIds | ForEach-Object { $script:ById[$_] })
    if ($selected.Count -eq 0) { return }
    $script:Mode = 'confirm'
    $script:ConfirmAction = @{ Kind = 'apply'; Dir = '' }
    Reset-ConfirmSheet
    Set-NavEnabled $false
    $ui = $script:Ui

    $rows = New-Collection
    $anyAdmin = $false
    foreach ($id in $script:CategoryIds) {
        $items = @($selected | Where-Object { $_.Page -eq $id })
        if ($items.Count -eq 0) { continue }
        $page = Get-Page $id
        $admin = (@($items | Where-Object { Test-DebloaterItemNeedsAdmin $_ }).Count -gt 0)
        if ($admin) { $anyAdmin = $true }
        $entries = @()
        if ($id -eq 'apps') {
            $apps = @($items | Where-Object { @($_.Packages).Count -gt 0 }).Count
            if ($apps -eq 1) { $entries += ,@((T 'confirm.row.apps.one'), (T 'confirm.note.store')) }
            elseif ($apps -gt 1) { $entries += ,@((T 'confirm.row.apps' $apps), (T 'confirm.note.store')) }
            if (@($items | Where-Object { @($_.Packages).Count -eq 0 }).Count -gt 0) { $entries += ,@((T 'confirm.row.gamebar'), '') }
        } elseif ($id -eq 'onedrive') {
            $entries += ,@((T 'confirm.row.onedrive'), '')
        } else {
            $note = ''
            if ($admin) { $note = T 'badge.admin' }
            if ($items.Count -eq 1) { $entries += ,@((T ('confirm.row.' + $id + '.one')), $note) }
            else { $entries += ,@((T ('confirm.row.' + $id) $items.Count), $note) }
        }
        foreach ($entry in $entries) {
            $row = New-Object Debloater.Ui.SummaryVm
            Set-AreaIcon $row $page
            $row.Text = $entry[0]
            $row.Note = $entry[1]
            $rows.Add($row)
        }
    }
    $ui.ConfirmRows.ItemsSource = $rows

    $areas = @($selected | ForEach-Object { $_.Page } | Sort-Object -Unique).Count
    $ui.ConfirmTitle.Text = T 'confirm.title'
    if ($selected.Count -eq 1) { $ui.ConfirmSub.Text = T 'confirm.sub.one' }
    elseif ($areas -eq 1) { $ui.ConfirmSub.Text = T 'confirm.sub.area' $selected.Count }
    else { $ui.ConfirmSub.Text = T 'confirm.sub' $selected.Count, $areas }

    $fine = @()
    if ($script:DryRun) { $fine += T 'confirm.fine.dryrun' }
    $fine += T 'confirm.fine.backup'
    if ($anyAdmin) { $fine += T 'confirm.fine.admin' }
    if (@($selected | Where-Object { $_.Id -eq 'onedrive.remove' }).Count -gt 0) { $fine += T 'confirm.fine.onedrive' }
    $ui.ConfirmFine.Text = $fine -join ' '

    $ui.BtnConfirmCancel.Content = T 'btn.cancel'
    $ui.BtnConfirmGo.Content = T 'btn.debloat.now'
    Open-ConfirmSheet
}

# The sheet arrives with a small bounce over a dimmed window.
function Open-ConfirmSheet {
    $ui = $script:Ui
    $ui.ConfirmOverlay.IsHitTestVisible = $true
    $ui.ConfirmOverlay.Visibility = 'Visible'
    Start-Motion $ui.ConfirmOverlay ([Windows.UIElement]::OpacityProperty) 1 200 -From 0 -Keep
    $scale = $ui.ConfirmSheet.RenderTransform.Children[0]
    $offset = $ui.ConfirmSheet.RenderTransform.Children[1]
    Start-Motion $scale ([Windows.Media.ScaleTransform]::ScaleXProperty) 1 320 -From 0.92 -Ease 'back'
    Start-Motion $scale ([Windows.Media.ScaleTransform]::ScaleYProperty) 1 320 -From 0.92 -Ease 'back'
    Start-Motion $offset ([Windows.Media.TranslateTransform]::YProperty) 0 320 -From 18 -Ease 'quint'
    [void]$ui.BtnConfirmGo.Focus()
}

# The same sheet, asking before a run is reverted, and saying what comes back: its
# settings, the apps it removed, OneDrive. An empty $RunDir means the pretended changes
# of a demo.
function Show-UndoConfirm {
    param([string]$RunDir)
    $counts = @{ settings = 0; apps = 0; onedrive = 0 }
    if ($RunDir) {
        foreach ($scope in 'User', 'Admin') {
            foreach ($entry in @(Get-DebloaterJournal $RunDir $scope)) {
                $group = Get-DebloaterEntryGroup $entry
                if ($group) { $counts[$group]++ }
            }
        }
    } else {
        foreach ($id in @(Get-DemoUndoIds)) {
            $item = $script:ById[$id]
            if (@($item.Actions) -contains 'RemoveOneDrive') { $counts.onedrive++ }
            elseif (@($item.Packages).Count -gt 0) { $counts.apps++ }
            else { $counts.settings++ }
        }
    }
    if (($counts.settings + $counts.apps + $counts.onedrive) -eq 0) { return }
    $script:Mode = 'confirm'
    $script:ConfirmAction = @{ Kind = 'undo'; Dir = $RunDir }
    Reset-ConfirmSheet
    Set-NavEnabled $false
    $ui = $script:Ui

    $rows = New-Collection
    $lines = @()
    if ($counts.settings -gt 0) { $lines += , @((TN 'confirm.undo.row' $counts.settings), (T 'confirm.undo.row.note'), 'history') }
    if ($counts.apps -gt 0) { $lines += , @((TN 'confirm.undo.apps' $counts.apps), (T 'confirm.undo.apps.note'), 'apps') }
    if ($counts.onedrive -gt 0) { $lines += , @((T 'confirm.undo.onedrive'), (T 'confirm.undo.onedrive.note'), 'onedrive') }
    foreach ($entry in $lines) {
        $row = New-Object Debloater.Ui.SummaryVm
        Set-AreaIcon $row (Get-Page $entry[2])
        $row.Text = $entry[0]
        $row.Note = $entry[1]
        $rows.Add($row)
    }
    $ui.ConfirmRows.ItemsSource = $rows
    $ui.ConfirmTitle.Text = T 'confirm.undo.title'
    $ui.ConfirmSub.Text = T 'confirm.undo.sub'
    $ui.ConfirmFine.Text = T 'confirm.undo.fine'
    $ui.BtnConfirmCancel.Content = T 'btn.cancel'
    $ui.BtnConfirmGo.Content = T 'btn.undo.now'
    Open-ConfirmSheet
}

# The sheet fades away. What it covered can be used at once; only the picture lingers.
function Hide-Confirm {
    # Not in the middle of a download: the installer is about to take over.
    if ($script:ConfirmAction -and $script:ConfirmAction.Kind -eq 'update-working') { return }
    $script:Mode = 'browse'
    Set-NavEnabled $true
    $overlay = $script:Ui.ConfirmOverlay
    $overlay.IsHitTestVisible = $false
    Start-Motion $overlay ([Windows.UIElement]::OpacityProperty) 0 160 -Keep -Then {
        if ($script:Mode -ne 'confirm') { $script:Ui.ConfirmOverlay.Visibility = 'Collapsed' }
    }
}

# The confirming button of the sheet, for whichever question it asked.
function Invoke-ConfirmGo {
    $action = $script:ConfirmAction
    if ($action -and $action.Kind -like 'update*') {
        if ($action.Kind -eq 'update') { Start-UpdateInstall }
        return
    }
    Hide-Confirm
    if ($action -and $action.Kind -eq 'undo') {
        if ($action.Dir) { Start-UndoRun ([string]$action.Dir) } else { Start-DemoUndo }
    } else {
        Start-Apply
    }
}

function Exit-ToBrowse {
    $script:Mode = 'browse'
    Set-NavEnabled $true
    Show-Page 'home'
}

# ================================================================ Apply and undo runs

function Get-RunItemTitle {
    param([string]$Id)
    $item = $script:ById[$Id]
    if ($item) { return (Get-DebloaterItemTitle $item) }
    return $Id
}

function Get-Step {
    param([string]$Id)
    if (-not $script:StepById.ContainsKey($Id)) {
        $step = New-Object Debloater.Ui.StepVm
        $step.Id = $Id
        $step.Title = Get-RunItemTitle $Id
        $step.Status = 'pending'
        $step.StatusText = T 'status.pending'
        $script:StepById[$Id] = $step
        $script:Steps.Add($step)
    }
    return $script:StepById[$Id]
}

function Set-StepStatus {
    param([string]$Id, [string]$Status, [string]$Message)
    $step = Get-Step $Id
    # A failure reported by one worker is not hidden by the other worker succeeding.
    if (-not ($step.Status -eq 'failed' -and $Status -in 'ok', 'running')) {
        $step.Status = $Status
        $step.StatusText = T ('status.' + $Status)
    }
    if ($Message) {
        $parts = @()
        if ($step.Message) { $parts = @($step.Message -split '; ') }
        if ($parts -notcontains $Message) { $step.Message = (@($parts) + $Message) -join '; ' }
    }
}

# Moves the overall bar smoothly. -Now sets it without the glide.
function Set-ProgressValue {
    param([double]$Value, [switch]$Now)
    $bar = $script:Ui.ProgressBar
    $property = [Windows.Controls.Primitives.RangeBase]::ValueProperty
    if ($Now) {
        $bar.BeginAnimation($property, $null)
        $bar.Value = $Value
        $script:BarTarget = $Value
        return
    }
    if ($script:BarTarget -eq $Value) { return }
    $script:BarTarget = $Value
    $animation = New-Object Windows.Media.Animation.DoubleAnimation
    $animation.To = $Value
    $animation.Duration = New-Object Windows.Duration([TimeSpan]::FromMilliseconds(280))
    $bar.BeginAnimation($property, $animation)
}

function Update-RunCounter {
    $run = $script:Run
    $script:Ui.ProgressCount.Text = T 'progress.count' $run.Finished, $run.Total
    # Doubles on purpose: with whole numbers PowerShell picks the integer Min and rounds
    # the fraction to 0 or 1.
    Set-ProgressValue ([Math]::Min([double]1, [double]$run.Finished / [double]$run.Total))
}

# One lane for each area that has something in this run, in the order of the overview's rows.
function Build-Lanes {
    param([string[]]$Ids)
    $script:Lanes = New-Collection
    $script:LaneByItem = @{}
    $script:LaneProblems = @{}
    foreach ($pageId in $script:CategoryIds) {
        $items = @($Ids | Where-Object { $script:ById[$_] -and $script:ById[$_].Page -eq $pageId })
        if ($items.Count -eq 0) { continue }
        $lane = New-Object Debloater.Ui.LaneVm
        $lane.Id = $pageId
        $lane.Title = T ('nav.' + $pageId)
        Set-AreaIcon $lane (Get-Page $pageId)
        $lane.Total = $items.Count
        $lane.TotalText = T 'lane.total' $items.Count
        $lane.Status = T 'status.pending'
        $script:Lanes.Add($lane)
        foreach ($id in $items) { $script:LaneByItem[$id] = $lane }
    }
    # Never fewer than four columns, so one or two lanes keep the shape of a card.
    $script:Ui.ProgressLanes.Tag = [Math]::Max(4, $script:Lanes.Count)
    $script:Ui.ProgressLanes.ItemsSource = $script:Lanes
}

function Show-ProgressView {
    $script:Mode = 'progress'
    Set-NavEnabled $false
    $ui = $script:Ui
    $ui.ProgressBar.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, 'Accent')
    if ($script:Run.Undo) { $ui.ProgressEyebrow.Text = Format-Caps (T 'undo.title') }
    else { $ui.ProgressEyebrow.Text = Format-Caps (T 'progress.eyebrow') }
    $ui.ProgressTitle.Text = T 'progress.starting'
    if ($script:DryRun) { $ui.ProgressIntro.Text = T 'progress.intro.dryrun' } else { $ui.ProgressIntro.Text = T 'progress.intro' }
    $ui.ProgressIntro.Visibility = 'Visible'
    $ui.ProgressNote.Visibility = 'Collapsed'
    $ui.ProgressButtons.Visibility = 'Collapsed'
    Set-ProgressValue 0 -Now
    $script:Feed = New-Collection
    $ui.ProgressFeed.ItemsSource = $script:Feed
    Show-View 'ViewProgress'

    # The parts of each lane that are moved from here: its bar and its count.
    $ui.ProgressLanes.UpdateLayout()
    $script:LaneParts = @{}
    for ($i = 0; $i -lt $script:Lanes.Count; $i++) {
        $container = $ui.ProgressLanes.ItemContainerGenerator.ContainerFromIndex($i)
        if (-not $container -or -not $container.ContentTemplate) { continue }
        $script:LaneParts[$script:Lanes[$i].Id] = @{
            Bar   = $container.ContentTemplate.FindName('LaneBar', $container)
            Count = $container.ContentTemplate.FindName('LaneCount', $container)
        }
    }
    Start-Cascade $ui.ProgressLanes 90 80 8 22
}

# Adds a line to the list of what has just been done. The newest is on top and
# bright; the ones below it fade, and the last drops off.
function Add-FeedLine {
    param([string]$Id, [string]$Kind)
    $line = New-Object Debloater.Ui.FeedVm
    $line.Title = Get-RunItemTitle $Id
    $line.Kind = $Kind
    $item = $script:ById[$Id]
    if ($item) { $line.Area = T ('nav.' + $item.Page) }
    $script:Feed.Insert(0, $line)
    while ($script:Feed.Count -gt 5) { $script:Feed.RemoveAt($script:Feed.Count - 1) }
    $strengths = @(1, 0.6, 0.36, 0.18, 0.07)
    for ($i = 0; $i -lt $script:Feed.Count; $i++) { $script:Feed[$i].Strength = $strengths[$i] }
    # The whole list starts one line higher and settles: the new line slides in from
    # above while the others move down to make room.
    Start-Motion $script:Ui.ProgressFeed.RenderTransform ([Windows.Media.TranslateTransform]::YProperty) 0 260 -From -30 -Ease 'quint'
}

# Each start function hands Start-Run a table of how many reports to expect per item
# from each worker: an item counts as finished when all of them have come in.
function Start-Apply {
    $ids = @(Get-SelectedIds)
    if ($ids.Count -eq 0) { return }
    $runDir = New-DebloaterRunFolder
    $plan = [pscustomobject]@{
        runId   = (Split-Path -Leaf $runDir)
        created = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        version = (Get-DebloaterVersion)
        userSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        dryRun  = [bool]$script:DryRun
        lang    = (Get-DebloaterLanguage)
        steps   = $ids
    }
    $planPath = Join-Path $runDir 'plan.json'
    Write-DebloaterJson $plan $planPath

    $parts = @{ Admin = @{}; User = @{} }
    foreach ($scope in 'Admin', 'User') {
        foreach ($id in $ids) { if (Test-DebloaterItemHasScope $script:ById[$id] $scope) { $parts[$scope][$id] = 1 } }
    }
    Start-Run -RunDir $runDir -PlanPath $planPath -Ids $ids -Parts $parts -Undo $false
}

function Start-UndoRun {
    param([string]$RunDir)
    $planPath = Join-Path $RunDir 'plan.json'
    if (-not (Test-Path -LiteralPath $planPath)) { return }
    $parts = @{ Admin = @{}; User = @{} }
    $ids = @()
    foreach ($scope in 'Admin', 'User') {
        foreach ($entry in @(Get-DebloaterJournal $RunDir $scope)) {
            if (-not (Test-DebloaterEntryUndoable $entry)) { continue }
            $id = [string]$entry.Item
            $parts[$scope][$id] = 1 + [int]$parts[$scope][$id]
            if ($ids -notcontains $id) { $ids += $id }
        }
    }
    if ($ids.Count -eq 0) { return }
    Start-Run -RunDir $RunDir -PlanPath $planPath -Ids $ids -Parts $parts -Undo $true
}

# What a demo could revert: everything it pretended to do, as a real run can be.
function Get-DemoUndoIds {
    return @($script:Catalog | Where-Object { $script:DemoDone[$_.Id] } | ForEach-Object { $_.Id })
}

# A demo has no journal to undo, so the same screen is played from made-up reports.
function Start-DemoUndo {
    $ids = @(Get-DemoUndoIds)
    if ($ids.Count -eq 0) { return }
    $parts = @{ Admin = @{}; User = @{} }
    $reports = @()
    foreach ($id in $ids) {
        $parts.User[$id] = 1
        $reports += @{ Id = $id; Status = 'start'; Message = '' }
        $reports += @{ Id = $id; Status = 'ok'; Message = (T 'msg.undo.would') }
    }
    Start-Run -RunDir '' -PlanPath '' -Ids $ids -Parts $parts -Undo $true -Reports $reports
}

function Start-Run {
    param([string]$RunDir, [string]$PlanPath, [string[]]$Ids, [hashtable]$Parts, [bool]$Undo, [object[]]$Reports)
    $script:LastRunDir = $RunDir
    $remaining = @{}
    $phases = @()
    foreach ($scope in 'Admin', 'User') {
        foreach ($id in @($Parts[$scope].Keys)) { $remaining[$id] = [int]$remaining[$id] + [int]$Parts[$scope][$id] }
        # Made-up reports need no worker.
        if ($Parts[$scope].Count -gt 0 -and -not $Reports) { $phases += $scope }
    }
    $script:Run = @{
        Dir        = $RunDir
        PlanPath   = $PlanPath
        Phases     = $phases
        Parts      = $Parts
        Remaining  = $remaining
        Total      = [Math]::Max(1, $remaining.Count)
        Finished   = 0
        Undo       = $Undo
        Current    = $null
        Problem    = ''
        ActiveLane = ''
        Queue      = New-Object System.Collections.Queue
    }
    foreach ($report in @($Reports)) { if ($report) { $script:Run.Queue.Enqueue($report) } }

    $script:Steps = New-Collection
    $script:StepById = @{}
    foreach ($id in $Ids) { [void](Get-Step $id) }
    Build-Lanes $Ids
    Show-ProgressView
    Update-RunCounter
    if (-not $script:Timer) {
        $script:Timer = New-Object Windows.Threading.DispatcherTimer
        $script:Timer.Interval = [TimeSpan]::FromMilliseconds(110)
        $script:Timer.Add_Tick({ Invoke-Guarded { Update-RunProgress } })
    }
    $script:TickBusy = $false
    # The first worker is started by the first tick, once the lanes are on screen.
    $script:Timer.Start()
}

function Show-ProgressNote {
    param([string]$Text)
    $script:Ui.ProgressNote.Text = $Text
    if ($Text) { $script:Ui.ProgressNote.Visibility = 'Visible' } else { $script:Ui.ProgressNote.Visibility = 'Collapsed' }
}

# An item is about to be worked on: its lane comes forward and the heading names its area.
function Start-RunItem {
    param([string]$Id)
    $run = $script:Run
    Set-StepStatus $Id 'running' ''
    $lane = $script:LaneByItem[$Id]
    if (-not $lane) { return }
    $lane.Status = Get-RunItemTitle $Id
    if ($run.ActiveLane -eq $lane.Id) { return }
    foreach ($other in $script:Lanes) {
        if (-not $other.IsActive) { continue }
        $other.IsActive = $false
        if (-not $other.IsDone) { $other.Status = T 'status.pending' }
    }
    $lane.IsActive = $true
    $run.ActiveLane = $lane.Id
    if ($run.Undo) { $script:Ui.ProgressTitle.Text = $lane.Title }
    else { $script:Ui.ProgressTitle.Text = T ('progress.area.' + $lane.Id) }
    Start-Entrance $script:Ui.ProgressTitle 0 300 9
}

function Complete-Lane {
    param($Lane)
    $problems = [int]$script:LaneProblems[$Lane.Id]
    $Lane.IsActive = $false
    if ($problems -gt 0) {
        $Lane.Status = TN 'lane.problems' $problems
        $Lane.HasProblem = $true
    } else {
        $Lane.Status = T 'status.ok'
    }
    $Lane.IsDone = $true
}

# One report for an item has come in, or will never come. When it was the last one
# expected, the item is finished and its lane moves on by one.
function Complete-RunPart {
    param([string]$Id, [string]$Status, [string]$Message)
    $run = $script:Run
    Set-StepStatus $Id $Status $Message
    if (-not $run.Remaining.ContainsKey($Id)) { return }
    $run.Remaining[$Id] = [int]$run.Remaining[$Id] - 1
    if ($run.Remaining[$Id] -gt 0) { return }
    $run.Remaining.Remove($Id)
    $run.Finished++
    $lane = $script:LaneByItem[$Id]
    if (-not $lane) { return }
    $lane.Count++
    $lane.CountText = [string]$lane.Count
    $lane.Progress = $lane.Count / [Math]::Max(1, $lane.Total)
    $parts = $script:LaneParts[$lane.Id]
    if ($parts) {
        Start-Motion $parts.Bar ([Windows.Controls.Primitives.RangeBase]::ValueProperty) $lane.Progress 340 -Keep
        Start-Bump $parts.Count
    }
    Add-FeedLine $Id ([string](Get-Step $Id).Status)
    if ((Get-Step $Id).Status -ne 'ok') { $script:LaneProblems[$lane.Id] = 1 + [int]$script:LaneProblems[$lane.Id] }
    if ($lane.Count -ge $lane.Total) { Complete-Lane $lane }
}

# Starts the next worker. Whatever happens, the timer decides what comes after.
function Start-RunPhase {
    $run = $script:Run
    $scope = $run.Phases[0]
    $run.Phases = @($run.Phases | Select-Object -Skip 1)

    $suffix = ''
    if ($run.Undo) { $suffix = '-undo' }
    $progressPath = Join-Path $run.Dir ('progress-' + $scope.ToLowerInvariant() + $suffix + '.jsonl')
    $entry = Join-Path $PSScriptRoot 'Debloater.ps1'
    $arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $entry + '" -Worker -PlanPath "' + $run.PlanPath + '" -Scope ' + $scope
    if ($run.Undo) { $arguments += ' -Undo' }

    $process = $null
    try {
        if ($scope -eq 'Admin' -and -not $script:DryRun) {
            # The one place where Windows asks for administrator permission.
            Show-ProgressNote (T 'progress.admin.prompt')
            # Let the lanes and the note reach the screen before Windows dims it.
            Invoke-UiIdle
            $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -PassThru
            Show-ProgressNote ''
        } else {
            $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WindowStyle Hidden -PassThru
        }
    } catch {
        $run.Problem = T 'progress.admin.declined'
        Show-ProgressNote $run.Problem
        foreach ($id in @($run.Parts[$scope].Keys)) {
            $parts = [int]$run.Parts[$scope][$id]
            # The other worker can still do its share of the same item, so only mark it
            # skipped outright when this worker was all it needed.
            $status = 'skipped'
            if ([int]$run.Remaining[$id] -gt $parts) { $status = 'pending' }
            for ($i = 0; $i -lt $parts; $i++) { Complete-RunPart $id $status $run.Problem }
        }
        Update-RunCounter
        return
    }
    $run.Current = @{ Scope = $scope; Process = $process; Path = $progressPath; Lines = 0; ExitTicks = 0; Ended = $false }
}

# One tick of the run: collect what the worker wrote, play a little of it, move on.
function Update-RunProgress {
    $run = $script:Run
    if ($script:Mode -ne 'progress' -or -not $run -or $script:TickBusy) { return }
    $script:TickBusy = $true
    try {
        $current = $run.Current
        if ($current -and -not $current.Ended) {
            $lines = @(Read-DebloaterLines $current.Path)
            while ($current.Lines -lt $lines.Count) {
                $line = $lines[$current.Lines]
                $current.Lines++
                if (-not $line.Trim()) { continue }
                $step = $null
                try { $step = $line | ConvertFrom-Json } catch { continue }
                if ([string]$step.status -eq 'done') { $current.Ended = $true; break }
                $run.Queue.Enqueue(@{ Id = [string]$step.id; Status = [string]$step.status; Message = [string]$step.message })
            }
            if (-not $current.Ended) {
                $exited = $false
                try { $exited = $current.Process.HasExited } catch {}
                if ($exited) {
                    # Give the last lines a moment to land before deciding the worker died.
                    $current.ExitTicks++
                    if ($current.ExitTicks -ge 12) {
                        $run.Queue.Enqueue(@{ Id = ''; Status = 'fatal'; Message = (T 'progress.worker.failed') })
                        $current.Ended = $true
                    }
                }
            }
        }

        # Play finished items one at a time, a few more when there is a backlog, so a
        # fast run can still be followed and a slow one is never held up for long.
        $budget = [Math]::Max(1, [int][Math]::Ceiling($run.Queue.Count / 30))
        while ($run.Queue.Count -gt 0 -and $budget -gt 0) {
            $report = $run.Queue.Dequeue()
            switch ([string]$report.Status) {
                'start'  { Start-RunItem $report.Id }
                'ok'     { Complete-RunPart $report.Id 'ok' $report.Message; $budget-- }
                'failed' { Complete-RunPart $report.Id 'failed' $report.Message; $budget-- }
                'fatal'  { $run.Problem = $report.Message; Show-ProgressNote $report.Message }
            }
        }
        Update-RunCounter

        if ($run.Queue.Count -eq 0) {
            if ($run.Current -and $run.Current.Ended) { $run.Current = $null }
            if (-not $run.Current) {
                if (@($run.Phases).Count -gt 0) { Start-RunPhase } else { Complete-Run }
            }
        }
    } finally {
        $script:TickBusy = $false
    }
}

function Complete-Run {
    $run = $script:Run
    if ($script:Timer) { $script:Timer.Stop() }
    # Anything a worker never reached counts as skipped.
    foreach ($step in $script:Steps) {
        if ($step.Status -in 'pending', 'running') { $step.Status = 'skipped'; $step.StatusText = T 'status.skipped' }
    }
    foreach ($lane in $script:Lanes) {
        if ($lane.IsDone) { continue }
        $script:LaneProblems[$lane.Id] = [int]$script:LaneProblems[$lane.Id] + ($lane.Total - $lane.Count)
        Complete-Lane $lane
    }
    $ok = @($script:Steps | Where-Object { $_.Status -eq 'ok' } | ForEach-Object { $_.Id })

    if ($script:Demo) {
        # Nothing was changed, so the demo keeps its own record of what it pretended.
        if ($run.Undo) {
            foreach ($id in $ok) { $script:DemoDone.Remove($id) }
            $script:LastApplied = $null
        } else {
            foreach ($id in $ok) { $script:DemoDone[$id] = $true }
            if ($ok.Count -gt 0) {
                $script:LastApplied = @{ When = (Get-Date); Done = $ok; Dir = ''; Undoable = @(Get-DemoUndoIds).Count; Session = $true }
            }
        }
    } elseif (-not $script:DryRun) {
        if ($run.Undo) { [IO.File]::WriteAllText((Join-Path $run.Dir 'undone.txt'), (Get-Date).ToString('yyyy-MM-dd HH:mm')) }
    }
    Update-RunRecord
    if ($script:LastApplied -and $run.Dir -and $script:LastApplied.Dir -eq $run.Dir) { $script:LastApplied.Session = $true }

    # The result is shown at once. Looking at the PC again takes a moment, so it happens
    # behind the picture, and the buttons appear when the overview is ready to be seen.
    $script:Mode = 'finishing'
    Show-RunFinished
    Start-StateScan {
        # Ready for the next round: whatever is still recommended is ticked again.
        $script:Selected = @{}
        foreach ($item in Get-TodoItems) { if ($item.Recommended) { $script:Selected[$item.Id] = $true } }
        $script:Mode = 'result'
        $ui = $script:Ui
        $ui.BtnProgressDetails.Content = T 'btn.details'
        $ui.BtnProgressDone.Content = T 'btn.done'
        $ui.ProgressButtons.Visibility = 'Visible'
        Start-Entrance $ui.ProgressButtons 0 320 10
        [void]$ui.BtnProgressDone.Focus()
        Update-Chrome
    }
}

# The lanes stay on screen, all ticked, with what happened and where to go next.
function Show-RunFinished {
    $run = $script:Run
    $ui = $script:Ui
    $ok = @($script:Steps | Where-Object { $_.Status -eq 'ok' }).Count
    $failed = @($script:Steps | Where-Object { $_.Status -eq 'failed' }).Count
    $skipped = @($script:Steps | Where-Object { $_.Status -eq 'skipped' }).Count

    if ($failed -gt 0 -or $skipped -gt 0 -or $run.Problem) {
        $ui.ProgressTitle.Text = T 'result.title.problems'
        $ui.ProgressCount.Text = T 'result.summary' $ok, $failed, $skipped
    } else {
        # A clean finish: the bar across the top turns from the accent to green.
        $ui.ProgressBar.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, 'SuccessFg')
        if ($run.Undo) {
            $ui.ProgressTitle.Text = T 'undo.done'
            $ui.ProgressCount.Text = TN 'undo.summary' $ok
        } elseif ($script:DryRun -and -not $script:Demo) {
            $ui.ProgressTitle.Text = T 'result.title.dryrun'
            $ui.ProgressCount.Text = (TN 'result.dryrun.summary' $ok) + ' ' + (T 'result.dryrun')
        } else {
            $ui.ProgressTitle.Text = T 'result.title'
            $ui.ProgressCount.Text = (TN 'home.done.sub' $ok) + ' ' + (T 'home.done.restart')
        }
    }
    Set-ProgressValue 1
    $ui.ProgressEyebrow.Text = Format-Caps (T 'progress.eyebrow.done')
    $ui.ProgressIntro.Visibility = 'Collapsed'
    Start-Entrance $ui.ProgressTitle 0 360 12
}

# The full list of steps, behind the Details button of a finished run.
function Show-Result {
    $script:Mode = 'result'
    $run = $script:Run
    $ui = $script:Ui
    $ok = @($script:Steps | Where-Object { $_.Status -eq 'ok' }).Count
    $failed = @($script:Steps | Where-Object { $_.Status -eq 'failed' }).Count
    $skipped = @($script:Steps | Where-Object { $_.Status -eq 'skipped' }).Count

    if ($failed -gt 0 -or $run.Problem) {
        $ui.ResultTitle.Text = T 'result.title.problems'
        $ui.ResultGlyph.Text = Glyph 0xE7BA
        $ui.ResultBadge.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'CautionBg')
        $ui.ResultGlyph.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'CautionFg')
    } else {
        # The same words as on the finished lanes this list was opened from.
        $ui.ResultTitle.Text = $ui.ProgressTitle.Text
        $ui.ResultGlyph.Text = Glyph 0xE73E
        $ui.ResultBadge.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'SuccessBg')
        $ui.ResultGlyph.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'SuccessFg')
    }
    if ($script:Steps.Count -eq 0) { $ui.ResultSummary.Text = T 'result.nothing' }
    else { $ui.ResultSummary.Text = T 'result.summary' $ok, $failed, $skipped }

    $stats = New-Collection
    foreach ($row in @(@($ok, 'status.ok', 'ok'), @($failed, 'status.failed', 'failed'), @($skipped, 'status.skipped', 'skipped'))) {
        $stat = New-Object Debloater.Ui.StatVm
        $stat.Value = [string]$row[0]
        $stat.Label = T $row[1]
        $stat.Kind = $row[2]
        $stats.Add($stat)
    }
    $ui.ResultStats.ItemsSource = $stats

    $notes = New-Collection
    $rows = @()
    if ($run.Problem) { $rows += ,@($run.Problem, 'warning', 0xE7BA) }
    if ($script:DryRun) { $rows += ,@((T 'result.dryrun'), 'success', 0xE73E) }
    elseif ($ok -gt 0) { $rows += ,@((T 'result.restart'), 'info', 0xE946) }
    foreach ($row in $rows) {
        $note = New-Object Debloater.Ui.NoteVm
        $note.Text = $row[0]
        $note.Kind = $row[1]
        $note.Glyph = Glyph $row[2]
        $notes.Add($note)
    }
    $ui.ResultNotes.ItemsSource = $notes

    # Problems first, then the rest in page order.
    $ordered = New-Collection
    foreach ($step in @($script:Steps | Where-Object { $_.Status -eq 'failed' })) { $ordered.Add($step) }
    foreach ($step in @($script:Steps | Where-Object { $_.Status -ne 'failed' })) { $ordered.Add($step) }
    $ui.ResultSteps.ItemsSource = $ordered
    $ui.BtnOpenLog.Content = T 'btn.openlog'
    $ui.BtnDone.Content = T 'btn.done'

    Show-View 'ViewResult'
    $ui.ResultScroll.ScrollToTop()
    Start-Cascade $ui.ResultStats 40 50 3 12
    Start-Cascade $ui.ResultSteps 120 28 12 12
    Update-Chrome
}

# ================================================================ History

function Build-History {
    $ui = $script:Ui
    $ui.HistoryOrb.Content = $script:NavById['history'].PSObject.BaseObject
    $ui.BtnHistoryBack.Content = Get-BackText
    $ui.HistoryTitle.Text = T 'nav.history'
    $ui.HistoryIntro.Text = T 'page.history.intro'
    $ui.HistoryEmptyTitle.Text = T 'history.empty.title'
    $ui.HistoryEmptyText.Text = T 'history.empty'

    $runs = New-Collection
    foreach ($run in @(Get-DebloaterRuns)) {
        $vm = New-Object Debloater.Ui.RunVm
        $vm.Dir = $run.Dir
        $changes = @($run.Steps).Count
        $vm.Title = $run.Created + '    ' + (T 'history.changes' $changes)
        if ($run.DryRun) { $vm.Title += '    (' + (T 'history.dryrun') + ')' }
        $undoable = $run.UndoableUser + $run.UndoableAdmin
        if ($run.Undone) { $vm.Subtitle = T 'history.undone' $run.Undone }
        elseif ($undoable -gt 0) { $vm.Subtitle = TN 'history.revert' $undoable }
        $vm.CanUndo = ($undoable -gt 0 -and -not $run.Undone -and -not $script:DryRun)
        $vm.UndoText = T 'btn.undo'
        $vm.OpenText = T 'btn.openfolder'
        $vm.AppsLabel = T 'history.apps'
        foreach ($app in @($run.Apps)) {
            $link = New-Object Debloater.Ui.AppLinkVm
            $link.Name = [string]$app.Name
            $link.Family = [string]$app.Family
            $link.Tip = T 'btn.store'
            $vm.Apps.Add($link)
        }
        $runs.Add($vm)
    }
    $ui.HistoryRuns.ItemsSource = $runs
    if ($runs.Count -eq 0) { $ui.HistoryEmpty.Visibility = 'Visible' } else { $ui.HistoryEmpty.Visibility = 'Collapsed' }
}

# ================================================================ Settings

function Build-Settings {
    $ui = $script:Ui
    $ui.SettingsOrb.Content = $script:NavById['settings'].PSObject.BaseObject
    $ui.BtnSettingsBack.Content = Get-BackText
    $ui.SettingsTitle.Text = T 'nav.settings'
    $ui.SettingsIntro.Text = T 'page.settings.intro'
    $ui.SettingsLangLabel.Text = Format-Caps (T 'settings.language')
    $ui.SettingsThemeLabel.Text = Format-Caps (T 'settings.theme')
    $ui.SettingsAboutLabel.Text = Format-Caps (T 'settings.about')

    $languages = New-Collection
    foreach ($language in Get-DebloaterLanguages) {
        $choice = New-Object Debloater.Ui.ChoiceVm
        $choice.Id = $language.Code
        $choice.Title = $language.Name
        $choice.IsChosen = ($language.Code -eq (Get-DebloaterLanguage))
        $languages.Add($choice)
    }
    $ui.LangChoices.ItemsSource = $languages

    $themes = New-Collection
    foreach ($theme in 'dark', 'light', 'system') {
        $choice = New-Object Debloater.Ui.ChoiceVm
        $choice.Id = $theme
        $choice.Title = T ('settings.theme.' + $theme)
        $choice.IsChosen = ($theme -eq $script:Theme)
        $themes.Add($choice)
    }
    $ui.ThemeChoices.ItemsSource = $themes

    $ui.AboutName.Text = T 'app.name'
    $ui.AboutVersion.Text = T 'settings.version' (Get-DebloaterVersion)
    $ui.AboutPrivacy.Text = T 'settings.privacy'
    $ui.LinkRepo.Content = T 'settings.link.repo'
    $ui.LinkChanges.Content = T 'settings.link.changes'
    $ui.LinkData.Content = T 'settings.link.data'
    $ui.AboutCopyright.Text = T 'settings.copyright' (Get-DebloaterCopyrightYear)
    $ui.LinkLicence.Content = T 'settings.link.licence'
    $ui.LinkSite.Content = 'coursion.studio'
    $ui.LinkSupport.Content = 'support@coursion.studio'
    Update-UpdateSettings ''
}

# Language, appearance and the size the window is at, so it opens the same way next time.
function Save-UiSettings {
    if ($script:SelfTestDir) { return }
    $window = $script:Window
    $maximized = ($window.WindowState -eq 'Maximized')
    # A maximised or minimised window remembers the size it would go back to.
    $bounds = $window.RestoreBounds
    $width = [int]$window.ActualWidth
    $height = [int]$window.ActualHeight
    if ($window.WindowState -ne 'Normal' -and -not $bounds.IsEmpty) { $width = [int]$bounds.Width; $height = [int]$bounds.Height }
    Save-DebloaterSettings ([pscustomobject]@{
        lang = (Get-DebloaterLanguage); theme = $script:Theme; width = $width; height = $height; maximized = $maximized
        updates = [bool]$script:UpdatesOn; updateChecked = [string]$script:UpdateChecked
    })
}

function Set-UiLanguage {
    param([string]$Code)
    Initialize-DebloaterLanguage $Code
    Save-UiSettings
    Update-Chrome
    if ($script:Mode -eq 'browse') { Show-Page $script:CurrentPage }
}

# ================================================================ Updates

# Whether this window may ask the internet at all. A dry run, a demo and a test never do.
function Test-UpdateAllowed {
    return (-not $script:DryRun -and -not $script:Demo -and -not $script:SelfTestDir)
}

# Once a day at most, and only while the switch on the Settings page is on.
function Test-UpdateDue {
    if (-not (Test-UpdateAllowed) -or -not $script:UpdatesOn) { return $false }
    $last = [datetime]::MinValue
    if ($script:UpdateChecked -and [datetime]::TryParse($script:UpdateChecked, [ref]$last)) {
        return (((Get-Date) - $last).TotalHours -ge 20)
    }
    return $true
}

# The pill in the top bar: there while a newer version is known, gone otherwise.
function Update-UpdatePill {
    $ui = $script:Ui
    if ($script:Update) {
        $ui.BtnUpdate.Content = T 'update.pill' $script:Update.Version
        $ui.BtnUpdate.Visibility = 'Visible'
    } else {
        $ui.BtnUpdate.Visibility = 'Collapsed'
    }
}

# Asks GitHub which release is the latest, on another thread so the window keeps
# moving, and hands 'found', 'none' or 'failed' to $Then on the window's own thread.
function Start-UpdateCheck {
    param([scriptblock]$Then)
    if ($script:UpdateJob) { return }
    $shell = [powershell]::Create()
    [void]$shell.AddScript({
        param($ModulePath)
        Import-Module $ModulePath -Force
        $found = Get-DebloaterUpdate
        $result = @{ Version = '' }
        if ($found) { foreach ($property in $found.PSObject.Properties) { $result[$property.Name] = $property.Value } }
        $result
    }.ToString()).AddArgument((Join-Path $PSScriptRoot 'Debloater.Engine.psm1'))
    $handle = $shell.BeginInvoke()
    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(150)
    $script:UpdateJob = @{ Shell = $shell; Handle = $handle; Timer = $timer; Then = $Then }
    $timer.Add_Tick({
        Invoke-Guarded {
            $job = $script:UpdateJob
            if (-not $job -or -not $job.Handle.IsCompleted) { return }
            $job.Timer.Stop()
            $script:UpdateJob = $null
            $result = $null
            $state = 'failed'
            try { $result = @($job.Shell.EndInvoke($job.Handle))[0] } catch {}
            if (-not $job.Shell.HadErrors -and $result -is [hashtable]) {
                if ($result.Version) {
                    $script:Update = [pscustomobject]$result
                    $state = 'found'
                } else {
                    $script:Update = $null
                    $state = 'none'
                }
                Set-DebloaterKnownUpdate $script:Update
                $script:UpdateChecked = (Get-Date).ToString('s')
                Save-UiSettings
            }
            $job.Shell.Dispose()
            Update-UpdatePill
            if ($job.Then) { & $job.Then $state }
        }
    })
    $timer.Start()
}

# A few words about a release, from the notes written for it: the first sentence of
# each of the first points, for as long as they fit on two lines.
function Get-UpdateSummary {
    param($Update)
    $text = ''
    foreach ($line in ([string]$Update.Notes -split "`n")) {
        $plain = ($line -replace '^[\s#>*+-]+', '' -replace '[*_`]', '' -replace '\[([^\]]*)\]\([^)]*\)', '$1').Trim()
        if (-not $plain) { continue }
        $end = $plain.IndexOf('. ')
        if ($end -gt 0) { $plain = $plain.Substring(0, $end) }
        $plain = $plain.TrimEnd('.', ':') + '.'
        if ($text -and ($text.Length + $plain.Length) -gt 150) { break }
        if ($text) { $text += ' ' }
        $text += $plain
    }
    if (-not $text) { return (T 'update.sub.none') }
    if ($text.Length -gt 170) { $text = $text.Substring(0, 167).TrimEnd() + '...' }
    return $text
}
# The small print under the rows. When there is none, its line goes too and the
# buttons keep their distance themselves.
function Set-ConfirmFine {
    param([string]$Text)
    $ui = $script:Ui
    $ui.ConfirmFine.Text = $Text
    if ($Text) {
        $ui.ConfirmFine.Visibility = 'Visible'
        $ui.ConfirmButtons.Margin = New-Object Windows.Thickness(0)
    } else {
        $ui.ConfirmFine.Visibility = 'Collapsed'
        $ui.ConfirmButtons.Margin = New-Object Windows.Thickness(0, 18, 0, 0)
    }
}

# The sheet goes back to its plain form: no label above, no bar, two buttons.
function Reset-ConfirmSheet {
    $ui = $script:Ui
    $ui.ConfirmFine.Visibility = 'Visible'
    $ui.ConfirmButtons.Margin = New-Object Windows.Thickness(0)
    $ui.ConfirmEyebrow.Visibility = 'Collapsed'
    $ui.ConfirmMeter.Visibility = 'Collapsed'
    $ui.BtnConfirmMore.Visibility = 'Collapsed'
    $ui.ConfirmCard.Visibility = 'Visible'
    $ui.ConfirmButtons.Visibility = 'Visible'
    $ui.BtnConfirmGo.Visibility = 'Visible'
}

# The same sheet, offering the newer version. A copy the installer put in place can
# update itself; one that was only unpacked is pointed at the release page.
function Show-UpdateSheet {
    param($Installed = $null)
    $update = $script:Update
    if (-not $update -or $script:Mode -ne 'browse') { return }
    if ($null -eq $Installed) { $Installed = Test-DebloaterInstalled }
    # A release whose feed names no signed installer cannot be put in place from here,
    # so it is offered the way it is to an unpacked copy: on its page.
    if (-not $update.SetupUrl -or -not $update.Signature) { $Installed = $false }
    $script:Mode = 'confirm'
    $script:ConfirmAction = @{ Kind = 'update'; Installed = [bool]$Installed }
    Set-NavEnabled $false
    $ui = $script:Ui
    Reset-ConfirmSheet

    $lines = @()
    if ($Installed) {
        $download = T 'update.row.download.nosize'
        if ([int64]$update.SetupSize -gt 0) { $download = T 'update.row.download' (Format-DebloaterSize ([int64]$update.SetupSize)) }
        $lines += , @($download, (T 'update.row.download.note'), 0xE896)
        $lines += , @((T 'update.row.restart'), (T 'update.row.restart.note'), 0xE72C)
    } else {
        $lines += , @((T 'update.row.portable'), (T 'update.row.portable.note'), 0xE896)
    }
    $rows = New-Collection
    foreach ($entry in $lines) {
        $row = New-Object Debloater.Ui.SummaryVm
        $row.Glyph = Glyph $entry[2]
        $row.Text = $entry[0]
        $row.Note = $entry[1]
        $rows.Add($row)
    }
    $ui.ConfirmRows.ItemsSource = $rows
    $ui.ConfirmEyebrow.Text = Format-Caps (T 'update.eyebrow' (Get-DebloaterVersion), $update.Version)
    $ui.ConfirmEyebrow.Visibility = 'Visible'
    $ui.ConfirmTitle.Text = T 'update.title' $update.Version
    $ui.ConfirmSub.Text = Get-UpdateSummary $update
    Set-ConfirmFine ''
    $ui.BtnConfirmCancel.Content = T 'update.btn.later'
    $ui.BtnConfirmMore.Content = T 'update.btn.notes'
    $ui.BtnConfirmMore.Visibility = 'Visible'
    if ($Installed) { $ui.BtnConfirmGo.Content = T 'update.btn.now' } else { $ui.BtnConfirmGo.Content = T 'update.btn.get' }
    Open-ConfirmSheet
}

# The page of the release on GitHub. The address comes from GitHub's answer, so it is
# only opened when it really is a page of this project.
function Open-UpdatePage {
    $page = ''
    if ($script:Update) { $page = [string]$script:Update.Page }
    if (-not $page.StartsWith($script:RepoUrl + '/', [StringComparison]::OrdinalIgnoreCase)) { $page = $script:RepoUrl + '/releases/latest' }
    Start-Process $page
}

# The sheet while the installer is fetched: a bar in place of the rows and the buttons.
function Show-UpdateWorking {
    $ui = $script:Ui
    $script:ConfirmAction = @{ Kind = 'update-working' }
    $ui.ConfirmCard.Visibility = 'Collapsed'
    $ui.ConfirmButtons.Visibility = 'Collapsed'
    $ui.ConfirmMeter.Value = 0
    $ui.ConfirmMeter.Visibility = 'Visible'
    $ui.ConfirmTitle.Text = T 'update.work.download'
    $ui.ConfirmSub.Text = ' '
    Set-ConfirmFine (T 'update.work.fine')
}

function Set-UpdateProgress {
    param([int64]$Done, [int64]$Total, [string]$Stage)
    $ui = $script:Ui
    if ($Stage -eq 'check') {
        $ui.ConfirmTitle.Text = T 'update.work.check'
        $ui.ConfirmMeter.Value = 1
        return
    }
    if ($Total -le 0) { return }
    # As doubles on purpose: handed a whole number and a fraction, PowerShell rounds the
    # fraction to a whole number first, and the bar would stand at full from the start.
    $ui.ConfirmMeter.Value = [Math]::Min([double]1, [double]$Done / [double]$Total)
    $ui.ConfirmSub.Text = T 'update.work.progress' (Format-DebloaterSize $Done), (Format-DebloaterSize $Total)
}

function Show-UpdateFailed {
    param([string]$Message)
    $ui = $script:Ui
    $script:ConfirmAction = @{ Kind = 'update-failed' }
    $ui.ConfirmMeter.Visibility = 'Collapsed'
    $ui.ConfirmCard.Visibility = 'Collapsed'
    $ui.ConfirmTitle.Text = T 'update.fail.title'
    $ui.ConfirmSub.Text = $Message
    Set-ConfirmFine ''
    $ui.ConfirmButtons.Visibility = 'Visible'
    $ui.BtnConfirmCancel.Content = T 'update.btn.later'
    $ui.BtnConfirmMore.Visibility = 'Visible'
    $ui.BtnConfirmGo.Visibility = 'Collapsed'
    [void]$ui.BtnConfirmCancel.Focus()
}

# Update now: fetch the installer on another thread, check it, hand over to it and
# close. The installer waits for this window to be gone before it touches a file.
function Start-UpdateInstall {
    $update = $script:Update
    $action = $script:ConfirmAction
    if (-not $update -or -not $action -or $action.Kind -ne 'update') { return }
    if (-not $action.Installed) {
        Open-UpdatePage
        Hide-Confirm
        return
    }
    Show-UpdateWorking

    $progress = [hashtable]::Synchronized(@{ Done = [int64]0; Total = [int64]$update.SetupSize; Stage = 'download' })
    $wanted = @{}
    foreach ($property in $update.PSObject.Properties) { $wanted[$property.Name] = $property.Value }
    $shell = [powershell]::Create()
    [void]$shell.AddScript({
        param($ModulePath, $Lang, $Update, $Progress)
        Import-Module $ModulePath -Force
        Initialize-DebloaterLanguage $Lang
        Save-DebloaterUpdate -Update ([pscustomobject]$Update) -Progress $Progress
    }.ToString()).AddArgument((Join-Path $PSScriptRoot 'Debloater.Engine.psm1')).AddArgument((Get-DebloaterLanguage)).AddArgument($wanted).AddArgument($progress)
    $handle = $shell.BeginInvoke()
    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(60)
    $script:UpdateWork = @{ Shell = $shell; Handle = $handle; Timer = $timer; Progress = $progress }
    $timer.Add_Tick({
        Invoke-Guarded {
            $work = $script:UpdateWork
            if (-not $work) { return }
            Set-UpdateProgress ([int64]$work.Progress.Done) ([int64]$work.Progress.Total) ([string]$work.Progress.Stage)
            if (-not $work.Handle.IsCompleted) { return }
            $work.Timer.Stop()
            $script:UpdateWork = $null
            $file = ''
            $problem = ''
            try { $file = [string]@($work.Shell.EndInvoke($work.Handle))[-1] }
            catch {
                $problem = $_.Exception.Message
                if ($_.Exception.InnerException) { $problem = $_.Exception.InnerException.Message }
            }
            $work.Shell.Dispose()
            if ($problem -or -not $file -or -not (Test-Path -LiteralPath $file)) {
                if (-not $problem) { $problem = T 'update.fail.network' }
                Show-UpdateFailed $problem
                return
            }
            $script:Ui.ConfirmTitle.Text = T 'update.work.install'
            $script:Ui.ConfirmMeter.Value = 1
            Start-DebloaterUpdate $file
            # A moment for the last words to be read, then the window makes way.
            $closing = New-Object Windows.Threading.DispatcherTimer
            $closing.Interval = [TimeSpan]::FromMilliseconds(500)
            $closing.Add_Tick({ param($s, $e) $s.Stop(); $script:Window.Close() })
            $closing.Start()
        }
    })
    $timer.Start()
}

# The rows about updates on the Settings page.
function Update-UpdateSettings {
    param([string]$State)
    $ui = $script:Ui
    $ui.UpdateSwitch.Content = T 'settings.updates'
    $ui.UpdateSwitch.IsChecked = [bool]$script:UpdatesOn
    $ui.LinkUpdate.Content = T 'settings.updates.check'
    # A dry run and a demo stay off the internet, so there is nothing to press there.
    $ui.LinkUpdate.IsEnabled = ((Test-UpdateAllowed) -and $State -ne 'checking')
    $text = ''
    switch ($State) {
        'checking' { $text = T 'settings.updates.checking' }
        'failed'   { $text = T 'settings.updates.failed' }
        'none'     { $text = T 'settings.updates.none' }
    }
    if ($State -ne 'checking' -and $State -ne 'failed' -and $script:Update) { $text = T 'settings.updates.found' $script:Update.Version }
    $ui.UpdateStatus.Text = $text
}

# ================================================================ Keys

function Invoke-KeyDown {
    param($e)
    $control = ([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Control) -ne 0
    $typing = ([Windows.Input.Keyboard]::FocusedElement -is [Windows.Controls.TextBox])
    $onArea = ($script:CategoryIds -contains $script:CurrentPage)
    if ($control -and $e.Key -eq 'Return') {
        # Ctrl+Enter is always the main action of the screen you are on.
        if ($script:Mode -eq 'browse' -and @(Get-SelectedIds).Count -gt 0 -and ($onArea -or $script:CurrentPage -eq 'home')) { Show-Confirm }
        elseif ($script:Mode -eq 'confirm') { Invoke-ConfirmGo }
        elseif ($script:Mode -eq 'result') { Exit-ToBrowse }
        $e.Handled = $true
    } elseif ($control -and $e.Key -eq 'R' -and $script:Mode -eq 'browse') {
        Reset-ToRecommended
        if ($script:CurrentPage -eq 'home') { Build-Home }
        $e.Handled = $true
    } elseif ($control -and $e.Key -eq 'A' -and $script:Mode -eq 'browse' -and -not $typing -and $onArea) {
        Set-ItemsSelected @(Get-TodoItems $script:CurrentPage) $true
        $e.Handled = $true
    } elseif ($control -and $e.Key -eq 'F' -and $script:Mode -eq 'browse' -and $onArea) {
        [void]$script:Ui.SearchBox.Focus()
        $script:Ui.SearchBox.SelectAll()
        $e.Handled = $true
    } elseif ($e.Key -eq 'Escape') {
        if ($script:Mode -eq 'confirm') { Hide-Confirm; $e.Handled = $true }
        elseif ($typing -and $script:Ui.SearchBox.Text) { $script:Ui.SearchBox.Text = ''; $e.Handled = $true }
        elseif ($script:Mode -eq 'browse' -and $script:CurrentPage -ne 'home') { Show-Page 'home'; $e.Handled = $true }
    }
}

# ================================================================ Self-test (dry run only)

# Puts a picture of the window on a see-through ground with the rounded corners and the
# shadow Windows 11 gives a window, which is how it looks on a desktop and what makes
# it sit well on a page. The shadow is a layer of its own behind the picture, so the
# picture itself stays sharp.
function ConvertTo-FramedPicture {
    param($Bitmap, [double]$Width, [double]$Height, [double]$Scale)
    $margin = 48
    $radius = New-Object Windows.CornerRadius(10)
    $holder = New-Object Windows.Controls.Grid
    $holder.Width = $Width + 2 * $margin
    $holder.Height = $Height + 2 * $margin

    $shadow = New-Object Windows.Controls.Border
    $shadow.Margin = New-Object Windows.Thickness($margin)
    $shadow.CornerRadius = $radius
    $shadow.Background = [Windows.Media.Brushes]::Black
    $cast = New-Object Windows.Media.Effects.DropShadowEffect
    $cast.BlurRadius = 44; $cast.ShadowDepth = 14; $cast.Direction = 270; $cast.Opacity = 0.5; $cast.Color = [Windows.Media.Colors]::Black
    $shadow.Effect = $cast
    [void]$holder.Children.Add($shadow)

    $face = New-Object Windows.Controls.Border
    $face.Margin = New-Object Windows.Thickness($margin)
    $face.CornerRadius = $radius
    $face.Background = New-Object Windows.Media.ImageBrush($Bitmap)
    $face.BorderBrush = New-Object Windows.Media.SolidColorBrush([Windows.Media.Color]::FromArgb(0x30, 0xFF, 0xFF, 0xFF))
    $face.BorderThickness = New-Object Windows.Thickness(1)
    [void]$holder.Children.Add($face)

    $size = New-Object Windows.Size($holder.Width, $holder.Height)
    $holder.Measure($size)
    $holder.Arrange((New-Object Windows.Rect($size)))
    $holder.UpdateLayout()
    $framed = New-Object Windows.Media.Imaging.RenderTargetBitmap([int]($holder.Width * $Scale), [int]($holder.Height * $Scale), (96 * $Scale), (96 * $Scale), [Windows.Media.PixelFormats]::Pbgra32)
    $framed.Render($holder)
    return $framed
}

# Saves a picture of the window. It waits for whatever is moving to come to rest first;
# -Now takes it as it is, for a picture from the middle of something.
function Save-DebloaterScreenshot {
    param([string]$Path, [switch]$Now)
    # Pictures for the README (DEBLOATER_SHOTS=readme, see scripts\build-pictures.ps1) are
    # of the window as people get it, so the tag that says "Demo" is not in them. The
    # window shows the tag again whenever it changes page, so it is made see-through.
    $forReadme = ($env:DEBLOATER_SHOTS -eq 'readme')
    if ($forReadme) { $script:Ui.ModeRow.Opacity = 0 }
    if ($Now) { Invoke-UiIdle } else { Wait-MotionSettled }
    $root = $script:Window.Content
    # The layout may be drawn larger than it is laid out; the picture is of what is drawn.
    $width = [int][Math]::Ceiling($root.ActualWidth * $script:Zoom)
    $height = [int][Math]::Ceiling($root.ActualHeight * $script:Zoom)
    # They are also drawn at twice the size, so they stay sharp on a dense screen.
    $scale = 1
    if ($forReadme) { $scale = 2 }
    $bitmap = New-Object Windows.Media.Imaging.RenderTargetBitmap(($width * $scale), ($height * $scale), (96 * $scale), (96 * $scale), [Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($root)
    if ($forReadme) { $bitmap = ConvertTo-FramedPicture $bitmap $width $height $scale }
    $encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream = [IO.File]::Create($Path)
    try { $encoder.Save($stream) } finally { $stream.Dispose() }
}

# Keeps the window alive until a condition holds. With -Quiet, running out of time is
# not an error, which makes it a plain pause that still lets animations move.
function Wait-DebloaterUi {
    param([scriptblock]$Until, [int]$TimeoutSeconds = 180, [switch]$Quiet)
    $end = (Get-Date).AddSeconds($TimeoutSeconds)
    while (-not (& $Until)) {
        if ($script:SelfTestError) { throw $script:SelfTestError }
        if ((Get-Date) -gt $end) {
            if ($Quiet) { return }
            throw 'Timed out waiting for the window.'
        }
        Invoke-UiIdle
        Start-Sleep -Milliseconds 40
    }
}

function Invoke-TestClick {
    param($Element)
    $Element.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
    Invoke-UiIdle
    if ($script:SelfTestError) { throw $script:SelfTestError }
}

# Goes to a page the way a person does: an area through its row on the overview,
# History and Settings through the top bar, the overview through the page's own
# Overview button.
function Select-TestNav {
    param([string]$Id)
    $ui = $script:Ui
    if ($script:CurrentPage -ne 'home' -and $Id -notin 'history', 'settings') {
        $back = $ui.BtnBack
        if ($script:CurrentPage -eq 'history') { $back = $ui.BtnHistoryBack }
        elseif ($script:CurrentPage -eq 'settings') { $back = $ui.BtnSettingsBack }
        Invoke-TestClick $back
        if ($script:CurrentPage -ne 'home') { throw 'The Overview button did not return to the overview.' }
    }
    if ($Id -eq 'history') { Invoke-TestClick $ui.BtnHistory }
    elseif ($Id -eq 'settings') { Invoke-TestClick $ui.BtnSettings }
    elseif ($Id -ne 'home') {
        $card = @(Find-Visuals $ui.HomeCards ([Windows.Controls.Button]) | Where-Object { $_.DataContext.Id -eq $Id })[0]
        if (-not $card) { throw "The overview has no row for $Id." }
        Invoke-TestClick $card
    }
    if ($script:CurrentPage -ne $Id) { throw "Navigation to $Id did not happen." }
}

# Every control of one type below an element, found the way a person's click finds it.
function Find-Visuals {
    param($Parent, [type]$Type)
    $found = @()
    $count = [Windows.Media.VisualTreeHelper]::GetChildrenCount($Parent)
    for ($i = 0; $i -lt $count; $i++) {
        $child = [Windows.Media.VisualTreeHelper]::GetChild($Parent, $i)
        if ($child -is $Type) { $found += $child }
        $found += @(Find-Visuals $child $Type)
    }
    return $found
}

# How many times the window drew itself during a short wait. A mistake in the layout
# file can stop the drawing altogether: nothing moves and nothing new appears, yet no
# error is raised. Zero here is how that gets noticed.
function Get-DrawnFrames {
    param([int]$Milliseconds = 300)
    $script:DrawnFrames = 0
    $handler = [EventHandler] { $script:DrawnFrames++ }
    [Windows.Media.CompositionTarget]::add_Rendering($handler)
    try {
        $clock = [Diagnostics.Stopwatch]::StartNew()
        while ($clock.ElapsedMilliseconds -lt $Milliseconds) { Invoke-UiIdle; Start-Sleep -Milliseconds 20 }
    } finally {
        [Windows.Media.CompositionTarget]::remove_Rendering($handler)
    }
    return $script:DrawnFrames
}

# Puts a control through its visual states. Hover and press effects only play under a
# real pointer, so this is how a mistake in one of them is caught without one.
function Test-VisualStates {
    param($Control, [string[]]$States)
    $name = $Control.GetType().Name
    if ($Control.Name) { $name = $Control.Name }
    # Something that has only just been shown may not have been drawn yet.
    $Control.UpdateLayout()
    foreach ($state in $States) {
        if (-not [Windows.VisualStateManager]::GoToState($Control, $state, $true)) {
            $parts = [Windows.Media.VisualTreeHelper]::GetChildrenCount($Control)
            throw ($name + ' has no visual state called ' + $state + ' (visible: ' + $Control.IsVisible + ', drawn parts: ' + $parts + ', width: ' + [int]$Control.ActualWidth + ')')
        }
        Invoke-UiIdle
        if ($script:SelfTestError) { throw ($name + ' / ' + $state + ': ' + $script:SelfTestError) }
    }
}

# Test aid: carries out an action and, when DEBLOATER_FILM is set, saves a strip of
# pictures taken while it plays, so the movement itself can be looked at. -Around
# films only one element and a little of what surrounds it, at full size.
function Save-DebloaterFilmstrip {
    param([string]$Name, [scriptblock]$Action, [int]$Frames = 6, [int]$Pause = 30, [switch]$Now, $Around, [int]$Columns = 3)
    if (-not $env:DEBLOATER_FILM) { & $Action; return }
    if (-not $Now) { Wait-MotionSettled }
    $root = $script:Window.Content
    $width = [int][Math]::Ceiling($root.ActualWidth * $script:Zoom)
    $height = [int][Math]::Ceiling($root.ActualHeight * $script:Zoom)
    $crop = $null
    if ($Around) {
        $corner = $Around.TranslatePoint((New-Object Windows.Point(0, 0)), $root)
        $left = [Math]::Max(0, [int](($corner.X - 46) * $script:Zoom))
        $top = [Math]::Max(0, [int](($corner.Y - 46) * $script:Zoom))
        $right = [Math]::Min($width, [int](($corner.X + $Around.ActualWidth + 46) * $script:Zoom))
        $bottom = [Math]::Min($height, [int](($corner.Y + $Around.ActualHeight + 46) * $script:Zoom))
        $crop = New-Object Windows.Int32Rect($left, $top, ($right - $left), ($bottom - $top))
    }
    $clock = [Diagnostics.Stopwatch]::StartNew()
    & $Action
    $shots = @()
    $times = @()
    for ($i = 0; $i -lt $Frames; $i++) {
        Invoke-UiIdle
        $bitmap = New-Object Windows.Media.Imaging.RenderTargetBitmap($width, $height, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
        $bitmap.Render($root)
        if ($crop) { $bitmap = New-Object Windows.Media.Imaging.CroppedBitmap($bitmap, $crop) }
        $shots += $bitmap
        $times += [int]$clock.ElapsedMilliseconds
        # Sleeping would stop the clock that animations run on, so wait with the window alive.
        $until = $clock.ElapsedMilliseconds + $Pause
        while ($clock.ElapsedMilliseconds -lt $until) { Invoke-UiIdle; Start-Sleep -Milliseconds 10 }
    }
    $columns = $Columns
    $cellWidth = 570
    if ($crop) { $width = $crop.Width; $height = $crop.Height; $cellWidth = $width }
    $cellHeight = [int]($height * $cellWidth / $width)
    $rows = [int][Math]::Ceiling($Frames / $columns)
    $sheet = New-Object Windows.Media.DrawingVisual
    $dc = $sheet.RenderOpen()
    $dc.DrawRectangle([Windows.Media.Brushes]::Black, $null, (New-Object Windows.Rect(0, 0, ($columns * $cellWidth), ($rows * ($cellHeight + 22)))))
    $typeface = New-Object Windows.Media.Typeface('Segoe UI')
    for ($i = 0; $i -lt $shots.Count; $i++) {
        $x = ($i % $columns) * $cellWidth
        $y = [Math]::Floor($i / $columns) * ($cellHeight + 22)
        $dc.DrawImage($shots[$i], (New-Object Windows.Rect($x, ($y + 22), $cellWidth, $cellHeight)))
        $label = New-Object Windows.Media.FormattedText(([string]$times[$i] + ' ms'), [Globalization.CultureInfo]::InvariantCulture, [Windows.FlowDirection]::LeftToRight, $typeface, 13, [Windows.Media.Brushes]::White)
        $dc.DrawText($label, (New-Object Windows.Point(($x + 8), ($y + 2))))
    }
    $dc.Close()
    $strip = New-Object Windows.Media.Imaging.RenderTargetBitmap(($columns * $cellWidth), ($rows * ($cellHeight + 22)), 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
    $strip.Render($sheet)
    $encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($strip))
    $stream = [IO.File]::Create((Join-Path $script:SelfTestDir ('film-' + $Name + '.png')))
    try { $encoder.Save($stream) } finally { $stream.Dispose() }
}

# Presses Debloat, confirms and waits for the run to end, saving a picture of each
# stage. Leaves the finished lanes on screen and adds what went through to $OkIds.
function Invoke-TestApply {
    param([string]$Dir, [string]$Prefix, [hashtable]$OkIds)
    $ui = $script:Ui
    Save-DebloaterFilmstrip ($Prefix + 'confirm') { Invoke-TestClick $ui.BtnDebloat }
    if ($script:Mode -ne 'confirm') { throw 'Debloat did not ask for confirmation.' }
    Save-DebloaterScreenshot (Join-Path $Dir ($Prefix + 'confirm.png'))
    Save-DebloaterFilmstrip ($Prefix + 'run-start') { Invoke-TestClick $ui.BtnConfirmGo } 9 60
    if ($script:Mode -notin 'progress', 'result') { throw 'Debloat now did not start.' }
    if ($ui.ViewProgress.Visibility -ne 'Visible' -or $script:Lanes.Count -eq 0) { throw 'The run did not show its lanes.' }

    # A picture from the middle of the run, with a lane lit up.
    Wait-DebloaterUi { $script:Mode -eq 'result' -or $script:Run.Finished -ge [Math]::Ceiling($script:Run.Total * 0.45) }
    if ($script:Mode -eq 'progress') {
        if (@($script:Lanes | Where-Object { $_.IsActive }).Count -ne 1) { throw 'No lane was lit up in the middle of the run.' }
        # The overall bar must be part of the way along, not empty and not full.
        if ($script:BarTarget -le 0 -or $script:BarTarget -ge 1) { throw 'The overall bar did not follow the run.' }
        Save-DebloaterScreenshot (Join-Path $Dir ($Prefix + 'progress.png')) -Now
    }
    if ($env:DEBLOATER_FILM) {
        # The last moments of the run and what follows, as a strip of pictures.
        Wait-DebloaterUi { $script:Mode -ne 'progress' -or $script:Run.Finished -ge ($script:Run.Total - 1) }
        Save-DebloaterFilmstrip ($Prefix + 'finish') { } 12 90 -Now
    }
    Wait-DebloaterUi { $script:Mode -eq 'result' }
    foreach ($lane in $script:Lanes) {
        if (-not $lane.IsDone -or $lane.Count -ne $lane.Total) { throw ('The lane ' + $lane.Id + ' did not finish.') }
    }
    if ($ui.ProgressButtons.Visibility -ne 'Visible') { throw 'The finished run did not offer Details and Done.' }
    # Let the ticks finish popping in before the picture.
    Wait-DebloaterUi { $false } 1 -Quiet
    Save-DebloaterScreenshot (Join-Path $Dir ($Prefix + 'progress-done.png'))
    foreach ($step in $script:Steps) { if ($step.Status -eq 'ok') { $OkIds[$step.Id] = $true } }
}

# Walks through the whole window without changing anything and saves a screenshot of
# each stage. It raises the same click and selection events a person would, so the
# real handlers run. Used by test\Run-Tests.ps1 and to make the pictures in the README.
function Invoke-DebloaterSelfTest {
    $dir = $script:SelfTestDir
    [void](New-Item -ItemType Directory -Force -Path $dir)
    $report = [ordered]@{ ok = $false; error = ''; done = 0; failed = 0; skipped = 0; undone = 0; finishedHome = $false; failures = @() }
    $ui = $script:Ui
    try {
        if ((Get-DrawnFrames) -eq 0) { throw 'The window is not drawing itself: nothing would move or update.' }

        # The window opens with exactly the recommended changes ticked.
        $recommended = @(Get-TodoItems | Where-Object { $_.Recommended }).Count
        if (@(Get-SelectedIds).Count -ne $recommended) { throw 'The recommended changes were not ticked on opening.' }
        Save-DebloaterScreenshot (Join-Path $dir 'home.png')

        # Hover, press and the other visual states of everything on the overview.
        $common = @('MouseOver', 'Pressed', 'MouseOver', 'Normal')
        # On a PC with nothing recommended left, a tick stands where the button would be.
        if ($ui.BtnDebloat.IsVisible) {
            # One full turn of the light around the button, when filming.
            Save-DebloaterFilmstrip 'button' { } 12 400 -Now -Around $ui.BtnDebloat -Columns 6
            Test-VisualStates $ui.BtnDebloat ($common + 'Disabled' + 'Normal')
        }
        Test-VisualStates $ui.BtnHistory ($common + 'Disabled' + 'Normal')
        Test-VisualStates $ui.BtnMin $common
        Test-VisualStates $ui.BtnClose $common
        foreach ($button in @(Find-Visuals $ui.HomeCards ([Windows.Controls.Button]))) { Test-VisualStates $button $common }
        if ($ui.OptionalSwitch.Visibility -eq 'Visible') { Test-VisualStates $ui.OptionalSwitch ($common + 'Checked' + 'Unchecked') }

        # Every area, opened from its row.
        foreach ($page in 'apps', 'ads', 'edge', 'look', 'onedrive') {
            Select-TestNav $page
            Save-DebloaterScreenshot (Join-Path $dir ('page-' + $page + '.png'))
        }
        Select-TestNav 'apps'

        $rows = @(Find-Visuals $ui.ListGroups ([Windows.Controls.CheckBox]))
        if ($rows.Count -gt 0) {
            # Ticking and unticking a row changes the selection.
            $row = $rows[0]
            $id = $row.DataContext.Id
            $was = [bool]$script:Selected[$id]
            $row.IsChecked = (-not $was)
            Invoke-UiIdle
            if ([bool]$script:Selected[$id] -eq $was) { throw 'Clicking a row did not change the selection.' }
            $row.IsChecked = $was
            Invoke-UiIdle
            if ([bool]$script:Selected[$id] -ne $was) { throw 'Clicking a row again did not change it back.' }

            # The visual states of a row and of the buttons around the list.
            $rowState = 'Unchecked'
            if ($row.IsChecked) { $rowState = 'Checked' }
            Test-VisualStates $row ($common + 'Checked' + 'Unchecked' + $rowState)
            Test-VisualStates $ui.BtnBack ($common + 'Disabled' + 'Normal')
            Test-VisualStates $ui.BtnSelectAll ($common + 'Disabled' + 'Normal')
            Test-VisualStates $ui.BtnDebloatSmall ($common + 'Disabled' + 'Normal')

            # Opening "What this changes" must not change the tick.
            $toggle = @(Find-Visuals $row ([Windows.Controls.Primitives.ToggleButton]))[0]
            Test-VisualStates $toggle ($common + 'Checked' + 'Unchecked')
            $toggle.IsChecked = $true
            Invoke-UiIdle
            if (-not $row.DataContext.IsExpanded) { throw 'The details panel did not open.' }
            if ([bool]$script:Selected[$id] -ne $was) { throw 'Opening the details changed the tick.' }
            Save-DebloaterScreenshot (Join-Path $dir 'details.png')
            $toggle.IsChecked = $false

            # Clear and Select all on the page.
            Invoke-TestClick $ui.BtnSelectNone
            if (@(Get-SelectedIds | Where-Object { $script:ById[$_].Page -eq 'apps' }).Count -ne 0) { throw 'Clear did not untick the page.' }
            Invoke-TestClick $ui.BtnSelectAll
            if (@(Get-SelectedIds | Where-Object { $script:ById[$_].Page -eq 'apps' }).Count -ne @(Get-TodoItems 'apps').Count) { throw 'Select all picked the wrong number of items.' }

            # Search filters the list.
            $ui.SearchBox.Text = 'zzzz-no-such-item'
            Invoke-UiIdle
            if ($ui.ListGroups.Items.Count -ne 0) { throw 'Search did not filter the list.' }
            $ui.SearchBox.Text = ''
            Invoke-UiIdle
            if ($ui.ListGroups.Items.Count -eq 0) { throw 'Clearing the search did not restore the list.' }

            # The small Debloat button on an area opens the confirmation; Cancel closes it.
            Invoke-TestClick $ui.BtnDebloatSmall
            if ($script:Mode -ne 'confirm') { throw 'Debloat on an area page did not ask for confirmation.' }
            Test-VisualStates $ui.BtnConfirmGo ($common + 'Disabled' + 'Normal')
            Test-VisualStates $ui.BtnConfirmCancel $common
            Invoke-TestClick $ui.BtnConfirmCancel
            if ($script:Mode -ne 'browse') { throw 'Cancel did not close the confirmation.' }
        }

        # Back returns to the overview, and a row opens its area.
        Save-DebloaterFilmstrip 'to-overview' { Invoke-TestClick $ui.BtnBack }
        if ($script:CurrentPage -ne 'home') { throw 'Back did not return to the overview.' }
        $card = @(Find-Visuals $ui.HomeCards ([Windows.Controls.Button]))[0]
        Save-DebloaterFilmstrip 'to-area' { Invoke-TestClick $card }
        if ($script:CurrentPage -ne $card.DataContext.Id) { throw 'A row did not open its area.' }
        Select-TestNav 'home'

        # The switch adds every optional item, and takes them out again.
        $everything = @(Get-TodoItems).Count
        if ($ui.OptionalSwitch.Visibility -eq 'Visible') {
            $ui.OptionalSwitch.IsChecked = $true
            Invoke-TestClick $ui.OptionalSwitch
            if (@(Get-SelectedIds).Count -ne $everything) { throw 'Switching optional items on did not tick everything.' }
            Save-DebloaterScreenshot (Join-Path $dir 'home-all.png')
            $ui.OptionalSwitch.IsChecked = $false
            Invoke-TestClick $ui.OptionalSwitch
            if (@(Get-SelectedIds | Where-Object { -not $script:ById[$_].Recommended }).Count -ne 0) { throw 'Switching optional items off left some ticked.' }
        }

        # A newer version: the pill in the top bar, the sheet it opens, and the sheet
        # while it downloads. The release is made up, so nothing is asked of the internet.
        $script:Update = [pscustomobject]@{
            Version = '9.9.9'; Notes = "Revert brings removed apps back.`nFixes for Windows 11 Home."
            Page = $script:RepoUrl + '/releases/tag/v9.9.9'; Setup = 'WindowsDebloaterSetup-9.9.9.exe'; SetupSize = [int64]612000
            SetupUrl = $script:RepoUrl + '/releases/download/v9.9.9/WindowsDebloaterSetup-9.9.9.exe'
            Sha256 = ('0' * 64); Signature = 'made-up'
        }
        Update-UpdatePill
        if ($ui.BtnUpdate.Visibility -ne 'Visible') { throw 'A newer version did not bring the pill into the top bar.' }
        Test-VisualStates $ui.BtnUpdate @('MouseOver', 'Pressed', 'MouseOver', 'Normal')
        Show-UpdateSheet $true
        if ($script:Mode -ne 'confirm' -or $ui.ConfirmEyebrow.Visibility -ne 'Visible' -or $ui.BtnConfirmMore.Visibility -ne 'Visible') { throw 'The update sheet did not open in full.' }
        Save-DebloaterScreenshot (Join-Path $dir 'update.png')
        Show-UpdateWorking
        Set-UpdateProgress 404000 612000 'download'
        Save-DebloaterScreenshot (Join-Path $dir 'update-working.png')
        Hide-Confirm
        if ($script:Mode -ne 'confirm') { throw 'The update sheet could be closed in the middle of a download.' }
        Show-UpdateFailed (T 'update.fail.signature')
        Save-DebloaterScreenshot (Join-Path $dir 'update-failed.png')
        Invoke-TestClick $ui.BtnConfirmCancel
        if ($script:Mode -ne 'browse') { throw 'Later did not close the update sheet.' }
        # Opened by the pill, as a person would. Only an installed copy updates in place.
        Invoke-TestClick $ui.BtnUpdate
        if ($script:Mode -ne 'confirm') { throw 'The pill did not open the update sheet.' }
        $expected = 'update.btn.get'
        if (Test-DebloaterInstalled) { $expected = 'update.btn.now' }
        if ([string]$ui.BtnConfirmGo.Content -ne (T $expected)) { throw 'The update sheet offers the wrong thing for this copy.' }
        Invoke-TestClick $ui.BtnConfirmCancel
        $script:Update = $null
        Update-UpdatePill
        if ($ui.BtnUpdate.Visibility -eq 'Visible') { throw 'The pill stayed after the update was gone.' }
        $report.updateShown = $true

        # First run: the recommended changes only, the way most people will use it.
        $okIds = @{}
        if (@(Get-SelectedIds).Count -gt 0) {
            Invoke-TestApply $dir '' $okIds
            Invoke-TestClick $ui.BtnProgressDone
            if ($script:Mode -ne 'browse' -or $script:CurrentPage -ne 'home') { throw 'Done did not return to the overview.' }

            if ($script:Demo) {
                # The overview is now a finished board, with a banner and a medal.
                if (-not (Test-HomeFinished)) { throw 'The overview still lists recommended changes after applying them.' }
                if ($ui.HomeBanner.Visibility -ne 'Visible') { throw 'The finished overview has no banner.' }
                if ($ui.HomeMedal.Visibility -ne 'Visible' -or $ui.BtnDebloat.Visibility -eq 'Visible') { throw 'The Debloat button did not give way to the medal.' }
                $report.finishedHome = $true
                Save-DebloaterScreenshot (Join-Path $dir 'home-done.png')

                # Ticking something optional brings the button back.
                if ($ui.OptionalSwitch.Visibility -eq 'Visible') {
                    $ui.OptionalSwitch.IsChecked = $true
                    Invoke-TestClick $ui.OptionalSwitch
                    if ($ui.BtnDebloat.Visibility -ne 'Visible') { throw 'Ticking optional items did not bring the Debloat button back.' }
                    $ui.OptionalSwitch.IsChecked = $false
                    Invoke-TestClick $ui.OptionalSwitch
                    if ($ui.HomeMedal.Visibility -ne 'Visible') { throw 'Unticking the optional items did not bring the medal back.' }
                }

                # Revert: asks first, plays the same screen, then lists things to do again.
                if ($ui.BtnHomeUndo.Visibility -ne 'Visible') { throw 'The finished overview does not offer Revert.' }
                Invoke-TestClick $ui.BtnHomeUndo
                if ($script:Mode -ne 'confirm') { throw 'Revert did not ask for confirmation.' }
                Save-DebloaterScreenshot (Join-Path $dir 'undo-confirm.png')
                Invoke-TestClick $ui.BtnConfirmCancel
                if ($script:Mode -ne 'browse' -or -not (Test-HomeFinished)) { throw 'Cancel did not leave the finished overview alone.' }
                Invoke-TestClick $ui.BtnHomeUndo
                Invoke-TestClick $ui.BtnConfirmGo
                Wait-DebloaterUi { $script:Mode -eq 'result' }
                $report.undone = @($script:Steps | Where-Object { $_.Status -eq 'ok' }).Count
                if ($report.undone -eq 0) { throw 'Reverting did nothing.' }
                Wait-DebloaterUi { $false } 1 -Quiet
                Save-DebloaterScreenshot (Join-Path $dir 'undo-done.png')
                Invoke-TestClick $ui.BtnProgressDone
                if (Test-HomeFinished) { throw 'The overview still looks finished after the run was reverted.' }
                if ($ui.HomeHead.Visibility -ne 'Visible' -or $ui.BtnDebloat.Visibility -ne 'Visible') { throw 'The overview did not go back to listing what there is to do.' }
            }
        }

        # Second run: everything that is left, optional items included.
        Set-ItemsSelected @(Get-TodoItems) $true
        Build-Home
        if (@(Get-SelectedIds).Count -gt 0) {
            Invoke-TestApply $dir 'all-' $okIds
            # Details opens the full list of steps.
            Invoke-TestClick $ui.BtnProgressDetails
            if ($ui.ViewResult.Visibility -ne 'Visible') { throw 'Details did not open the list of steps.' }
            Save-DebloaterScreenshot (Join-Path $dir 'result.png')
            Invoke-TestClick $ui.BtnDone
            if ($script:Mode -ne 'browse' -or $script:CurrentPage -ne 'home') { throw 'Done did not return to the overview.' }
            if ($script:Demo) {
                if (@(Get-TodoItems).Count -ne 0) { throw 'Something was still listed after everything had been applied.' }
                Save-DebloaterScreenshot (Join-Path $dir 'home-done-all.png')
            }
        }
        foreach ($step in $script:Steps) {
            if ($step.Status -eq 'failed') { $report.failed++; $report.failures += ($step.Id + ': ' + $step.Message) }
            elseif ($step.Status -ne 'ok') { $report.skipped++ }
        }
        # Every item that went through a run successfully, counted once.
        $report.done = $okIds.Count

        Select-TestNav 'history'
        Save-DebloaterScreenshot (Join-Path $dir 'history.png')

        # Settings: switch theme and language through the real rows.
        Select-TestNav 'settings'
        Save-DebloaterScreenshot (Join-Path $dir 'settings.png')
        $wanted = 'light'
        if ($script:EffectiveTheme -eq 'light') { $wanted = 'dark' }
        $themeRow = @(Find-Visuals $ui.ThemeChoices ([Windows.Controls.Button]) | Where-Object { $_.DataContext.Id -eq $wanted })[0]
        Test-VisualStates $themeRow @('MouseOver', 'Pressed', 'MouseOver', 'Normal')
        Test-VisualStates $ui.LinkRepo @('MouseOver', 'Pressed', 'MouseOver', 'Normal')
        Invoke-TestClick $themeRow
        if ($script:EffectiveTheme -ne $wanted) { throw 'The theme row did not switch theme.' }
        Select-TestNav 'home'
        Save-DebloaterScreenshot (Join-Path $dir ('home-' + $wanted + '.png'))
        Select-TestNav 'ads'
        Save-DebloaterScreenshot (Join-Path $dir ('page-ads-' + $wanted + '.png'))

        Select-TestNav 'settings'
        $languageRow = @(Find-Visuals $ui.LangChoices ([Windows.Controls.Button]) | Where-Object { $_.DataContext.Id -eq 'tr' })[0]
        Invoke-TestClick $languageRow
        if ((Get-DebloaterLanguage) -ne 'tr') { throw 'The language row did not switch language.' }
        Select-TestNav 'home'
        Save-DebloaterScreenshot (Join-Path $dir 'home-tr.png')
        if ((Get-DrawnFrames) -eq 0) { throw 'The window stopped drawing itself somewhere along the way.' }
        if ($script:SelfTestError) { throw $script:SelfTestError }
        $report.ok = $true
    } catch {
        $report.error = $_.Exception.Message + ' @ ' + $_.ScriptStackTrace
    }
    Write-DebloaterJson ([pscustomobject]$report) (Join-Path $dir 'selftest.json')
    $script:Window.Close()
}

# ================================================================ Window

function Show-DebloaterWindow {
    param([switch]$DryRun, [switch]$Demo, [string]$SelfTestDir, [string]$Theme)

    $script:SelfTestDir = $SelfTestDir
    $script:SelfTestError = $null
    # A self-test must never change the PC, whatever else was passed.
    $script:DryRun = ([bool]$DryRun -or [bool]$SelfTestDir)
    $script:Demo = [bool]$Demo
    $script:Catalog = @(Get-DebloaterCatalog)
    $script:ById = @{}
    foreach ($item in $script:Catalog) { $script:ById[$item.Id] = $item }
    $script:State = @{}
    foreach ($item in $script:Catalog) { $script:State[$item.Id] = [pscustomobject]@{ State = 'absent' } }
    $script:Selected = @{}
    $script:PageVms = @{}
    $script:Steps = New-Collection
    $script:StepById = @{}
    $script:Mode = 'loading'
    $script:CurrentPage = 'home'
    $script:HomeCountShown = -1
    $script:LightLeft = 0
    $script:Run = $null
    $script:LastRunDir = $null
    $script:LastApplied = $null
    $script:AppliedIds = @{}
    $script:DemoDone = @{}
    $script:Lanes = New-Collection
    $script:LaneByItem = @{}
    $script:LaneProblems = @{}
    $script:ConfirmAction = $null
    $script:Update = $null
    $script:UpdateJob = $null
    $script:UpdateWork = $null
    $script:UpdatesOn = $true
    $script:UpdateChecked = ''
    $script:BarTarget = 0
    $script:TickBusy = $false
    $script:MotionUntil = [DateTime]::MinValue
    $script:Zoom = 1
    $script:ScanJob = $null
    $script:Feed = New-Collection
    $script:LaneParts = @{}
    $script:FaultShown = $false
    $script:CurrentView = ''
    # No movement when Windows is set to show none, when the PC draws without a graphics
    # card, or when asked for with DEBLOATER_MOTION=0.
    $script:Motion = ([Windows.SystemParameters]::ClientAreaAnimation -and
        ([Windows.Media.RenderCapability]::Tier -shr 16) -gt 0 -and $env:DEBLOATER_MOTION -ne '0')
    $script:Timer = $null
    $script:Scanned = $false

    [Debloater.Ui.Win32]::SetAppId('Coursion.WindowsDebloater')
    $xaml = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'ui\MainWindow.xaml') -Raw -Encoding UTF8
    $script:Window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$xaml)))
    $names = @(
        'Root', 'TopBar', 'BrandName', 'ModeRow', 'ModeTag', 'BtnHistory', 'BtnSettings',
        'BtnMin', 'BtnMax', 'MaxGlyph', 'BtnClose', 'LoadingText', 'LoadingHalo', 'HistoryScroll',
        'HomeHead', 'HomeEyebrow', 'HomeTitle', 'HomeSub', 'HomeBanner', 'HomeBannerTitle', 'HomeBannerSub', 'BtnHomeUndo',
        'HomeCards', 'HomePanelLabel', 'HomeCount', 'HomeReady', 'HomeReadySub', 'BtnDebloat', 'HomeMedal', 'OptionalSwitch',
        'BtnBack', 'ListOrb', 'ListTitle', 'ListIntro', 'SearchBox', 'BtnSelectAll', 'BtnSelectNone', 'ListScroll', 'ListGroups',
        'ListEmpty', 'ListEmptyBadge', 'ListEmptyGlyph', 'ListEmptyTitle', 'ListEmptyText', 'DoneLabel', 'DoneCard', 'DoneItems',
        'BtnDebloatSmall', 'BarTitle', 'BarSub',
        'ProgressEyebrow', 'ProgressTitle', 'ProgressCount', 'ProgressBar', 'ProgressNote', 'ProgressLanes', 'ProgressFeed', 'ProgressIntro',
        'ProgressButtons', 'BtnProgressDetails', 'BtnProgressDone',
        'ResultBadge', 'ResultGlyph', 'ResultTitle', 'ResultSummary', 'ResultStats', 'ResultNotes', 'ResultScroll', 'ResultSteps', 'BtnOpenLog', 'BtnDone',
        'BtnHistoryBack', 'HistoryOrb', 'HistoryTitle', 'HistoryIntro', 'HistoryRuns', 'HistoryEmpty', 'HistoryEmptyTitle', 'HistoryEmptyText',
        'BtnSettingsBack', 'SettingsOrb', 'SettingsTitle', 'SettingsIntro', 'SettingsLangLabel', 'LangChoices', 'SettingsThemeLabel', 'ThemeChoices',
        'SettingsAboutLabel', 'AboutName', 'AboutVersion', 'AboutCopyright', 'AboutPrivacy', 'LinkRepo', 'LinkChanges', 'LinkData',
        'LinkLicence', 'LinkSite', 'LinkSupport',
        'ConfirmOverlay', 'ConfirmSheet', 'ConfirmEyebrow', 'ConfirmTitle', 'ConfirmSub', 'ConfirmCard', 'ConfirmRows', 'ConfirmMeter', 'ConfirmFine',
        'ConfirmButtons', 'BtnConfirmCancel', 'BtnConfirmMore', 'BtnConfirmGo', 'BtnUpdate', 'UpdateSwitch', 'LinkUpdate', 'UpdateStatus'
    ) + $script:ViewNames
    foreach ($name in $names) {
        $script:Ui[$name] = $script:Window.FindName($name)
        if (-not $script:Ui[$name]) { throw "The window layout has no element named $name." }
    }
    $ui = $script:Ui

    # The icon is read into memory, so the file itself stays free while the window is open.
    $icon = Join-Path $PSScriptRoot 'ui\icon.ico'
    if (Test-Path -LiteralPath $icon) {
        try {
            $script:IconStream = New-Object IO.MemoryStream(, [IO.File]::ReadAllBytes($icon))
            $script:Window.Icon = [Windows.Media.Imaging.BitmapFrame]::Create($script:IconStream,
                [Windows.Media.Imaging.BitmapCreateOptions]::None, [Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
        } catch {}
    }

    if ($SelfTestDir) {
        # Keep the self-test window out of the way; it is rendered to image files instead.
        $script:Window.WindowStartupLocation = 'Manual'
        $script:Window.Left = -20000
        $script:Window.Top = -20000
        $script:Window.ShowInTaskbar = $false
        $script:Window.ShowActivated = $false
        # A size to test the layout at, such as 980x680 for the smallest the window goes.
        if ($env:DEBLOATER_TEST_SIZE -match '^(\d+)x(\d+)$') {
            $script:Window.Width = [int]$Matches[1]
            $script:Window.Height = [int]$Matches[2]
        }
    }

    $saved = Get-DebloaterSettings
    $script:UpdatesOn = [bool]$saved.updates
    $script:UpdateChecked = [string]$saved.updateChecked
    # A newer version found on an earlier day is offered again without asking anew.
    if (Test-UpdateAllowed) { $script:Update = Get-DebloaterKnownUpdate }
    if (-not $SelfTestDir) {
        # Open at the size it was left at, as long as that still fits this screen.
        $area = [Windows.SystemParameters]::WorkArea
        if ($saved.width -ge $script:Window.MinWidth -and $saved.width -le $area.Width -and
            $saved.height -ge $script:Window.MinHeight -and $saved.height -le $area.Height) {
            $script:Window.Width = $saved.width
            $script:Window.Height = $saved.height
        }
        if ($saved.maximized) { $script:Window.WindowState = 'Maximized' }
    }
    if (-not $Theme) { $Theme = $saved.theme }
    if ($Theme -notin 'system', 'light', 'dark') { $Theme = 'dark' }
    Set-UiTheme $Theme

    Build-Nav
    Select-NavEntry 'home'
    $ui.LoadingText.Text = T 'scan.working'
    Show-View 'ViewLoading'
    Update-Chrome

    # The one thing in the layout that moves without end: the light around the Debloat
    # button. It rests when movement is off.
    if ($script:Motion) { $ui.BtnDebloat.Tag = 'lively' }

    # The mouse wheel glides in every list.
    [Debloater.Ui.Glide]::Enabled = [bool]$script:Motion
    foreach ($viewer in $ui.ListScroll, $ui.ResultScroll, $ui.HistoryScroll, $ui.ViewSettings) { [Debloater.Ui.Glide]::Attach($viewer) }

    # ---- Events
    # The top bar. Pressing the button of the page that is already open goes back.
    $ui.BtnHistory.Add_Click({
        Invoke-Guarded {
            if ($script:Mode -ne 'browse') { return }
            if ($script:CurrentPage -eq 'history') { Show-Page 'home' } else { Show-Page 'history' }
        }
    })
    $ui.BtnSettings.Add_Click({
        Invoke-Guarded {
            if ($script:Mode -ne 'browse') { return }
            if ($script:CurrentPage -eq 'settings') { Show-Page 'home' } else { Show-Page 'settings' }
        }
    })
    $ui.BtnHistoryBack.Add_Click({ Invoke-Guarded { if ($script:Mode -eq 'browse') { Show-Page 'home' } } })
    $ui.BtnSettingsBack.Add_Click({ Invoke-Guarded { if ($script:Mode -eq 'browse') { Show-Page 'home' } } })

    $script:SelectionHandler = [EventHandler] {
        param($s, $e)
        Invoke-Guarded {
            if ($s.IsSelected) { $script:Selected[$s.Id] = $true } else { $script:Selected.Remove($s.Id) }
            Update-Bars
        }
    }
    [Debloater.Ui.ItemVm]::add_AnySelectionChanged($script:SelectionHandler)

    # The one main action, wherever it is pressed.
    $ui.BtnDebloat.Add_Click({ Invoke-Guarded { Show-Confirm } })
    $ui.BtnDebloatSmall.Add_Click({ Invoke-Guarded { Show-Confirm } })
    $ui.BtnConfirmCancel.Add_Click({ Invoke-Guarded { Hide-Confirm } })
    $ui.BtnConfirmGo.Add_Click({ Invoke-Guarded { Invoke-ConfirmGo } })
    $ui.BtnConfirmMore.Add_Click({ Invoke-Guarded { Open-UpdatePage } })
    $ui.BtnUpdate.Add_Click({ Invoke-Guarded { Show-UpdateSheet } })
    $ui.UpdateSwitch.Add_Click({
        Invoke-Guarded {
            $script:UpdatesOn = [bool]$script:Ui.UpdateSwitch.IsChecked
            Save-UiSettings
        }
    })
    $ui.LinkUpdate.Add_Click({
        Invoke-Guarded {
            if (-not (Test-UpdateAllowed) -or $script:UpdateJob) { return }
            Update-UpdateSettings 'checking'
            Start-UpdateCheck { param($state) Update-UpdateSettings $state }
        }
    })
    $ui.BtnProgressDetails.Add_Click({ Invoke-Guarded { Show-Result } })
    $ui.BtnProgressDone.Add_Click({ Invoke-Guarded { Exit-ToBrowse } })
    $ui.BtnHomeUndo.Add_Click({
        Invoke-Guarded {
            if (-not $script:LastApplied -or $script:Mode -ne 'browse') { return }
            Show-UndoConfirm ([string]$script:LastApplied.Dir)
        }
    })
    $ui.BtnDone.Add_Click({ Invoke-Guarded { Exit-ToBrowse } })
    $ui.BtnOpenLog.Add_Click({ Invoke-Guarded { Open-Path $script:LastRunDir } })

    $ui.OptionalSwitch.Add_Click({
        Invoke-Guarded {
            $optional = @(Get-TodoItems | Where-Object { -not $_.Recommended })
            Set-ItemsSelected $optional ([bool]$script:Ui.OptionalSwitch.IsChecked)
            Build-Home
        }
    })
    $ui.BtnBack.Add_Click({ Invoke-Guarded { Show-Page 'home' } })
    $ui.BtnSelectAll.Add_Click({ Invoke-Guarded { Set-ItemsSelected @($script:PageVms.Keys | ForEach-Object { $script:ById[$_] }) $true } })
    $ui.BtnSelectNone.Add_Click({ Invoke-Guarded { Set-ItemsSelected @(Get-TodoItems $script:CurrentPage) $false } })
    $ui.SearchBox.Add_TextChanged({ Invoke-Guarded { if ($script:Mode -eq 'browse' -and $script:CategoryIds -contains $script:CurrentPage) { Build-List } } })
    $ui.LinkRepo.Add_Click({ Invoke-Guarded { Start-Process $script:RepoUrl } })
    $ui.LinkChanges.Add_Click({ Invoke-Guarded { Open-ChangesList } })
    $ui.LinkData.Add_Click({ Invoke-Guarded { $root = Get-DebloaterDataRoot; [void](New-Item -ItemType Directory -Force -Path $root); Open-Path $root } })
    $ui.LinkLicence.Add_Click({ Invoke-Guarded { Open-Licence } })
    $ui.LinkSite.Add_Click({ Invoke-Guarded { Start-Process 'https://coursion.studio' } })
    $ui.LinkSupport.Add_Click({ Invoke-Guarded { Start-Process 'mailto:support@coursion.studio' } })

    $click = [Windows.Controls.Primitives.ButtonBase]::ClickEvent
    $ui.HomeCards.AddHandler($click, [Windows.RoutedEventHandler] {
        param($s, $e)
        Invoke-Guarded { $context = $e.OriginalSource.DataContext; if ($context -and $context.Id) { Show-Page ([string]$context.Id) } }
    })
    $ui.HistoryRuns.AddHandler($click, [Windows.RoutedEventHandler] {
        param($s, $e)
        Invoke-Guarded {
            $button = $e.OriginalSource
            $context = $button.DataContext
            switch ([string]$button.Tag) {
                'undo'  { Show-UndoConfirm ([string]$context.Dir) }
                'open'  { Open-Path ([string]$context.Dir) }
                'store' { Start-Process ('ms-windows-store://pdp/?PFN=' + [string]$context.Family) }
            }
        }
    })
    $ui.LangChoices.AddHandler($click, [Windows.RoutedEventHandler] {
        param($s, $e)
        Invoke-Guarded { $context = $e.OriginalSource.DataContext; if ($context -and $context.Id) { Set-UiLanguage ([string]$context.Id) } }
    })
    $ui.ThemeChoices.AddHandler($click, [Windows.RoutedEventHandler] {
        param($s, $e)
        Invoke-Guarded {
            $context = $e.OriginalSource.DataContext
            if (-not $context -or -not $context.Id) { return }
            Set-UiTheme ([string]$context.Id)
            Save-UiSettings
            Build-Settings
        }
    })

    # Title bar buttons (the window draws its own, so its colours can run to the top).
    $ui.BtnMin.Add_Click({ $script:Window.WindowState = 'Minimized' })
    $ui.BtnMax.Add_Click({
        if ($script:Window.WindowState -eq 'Maximized') { $script:Window.WindowState = 'Normal' } else { $script:Window.WindowState = 'Maximized' }
    })
    $ui.BtnClose.Add_Click({ $script:Window.Close() })
    $script:Window.Add_StateChanged({
        # A maximised window with custom chrome hangs over the screen edge by the resize border.
        if ($script:Window.WindowState -eq 'Maximized') {
            $script:Ui.Root.Margin = New-Object Windows.Thickness(7)
            $script:Ui.MaxGlyph.Text = Glyph 0xE923
        } else {
            $script:Ui.Root.Margin = New-Object Windows.Thickness(0)
            $script:Ui.MaxGlyph.Text = Glyph 0xE922
        }
    })
    $script:Window.Add_PreviewKeyDown({ param($s, $e) Invoke-Guarded { Invoke-KeyDown $e } })
    $script:Window.Add_SourceInitialized({ Set-WindowLook })
    $script:Window.Add_SizeChanged({ Invoke-Guarded { Update-Zoom } })
    $script:Window.Dispatcher.add_UnhandledException({
        param($s, $e)
        $e.Handled = $true
        Register-DebloaterFault $e.Exception
    })

    $script:Window.Add_ContentRendered({
        Invoke-Guarded {
            if ($script:Scanned) { return }
            $script:Scanned = $true
            Start-LoadingPulse
            Start-StateScan {
                Stop-LoadingPulse
                # A demo starts from a made-up PC, so this PC's real history has no place in it.
                Update-RunRecord
                foreach ($item in Get-TodoItems) { if ($item.Recommended) { $script:Selected[$item.Id] = $true } }
                $script:Mode = 'browse'
                Show-Page 'home'
                if ($script:SelfTestDir) { Invoke-DebloaterSelfTest }
                elseif (Test-UpdateDue) {
                    # Never a reason to bother anyone: no answer just means no pill.
                    try { Start-UpdateCheck $null } catch {}
                }
            }
        }
    })
    $script:Window.Add_Closing({ Invoke-Guarded { Save-UiSettings } })
    $script:Window.Add_Closed({
        if ($script:Timer) { $script:Timer.Stop() }
        if ($script:ScanJob) { $script:ScanJob.Timer.Stop() }
        if ($script:UpdateJob) { $script:UpdateJob.Timer.Stop() }
        if ($script:UpdateWork) { $script:UpdateWork.Timer.Stop() }
        [Debloater.Ui.ItemVm]::remove_AnySelectionChanged($script:SelectionHandler)
    })

    [void]$script:Window.ShowDialog()
}
