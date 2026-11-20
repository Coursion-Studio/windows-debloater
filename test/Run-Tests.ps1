# Runs every check that can run without changing the PC.
#
#   powershell -ExecutionPolicy Bypass -File test\Run-Tests.ps1
#
# What it touches: a scratch registry key (HKCU\Software\DebloaterSelfTest) that it creates
# and deletes, a temporary folder, and bin\, where it builds the two programs. The
# installer is tried inside the temporary folder and the scratch key, so the real Start
# menu and the list of installed apps are left alone. The window test runs in demo mode
# off-screen and changes nothing. Use -SkipWindow to leave the window tests out.

param([switch]$SkipWindow)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$src = Join-Path $root 'src'
$script:Passed = 0
$script:Failed = 0

function Check {
    param([string]$Name, [scriptblock]$Test)
    try {
        & $Test
        $script:Passed++
        Write-Host "PASS  $Name"
    } catch {
        $script:Failed++
        Write-Host "FAIL  $Name"
        Write-Host "      $($_.Exception.Message)"
    }
}

function Assert {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$scripts = @(Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object {
    $_.Extension -in '.ps1', '.psm1' -and $_.FullName -notlike '*\dist\*' -and $_.FullName -notlike '*\bin\*' })
$jsonFiles = @(Get-ChildItem -LiteralPath $src -Recurse -File -Filter '*.json')

# ---------------------------------------------------------------- Source files

Check 'scripts parse without errors' {
    foreach ($file in $scripts) {
        $tokens = $null; $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
        Assert (@($errors).Count -eq 0) ("{0}: {1}" -f $file.Name, (@($errors | ForEach-Object { $_.Message }) -join '; '))
    }
}

Check 'scripts are plain ASCII (Windows PowerShell reads them correctly)' {
    foreach ($file in $scripts) {
        $text = [IO.File]::ReadAllText($file.FullName)
        Assert (-not [regex]::IsMatch($text, '[^\x00-\x7F]')) "$($file.Name) contains non-ASCII characters"
    }
}

Check 'the helper code compiles and is plain ASCII' {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml
    foreach ($name in 'ViewModels.cs', 'Motion.cs') {
        $file = Join-Path $src ('ui\' + $name)
        $text = [IO.File]::ReadAllText($file)
        Assert (-not [regex]::IsMatch($text, '[^\x00-\x7F]')) "$name contains non-ASCII characters"
    }
    # Built the way the window builds them; a mistake in either stops the window opening.
    Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $src 'ui\ViewModels.cs')))
    Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $src 'ui\Motion.cs'))) `
        -ReferencedAssemblies PresentationFramework, PresentationCore, WindowsBase, System.Xaml
    Assert ($null -ne ('Debloater.Ui.Glide' -as [type])) 'Motion.cs did not produce its types'
}

Check 'JSON files load' {
    foreach ($file in $jsonFiles) {
        try { [void](Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json) }
        catch { throw "$($file.Name): $($_.Exception.Message)" }
    }
}

Import-Module (Join-Path $src 'Debloater.Engine.psm1') -Force -DisableNameChecking
Initialize-DebloaterLanguage 'en'
$catalog = @(Get-DebloaterCatalog)

$pages = @{
    apps     = @('remove', 'optional', 'gaming')
    ads      = @('promoted', 'start', 'tips', 'privacy')
    edge     = @('edge', 'widgets')
    look     = @('lock', 'desktop')
    onedrive = @('onedrive')
}
$knownActions = @('RemoveEdgeAutostart', 'SetDesktopPicture', 'SetLockScreenPicture', 'RemoveOneDrive')

# ---------------------------------------------------------------- Catalog

Check 'catalog ids are unique' {
    $duplicates = @($catalog | Group-Object Id | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
    Assert ($duplicates.Count -eq 0) ("duplicate ids: " + ($duplicates -join ', '))
}

Check 'every catalog item is well formed' {
    foreach ($item in $catalog) {
        Assert ($pages.ContainsKey($item.Page)) "$($item.Id): unknown page '$($item.Page)'"
        Assert ($pages[$item.Page] -contains $item.Group) "$($item.Id): unknown group '$($item.Group)'"
        $work = @($item.Packages).Count + @($item.Registry).Count + @($item.Actions).Count
        Assert ($work -gt 0) "$($item.Id): nothing to do"
        if ($item.Kind -eq 'app') { Assert ([bool]$item.Title) "$($item.Id): no title" }
        foreach ($entry in @($item.Registry)) {
            Assert ($entry.Path -match '^(HKCU|HKLM)\\') "$($item.Id): bad registry path $($entry.Path)"
            Assert ([bool]$entry.Name) "$($item.Id): registry entry without a name"
            Assert ($null -ne $entry.Value) "$($item.Id): registry entry without a value"
        }
        foreach ($action in @($item.Actions)) {
            Assert ($knownActions -contains $action) "$($item.Id): unknown action $action"
        }
    }
}

Check 'machine-wide entries are marked as needing administrator' {
    foreach ($item in $catalog) {
        foreach ($entry in @($item.Registry)) {
            if ($entry.Path -like 'HKLM\*' -or $entry.Path -like 'HKCU\Software\Policies\*') {
                Assert ([bool]$entry.Admin) "$($item.Id): $($entry.Name) should need administrator"
            }
        }
    }
}

# ---------------------------------------------------------------- Languages

$languages = @{}
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $src 'lang') -Filter '*.json') {
    $table = @{}
    $object = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($p in $object.PSObject.Properties) { $table[$p.Name] = [string]$p.Value }
    $languages[$file.BaseName] = $table
}

Check 'every language has the same keys as English' {
    $english = $languages['en']
    foreach ($code in $languages.Keys) {
        $missing = @($english.Keys | Where-Object { -not $languages[$code].ContainsKey($_) })
        $extra = @($languages[$code].Keys | Where-Object { -not $english.ContainsKey($_) })
        Assert ($missing.Count -eq 0) ("$code is missing: " + ($missing -join ', '))
        Assert ($extra.Count -eq 0) ("$code has unknown keys: " + ($extra -join ', '))
    }
}

Check 'translations keep the same {0} placeholders' {
    $english = $languages['en']
    foreach ($code in $languages.Keys) {
        foreach ($key in $english.Keys) {
            $want = @([regex]::Matches($english[$key], '\{\d\}') | ForEach-Object { $_.Value } | Sort-Object -Unique) -join ''
            $have = @([regex]::Matches($languages[$code][$key], '\{\d\}') | ForEach-Object { $_.Value } | Sort-Object -Unique) -join ''
            Assert ($want -eq $have) ($code + ' / ' + $key + ': placeholders differ')
        }
    }
}

Check 'texts shown with a number have a wording for one and for many' {
    $english = $languages['en']
    $source = Get-Content -LiteralPath (Join-Path $src 'Debloater.UI.ps1') -Raw
    $keys = @([regex]::Matches($source, "TN '([a-z.]+)'") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    # The rows of a finished overview build their key from the page.
    $keys += 'card.fin.apps', 'card.fin.ads', 'card.fin.edge', 'card.fin.look'
    Assert ($keys.Count -gt 8) 'the numbered texts were not found in the window code'
    foreach ($key in $keys) {
        Assert ($english.ContainsKey($key)) ('missing ' + $key)
        Assert ($english[$key] -match '\{0\}') ($key + ' has no {0} for the number')
        Assert ($english.ContainsKey($key + '.one')) ('missing ' + $key + '.one')
    }
}

Check 'every item, page and group has its texts' {
    $english = $languages['en']
    foreach ($page in $pages.Keys) {
        Assert ($english.ContainsKey("nav.$page")) "missing nav.$page"
        Assert ($english.ContainsKey("page.$page.intro")) "missing page.$page.intro"
        foreach ($group in $pages[$page]) { Assert ($english.ContainsKey("group.$page.$group")) "missing group.$page.$group" }
    }
    foreach ($item in $catalog) {
        if ($item.Kind -eq 'app') {
            if ($item.NoteKey) { Assert ($english.ContainsKey($item.NoteKey)) "missing $($item.NoteKey)" }
        } else {
            Assert ($english.ContainsKey("item.$($item.Id).title")) "missing item.$($item.Id).title"
            Assert ($english.ContainsKey("item.$($item.Id).desc")) "missing item.$($item.Id).desc"
        }
    }
}

# ---------------------------------------------------------------- Engine

Check 'scan returns a state for every item' {
    $state = Get-DebloaterState -Catalog $catalog
    foreach ($item in $catalog) {
        Assert ($state.ContainsKey($item.Id)) "no state for $($item.Id)"
        Assert ($state[$item.Id].State -in 'todo', 'done', 'absent') "bad state for $($item.Id)"
    }
}

Check 'an elevated worker reaches the user hive through HKEY_USERS' {
    Assert ((Resolve-DebloaterRegPath 'HKCU\Software\X' 'S-1-5-21-1') -eq 'Registry::HKEY_USERS\S-1-5-21-1\Software\X') 'HKCU with SID'
    Assert ((Resolve-DebloaterRegPath 'HKCU\Software\X' $null) -eq 'Registry::HKEY_CURRENT_USER\Software\X') 'HKCU without SID'
    Assert ((Resolve-DebloaterRegPath 'HKLM\SOFTWARE\X' 'S-1-5-21-1') -eq 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\X') 'HKLM'
}

$scratchKey = 'HKCU:\Software\DebloaterSelfTest'
$scratchItem = [pscustomobject]@{
    Id = 'test.scratch'; Kind = 'tweak'; Page = 'ads'; Group = 'tips'; Recommended = $false
    Title = ''; NoteKey = ''; Packages = @(); Actions = @()
    Registry = @(
        [pscustomobject]@{ Path = 'HKCU\Software\DebloaterSelfTest\Key'; Name = 'Existing'; Value = 0; Type = 'DWord'; Admin = $false },
        [pscustomobject]@{ Path = 'HKCU\Software\DebloaterSelfTest\Key'; Name = 'Fresh'; Value = 1; Type = 'DWord'; Admin = $false },
        [pscustomobject]@{ Path = 'HKCU\Software\DebloaterSelfTest\Other'; Name = 'Elsewhere'; Value = 1; Type = 'DWord'; Admin = $false }
    )
}

function Reset-Scratch {
    if (Test-Path $scratchKey) { Remove-Item -Path $scratchKey -Recurse -Force }
    [void](New-Item -Path "$scratchKey\Key" -Force)
    [void](New-ItemProperty -Path "$scratchKey\Key" -Name 'Existing' -Value 5 -PropertyType DWord -Force)
    [void](New-ItemProperty -Path "$scratchKey\Key" -Name 'Untouched' -Value 'keep me' -PropertyType String -Force)
}

function Get-Scratch {
    param([string]$SubKey, [string]$Name)
    return (Get-DebloaterRegValue ("Registry::HKEY_CURRENT_USER\Software\DebloaterSelfTest\" + $SubKey) $Name)
}

Check 'a dry run changes nothing and records nothing' {
    Reset-Scratch
    $journal = New-Object System.Collections.ArrayList
    $messages = @(Invoke-DebloaterItem $scratchItem 'User' $null $true $journal)
    Assert ($journal.Count -eq 0) 'journal is not empty'
    Assert ((Get-Scratch 'Key' 'Existing').Value -eq 5) 'Existing was changed'
    Assert (-not (Get-Scratch 'Key' 'Fresh').Exists) 'Fresh was created'
    Assert ($messages.Count -eq 3) "expected 3 messages, got $($messages.Count)"
}

Check 'apply sets the values and records the old ones' {
    Reset-Scratch
    $script:scratchJournal = New-Object System.Collections.ArrayList
    [void](Invoke-DebloaterItem $scratchItem 'User' $null $false $script:scratchJournal)
    Assert ((Get-Scratch 'Key' 'Existing').Value -eq 0) 'Existing not set'
    Assert ((Get-Scratch 'Key' 'Fresh').Value -eq 1) 'Fresh not set'
    Assert ((Get-Scratch 'Other' 'Elsewhere').Value -eq 1) 'Elsewhere not set'
    Assert ((Get-Scratch 'Key' 'Untouched').Value -eq 'keep me') 'an unrelated value was lost'
    Assert ($script:scratchJournal.Count -eq 3) 'journal should have 3 entries'
}

Check 'applying again does nothing' {
    $journal = New-Object System.Collections.ArrayList
    [void](Invoke-DebloaterItem $scratchItem 'User' $null $false $journal)
    Assert ($journal.Count -eq 0) 'second apply recorded changes'
}

Check 'undo survives a round trip through the journal file and restores everything' {
    $file = Join-Path $env:TEMP ('debloater-journal-' + [guid]::NewGuid().ToString('N') + '.json')
    try {
        Write-DebloaterJson $script:scratchJournal.ToArray() $file
        $entries = @(Read-DebloaterJson $file)
        for ($i = $entries.Count - 1; $i -ge 0; $i--) { [void](Undo-DebloaterEntry $entries[$i]) }
    } finally {
        if (Test-Path $file) { Remove-Item -LiteralPath $file -Force }
    }
    Assert ((Get-Scratch 'Key' 'Existing').Value -eq 5) 'Existing not restored'
    Assert (-not (Get-Scratch 'Key' 'Fresh').Exists) 'Fresh not removed'
    Assert (-not (Get-Scratch 'Other' 'Elsewhere').Exists) 'Elsewhere not removed'
    Assert ((Get-Scratch 'Key' 'Untouched').Value -eq 'keep me') 'an unrelated value was lost'
}

if (Test-Path $scratchKey) { Remove-Item -Path $scratchKey -Recurse -Force }

# ---------------------------------------------------------------- Workers and window (dry run)

$temp = Join-Path $env:TEMP ('debloater-test-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Force -Path $temp)
$env:DEBLOATER_DATA = Join-Path $temp 'data'
$entryScript = Join-Path $src 'Debloater.ps1'

Check 'both workers get through every item in a dry run' {
    $runDir = Join-Path $temp 'run'
    [void](New-Item -ItemType Directory -Force -Path $runDir)
    $plan = [pscustomobject]@{
        runId = 'test'; created = (Get-Date).ToString('s'); version = (Get-DebloaterVersion)
        userSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        dryRun = $true; lang = 'en'; steps = @($catalog | ForEach-Object { $_.Id })
    }
    $planPath = Join-Path $runDir 'plan.json'
    Write-DebloaterJson $plan $planPath
    foreach ($scope in 'Admin', 'User') {
        $arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $entryScript + '" -Worker -PlanPath "' + $planPath + '" -Scope ' + $scope
        $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WindowStyle Hidden -PassThru
        Assert ($process.WaitForExit(180000)) "$scope worker did not finish"
        $events = @(Read-DebloaterLines (Join-Path $runDir ('progress-' + $scope.ToLower() + '.jsonl')) | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })
        Assert (@($events | Where-Object { $_.status -eq 'done' }).Count -eq 1) "$scope worker did not report done"
        $bad = @($events | Where-Object { $_.status -in 'failed', 'fatal' })
        Assert ($bad.Count -eq 0) ("$scope worker failures: " + (@($bad | ForEach-Object { $_.id + ' ' + $_.message }) -join ' | '))
        $expected = @($catalog | Where-Object { Test-DebloaterItemHasScope $_ $scope }).Count
        Assert (@($events | Where-Object { $_.status -eq 'ok' }).Count -eq $expected) "$scope worker handled a different number of items than expected"
        Assert (-not (Test-Path (Join-Path $runDir ('journal-' + $scope.ToLower() + '.json')))) "$scope worker wrote a journal in a dry run"
    }
}

Check 'history reports what each run got done' {
    $runDir = Join-Path $env:DEBLOATER_DATA 'runs\2000-01-01_00-00-00'
    [void](New-Item -ItemType Directory -Force -Path $runDir)
    $plan = [pscustomobject]@{ runId = 'test'; created = '2000-01-01 00:00:00'; dryRun = $false; lang = 'en'; steps = @('a', 'b', 'c') }
    Write-DebloaterJson $plan (Join-Path $runDir 'plan.json')
    Write-DebloaterProgress (Join-Path $runDir 'progress-user.jsonl') 'a' 'ok' ''
    Write-DebloaterProgress (Join-Path $runDir 'progress-user.jsonl') 'b' 'ok' ''
    Write-DebloaterProgress (Join-Path $runDir 'progress-admin.jsonl') 'b' 'failed' 'no'
    $run = @(Get-DebloaterRuns | Where-Object { $_.Dir -eq $runDir }) | Select-Object -First 1
    Assert ($null -ne $run) 'the run was not listed'
    # b failed in one worker and c was never reached, so only a counts as done.
    Assert ((@($run.Done) -join ',') -eq 'a') ('expected only a, got: ' + (@($run.Done) -join ','))
    Remove-Item -LiteralPath $runDir -Recurse -Force
}

Check 'every page has an icon' {
    foreach ($name in 'overview', 'apps', 'ads', 'edge', 'look', 'onedrive', 'history', 'settings') {
        Assert (Test-Path -LiteralPath (Join-Path $src ('ui\icons\' + $name + '.png'))) "missing ui\icons\$name.png (put it in design\icons and run scripts\import-icons.ps1)"
    }
}

# The README says how many changes are recommended and how many are optional. Those
# numbers come from the catalog, so they must move when the catalog does.
Check 'the README quotes the number of changes the catalog holds' {
    $readme = [IO.File]::ReadAllText((Join-Path $root 'README.md'))
    $recommended = @($catalog | Where-Object { $_.Recommended }).Count
    $optional = $catalog.Count - $recommended
    Assert ($readme.Contains("the recommended selection: $recommended changes")) "the README should say the recommended selection is $recommended changes"
    Assert ($readme.Contains("Another $optional are there")) "the README should say another $optional are optional"
    Assert ($readme.Contains("The $optional optional changes")) "the README should head its list of optional changes with their number, $optional"
}

Check 'every picture the README shows exists' {
    $readme = [IO.File]::ReadAllText((Join-Path $root 'README.md'))
    $shown = @([regex]::Matches($readme, '(?:src="|\]\()(docs/[^")]+)') | ForEach-Object { $_.Groups[1].Value })
    Assert ($shown.Count -ge 10) 'the README shows fewer pictures than it should'
    foreach ($picture in $shown) {
        Assert (Test-Path -LiteralPath (Join-Path $root $picture.Replace('/', '\'))) ('the README shows a file that does not exist: ' + $picture)
    }
}
# ---------------------------------------------------------------- Revert

# Bringing an app back means asking Windows to register a package again, which a test
# must not do. For this one check the two commands involved are stand-ins that keep
# their own list of what is "installed" and what Windows "still has a copy of".
Check 'revert brings a removed app back from the copy Windows keeps, and says so when there is none' {
    $global:DebloaterTestApps = @{ Present = @{}; Kept = @{ 'Contoso.Kept' = $true } }
    function global:Get-AppxPackage {
        [CmdletBinding()] param([string]$Name)
        if ($global:DebloaterTestApps.Present[$Name]) { [pscustomobject]@{ Name = $Name } }
    }
    function global:Add-AppxPackage {
        [CmdletBinding()] param([switch]$RegisterByFamilyName, [string]$MainPackage)
        $name = $MainPackage.Split('_')[0]
        if (-not $global:DebloaterTestApps.Kept[$name]) { throw 'Deployment failed: the package could not be found.' }
        $global:DebloaterTestApps.Present[$name] = $true
    }
    try {
        $kept = [pscustomobject]@{ Kind = 'app'; Item = 'x'; Name = 'Contoso.Kept'; Family = 'Contoso.Kept_8wekyb3d8bbwe' }
        $gone = [pscustomobject]@{ Kind = 'app'; Item = 'x'; Name = 'Contoso.Gone'; Family = 'Contoso.Gone_8wekyb3d8bbwe' }
        Assert (Test-DebloaterEntryUndoable $kept) 'a removed app does not count as something Revert can put back'
        Assert ((Get-DebloaterEntryGroup $kept) -eq 'apps') 'a removed app is not counted with the apps'
        Assert ((Get-DebloaterEntryGroup ([pscustomobject]@{ Kind = 'reg' })) -eq 'settings') 'a registry value is not counted with the settings'
        Assert ((Get-DebloaterEntryGroup ([pscustomobject]@{ Kind = 'onedrive-app' })) -eq 'onedrive') 'OneDrive is not counted on its own'
        Assert (-not (Test-DebloaterEntryUndoable ([pscustomobject]@{ Kind = 'onedrive' }))) 'the record of where folders pointed is treated as something to undo'

        Assert ((Undo-DebloaterEntry $kept) -eq (Get-DebloaterText 'msg.undo.app' 'Contoso.Kept')) 'bringing an app back did not report it'
        Assert ([bool]$global:DebloaterTestApps.Present['Contoso.Kept']) 'the app was not registered again'
        Assert ((Undo-DebloaterEntry $kept) -eq (Get-DebloaterText 'msg.undo.app.present' 'Contoso.Kept')) 'an app that is already there was registered a second time'

        $said = ''
        try { [void](Undo-DebloaterEntry $gone) } catch { $said = $_.Exception.Message }
        Assert ($said -eq (Get-DebloaterText 'msg.undo.app.store' 'Contoso.Gone')) ('an app Windows no longer has should point at the Store, not say: ' + $said)
    } finally {
        Remove-Item -Path Function:\Get-AppxPackage, Function:\Add-AppxPackage -ErrorAction SilentlyContinue
        Remove-Variable -Name DebloaterTestApps -Scope Global -ErrorAction SilentlyContinue
    }
    Assert ((Get-Command Get-AppxPackage).CommandType -eq 'Cmdlet') 'the stand-in for Get-AppxPackage was left behind'
}

# ---------------------------------------------------------------- Updates

Check 'version numbers are compared as numbers' {
    Assert ((Compare-DebloaterVersion '0.10.0' '0.9.0') -gt 0) '0.10.0 should be newer than 0.9.0'
    Assert ((Compare-DebloaterVersion '0.4.0' '0.4.0') -eq 0) 'a version should equal itself'
    Assert ((Compare-DebloaterVersion '0.3.9' '0.4.0') -lt 0) '0.3.9 should be older than 0.4.0'
    Assert ((Compare-DebloaterVersion 'nonsense' '0.4.0') -eq 0) 'something that is no version should never count as newer'
}

Check 'an update may only come from this project on GitHub' {
    $official = 'https://github.com/Coursion-Studio/windows-debloater/releases/download/v9.9.9/WindowsDebloaterSetup-9.9.9.exe'
    Assert (Test-DebloaterUpdateSource $official '') 'the project''s own release was refused'
    foreach ($other in 'https://github.com/someone-else/windows-debloater/releases/download/v9.9.9/x.exe',
                       'https://example.com/WindowsDebloaterSetup-9.9.9.exe',
                       'http://github.com/Coursion-Studio/windows-debloater/releases/download/v9.9.9/x.exe',
                       'file:///C:/somewhere/WindowsDebloaterSetup-9.9.9.exe') {
        Assert (-not (Test-DebloaterUpdateSource $other '')) "$other was accepted as a source"
    }
}

# A made-up release kept in a folder and read through file:// addresses, signed with a
# key made for this test, so that finding, downloading and checking can be tried without
# the internet and without the real signing key.
Check 'an update is found and downloaded, and only a signed, untouched installer is accepted' {
    $feedDir = Join-Path $temp 'feed'
    [void](New-Item -ItemType Directory -Force -Path $feedDir)
    $name = 'WindowsDebloaterSetup-9.9.9.exe'
    $installer = Join-Path $feedDir $name
    $bytes = New-Object byte[] 150000
    (New-Object Random 7).NextBytes($bytes)
    [IO.File]::WriteAllBytes($installer, $bytes)
    $base = ([Uri]($feedDir + '\')).AbsoluteUri
    $feed = $base + 'update.json'

    $key = New-Object System.Security.Cryptography.RSACryptoServiceProvider -ArgumentList 2048, (New-Object System.Security.Cryptography.CspParameters 24)
    $key.PersistKeyInCsp = $false
    $publicKey = $key.ToXmlString($false)
    $other = New-Object System.Security.Cryptography.RSACryptoServiceProvider -ArgumentList 2048, (New-Object System.Security.Cryptography.CspParameters 24)
    $other.PersistKeyInCsp = $false

    function Get-TestHash { param([byte[]]$Data)
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($Data))).Replace('-', '').ToLowerInvariant() } finally { $sha.Dispose() }
    }
    # Writes the feed the way scripts\build-release.ps1 does.
    function Set-TestFeed { param([string]$Version, [string]$Sha256, [string]$Signature)
        $entry = [ordered]@{
            version = $Version; published = '2026-01-01'; url = $base + $name; sha256 = $Sha256; signature = $Signature
            size = $bytes.Length; notes = @('One thing is new.', 'Another thing is fixed.')
        }
        [IO.File]::WriteAllText((Join-Path $feedDir 'update.json'), ($entry | ConvertTo-Json -Depth 3))
    }
    function Get-Refusal { param($Update)
        try { [void](Save-DebloaterUpdate -Update $Update -Feed $feed -KeyXml $publicKey); return '' } catch { return $_.Exception.Message }
    }

    $saved = $env:DEBLOATER_DATA
    $env:DEBLOATER_DATA = Join-Path $temp 'update-data'
    try {
        $genuine = [Convert]::ToBase64String($key.SignData($bytes, 'SHA256'))
        Set-TestFeed '9.9.9' (Get-TestHash $bytes) $genuine

        $update = Get-DebloaterUpdate -Feed $feed -Current '0.4.0'
        Assert ($null -ne $update -and $update.Version -eq '9.9.9') 'the newer version was not found'
        Assert ($update.Setup -eq $name -and $update.SetupSize -eq $bytes.Length) 'the installer of the release was not picked out'
        Assert ($update.Notes -eq "One thing is new.`nAnother thing is fixed.") 'the notes of the release were not read'
        Assert ($update.Page -eq 'https://github.com/Coursion-Studio/windows-debloater/releases/tag/v9.9.9') 'the page of the release is wrong'
        Assert ($null -eq (Get-DebloaterUpdate -Feed $feed -Current '9.9.9')) 'the version already in use was offered as an update'
        Assert ($null -eq (Get-DebloaterUpdate -Feed $feed -Current '10.0.0')) 'an older version was offered as an update'

        # Genuine: accepted, and where it was said to be.
        $progress = [hashtable]::Synchronized(@{ Done = [int64]0; Total = [int64]0; Stage = 'download' })
        $file = Save-DebloaterUpdate -Update $update -Progress $progress -Feed $feed -KeyXml $publicKey
        Assert (Test-Path -LiteralPath $file) 'the download is not where it was said to be'
        Assert ((Get-TestHash ([IO.File]::ReadAllBytes($file))) -eq (Get-TestHash $bytes)) 'the download differs from the original'
        Assert ($progress.Done -eq $bytes.Length -and $progress.Stage -eq 'check') 'the download did not report how far it was'

        # Without a feed of its own the installer has to come from GitHub, so this one is refused unread.
        $said = ''
        try { [void](Save-DebloaterUpdate -Update $update -KeyXml $publicKey) } catch { $said = $_.Exception.Message }
        Assert ($said -eq (Get-DebloaterText 'update.fail.source')) ('a download from outside GitHub was not refused: ' + $said)

        # The key that ships with the tool did not sign this, so without the test's key it is refused.
        $said = ''
        try { [void](Save-DebloaterUpdate -Update $update -Feed $feed) } catch { $said = $_.Exception.Message }
        Assert ($said -eq (Get-DebloaterText 'update.fail.signature')) ('an installer signed with some other key was accepted: ' + $said)

        # 1. One byte of the installer changed: the checksum no longer matches.
        $changed = [byte[]]$bytes.Clone()
        $changed[1000] = $changed[1000] -bxor 1
        [IO.File]::WriteAllBytes($installer, $changed)
        Assert ((Get-Refusal $update) -eq (Get-DebloaterText 'update.fail.hash')) 'a changed installer was not refused for its checksum'
        Assert (-not (Test-Path -LiteralPath (Join-Path $env:DEBLOATER_DATA 'updates'))) 'a refused download was kept'

        # 2. The installer changed and the feed's checksum changed with it: the signature no longer fits.
        Set-TestFeed '9.9.9' (Get-TestHash $changed) $genuine
        $forged = Get-DebloaterUpdate -Feed $feed -Current '0.4.0'
        Assert ((Get-Refusal $forged) -eq (Get-DebloaterText 'update.fail.signature')) 'a changed installer with a matching checksum was accepted'

        # 3. Signed, but by someone else's key.
        Set-TestFeed '9.9.9' (Get-TestHash $changed) ([Convert]::ToBase64String($other.SignData($changed, 'SHA256')))
        $foreign = Get-DebloaterUpdate -Feed $feed -Current '0.4.0'
        Assert ((Get-Refusal $foreign) -eq (Get-DebloaterText 'update.fail.signature')) 'an installer signed with another key was accepted'

        # 4. A signature that is not one at all.
        Set-TestFeed '9.9.9' (Get-TestHash $changed) 'not a signature'
        $junk = Get-DebloaterUpdate -Feed $feed -Current '0.4.0'
        Assert ((Get-Refusal $junk) -eq (Get-DebloaterText 'update.fail.signature')) 'an installer with a junk signature was accepted'
        Assert (-not (Test-Path -LiteralPath (Join-Path $env:DEBLOATER_DATA 'updates'))) 'a refused download was kept'

        # A feed that leaves out the signature is not a feed.
        [IO.File]::WriteAllText((Join-Path $feedDir 'update.json'), '{ "version": "9.9.9", "url": "x", "sha256": "y" }')
        $said = ''
        try { [void](Get-DebloaterUpdate -Feed $feed -Current '0.4.0') } catch { $said = $_.Exception.Message }
        Assert ($said -like '*incomplete*') 'a feed without a signature was taken as complete'

        # What was found is remembered until this copy has caught up with it.
        Set-DebloaterKnownUpdate $update
        Assert ((Get-DebloaterKnownUpdate).Version -eq '9.9.9') 'a found update was not remembered'
        Set-DebloaterKnownUpdate ([pscustomobject]@{ Version = '0.0.1' })
        Assert ($null -eq (Get-DebloaterKnownUpdate)) 'an update older than this copy was still offered'
        Assert (-not (Test-Path -LiteralPath (Join-Path $env:DEBLOATER_DATA 'update.json'))) 'an outdated note of an update was kept'
    } finally {
        $env:DEBLOATER_DATA = $saved
        $key.Dispose()
        $other.Dispose()
    }
}

