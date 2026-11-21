# Debloater.Engine.psm1
# Catalog, detection and the apply / undo engine. No window code lives here, so
# everything in this file can be run and tested without showing any UI.

$script:Root = $PSScriptRoot
$script:Strings = @{}
$script:Fallback = @{}
$script:Lang = 'en'
$script:Utf8 = New-Object System.Text.UTF8Encoding($false)

# ================================================================ JSON and files

function Read-DebloaterJson {
    param([string]$Path)
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Write-DebloaterJson {
    param($Object, [string]$Path)
    $json = ConvertTo-Json -InputObject $Object -Depth 10
    [IO.File]::WriteAllText($Path, $json, $script:Utf8)
}

function Get-OptionalProperty {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $p = $Object.PSObject.Properties[$Name]
    if ($p) { return $p.Value }
    return $null
}

function Get-DebloaterVersion {
    $file = Join-Path $script:Root 'version.txt'
    if (Test-Path -LiteralPath $file) { return (Get-Content -LiteralPath $file -Raw).Trim() }
    return '0.0.0'
}

# The licence travels with the tool, in the folder above this one. Its first lines
# give the year of the copyright.
function Get-DebloaterLicencePath {
    return (Join-Path (Split-Path -Parent $script:Root) 'LICENSE.md')
}

function Get-DebloaterCopyrightYear {
    $file = Get-DebloaterLicencePath
    if (Test-Path -LiteralPath $file) {
        $found = [regex]::Match([IO.File]::ReadAllText($file), 'Copyright \S+ (\d{4}) Coursion Studio')
        if ($found.Success) { return $found.Groups[1].Value }
    }
    return '2026'
}

function Get-DebloaterDataRoot {
    # DEBLOATER_DATA lets tests keep their run folders away from the real history.
    if ($env:DEBLOATER_DATA) { return $env:DEBLOATER_DATA }
    return (Join-Path $env:LOCALAPPDATA 'WindowsDebloater')
}

# Preferences the window remembers between runs (language and theme).
function Get-DebloaterSettings {
    # Dark is the default look; "light" and "system" are choices on the Settings page.
    # width and height are the size the window was left at; 0 means the size it is designed for.
    # updates says whether to ask GitHub for a newer version when the window opens, and
    # updateChecked is when that was last asked, so it happens once a day at most.
    # selection is what was ticked when the window was last closed; nothing when it has
    # never been closed with this version or a later one.
    $settings = [pscustomobject]@{ lang = ''; theme = 'dark'; width = 0; height = 0; maximized = $false; updates = $true; updateChecked = ''; selection = $null }
    $file = Join-Path (Get-DebloaterDataRoot) 'settings.json'
    if (Test-Path -LiteralPath $file) {
        try {
            $saved = Read-DebloaterJson $file
            $lang = [string](Get-OptionalProperty $saved 'lang')
            $theme = [string](Get-OptionalProperty $saved 'theme')
            if ($lang) { $settings.lang = $lang }
            if ($theme -in 'system', 'light', 'dark') { $settings.theme = $theme }
            $width = 0
            $height = 0
            if ([int]::TryParse([string](Get-OptionalProperty $saved 'width'), [ref]$width)) { $settings.width = $width }
            if ([int]::TryParse([string](Get-OptionalProperty $saved 'height'), [ref]$height)) { $settings.height = $height }
            $settings.maximized = ([string](Get-OptionalProperty $saved 'maximized') -eq 'True')
            $settings.updates = ([string](Get-OptionalProperty $saved 'updates') -ne 'False')
            $settings.updateChecked = [string](Get-OptionalProperty $saved 'updateChecked')
            $choice = Get-OptionalProperty $saved 'selection'
            $kind = [string](Get-OptionalProperty $choice 'kind')
            if ($kind -in 'recommended', 'everything', 'saved', 'custom') {
                $settings.selection = [pscustomobject]@{
                    kind = $kind
                    name = (ConvertTo-DebloaterSelectionName ([string](Get-OptionalProperty $choice 'name')))
                    ids = @(ConvertTo-DebloaterIdList (Get-OptionalProperty $choice 'ids'))
                    known = @(ConvertTo-DebloaterIdList (Get-OptionalProperty $choice 'known'))
                }
            }
        } catch {}
    }
    return $settings
}

function Save-DebloaterSettings {
    param($Settings)
    try {
        $root = Get-DebloaterDataRoot
        [void](New-Item -ItemType Directory -Force -Path $root)
        Write-DebloaterJson $Settings (Join-Path $root 'settings.json')
    } catch {}
}

# ================================================================ Selections
#
# A selection is a list of item ids: what someone wants debloated. The tool has two of
# its own, the recommended items and everything, and keeps the ones a person saved
# under a name in selections.json, next to the settings. A selection can also travel as
# a file of its own, to be used on another PC.

# A name as it may be kept: one line, no control characters, 40 characters at most.
function ConvertTo-DebloaterSelectionName {
    param([string]$Name)
    $clean = (([string]$Name -replace '[\x00-\x1F\x7F]', ' ') -replace '\s+', ' ').Trim()
    if ($clean.Length -gt 40) { $clean = $clean.Substring(0, 40).Trim() }
    return $clean
}

# Whatever was handed over, as a list of item ids: only texts of the shape an id has,
# each of them once, and no more than a catalog could ever hold.
function ConvertTo-DebloaterIdList {
    param($Ids)
    $seen = @{}
    $list = New-Object 'System.Collections.Generic.List[string]'
    foreach ($id in @($Ids)) {
        $text = [string]$id
        if ($text -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$' -or $seen.ContainsKey($text)) { continue }
        $seen[$text] = $true
        $list.Add($text)
        if ($list.Count -ge 2000) { break }
    }
    return $list.ToArray()
}

function Get-DebloaterSelectionsPath {
    return (Join-Path (Get-DebloaterDataRoot) 'selections.json')
}

# The selections saved under a name, in the order they were saved. Each has a Name,
# the day it was Saved and its Ids.
function Get-DebloaterSelections {
    $list = @()
    $file = Get-DebloaterSelectionsPath
    if (Test-Path -LiteralPath $file) {
        try {
            $names = @{}
            foreach ($entry in @(Get-OptionalProperty (Read-DebloaterJson $file) 'selections')) {
                $name = ConvertTo-DebloaterSelectionName ([string](Get-OptionalProperty $entry 'name'))
                if (-not $name -or $names.ContainsKey($name)) { continue }
                $names[$name] = $true
                $list += [pscustomobject]@{
                    Name = $name
                    Saved = [string](Get-OptionalProperty $entry 'saved')
                    Ids = @(ConvertTo-DebloaterIdList (Get-OptionalProperty $entry 'ids'))
                }
            }
        } catch { $list = @() }
    }
    return $list
}

function Save-DebloaterSelections {
    param($Selections)
    $root = Get-DebloaterDataRoot
    [void](New-Item -ItemType Directory -Force -Path $root)
    $list = @()
    foreach ($entry in @($Selections)) {
        $list += [pscustomobject]@{ name = [string]$entry.Name; saved = [string]$entry.Saved; ids = @(ConvertTo-DebloaterIdList $entry.Ids) }
    }
    Write-DebloaterJson ([pscustomobject]@{ selections = $list }) (Get-DebloaterSelectionsPath)
}

# Writes a selection to a file of its own, to be carried to another PC. It names the
# items and nothing else: not the PC and not the person.
function Export-DebloaterSelection {
    param([string]$Name, $Ids, [string]$Path)
    Write-DebloaterJson ([pscustomobject][ordered]@{
        app = 'Windows Debloater'; kind = 'selection'; version = (Get-DebloaterVersion)
        name = (ConvertTo-DebloaterSelectionName $Name); saved = (Get-Date).ToString('yyyy-MM-dd')
        ids = @(ConvertTo-DebloaterIdList $Ids)
    }) $Path
}

# Reads a selection file. It is somebody's file, so nothing in it is taken on trust: it
# has to say what it is, it may not be large, and only texts of the shape of an id are
# taken from it. What is wrong is thrown as the key of the text that says so.
function Import-DebloaterSelection {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'select.fail.missing' }
    if ((Get-Item -LiteralPath $Path).Length -gt 262144) { throw 'select.fail.format' }
    $data = $null
    try { $data = Read-DebloaterJson $Path } catch { throw 'select.fail.format' }
    if ([string](Get-OptionalProperty $data 'kind') -cne 'selection' -or [string](Get-OptionalProperty $data 'app') -cne 'Windows Debloater') {
        throw 'select.fail.format'
    }
    $ids = @(ConvertTo-DebloaterIdList (Get-OptionalProperty $data 'ids'))
    if ($ids.Count -eq 0) { throw 'select.fail.empty' }
    $name = ConvertTo-DebloaterSelectionName ([string](Get-OptionalProperty $data 'name'))
    if (-not $name) { $name = ConvertTo-DebloaterSelectionName ([IO.Path]::GetFileNameWithoutExtension($Path)) }
    $saved = [string](Get-OptionalProperty $data 'saved')
    if ($saved -notmatch '^\d{4}-\d{2}-\d{2}$') { $saved = '' }
    $version = [string](Get-OptionalProperty $data 'version')
    if ($version -notmatch '^\d+(\.\d+){1,3}$') { $version = '' }
    return [pscustomobject]@{ Name = $name; Saved = $saved; Version = $version; Ids = $ids }
}

# The ids a remembered choice stands for today. "recommended" and "everything" are
# worked out from the catalog each time, so they follow it as it grows. A saved one is
# exactly its list. What someone ticked by hand is their list, plus whatever is
# recommended and was not in the catalog yet when they chose: they have not decided
# about that, so it follows the recommendation.
function Resolve-DebloaterSelection {
    param($Choice, $Catalog, $Selections)
    $kind = [string](Get-OptionalProperty $Choice 'kind')
    $name = [string](Get-OptionalProperty $Choice 'name')
    if ($kind -eq 'saved') {
        $entry = @($Selections) | Where-Object { $_.Name -eq $name } | Select-Object -First 1
        if ($entry) { return [pscustomobject]@{ Kind = 'saved'; Name = [string]$entry.Name; Ids = @(ConvertTo-DebloaterIdList $entry.Ids) } }
        # Its list is gone; the copy kept with the choice is what was ticked.
        $kind = 'custom'
    }
    if ($kind -eq 'everything') {
        return [pscustomobject]@{ Kind = 'everything'; Name = ''; Ids = @(@($Catalog) | ForEach-Object { $_.Id }) }
    }
    if ($kind -eq 'custom') {
        $ids = @(ConvertTo-DebloaterIdList (Get-OptionalProperty $Choice 'ids'))
        $known = @{}
        foreach ($id in @(ConvertTo-DebloaterIdList (Get-OptionalProperty $Choice 'known'))) { $known[$id] = $true }
        if ($known.Count -gt 0) {
            foreach ($item in @($Catalog)) { if ($item.Recommended -and -not $known.ContainsKey($item.Id)) { $ids += $item.Id } }
        }
        return [pscustomobject]@{ Kind = 'custom'; Name = ''; Ids = @(ConvertTo-DebloaterIdList $ids) }
    }
    return [pscustomobject]@{ Kind = 'recommended'; Name = ''; Ids = @(@($Catalog) | Where-Object { $_.Recommended } | ForEach-Object { $_.Id }) }
}

# What a list of ids comes to on one PC. $States gives each item's state there: "todo",
# "done" or "absent". Ticked can be done here, Done is in place already, Missing is not
# on this PC (an app that is not installed), and Unknown is not in this version's catalog.
function Get-DebloaterSelectionFit {
    param($Ids, $Catalog, $States)
    $known = @{}
    foreach ($item in @($Catalog)) { $known[$item.Id] = $true }
    $ticked = @(); $done = @(); $missing = @(); $unknown = @()
    foreach ($id in @(ConvertTo-DebloaterIdList $Ids)) {
        if (-not $known.ContainsKey($id)) { $unknown += $id; continue }
        $state = $States[$id]
        if ($state -isnot [string]) { $state = [string](Get-OptionalProperty $state 'State') }
        if ($state -eq 'todo') { $ticked += $id } elseif ($state -eq 'done') { $done += $id } else { $missing += $id }
    }
    return [pscustomobject]@{ Ticked = $ticked; Done = $done; Missing = $missing; Unknown = $unknown }
}

function Get-DebloaterWindowsInfo {
    $name = 'Windows'
    try { $name = ([string](Get-CimInstance Win32_OperatingSystem).Caption).Replace('Microsoft ', '').Trim() } catch {}
    return ($name + ', build ' + [Environment]::OSVersion.Version.Build)
}

function New-DebloaterRunFolder {
    $runs = Join-Path (Get-DebloaterDataRoot) 'runs'
    $name = Get-Date -Format 'yyyyMMdd-HHmmss'
    $dir = Join-Path $runs $name
    $n = 1
    while (Test-Path -LiteralPath $dir) { $n++; $dir = Join-Path $runs ($name + '-' + $n) }
    [void](New-Item -ItemType Directory -Force -Path $dir)
    return $dir
}

# Reads the complete lines of a file that another process may still be writing.
function Read-DebloaterLines {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $text = ''
    try {
        $fs = New-Object IO.FileStream($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        try {
            $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)
            $text = $sr.ReadToEnd()
        } finally { $fs.Dispose() }
    } catch { return @() }
    $end = $text.LastIndexOf("`n")
    if ($end -lt 0) { return @() }
    return @($text.Substring(0, $end) -split "`n")
}

function Format-DebloaterSize {
    param([int64]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:N1} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
    return ('{0:N0} KB' -f [Math]::Ceiling($Bytes / 1KB))
}

# ================================================================ Language

function ConvertTo-DebloaterHashtable {
    param($Object)
    $h = @{}
    foreach ($p in $Object.PSObject.Properties) { $h[$p.Name] = [string]$p.Value }
    return $h
}

function Get-DebloaterLanguages {
    $list = @()
    foreach ($f in Get-ChildItem -LiteralPath (Join-Path $script:Root 'lang') -Filter '*.json' | Sort-Object Name) {
        $name = $f.BaseName
        try { $name = [string](Read-DebloaterJson $f.FullName).'language.name' } catch {}
        $list += [pscustomobject]@{ Code = $f.BaseName; Name = $name }
    }
    return $list
}

function Get-DebloaterDefaultLanguage {
    $code = (Get-UICulture).TwoLetterISOLanguageName
    if (Test-Path -LiteralPath (Join-Path $script:Root ("lang\" + $code + ".json"))) { return $code }
    return 'en'
}

function Initialize-DebloaterLanguage {
    param([string]$Lang)
    $dir = Join-Path $script:Root 'lang'
    $script:Fallback = ConvertTo-DebloaterHashtable (Read-DebloaterJson (Join-Path $dir 'en.json'))
    $file = Join-Path $dir ($Lang + '.json')
    if ($Lang -and $Lang -ne 'en' -and (Test-Path -LiteralPath $file)) {
        $script:Strings = ConvertTo-DebloaterHashtable (Read-DebloaterJson $file)
        $script:Lang = $Lang
    } else {
        $script:Strings = $script:Fallback
        $script:Lang = 'en'
    }
}

function Get-DebloaterLanguage { return $script:Lang }

# Looks up a text by key in the current language, falling back to English.
function Get-DebloaterText {
    param([string]$Key, [object[]]$FormatArgs)
    $s = $script:Strings[$Key]
    if (-not $s) { $s = $script:Fallback[$Key] }
    if (-not $s) { return $Key }
    # Compare with $null on purpose: a single argument of 0 is "false" to PowerShell,
    # which would leave the {0} placeholder unfilled.
    if ($null -ne $FormatArgs -and $FormatArgs.Count -gt 0) { return ($s -f $FormatArgs) }
    return $s
}
Set-Alias -Name T -Value Get-DebloaterText

# ================================================================ Catalog

function Get-DebloaterCatalog {
    $items = New-Object System.Collections.ArrayList

    $apps = Read-DebloaterJson (Join-Path $script:Root 'catalog\apps.json')
    foreach ($a in $apps.items) {
        [void]$items.Add([pscustomobject]@{
            Id          = [string]$a.id
            Kind        = 'app'
            Page        = 'apps'
            Group       = [string]$a.group
            Recommended = [bool]$a.recommended
            Title       = [string]$a.title
            NoteKey     = [string](Get-OptionalProperty $a 'note')
            Packages    = @($a.packages)
            Registry    = @()
            Actions     = @()
        })
    }

    $tweaks = Read-DebloaterJson (Join-Path $script:Root 'catalog\tweaks.json')
    foreach ($t in $tweaks.items) {
        $registry = @()
        foreach ($r in @(Get-OptionalProperty $t 'registry')) {
            if ($null -eq $r) { continue }
            $admin = ([string]$r.path -like 'HKLM\*') -or [bool](Get-OptionalProperty $r 'admin')
            $registry += [pscustomobject]@{
                Path  = [string]$r.path
                Name  = [string]$r.name
                Value = $r.value
                Type  = 'DWord'
                Admin = $admin
            }
        }
        $actions = @()
        foreach ($a in @(Get-OptionalProperty $t 'actions')) { if ($a) { $actions += [string]$a } }
        [void]$items.Add([pscustomobject]@{
            Id          = [string]$t.id
            Kind        = 'tweak'
            Page        = [string]$t.page
            Group       = [string]$t.group
            Recommended = [bool]$t.recommended
            Title       = ''
            NoteKey     = ''
            Packages    = @()
            Registry    = $registry
            Actions     = $actions
        })
    }
    return $items.ToArray()
}

function Get-DebloaterItemTitle {
    param($Item)
    if ($Item.Kind -eq 'app') { return $Item.Title }
    return (Get-DebloaterText ('item.' + $Item.Id + '.title'))
}

function Get-DebloaterItemDescription {
    param($Item)
    if ($Item.Kind -eq 'app') {
        if ($Item.NoteKey) { return (Get-DebloaterText $Item.NoteKey) }
        return ''
    }
    return (Get-DebloaterText ('item.' + $Item.Id + '.desc'))
}

function Test-DebloaterItemNeedsAdmin {
    param($Item)
    return (@($Item.Registry | Where-Object { $_.Admin }).Count -gt 0)
}

# The exact changes an item makes, one per line, for the "What this changes" panel.
function Get-DebloaterItemDetails {
    param($Item)
    $lines = @()
    foreach ($package in @($Item.Packages)) { $lines += (Get-DebloaterText 'detail.package' $package) }
    foreach ($entry in @($Item.Registry)) {
        $lines += (Get-DebloaterText 'detail.registry' ($entry.Path + '\' + $entry.Name), $entry.Value)
    }
    foreach ($action in @($Item.Actions)) { $lines += (Get-DebloaterText ('detail.action.' + $action)) }
    return ($lines -join "`n")
}

# True when the item has work for the given worker ("User" or "Admin").
function Test-DebloaterItemHasScope {
    param($Item, [string]$Scope)
    if ($Scope -eq 'Admin') { return (Test-DebloaterItemNeedsAdmin $Item) }
    if (@($Item.Packages).Count -gt 0) { return $true }
    if (@($Item.Actions).Count -gt 0) { return $true }
    return (@($Item.Registry | Where-Object { -not $_.Admin }).Count -gt 0)
}

# ================================================================ Registry

# Catalog paths look like "HKCU\Software\..." or "HKLM\SOFTWARE\...". An elevated
# worker may run as a different account, so it reaches the signed-in user's hive
# through HKEY_USERS\<sid> instead of its own HKEY_CURRENT_USER.
function Resolve-DebloaterRegPath {
    param([string]$Path, [string]$UserSid)
    if ($Path -like 'HKLM\*') { return ('Registry::HKEY_LOCAL_MACHINE\' + $Path.Substring(5)) }
    if ($Path -like 'HKCU\*') {
        if ($UserSid) { return ('Registry::HKEY_USERS\' + $UserSid + '\' + $Path.Substring(5)) }
        return ('Registry::HKEY_CURRENT_USER\' + $Path.Substring(5))
    }
    throw "Unsupported registry path: $Path"
}

function Get-DebloaterRegValue {
    param([string]$PsPath, [string]$Name)
    $result = [pscustomobject]@{ Exists = $false; Value = $null; Kind = $null }
    if (-not (Test-Path -LiteralPath $PsPath)) { return $result }
    $key = Get-Item -LiteralPath $PsPath
    if (@($key.GetValueNames()) -notcontains $Name) { return $result }
    $result.Exists = $true
    $result.Value = $key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    $result.Kind = [string]$key.GetValueKind($Name)
    return $result
}

function Set-DebloaterRegValue {
    param([string]$PsPath, [string]$Name, $Value, [string]$Kind)
    # New-Item -Force on an existing key would wipe its values, so only create when missing.
    if (-not (Test-Path -LiteralPath $PsPath)) { [void](New-Item -Path $PsPath -Force) }
    [void](New-ItemProperty -LiteralPath $PsPath -Name $Name -Value $Value -PropertyType $Kind -Force)
}

function Remove-DebloaterRegValue {
    param([string]$PsPath, [string]$Name)
    if (-not (Test-Path -LiteralPath $PsPath)) { return }
    $key = Get-Item -LiteralPath $PsPath
    if (@($key.GetValueNames()) -contains $Name) { Remove-ItemProperty -LiteralPath $PsPath -Name $Name }
}

function Test-DebloaterRegEntryApplied {
    param($Entry, [string]$UserSid)
    $current = Get-DebloaterRegValue (Resolve-DebloaterRegPath $Entry.Path $UserSid) $Entry.Name
    return ($current.Exists -and ("$($current.Value)" -eq "$($Entry.Value)"))
}

# ================================================================ Native calls

function Initialize-DebloaterNative {
    if ('Debloater.Native' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace Debloater {
    public static class Native {
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, string pvParam, uint fWinIni);

        [DllImport("shell32.dll")]
        public static extern int SHSetKnownFolderPath(ref Guid rfid, uint dwFlags, IntPtr hToken,
            [MarshalAs(UnmanagedType.LPWStr)] string pszPath);
    }
}
'@
}

# ================================================================ Desktop and lock screen

function Get-DebloaterDesktopPictureSource {
    try {
        $cache = (Get-ItemProperty 'HKCU:\Control Panel\Desktop' -Name TranscodedImageCache -ErrorAction Stop).TranscodedImageCache
        if ($cache.Length -gt 24) {
            return ([Text.Encoding]::Unicode.GetString($cache, 24, $cache.Length - 24) -split "`0")[0]
        }
    } catch {}
    return ''
}

function Get-DebloaterStandardDesktopPictures {
    $dir = Join-Path $env:SystemRoot 'Web\Wallpaper\Windows'
    return @((Join-Path $dir 'img0.jpg'), (Join-Path $dir 'img19.jpg'))
}

function Get-DebloaterDesktopPictureTarget {
    $pictures = Get-DebloaterStandardDesktopPictures
    $light = 1
    try { $light = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name AppsUseLightTheme -ErrorAction Stop).AppsUseLightTheme } catch {}
    if ($light -eq 0 -and (Test-Path -LiteralPath $pictures[1])) { return $pictures[1] }
    return $pictures[0]
}

function Invoke-ActionSetDesktopPicture {
    param($Item, [bool]$DryRun, [System.Collections.ArrayList]$Journal)
    $target = Get-DebloaterDesktopPictureTarget
    if (-not (Test-Path -LiteralPath $target)) { return @(Get-DebloaterText 'msg.desktop.missing') }
    if ($DryRun) { return @(Get-DebloaterText 'msg.desktop.would') }
    Initialize-DebloaterNative
    $previous = Get-DebloaterDesktopPictureSource
    if (-not [Debloater.Native]::SystemParametersInfo(0x14, 0, $target, 3)) { throw (Get-DebloaterText 'msg.desktop.failed') }
    [void]$Journal.Add([pscustomobject]@{ Kind = 'wallpaper'; Item = $Item.Id; Previous = $previous })
    return @(Get-DebloaterText 'msg.desktop.set')
}

function Invoke-ActionSetLockScreenPicture {
    param($Item, [bool]$DryRun, [System.Collections.ArrayList]$Journal)
    $picture = Join-Path $env:SystemRoot 'Web\Screen\img100.jpg'
    if ($DryRun) { return @(Get-DebloaterText 'msg.lock.would') }
    try {
        if (-not (Test-Path -LiteralPath $picture)) { throw 'picture not found' }
        [void][Windows.System.UserProfile.LockScreen, Windows.System.UserProfile, ContentType = WindowsRuntime]
        [void][Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
        Add-Type -AssemblyName System.Runtime.WindowsRuntime
        $asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() |
            Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 }
        $asTaskOperation = @($asTask | Where-Object { $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
        $asTaskAction = @($asTask | Where-Object { $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncAction' })[0]

        $fileTask = $asTaskOperation.MakeGenericMethod([Windows.Storage.StorageFile]).Invoke(
            $null, @([Windows.Storage.StorageFile]::GetFileFromPathAsync($picture)))
        if (-not $fileTask.Wait(30000)) { throw 'timed out opening the picture' }
        $setTask = $asTaskAction.Invoke(
            $null, @([Windows.System.UserProfile.LockScreen]::SetImageFileAsync($fileTask.Result)))
        if (-not $setTask.Wait(30000)) { throw 'timed out setting the picture' }
        [void]$Journal.Add([pscustomobject]@{ Kind = 'lock'; Item = $Item.Id })
        return @(Get-DebloaterText 'msg.lock.set')
    } catch {
        # Not fatal: Spotlight is switched off by the registry part of the same item.
        return @(Get-DebloaterText 'msg.lock.failed' $_.Exception.Message)
    }
}

# ================================================================ Edge autostart

function Get-DebloaterEdgeAutostartNames {
    $run = 'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run'
    if (-not (Test-Path -LiteralPath $run)) { return @() }
    return @((Get-Item -LiteralPath $run).GetValueNames() | Where-Object { $_ -like 'MicrosoftEdgeAutoLaunch_*' })
}

function Invoke-ActionRemoveEdgeAutostart {
    param($Item, [bool]$DryRun, [System.Collections.ArrayList]$Journal)
    $run = 'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run'
    $messages = @()
    foreach ($name in Get-DebloaterEdgeAutostartNames) {
        if ($DryRun) { $messages += (Get-DebloaterText 'msg.edge.would' $name); continue }
        $current = Get-DebloaterRegValue $run $name
        [void]$Journal.Add([pscustomobject]@{ Kind = 'run'; Item = $Item.Id; Path = $run; Name = $name; Value = $current.Value; ValueKind = $current.Kind })
        Remove-ItemProperty -LiteralPath $run -Name $name
        $messages += (Get-DebloaterText 'msg.edge.removed' $name)
    }
    return $messages
}

# ================================================================ OneDrive

$script:KnownFolders = @(
    @{ Name = 'Desktop';   Special = 'Desktop';     Id = 'B4BFCC3A-DB2C-424C-B029-7FE99A87C641'; LocalId = '{754AC886-DF64-4CBA-86B5-F7FBF4FBCEF5}' },
    @{ Name = 'Documents'; Special = 'MyDocuments'; Id = 'FDD39AD0-238F-46AF-ADB4-6C85480369C7'; LocalId = '{F42EE2D3-909F-4907-8871-4C22FC0BF756}' },
    @{ Name = 'Pictures';  Special = 'MyPictures';  Id = '33E28130-4E1E-4676-835A-98395C3BC3BB'; LocalId = '{0DDD015D-B06C-45D5-8C4C-F59713854639}' },
    @{ Name = 'Music';     Special = 'MyMusic';     Id = '4BD8D571-6D19-48D3-BE97-422220080E43'; LocalId = '{A0C69A99-21C8-4671-8703-7934162FCF1D}' },
    @{ Name = 'Videos';    Special = 'MyVideos';    Id = '18989B1D-99B5-455B-841C-AB7C74E4DDFC'; LocalId = '{35286A68-3C57-41A1-BBB1-0EAE73D76C95}' }
)

function Get-DebloaterOneDriveInfo {
    $root = $null
    try { $root = (Get-ItemProperty 'HKCU:\Software\Microsoft\OneDrive\Accounts\Personal' -Name UserFolder -ErrorAction Stop).UserFolder } catch {}
    if (-not $root) { $root = $env:OneDriveConsumer }
    if (-not $root) { $root = $env:OneDrive }
    if (-not $root) { $root = Join-Path $env:USERPROFILE 'OneDrive' }
    $root = $root.TrimEnd('\')

    $business = $false
    try {
        $b = (Get-ItemProperty 'HKCU:\Software\Microsoft\OneDrive\Accounts\Business1' -Name UserFolder -ErrorAction Stop).UserFolder
        if ($b) { $business = $true }
    } catch {}

    $uninstall = $null
    $perMachine = $false
    $keys = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\OneDriveSetup.exe',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\OneDriveSetup.exe',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\OneDriveSetup.exe'
    )
    foreach ($k in $keys) {
        try {
            $u = (Get-ItemProperty $k -Name UninstallString -ErrorAction Stop).UninstallString
            if ($u) { $uninstall = [string]$u; $perMachine = ($k -like 'HKLM:*'); break }
        } catch {}
    }

    $redirected = @()
    foreach ($f in $script:KnownFolders) {
        $current = [Environment]::GetFolderPath($f.Special)
        if ($current -and $current.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
            $redirected += [pscustomobject]@{
                Name    = $f.Name
                Id      = $f.Id
                LocalId = $f.LocalId
                Current = $current
                Default = (Join-Path $env:USERPROFILE $f.Name)
            }
        }
    }

    return [pscustomobject]@{
        Root            = $root
        RootExists      = (Test-Path -LiteralPath $root)
        HasBusiness     = $business
        UninstallString = $uninstall
        PerMachine      = $perMachine
        Installed       = [bool]$uninstall
        Redirected      = $redirected
    }
}

# A file that OneDrive shows locally but keeps only online.
function Test-DebloaterCloudOnly {
    param($File)
    $attributes = [int]$File.Attributes
    return ((($attributes -band 0x400000) -ne 0) -or (($attributes -band 0x1000) -ne 0))
}

function Invoke-ActionRemoveOneDrive {
    param($Item, [bool]$DryRun, [System.Collections.ArrayList]$Journal)
    $messages = New-Object System.Collections.ArrayList
    $info = Get-DebloaterOneDriveInfo

    # Refuse before touching anything.
    if ($info.HasBusiness) { throw (Get-DebloaterText 'msg.onedrive.business') }
    if ($info.PerMachine) { throw (Get-DebloaterText 'msg.onedrive.permachine') }
    if (-not $info.Installed -and @($info.Redirected).Count -eq 0) {
        return @(Get-DebloaterText 'msg.onedrive.nothing')
    }

    # 1. Download files that exist only online, while OneDrive can still fetch them.
    if ($info.RootExists) {
        $cloud = @(Get-ChildItem -LiteralPath $info.Root -Recurse -Force -File -ErrorAction SilentlyContinue |
            Where-Object { Test-DebloaterCloudOnly $_ })
        if ($cloud.Count -gt 0) {
            $bytes = [int64]0
            foreach ($c in $cloud) { $bytes += $c.Length }
            if (-not $info.Installed) { throw (Get-DebloaterText 'msg.onedrive.cloudnoclient' $cloud.Count) }
            $drive = New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($info.Root))
            if ($drive.AvailableFreeSpace -lt ($bytes + 1GB)) {
                throw (Get-DebloaterText 'msg.onedrive.nospace' (Format-DebloaterSize $bytes))
            }
            if ($DryRun) {
                [void]$messages.Add((Get-DebloaterText 'msg.onedrive.woulddownload' $cloud.Count, (Format-DebloaterSize $bytes)))
            } else {
                [void]$messages.Add((Get-DebloaterText 'msg.onedrive.downloading' $cloud.Count, (Format-DebloaterSize $bytes)))
                foreach ($c in $cloud) {
                    try {
                        # Reading a placeholder to the end makes OneDrive download it.
                        $stream = [IO.File]::Open($c.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
                        try { $stream.CopyTo([IO.Stream]::Null) } finally { $stream.Dispose() }
                    } catch {}
                }
                $left = @(Get-ChildItem -LiteralPath $info.Root -Recurse -Force -File -ErrorAction SilentlyContinue |
                    Where-Object { Test-DebloaterCloudOnly $_ }).Count
                if ($left -gt 0) { throw (Get-DebloaterText 'msg.onedrive.downloadfailed' $left) }
            }
        }
    }

    # 2. Copy the redirected folders to their normal locations. Nothing is moved or overwritten.
    foreach ($r in @($info.Redirected)) {
        if ($DryRun) {
            [void]$messages.Add((Get-DebloaterText 'msg.onedrive.wouldcopy' $r.Name, $r.Default))
            continue
        }
        [void](New-Item -ItemType Directory -Force -Path $r.Default)
        $copied = 0
        if (Test-Path -LiteralPath $r.Current) {
            foreach ($entry in Get-ChildItem -LiteralPath $r.Current -Recurse -Force) {
                $target = Join-Path $r.Default $entry.FullName.Substring($r.Current.Length).TrimStart('\')
                if ($entry.PSIsContainer) { [void](New-Item -ItemType Directory -Force -Path $target); continue }
                if ($entry.Name -eq 'desktop.ini' -or (Test-Path -LiteralPath $target)) { continue }
                [void](New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent))
                Copy-Item -LiteralPath $entry.FullName -Destination $target
                $copied++
            }
        }
        [void]$messages.Add((Get-DebloaterText 'msg.onedrive.copied' $r.Name, $copied, $r.Default))
    }

    # 3. Uninstall OneDrive.
    if ($info.Installed) {
        if ($DryRun) {
            [void]$messages.Add((Get-DebloaterText 'msg.onedrive.woulduninstall'))
        } else {
            $exe = Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\OneDrive.exe'
            if (Test-Path -LiteralPath $exe) { Start-Process -FilePath $exe -ArgumentList '/shutdown' -Wait }
            $waited = 0
            while (@(Get-Process | Where-Object { $_.Name -eq 'OneDrive' }).Count -gt 0 -and $waited -lt 30) { Start-Sleep -Seconds 1; $waited++ }

            $file = $info.UninstallString
            $arguments = '/uninstall'
            if ($info.UninstallString -match '^\s*"([^"]+)"\s*(.*)$') {
                $file = $Matches[1]
                if ($Matches[2].Trim()) { $arguments = $Matches[2].Trim() }
            } elseif ($info.UninstallString -match '^(\S+)\s+(.+)$') {
                $file = $Matches[1]
                $arguments = $Matches[2].Trim()
            }
            Start-Process -FilePath $file -ArgumentList $arguments -Wait

            $uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\OneDriveSetup.exe'
            $waited = 0
            while ((Test-Path $uninstallKey) -and $waited -lt 90) { Start-Sleep -Seconds 2; $waited += 2 }
            if (Test-Path $uninstallKey) { throw (Get-DebloaterText 'msg.onedrive.uninstallfailed') }

            foreach ($p in @(Get-AppxPackage -Name 'Microsoft.OneDriveSync')) {
                try { Remove-AppxPackage -Package $p.PackageFullName -ErrorAction Stop } catch {}
            }
            # Noted so that reverting this run knows to install OneDrive again.
            [void]$Journal.Add([pscustomobject]@{ Kind = 'onedrive-app'; Item = $Item.Id })
            [void]$messages.Add((Get-DebloaterText 'msg.onedrive.uninstalled'))
        }
    }

    # 4. Point Windows back at the normal folders.
    if (@($info.Redirected).Count -gt 0) {
        if (-not $DryRun) { Initialize-DebloaterNative }
        $shellFolders = 'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
        $previous = @()
        foreach ($r in @($info.Redirected)) {
            if ($DryRun) {
                [void]$messages.Add((Get-DebloaterText 'msg.onedrive.wouldrepoint' $r.Name, $r.Default))
                continue
            }
            $id = [Guid]$r.Id
            $hr = [Debloater.Native]::SHSetKnownFolderPath([ref]$id, 0, [IntPtr]::Zero, $r.Default)
            if ($hr -ne 0) { throw (Get-DebloaterText 'msg.onedrive.repointfailed' $r.Name, ('0x{0:X8}' -f $hr)) }
            if ((Get-DebloaterRegValue $shellFolders $r.LocalId).Exists) {
                Set-DebloaterRegValue $shellFolders $r.LocalId ('%USERPROFILE%\' + $r.Name) 'ExpandString'
            }
            $previous += [pscustomobject]@{ Name = $r.Name; Previous = $r.Current }
            [void]$messages.Add((Get-DebloaterText 'msg.onedrive.repointed' $r.Name, $r.Default))
        }
        if (-not $DryRun) {
            [void]$Journal.Add([pscustomobject]@{ Kind = 'onedrive'; Item = $Item.Id; Root = $info.Root; Folders = $previous })
        }
    }

    if ($info.RootExists -and -not $DryRun) { [void]$messages.Add((Get-DebloaterText 'msg.onedrive.leftfolder' $info.Root)) }
    return $messages.ToArray()
}

# ================================================================ Actions

# Whether an action still has something to do: 'todo', 'done', 'absent' or 'neutral'.
function Test-DebloaterAction {
    param([string]$Name)
    switch ($Name) {
        'RemoveEdgeAutostart' {
            if (@(Get-DebloaterEdgeAutostartNames).Count -gt 0) { return 'todo' }
            return 'done'
        }
        'SetDesktopPicture' {
            $source = Get-DebloaterDesktopPictureSource
            foreach ($p in Get-DebloaterStandardDesktopPictures) { if ($source -and ($source -ieq $p)) { return 'done' } }
            return 'todo'
        }
        'SetLockScreenPicture' { return 'neutral' }
        'RemoveOneDrive' {
            $info = Get-DebloaterOneDriveInfo
            if ($info.Installed -or @($info.Redirected).Count -gt 0) { return 'todo' }
            return 'absent'
        }
    }
    return 'neutral'
}

function Invoke-DebloaterAction {
    param([string]$Name, $Item, [bool]$DryRun, [System.Collections.ArrayList]$Journal)
    switch ($Name) {
        'RemoveEdgeAutostart'  { return @(Invoke-ActionRemoveEdgeAutostart $Item $DryRun $Journal) }
        'SetDesktopPicture'    { return @(Invoke-ActionSetDesktopPicture $Item $DryRun $Journal) }
        'SetLockScreenPicture' { return @(Invoke-ActionSetLockScreenPicture $Item $DryRun $Journal) }
        'RemoveOneDrive'       { return @(Invoke-ActionRemoveOneDrive $Item $DryRun $Journal) }
    }
    throw "Unknown action: $Name"
}

# ================================================================ Detection

function Get-DebloaterInstalledPackages {
    $installed = @{}
    foreach ($p in Get-AppxPackage) { $installed[$p.Name.ToLowerInvariant()] = $true }
    return $installed
}

# Returns a table of item id -> state. 'todo' means there is something to change,
# 'done' means it is already the way the tool would set it, 'absent' means it does not
# apply to this PC (an app that is not installed, for example).
# -Demo pretends every item is 'todo' so the window can be shown off safely.
function Get-DebloaterState {
    param($Catalog, [switch]$Demo)
    $state = @{}
    $installed = @{}
    if (-not $Demo) { $installed = Get-DebloaterInstalledPackages }

    foreach ($item in $Catalog) {
        if ($Demo) { $state[$item.Id] = [pscustomobject]@{ State = 'todo' }; continue }
        $todo = $false
        $relevant = $false

        foreach ($name in @($item.Packages)) {
            if ($installed.ContainsKey($name.ToLowerInvariant())) { $todo = $true }
        }
        foreach ($entry in @($item.Registry)) {
            $relevant = $true
            if (-not (Test-DebloaterRegEntryApplied $entry $null)) { $todo = $true }
        }
        foreach ($action in @($item.Actions)) {
            $result = Test-DebloaterAction $action
            if ($result -eq 'todo') { $todo = $true; $relevant = $true }
            elseif ($result -eq 'done') { $relevant = $true }
        }

        $value = 'absent'
        if ($todo) { $value = 'todo' } elseif ($relevant) { $value = 'done' }
        $state[$item.Id] = [pscustomobject]@{ State = $value }
    }
    return $state
}

# ================================================================ Apply

# Applies the part of one item that belongs to the given worker and returns messages.
# Every change is added to $Journal before it is made, so it can be put back later.
function Invoke-DebloaterItem {
    param($Item, [string]$Scope, [string]$UserSid, [bool]$DryRun, [System.Collections.ArrayList]$Journal)
    $messages = @()

    if ($Scope -eq 'User') {
        foreach ($name in @($Item.Packages)) {
            foreach ($package in @(Get-AppxPackage -Name $name)) {
                if ($DryRun) { $messages += (Get-DebloaterText 'msg.app.would' $package.Name); continue }
                Remove-AppxPackage -Package $package.PackageFullName -ErrorAction Stop
                [void]$Journal.Add([pscustomobject]@{
                    Kind = 'app'; Item = $Item.Id; Title = $Item.Title
                    Name = $package.Name; Family = $package.PackageFamilyName
                })
                $messages += (Get-DebloaterText 'msg.app.removed' $package.Name)
            }
        }
    }

    foreach ($entry in @($Item.Registry)) {
        if (($Scope -eq 'Admin') -ne [bool]$entry.Admin) { continue }
        $sid = $null
        if ($Scope -eq 'Admin') { $sid = $UserSid }
        $psPath = Resolve-DebloaterRegPath $entry.Path $sid
        $current = Get-DebloaterRegValue $psPath $entry.Name
        if ($current.Exists -and ("$($current.Value)" -eq "$($entry.Value)")) { continue }
        if ($DryRun) { $messages += (Get-DebloaterText 'msg.reg.would' $entry.Name, $entry.Value); continue }
        [void]$Journal.Add([pscustomobject]@{
            Kind = 'reg'; Item = $Item.Id; Path = $psPath; Name = $entry.Name
            Existed = $current.Exists; OldValue = $current.Value; OldKind = $current.Kind; NewValue = $entry.Value
        })
        Set-DebloaterRegValue $psPath $entry.Name $entry.Value $entry.Type
        $messages += (Get-DebloaterText 'msg.reg.set' $entry.Name, $entry.Value)
    }

    if ($Scope -eq 'User') {
        foreach ($action in @($Item.Actions)) {
            $messages += @(Invoke-DebloaterAction $action $Item $DryRun $Journal)
        }
    }

    if (@($messages).Count -eq 0) { $messages = @(Get-DebloaterText 'msg.nothing') }
    return $messages
}

# ================================================================ Undo

# Puts back one journal entry. Returns a message, or $null when the entry is only a record.
function Undo-DebloaterEntry {
    param($Entry)
    switch ([string]$Entry.Kind) {
        'reg' {
            if ($Entry.Existed) {
                $value = $Entry.OldValue
                if ($Entry.OldKind -eq 'Binary') { $value = [byte[]]@($value) }
                elseif ($Entry.OldKind -eq 'MultiString') { $value = [string[]]@($value) }
                Set-DebloaterRegValue $Entry.Path $Entry.Name $value $Entry.OldKind
            } else {
                Remove-DebloaterRegValue $Entry.Path $Entry.Name
            }
            return (Get-DebloaterText 'msg.undo.reg' $Entry.Name)
        }
        'run' {
            $kind = [string]$Entry.ValueKind
            if (-not $kind) { $kind = 'String' }
            Set-DebloaterRegValue $Entry.Path $Entry.Name $Entry.Value $kind
            return (Get-DebloaterText 'msg.undo.run' $Entry.Name)
        }
        'wallpaper' {
            if ($Entry.Previous -and (Test-Path -LiteralPath $Entry.Previous)) {
                Initialize-DebloaterNative
                [void][Debloater.Native]::SystemParametersInfo(0x14, 0, [string]$Entry.Previous, 3)
                return (Get-DebloaterText 'msg.undo.wallpaper')
            }
            return (Get-DebloaterText 'msg.undo.skipped')
        }
        'app' {
            # Removing an app for one person leaves the copy Windows itself keeps, the
            # one a new user account would get. Registering that copy again brings the
            # app back without the Store. When Windows no longer has it, this fails and
            # the Store is the way.
            $name = [string]$Entry.Name
            if (@(Get-AppxPackage -Name $name).Count -gt 0) { return (Get-DebloaterText 'msg.undo.app.present' $name) }
            try {
                Add-AppxPackage -RegisterByFamilyName -MainPackage ([string]$Entry.Family) -ErrorAction Stop
            } catch {
                throw (Get-DebloaterText 'msg.undo.app.store' $name)
            }
            if (@(Get-AppxPackage -Name $name).Count -eq 0) { throw (Get-DebloaterText 'msg.undo.app.store' $name) }
            return (Get-DebloaterText 'msg.undo.app' $name)
        }
        'onedrive-app' {
            # Windows carries the OneDrive installer. The folders that were pointed back
            # at the user profile stay there: moving them is for the person to choose,
            # in OneDrive, once they have signed in.
            if ((Get-DebloaterOneDriveInfo).Installed) { return (Get-DebloaterText 'msg.undo.onedrive.present') }
            $setup = $null
            foreach ($folder in 'System32', 'SysWOW64') {
                $candidate = Join-Path $env:SystemRoot ($folder + '\OneDriveSetup.exe')
                if (-not $setup -and (Test-Path -LiteralPath $candidate)) { $setup = $candidate }
            }
            if (-not $setup) { throw (Get-DebloaterText 'msg.undo.onedrive.missing') }
            Start-Process -FilePath $setup -ArgumentList '/silent' -Wait
            return (Get-DebloaterText 'msg.undo.onedrive')
        }
    }
    return $null
}

# What Revert can put back: a setting, a startup entry, the desktop picture, an app,
# OneDrive itself. A record of where OneDrive's folders used to point is only a record.
function Test-DebloaterEntryUndoable {
    param($Entry)
    return ([string]$Entry.Kind -in 'reg', 'run', 'wallpaper', 'app', 'onedrive-app')
}

# The same, sorted into what the question before a revert tells apart.
function Get-DebloaterEntryGroup {
    param($Entry)
    switch ([string]$Entry.Kind) {
        'app' { return 'apps' }
        'onedrive-app' { return 'onedrive' }
        { $_ -in 'reg', 'run', 'wallpaper' } { return 'settings' }
    }
    return ''
}

# ================================================================ Runs (history)

function Get-DebloaterJournal {
    param([string]$RunDir, [string]$Scope)
    $file = Join-Path $RunDir ('journal-' + $Scope.ToLowerInvariant() + '.json')
    if (-not (Test-Path -LiteralPath $file)) { return @() }
    return @(Read-DebloaterJson $file | Where-Object { $null -ne $_ })
}

function Get-DebloaterRuns {
    $dir = Join-Path (Get-DebloaterDataRoot) 'runs'
    if (-not (Test-Path -LiteralPath $dir)) { return @() }
    $runs = @()
    foreach ($d in Get-ChildItem -LiteralPath $dir -Directory | Sort-Object Name -Descending) {
        $planPath = Join-Path $d.FullName 'plan.json'
        if (-not (Test-Path -LiteralPath $planPath)) { continue }
        $plan = $null
        try { $plan = Read-DebloaterJson $planPath } catch { continue }
        $apps = @()
        $undoable = @{ User = 0; Admin = 0 }
        foreach ($scope in 'User', 'Admin') {
            foreach ($entry in Get-DebloaterJournal $d.FullName $scope) {
                if ($entry.Kind -eq 'app') { $apps += $entry }
                if (Test-DebloaterEntryUndoable $entry) { $undoable[$scope]++ }
            }
        }
        $undone = ''
        $marker = Join-Path $d.FullName 'undone.txt'
        if (Test-Path -LiteralPath $marker) { $undone = (Get-Content -LiteralPath $marker -Raw).Trim() }
        # What the run got done: items a worker reported as finished and none as failed.
        $ok = @{}
        $failed = @{}
        foreach ($scope in 'user', 'admin') {
            foreach ($line in @(Read-DebloaterLines (Join-Path $d.FullName ('progress-' + $scope + '.jsonl')))) {
                if (-not $line.Trim()) { continue }
                $step = $null
                try { $step = $line | ConvertFrom-Json } catch { continue }
                if ([string]$step.status -eq 'ok') { $ok[[string]$step.id] = $true }
                elseif ([string]$step.status -eq 'failed') { $failed[[string]$step.id] = $true }
            }
        }
        $runs += [pscustomobject]@{
            Dir           = $d.FullName
            Id            = $d.Name
            PlanPath      = $planPath
            Created       = [string]$plan.created
            DryRun        = [bool]$plan.dryRun
            Steps         = @($plan.steps)
            Done          = @($plan.steps | Where-Object { $ok[[string]$_] -and -not $failed[[string]$_] } | ForEach-Object { [string]$_ })
            Apps          = $apps
            UndoableUser  = $undoable.User
            UndoableAdmin = $undoable.Admin
            Undone        = $undone
        }
    }
    return $runs
}

# ================================================================ Updates

# The one thing this tool asks the internet: which version is the newest. The answer is
# a small file, update.json, that every release carries. It names the version, where its
# installer is, the installer's SHA-256 and a signature made with Coursion Studio's
# update key. An installer is only ever run when both of those check out.
$script:UpdateFeed = 'https://github.com/Coursion-Studio/windows-debloater/releases/latest/download/update.json'
$script:UpdateFiles = 'https://github.com/Coursion-Studio/windows-debloater/releases/download/'
$script:UpdatePage = 'https://github.com/Coursion-Studio/windows-debloater/releases/tag/v'

# True for a copy the installer put in place, which the installer can then update.
# A copy that was only unpacked from the zip has no uninstaller next to it.
function Test-DebloaterInstalled {
    $folder = Split-Path -Parent $script:Root
    return ((Test-Path -LiteralPath (Join-Path $folder 'Uninstall.exe')) -and (Test-Path -LiteralPath (Join-Path $folder 'installed.txt')))
}

# 1 when $A is the newer version, -1 when $B is, 0 when they are the same or one of
# them is not a version at all.
function Compare-DebloaterVersion {
    param([string]$A, [string]$B)
    $first = $null
    $second = $null
    if (-not [version]::TryParse($A, [ref]$first) -or -not [version]::TryParse($B, [ref]$second)) { return 0 }
    return $first.CompareTo($second)
}

function New-DebloaterWebClient {
    # GitHub only answers over TLS 1.2 or newer, which Windows PowerShell does not
    # always offer by itself.
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $client = New-Object Net.WebClient
    $client.Encoding = [Text.Encoding]::UTF8
    # What is asking, and nothing else.
    $client.Headers['User-Agent'] = 'WindowsDebloater-Windows/' + (Get-DebloaterVersion)
    return $client
}

# An installer may only come from this project's releases on GitHub. A test hands in a
# feed of its own, a file on disk, and then the installer has to sit next to that feed.
function Test-DebloaterUpdateSource {
    param([string]$Url, [string]$Feed)
    if (-not $Feed -or $Feed -eq $script:UpdateFeed) {
        return $Url.StartsWith($script:UpdateFiles, [StringComparison]::OrdinalIgnoreCase)
    }
    $base = $Feed.Substring(0, $Feed.LastIndexOf('/') + 1)
    return $Url.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)
}

# The public half of the key that signs updates. It ships with the tool; the private
# half never leaves the maintainer's PC (see scripts\new-update-key.ps1).
function Get-DebloaterUpdateKey {
    $file = Join-Path $script:Root 'update-key.xml'
    if (-not (Test-Path -LiteralPath $file)) { return '' }
    return ([IO.File]::ReadAllText($file)).Trim()
}

# Reads the feed. Returns what is needed to offer the version it names when that is
# newer than this copy, and nothing when it is not. Throws when the feed cannot be had
# or is not complete.
function Get-DebloaterUpdate {
    param([string]$Feed, [string]$Current)
    if (-not $Feed) { $Feed = $script:UpdateFeed }
    if (-not $Current) { $Current = Get-DebloaterVersion }
    $client = New-DebloaterWebClient
    try { $entry = $client.DownloadString($Feed) | ConvertFrom-Json } finally { $client.Dispose() }

    $version = ([string](Get-OptionalProperty $entry 'version')).Trim().TrimStart('v', 'V')
    $url = [string](Get-OptionalProperty $entry 'url')
    $sha256 = [string](Get-OptionalProperty $entry 'sha256')
    $signature = [string](Get-OptionalProperty $entry 'signature')
    if (-not $version -or -not $url -or -not $sha256 -or -not $signature) { throw 'The update feed is incomplete.' }
    if ((Compare-DebloaterVersion $version $Current) -le 0) { return $null }

    $size = [int64]0
    [void][int64]::TryParse([string](Get-OptionalProperty $entry 'size'), [ref]$size)
    return [pscustomobject]@{
        Version = $version
        # One line for each thing that is new, from the changelog.
        Notes = (@(Get-OptionalProperty $entry 'notes') | ForEach-Object { [string]$_ }) -join "`n"
        Page = $script:UpdatePage + $version
        Setup = [IO.Path]::GetFileName(([Uri]$url).LocalPath)
        SetupUrl = $url; SetupSize = $size; Sha256 = $sha256; Signature = $signature
    }
}

# Checks a downloaded installer against the feed: the SHA-256 has to match, and the
# signature has to have been made over exactly these bytes with the update key.
# The first catches a damaged download. The second is the one that cannot be forged:
# someone who could change both the installer and the feed still has no key to sign with.
function Test-DebloaterUpdateFile {
    param([string]$Path, $Update, [string]$KeyXml)
    $bytes = [IO.File]::ReadAllBytes($Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() } finally { $sha.Dispose() }
    if ($hash -ne ([string]$Update.Sha256).Trim().ToLowerInvariant()) { throw (Get-DebloaterText 'update.fail.hash') }

    if (-not $KeyXml) { $KeyXml = Get-DebloaterUpdateKey }
    $signed = $false
    try {
        $rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider -ArgumentList (New-Object System.Security.Cryptography.CspParameters 24)
        try {
            $rsa.PersistKeyInCsp = $false
            $rsa.FromXmlString($KeyXml)
            $signed = $rsa.VerifyData($bytes, 'SHA256', [Convert]::FromBase64String([string]$Update.Signature))
        } finally { $rsa.Dispose() }
    } catch { $signed = $false }
    if (-not $signed) { throw (Get-DebloaterText 'update.fail.signature') }
}

# Downloads the installer of an update into the data folder and checks it. Returns the
# file, or throws and leaves nothing behind. $Progress, when given, is told how far the
# download is: Done and Total, in bytes. $Feed and $KeyXml are for tests, which keep a
# made-up release on disk and sign it with a key of their own; the window never passes
# them, so there the installer can only come from this project's releases on GitHub and
# only the key that ships with the tool counts.
function Save-DebloaterUpdate {
    param($Update, [hashtable]$Progress, [string]$Feed, [string]$KeyXml)
    if (-not $Update.SetupUrl -or -not $Update.Sha256 -or -not $Update.Signature) { throw (Get-DebloaterText 'update.fail.source') }
    if (-not (Test-DebloaterUpdateSource ([string]$Update.SetupUrl) $Feed)) { throw (Get-DebloaterText 'update.fail.source') }
    if ([string]$Update.Setup -notmatch '^WindowsDebloaterSetup-[0-9.]+\.exe$') { throw (Get-DebloaterText 'update.fail.source') }

    $folder = Join-Path (Get-DebloaterDataRoot) 'updates'
    if (Test-Path -LiteralPath $folder) { Remove-Item -LiteralPath $folder -Recurse -Force }
    [void](New-Item -ItemType Directory -Force -Path $folder)
    $target = Join-Path $folder $Update.Setup

    $client = New-DebloaterWebClient
    try {
        try {
            $source = $client.OpenRead([string]$Update.SetupUrl)
            try {
                $total = [int64]$Update.SetupSize
                $length = [int64]0
                if ($client.ResponseHeaders -and [int64]::TryParse([string]$client.ResponseHeaders['Content-Length'], [ref]$length) -and $length -gt 0) { $total = $length }
                $file = [IO.File]::Create($target)
                try {
                    $buffer = New-Object byte[] 65536
                    $done = [int64]0
                    while (($read = $source.Read($buffer, 0, $buffer.Length)) -gt 0) {
                        $file.Write($buffer, 0, $read)
                        $done += $read
                        if ($Progress) { $Progress.Done = $done; $Progress.Total = $total }
                    }
                } finally { $file.Dispose() }
            } finally { $source.Dispose() }
        } catch {
            if (Test-Path -LiteralPath $folder) { Remove-Item -LiteralPath $folder -Recurse -Force }
            throw (Get-DebloaterText 'update.fail.network')
        }
    } finally { $client.Dispose() }

    if ($Progress) { $Progress.Stage = 'check' }
    try {
        Test-DebloaterUpdateFile -Path $target -Update $Update -KeyXml $KeyXml
    } catch {
        Remove-Item -LiteralPath $folder -Recurse -Force
        throw
    }
    return $target
}

# A newer version that was found is remembered, so the window can offer it the next
# time it opens without asking GitHub again that day. One that is no longer newer than
# this copy, because the update has been done, is forgotten. What is remembered is
# checked again in full when it is downloaded.
function Get-DebloaterKnownUpdate {
    $file = Join-Path (Get-DebloaterDataRoot) 'update.json'
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    try {
        $saved = Read-DebloaterJson $file
        if ((Compare-DebloaterVersion ([string]$saved.Version) (Get-DebloaterVersion)) -gt 0) { return $saved }
    } catch {}
    try { Remove-Item -LiteralPath $file -Force } catch {}
    return $null
}

function Set-DebloaterKnownUpdate {
    param($Update)
    try {
        $root = Get-DebloaterDataRoot
        $file = Join-Path $root 'update.json'
        if ($Update) {
            [void](New-Item -ItemType Directory -Force -Path $root)
            Write-DebloaterJson $Update $file
        } elseif (Test-Path -LiteralPath $file) {
            Remove-Item -LiteralPath $file -Force
        }
    } catch {}
}

# Hands over to the downloaded installer. It waits for this window to close, puts the
# new version in place and opens it.
function Start-DebloaterUpdate {
    param([string]$Setup)
    Start-Process -FilePath $Setup -ArgumentList '/update'
}

# ================================================================ Worker

function Write-DebloaterProgress {
    param([string]$Path, [string]$Id, [string]$Status, [string]$Message)
    $line = ConvertTo-Json -InputObject ([pscustomobject]@{ id = $Id; status = $Status; message = $Message }) -Compress
    for ($try = 0; $try -lt 5; $try++) {
        try { [IO.File]::AppendAllText($Path, $line + "`n", $script:Utf8); return } catch { Start-Sleep -Milliseconds 80 }
    }
}

# Runs in a separate, hidden PowerShell process started by the window: once without
# elevation for per-user changes and once elevated for machine-wide settings. It reads
# plan.json, does the work for its scope and reports each step as a line of JSON.
function Invoke-DebloaterWorker {
    param([string]$PlanPath, [string]$Scope, [switch]$Undo)
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'

    $runDir = Split-Path -Parent $PlanPath
    $suffix = ''
    if ($Undo) { $suffix = '-undo' }
    $progress = Join-Path $runDir ('progress-' + $Scope.ToLowerInvariant() + $suffix + '.jsonl')
    $journalPath = Join-Path $runDir ('journal-' + $Scope.ToLowerInvariant() + '.json')

    try {
        $plan = Read-DebloaterJson $PlanPath
        Initialize-DebloaterLanguage ([string]$plan.lang)
        $dryRun = [bool]$plan.dryRun

        if ($Undo) {
            $entries = @(Get-DebloaterJournal $runDir $Scope)
            for ($i = $entries.Count - 1; $i -ge 0; $i--) {
                $entry = $entries[$i]
                if (-not (Test-DebloaterEntryUndoable $entry)) { continue }
                Write-DebloaterProgress $progress ([string]$entry.Item) 'start' ''
                try {
                    $message = Undo-DebloaterEntry $entry
                    Write-DebloaterProgress $progress ([string]$entry.Item) 'ok' ([string]$message)
                } catch {
                    Write-DebloaterProgress $progress ([string]$entry.Item) 'failed' $_.Exception.Message
                }
            }
        } else {
            $byId = @{}
            foreach ($item in Get-DebloaterCatalog) { $byId[$item.Id] = $item }
            $journal = New-Object System.Collections.ArrayList
            foreach ($id in @($plan.steps)) {
                $item = $byId[[string]$id]
                if (-not $item) { Write-DebloaterProgress $progress ([string]$id) 'failed' (Get-DebloaterText 'msg.unknown'); continue }
                if (-not (Test-DebloaterItemHasScope $item $Scope)) { continue }
                Write-DebloaterProgress $progress $item.Id 'start' ''
                try {
                    $messages = @(Invoke-DebloaterItem $item $Scope ([string]$plan.userSid) $dryRun $journal)
                    Write-DebloaterProgress $progress $item.Id 'ok' ($messages -join '; ')
                } catch {
                    Write-DebloaterProgress $progress $item.Id 'failed' $_.Exception.Message
                }
                if ($journal.Count -gt 0) { Write-DebloaterJson $journal.ToArray() $journalPath }
            }
        }
    } catch {
        Write-DebloaterProgress $progress '' 'fatal' $_.Exception.Message
    }
    Write-DebloaterProgress $progress '' 'done' ''
}

Export-ModuleMember -Function * -Alias *
