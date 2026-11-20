# Real apply-and-undo test. It REALLY changes Windows settings and removes apps, so it
# only runs inside Windows Sandbox (a throwaway copy of Windows). scripts\open-sandbox.ps1
# starts it there automatically.
#
# What it does:
#   1. Records the current value of every registry setting in the catalog.
#   2. Applies every item that still needs doing, through the same workers the window uses.
#   3. Checks that the tool now sees each of those items as done.
#   4. Undoes the run and checks that every recorded value is back exactly as it was.
#
# OneDrive removal is left out: the sandbox has no OneDrive to remove.
#
# -DryRun walks through the same steps without changing anything, and may run anywhere.

param(
    [switch]$DryRun,
    [switch]$Force,
    [string]$ReportDir
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$src = Join-Path $root 'src'
$inSandbox = ($env:USERNAME -eq 'WDAGUtilityAccount')

if (-not $DryRun -and -not $inSandbox -and -not $Force) {
    Write-Host 'This test really changes Windows settings and removes apps.'
    Write-Host 'It only runs inside Windows Sandbox. Use scripts\open-sandbox.ps1 to start it there,'
    Write-Host 'or add -DryRun to walk through it here without changing anything.'
    exit 2
}

Import-Module (Join-Path $src 'Debloater.Engine.psm1') -Force -DisableNameChecking
Initialize-DebloaterLanguage 'en'
if (-not $ReportDir) { $ReportDir = Get-DebloaterDataRoot }
[void](New-Item -ItemType Directory -Force -Path $ReportDir)

$catalog = @(Get-DebloaterCatalog | Where-Object { $_.Id -ne 'onedrive.remove' })
$entryScript = Join-Path $src 'Debloater.ps1'
$checks = New-Object System.Collections.ArrayList

function Add-Check {
    param([string]$Name, [bool]$Ok, [string]$Detail)
    [void]$checks.Add([pscustomobject]@{ name = $Name; ok = $Ok; detail = $Detail })
    $mark = 'PASS'
    if (-not $Ok) { $mark = 'FAIL' }
    Write-Host ("{0}  {1}" -f $mark, $Name)
    if ($Detail -and -not $Ok) { Write-Host ("      " + $Detail) }
}

function Get-Snapshot {
    $snapshot = @{}
    foreach ($item in $catalog) {
        foreach ($entry in @($item.Registry)) {
            $value = Get-DebloaterRegValue (Resolve-DebloaterRegPath $entry.Path $null) $entry.Name
            $snapshot[$entry.Path + '\' + $entry.Name] = [pscustomobject]@{ Exists = $value.Exists; Value = "$($value.Value)" }
        }
    }
    return $snapshot
}

function Test-Elevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal $identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-Worker {
    param([string]$PlanPath, [string]$Scope, [switch]$Undo)
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $entryScript + '" -Worker -PlanPath "' + $PlanPath + '" -Scope ' + $Scope
    $suffix = ''
    if ($Undo) { $arguments += ' -Undo'; $suffix = '-undo' }
    if ($Scope -eq 'Admin' -and -not $DryRun -and -not (Test-Elevated)) {
        $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -PassThru
    } else {
        $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WindowStyle Hidden -PassThru
    }
    [void]$process.WaitForExit(600000)
    $file = Join-Path (Split-Path -Parent $PlanPath) ('progress-' + $Scope.ToLower() + $suffix + '.jsonl')
    return @(Read-DebloaterLines $file | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })
}

# ---------------------------------------------------------------- Before

$before = Get-Snapshot
$stateBefore = Get-DebloaterState -Catalog $catalog
$todo = @($catalog | Where-Object { $stateBefore[$_.Id].State -eq 'todo' })
Write-Host ("Items in the catalog: {0}. Still to do on this Windows: {1}." -f $catalog.Count, $todo.Count)
if ($DryRun) { Write-Host 'Dry run: nothing will be changed.' }

$runDir = New-DebloaterRunFolder
$planPath = Join-Path $runDir 'plan.json'
$plan = [pscustomobject]@{
    runId   = (Split-Path -Leaf $runDir)
    created = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    version = (Get-DebloaterVersion)
    userSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    dryRun  = [bool]$DryRun
    lang    = 'en'
    steps   = @($todo | ForEach-Object { $_.Id })
}
Write-DebloaterJson $plan $planPath

# ---------------------------------------------------------------- Apply

$failedItems = @()
foreach ($scope in 'Admin', 'User') {
    $expected = @($todo | Where-Object { Test-DebloaterItemHasScope $_ $scope }).Count
    if ($expected -eq 0) { continue }
    $events = @(Invoke-Worker $planPath $scope)
    $bad = @($events | Where-Object { $_.status -in 'failed', 'fatal' })
    $failedItems += @($bad | ForEach-Object { [string]$_.id })
    Add-Check "$scope worker finished" (@($events | Where-Object { $_.status -eq 'done' }).Count -eq 1) 'no done line was written'
    Add-Check "$scope worker reported no failures" ($bad.Count -eq 0) (@($bad | ForEach-Object { $_.id + ': ' + $_.message }) -join ' | ')
    Add-Check "$scope worker handled all $expected of its items" (@($events | Where-Object { $_.status -in 'ok', 'failed' }).Count -eq $expected) 'a different number of items was reported'
}

if (-not $DryRun) {
    # Windows records a new desktop picture a moment after it is set, so allow a short wait.
    $stillTodo = @()
    for ($attempt = 0; $attempt -lt 10; $attempt++) {
        $stateAfter = Get-DebloaterState -Catalog $catalog
        $stillTodo = @($todo | Where-Object { $stateAfter[$_.Id].State -eq 'todo' -and $failedItems -notcontains $_.Id } | ForEach-Object { $_.Id })
        if ($stillTodo.Count -eq 0) { break }
        Start-Sleep -Seconds 1
    }
    Add-Check 'every applied item is now seen as done' ($stillTodo.Count -eq 0) ('still to do: ' + ($stillTodo -join ', '))

    $afterApply = Get-Snapshot
    $changedCount = @($before.Keys | Where-Object { $before[$_].Exists -ne $afterApply[$_].Exists -or $before[$_].Value -ne $afterApply[$_].Value }).Count
    Add-Check 'applying changed registry values' ($changedCount -gt 0 -or $todo.Count -eq 0) 'no registry value changed'

    # ------------------------------------------------------------ Undo

    foreach ($scope in 'Admin', 'User') {
        $undoable = @(Get-DebloaterJournal $runDir $scope | Where-Object { Test-DebloaterEntryUndoable $_ }).Count
        if ($undoable -eq 0) { continue }
        $events = @(Invoke-Worker $planPath $scope -Undo)
        $bad = @($events | Where-Object { $_.status -in 'failed', 'fatal' })
        Add-Check "$scope undo finished" (@($events | Where-Object { $_.status -eq 'done' }).Count -eq 1) 'no done line was written'
        Add-Check "$scope undo reported no failures" ($bad.Count -eq 0) (@($bad | ForEach-Object { $_.id + ': ' + $_.message }) -join ' | ')
        Add-Check "$scope undo handled all $undoable recorded changes" (@($events | Where-Object { $_.status -eq 'ok' }).Count -eq $undoable) 'a different number was reported'
    }

    # Mark the run as undone, the same way the History page does.
    [IO.File]::WriteAllText((Join-Path $runDir 'undone.txt'), (Get-Date).ToString('yyyy-MM-dd HH:mm'))

    $afterUndo = Get-Snapshot
    $different = @($before.Keys | Where-Object { $before[$_].Exists -ne $afterUndo[$_].Exists -or $before[$_].Value -ne $afterUndo[$_].Value })
    Add-Check 'after undo every registry value is back as it was' ($different.Count -eq 0) ('not restored: ' + ($different -join ', '))
}

# ---------------------------------------------------------------- Report

$passed = @($checks | Where-Object { $_.ok }).Count
$failed = @($checks | Where-Object { -not $_.ok }).Count
$report = [pscustomobject]@{
    finished    = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    dryRun      = [bool]$DryRun
    inSandbox   = $inSandbox
    windows     = (Get-CimInstance Win32_OperatingSystem).Caption + ' build ' + [Environment]::OSVersion.Version.Build
    catalogSize = $catalog.Count
    applied     = @($todo | ForEach-Object { $_.Id })
    passed      = $passed
    failed      = $failed
    checks      = $checks.ToArray()
    runFolder   = $runDir
}
$reportPath = Join-Path $ReportDir 'sandbox-report.json'
Write-DebloaterJson $report $reportPath

Write-Host ''
Write-Host ("{0} checks passed, {1} failed. Report: {2}" -f $passed, $failed, $reportPath)

if ($inSandbox -and -not $DryRun) {
    Add-Type -AssemblyName PresentationFramework
    $text = "Windows Debloater sandbox test finished.`n`n$passed checks passed, $failed failed.`n`nThe report was saved to the host PC. The app opens next so you can try it by hand."
    [void][Windows.MessageBox]::Show($text, 'Windows Debloater sandbox test')
}

if ($failed -gt 0) { exit 1 }
exit 0