Check 'the tool carries the public half of the update key, and only that' {
    $file = Join-Path $src 'update-key.xml'
    Assert (Test-Path -LiteralPath $file) 'src\update-key.xml is missing; run scripts\new-update-key.ps1 once'
    $xml = [IO.File]::ReadAllText($file)
    Assert ($xml -match '<Modulus>' -and $xml -match '<Exponent>') 'src\update-key.xml is not an RSA key'
    Assert ($xml -notmatch '<D>|<P>|<Q>|<DP>|<DQ>|<InverseQ>') 'src\update-key.xml holds the PRIVATE key; it must never be in this folder'
    Assert ((Get-DebloaterUpdateKey) -eq $xml.Trim()) 'the tool does not read the key that ships with it'
    # No private key anywhere in the project.
    foreach ($found in @(Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object {
            $_.Extension -in '.xml', '.json', '.txt', '.ps1', '.psm1', '.cs', '.md' -and $_.Length -lt 400000 -and
            $_.FullName -notlike '*\dist\*' -and $_.FullName -notlike '*\bin\*' -and $_.FullName -ne $PSCommandPath })) {
        Assert ([IO.File]::ReadAllText($found.FullName) -notmatch '<InverseQ>') "$($found.Name) holds a private key"
    }
    # Where the maintainer's private half is on this PC, it has to be the one the public half belongs to.
    $private = Join-Path $env:APPDATA 'Coursion\keys\windows-debloater-update.xml'
    if (Test-Path -LiteralPath $private) {
        $signer = New-Object System.Security.Cryptography.RSACryptoServiceProvider -ArgumentList (New-Object System.Security.Cryptography.CspParameters 24)
        $checker = New-Object System.Security.Cryptography.RSACryptoServiceProvider -ArgumentList (New-Object System.Security.Cryptography.CspParameters 24)
        try {
            $signer.PersistKeyInCsp = $false
            $checker.PersistKeyInCsp = $false
            $signer.FromXmlString([IO.File]::ReadAllText($private))
            $checker.FromXmlString($xml)
            $sample = [Text.Encoding]::ASCII.GetBytes('windows-debloater')
            Assert ($checker.VerifyData($sample, 'SHA256', $signer.SignData($sample, 'SHA256'))) 'the private key on this PC and src\update-key.xml are not a pair'
        } finally { $signer.Dispose(); $checker.Dispose() }
    }
}

