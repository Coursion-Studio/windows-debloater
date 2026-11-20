# Writes docs\changes.md from the catalog, so the list of what Windows Debloater changes can never
# drift away from what the code actually does.
#
#   powershell -ExecutionPolicy Bypass -File scripts\build-docs.ps1

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'src\Debloater.Engine.psm1') -Force -DisableNameChecking
Initialize-DebloaterLanguage 'en'
$catalog = @(Get-DebloaterCatalog)

$pages = @(
    @{ Id = 'apps';     Groups = @('remove', 'optional', 'gaming') },
    @{ Id = 'ads';      Groups = @('promoted', 'start', 'tips', 'privacy') },
    @{ Id = 'edge';     Groups = @('edge', 'widgets') },
    @{ Id = 'look';     Groups = @('lock', 'desktop') },
    @{ Id = 'onedrive'; Groups = @('onedrive') }
)

$actionText = @{
    RemoveEdgeAutostart  = 'Removes the `MicrosoftEdgeAutoLaunch_*` values from `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`.'
    SetDesktopPicture    = 'Sets the desktop picture to `%SystemRoot%\Web\Wallpaper\Windows\img0.jpg` (`img19.jpg` in dark mode).'
    SetLockScreenPicture = 'Sets the lock screen picture to `%SystemRoot%\Web\Screen\img100.jpg`.'
    RemoveOneDrive       = 'Downloads online-only files, copies Desktop, Documents, Pictures, Music and Videos out of the OneDrive folder, runs the OneDrive uninstaller and points the known folders back at `%USERPROFILE%`.'
}

$lines = New-Object System.Collections.ArrayList
[void]$lines.Add('# What Windows Debloater changes')
[void]$lines.Add('')
[void]$lines.Add('This file is generated from `src/catalog` by `scripts/build-docs.ps1`. Do not edit it by hand.')
[void]$lines.Add('')
[void]$lines.Add('Windows Debloater only changes what you tick. Items marked **admin** are machine-wide and need the one administrator prompt; everything else applies to the signed-in user only.')

foreach ($page in $pages) {
    [void]$lines.Add('')
    [void]$lines.Add('## ' + (Get-DebloaterText ('nav.' + $page.Id)))
    foreach ($group in $page.Groups) {
        $items = @($catalog | Where-Object { $_.Page -eq $page.Id -and $_.Group -eq $group })
        if ($items.Count -eq 0) { continue }
        [void]$lines.Add('')
        [void]$lines.Add('### ' + (Get-DebloaterText ('group.' + $page.Id + '.' + $group)))
        [void]$lines.Add('')
        foreach ($item in $items) {
            $title = Get-DebloaterItemTitle $item
            $tags = @()
            if ($item.Recommended) { $tags += 'recommended' }
            if (Test-DebloaterItemNeedsAdmin $item) { $tags += '**admin**' }
            $suffix = ''
            if ($tags.Count -gt 0) { $suffix = ' (' + ($tags -join ', ') + ')' }
            [void]$lines.Add('- **' + $title + '**' + $suffix)
            foreach ($package in @($item.Packages)) { [void]$lines.Add('  - removes the app package `' + $package + '`') }
            foreach ($entry in @($item.Registry)) {
                [void]$lines.Add('  - sets `' + $entry.Path + '\' + $entry.Name + '` to `' + $entry.Value + '`')
            }
            foreach ($action in @($item.Actions)) { [void]$lines.Add('  - ' + $actionText[$action]) }
        }
    }
}
[void]$lines.Add('')

$target = Join-Path $root 'docs\changes.md'
[IO.File]::WriteAllText($target, ($lines -join "`n"), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Wrote $target ($($catalog.Count) items)"