# ---------------------------------------------------------------- The programs

$binDir = Join-Path $root 'bin'
$appExe = Join-Path $binDir 'WindowsDebloater.exe'
$setupExe = Join-Path $binDir 'WindowsDebloaterSetup.exe'

Check 'the program and the installer build, and carry the version' {
    foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $root 'exe'), (Join-Path $root 'setup') -Filter '*.cs')) {
        Assert (-not [regex]::IsMatch([IO.File]::ReadAllText($file.FullName), '[^\x00-\x7F]')) "$($file.Name) contains non-ASCII characters"
    }
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'scripts\build-exe.ps1') 2>&1
    Assert ($LASTEXITCODE -eq 0) ("the build failed: " + ($output -join ' '))
    $version = Get-DebloaterVersion
    foreach ($file in $appExe, $setupExe) {
        Assert (Test-Path -LiteralPath $file) "$(Split-Path -Leaf $file) was not built"
        $info = (Get-Item -LiteralPath $file).VersionInfo
        Assert ($info.ProductVersion -eq $version) "$(Split-Path -Leaf $file) says version $($info.ProductVersion), src\version.txt says $version"
        Assert ($info.CompanyName -eq 'Coursion Studio') "$(Split-Path -Leaf $file) has no publisher name"
    }
}

Check 'the installer has its texts in every language' {
    $english = $languages['en']
    $wanted = @()
    foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $root 'setup') -Filter '*.cs')) {
        $wanted += @([regex]::Matches([IO.File]::ReadAllText($file.FullName), '"(setup\.[a-z.]+[a-z])"') | ForEach-Object { $_.Groups[1].Value })
    }
    # Keys put together from a word while the installer runs.
    foreach ($word in 'install', 'update', 'reinstall') { $wanted += "setup.$word.heading", "setup.btn.$word" }
    foreach ($word in 'install', 'update', 'uninstall') { $wanted += "setup.work.$word" }
    foreach ($step in 'start', 'close', 'copy', 'shortcut', 'unlink', 'register', 'files', 'done') { $wanted += "setup.step.$step" }
    $wanted = @($wanted | Sort-Object -Unique)
    Assert ($wanted.Count -gt 30) 'the installer''s texts were not found in its code'
    foreach ($key in $wanted) { Assert ($english.ContainsKey($key)) "the installer asks for a text that does not exist: $key" }
    $unused = @($english.Keys | Where-Object { $_ -like 'setup.*' -and $wanted -notcontains $_ })
    Assert ($unused.Count -eq 0) ('texts for the installer that it never shows: ' + ($unused -join ', '))
}

Check 'the setup window draws every one of its pages, in every language' {
    Assert (Test-Path -LiteralPath $setupExe) 'the installer was not built'
    foreach ($code in $languages.Keys) {
        $shots = Join-Path $temp ('setup-pages-' + $code)
        $process = Start-Process -FilePath $setupExe -ArgumentList ('"/shots=' + $shots + '" /lang=' + $code + ' "/sandbox=' + (Join-Path $temp 'shot-box') + '"') -PassThru
        Assert ($process.WaitForExit(90000)) 'drawing the setup window did not finish'
        Assert ($process.ExitCode -eq 0) "drawing the setup window in $code failed; see %TEMP%\WindowsDebloaterSetup.log"
        $pages = @(Get-ChildItem -LiteralPath $shots -Filter 'setup-*.png' | Where-Object { $_.Length -gt 20000 })
        Assert ($pages.Count -eq 11) "expected 11 pages of the setup window in $code, got $($pages.Count)"
    }
}

# Runs the installer with everything pointed at a folder in TEMP and at the scratch
# registry key, so the real Start menu and the real list of installed apps never see it.
function Invoke-TestSetup {
    param([string]$Program, [string]$Box, [string]$Arguments)
    $process = Start-Process -FilePath $Program -ArgumentList ($Arguments + ' "/sandbox=' + $Box + '"') -PassThru
    Assert ($process.WaitForExit(60000)) 'the installer did not finish'
    return $process.ExitCode
}

Check 'the installer puts the program in place, updates it and takes it away again' {
    Assert (Test-Path -LiteralPath $setupExe) 'the installer was not built'
    # A space in the path, because a user name can have one.
    $box = Join-Path $temp 'setup box'
    $dir = Join-Path $box 'program files'
    $entry = "$scratchKey\Uninstall"
    try {
        Assert ((Invoke-TestSetup $setupExe $box '/S /desktop') -eq 0) 'installing failed'
        foreach ($name in 'WindowsDebloater.exe', 'Uninstall.exe', 'installed.txt', 'LICENSE.md', 'docs\changes.md', 'src\Debloater.ps1') {
            Assert (Test-Path -LiteralPath (Join-Path $dir $name)) "$name was not installed"
        }
        $wanted = @(Get-ChildItem -LiteralPath $src -Recurse -File | ForEach-Object { $_.FullName.Substring($src.Length) } | Sort-Object)
        $found = @(Get-ChildItem -LiteralPath (Join-Path $dir 'src') -Recurse -File | ForEach-Object { $_.FullName.Substring((Join-Path $dir 'src').Length) } | Sort-Object)
        Assert (($wanted -join '|') -eq ($found -join '|')) 'the installed src folder differs from the one here'

        $shell = New-Object -ComObject Shell.Application
        foreach ($place in 'start menu', 'desktop') {
            $link = $shell.Namespace((Join-Path $box $place)).ParseName('Windows Debloater.lnk')
            Assert ($null -ne $link) "no shortcut in the $place"
            Assert ($link.GetLink.Path -eq (Join-Path $dir 'WindowsDebloater.exe')) "the $place shortcut points at $($link.GetLink.Path)"
            # The id the window gives itself; with it the taskbar treats them as one program.
            Assert ($link.ExtendedProperty('System.AppUserModel.ID') -eq 'Coursion.WindowsDebloater') "the $place shortcut has no application id"
        }

        $listed = Get-ItemProperty -LiteralPath $entry
        Assert ($listed.DisplayName -eq 'Windows Debloater') 'the entry for Installed apps has the wrong name'
        Assert ($listed.DisplayVersion -eq (Get-DebloaterVersion)) 'the entry for Installed apps has the wrong version'
        Assert ($listed.InstallLocation -eq $dir) 'the entry for Installed apps has the wrong folder'
        Assert ($listed.UninstallString -eq ('"' + (Join-Path $dir 'Uninstall.exe') + '" /uninstall')) 'the entry for Installed apps cannot uninstall'

        # An update takes a file the older version listed and leaves a stranger alone.
        [IO.File]::WriteAllText((Join-Path $dir 'src\gone-in-this-version.ps1'), '# old')
        [IO.File]::AppendAllText((Join-Path $dir 'installed.txt'), "src\gone-in-this-version.ps1`r`n")
        [IO.File]::WriteAllText((Join-Path $dir 'my notes.txt'), 'not the installer''s')
        Assert ((Invoke-TestSetup $setupExe $box '/S') -eq 0) 'updating failed'
        Assert (-not (Test-Path -LiteralPath (Join-Path $dir 'src\gone-in-this-version.ps1'))) 'an update left a file of the older version behind'
        Assert (Test-Path -LiteralPath (Join-Path $dir 'my notes.txt')) 'an update deleted a file that was not its own'
        Assert (Test-Path -LiteralPath (Join-Path $dir 'src\Debloater.ps1')) 'an update lost the scripts'

        if (-not $SkipWindow) {
            # The way the tool updates itself: the installer shows only its bar, puts
            # the files in place and opens the program again. In a sandbox "opening"
            # is the program's off-screen walk in demo mode, the same one the scripts
            # do further down, so this also proves the installed program works.
            $out = Join-Path $box 'launched'
            $saved = $env:DEBLOATER_DATA
            $env:DEBLOATER_DATA = Join-Path $box 'data'
            try {
                Assert ((Invoke-TestSetup $setupExe $box '/update') -eq 0) 'updating the way the tool updates itself failed'
                $reportFile = Join-Path $out 'selftest.json'
                $problem = Join-Path $out 'exe-error.txt'
                for ($wait = 0; $wait -lt 600 -and -not (Test-Path -LiteralPath $reportFile) -and -not (Test-Path -LiteralPath $problem); $wait++) { Start-Sleep -Milliseconds 500 }
            } finally { $env:DEBLOATER_DATA = $saved }
            Assert (-not (Test-Path -LiteralPath $problem)) ('the program opened after the update reported: ' + $(if (Test-Path -LiteralPath $problem) { Get-Content -LiteralPath $problem -Raw }))
            Assert (Test-Path -LiteralPath $reportFile) 'the program was not opened after the update, or never finished its walk'
            $report = Get-Content -LiteralPath $reportFile -Raw | ConvertFrom-Json
            Assert ([bool]$report.ok) ("the walk of the program opened after the update: " + $report.error)
            Assert ($report.done -eq $catalog.Count -and $report.failed -eq 0) 'the installed program did not get through every item'
            Assert ([bool]$report.updateShown) 'the installed program did not show its update sheet'
            # The program has just written its report; give it a moment to close.
            for ($wait = 0; $wait -lt 40 -and @(Get-Process -Name WindowsDebloater -ErrorAction SilentlyContinue | Where-Object { $_.Path -like ($dir + '\*') }).Count -gt 0; $wait++) { Start-Sleep -Milliseconds 250 }
        }

        # Uninstalling keeps the history unless asked, and never takes the stranger.
        [void](New-Item -ItemType Directory -Force -Path (Join-Path $box 'data\runs\20260101-000000'))
        [IO.File]::WriteAllText((Join-Path $box 'data\settings.json'), '{}')
        Assert ((Invoke-TestSetup (Join-Path $dir 'Uninstall.exe') $box '/uninstall /S') -eq 0) 'uninstalling failed'
        # The uninstaller deletes itself a moment after it ends.
        for ($wait = 0; $wait -lt 40 -and (Test-Path -LiteralPath (Join-Path $dir 'Uninstall.exe')); $wait++) { Start-Sleep -Milliseconds 250 }
        $left = @(Get-ChildItem -LiteralPath $dir -Recurse -File | ForEach-Object { $_.Name })
        Assert (($left -join ',') -eq 'my notes.txt') ('uninstalling left: ' + ($left -join ', '))
        foreach ($place in 'start menu', 'desktop') {
            Assert (-not (Test-Path -LiteralPath (Join-Path $box "$place\Windows Debloater.lnk"))) "uninstalling left the $place shortcut"
        }
        Assert (-not (Test-Path -LiteralPath $entry)) 'uninstalling left the entry for Installed apps'
        Assert (Test-Path -LiteralPath (Join-Path $box 'data\runs\20260101-000000')) 'uninstalling deleted the history without being asked'

        # With /purge the history goes too.
        Assert ((Invoke-TestSetup $setupExe $box '/S') -eq 0) 'installing again failed'
        Assert ((Invoke-TestSetup $setupExe $box '/uninstall /S /purge') -eq 0) 'uninstalling with /purge failed'
        Assert (-not (Test-Path -LiteralPath (Join-Path $box 'data'))) 'uninstalling with /purge left the history'
        Assert (-not (Test-Path -LiteralPath (Join-Path $dir 'WindowsDebloater.exe'))) 'uninstalling from the installer itself left the program'
    } finally {
        if (Test-Path $scratchKey) { Remove-Item -Path $scratchKey -Recurse -Force }
    }
}

if (-not $SkipWindow) {
    Check 'the window walks through every page, both runs, the finished overview and undo in demo mode' {
        $out = Join-Path $temp 'window'
        $arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $entryScript + '" -Demo -Lang en -SelfTest "' + $out + '"'
        $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WindowStyle Hidden -PassThru
        Assert ($process.WaitForExit(300000)) 'the window self-test did not finish'
        $reportFile = Join-Path $out 'selftest.json'
        Assert (Test-Path $reportFile) 'no self-test report was written'
        $report = Get-Content -LiteralPath $reportFile -Raw | ConvertFrom-Json
        Assert ([bool]$report.ok) ("self-test error: " + $report.error)
        Assert ($report.failed -eq 0) ("failed items: " + (@($report.failures) -join ' | '))
        Assert ($report.done -eq $catalog.Count) "expected $($catalog.Count) items, the window reported $($report.done)"
        Assert ([bool]$report.finishedHome) 'the overview never showed the finished board'
        Assert ($report.undone -gt 0) 'reverting a run was not exercised'
        Assert ([bool]$report.updateShown) 'the update pill and its sheet were not exercised'
        Assert (@(Get-ChildItem -LiteralPath $out -Filter '*.png').Count -ge 20) 'screenshots are missing'
    }
}

Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
exit 0
