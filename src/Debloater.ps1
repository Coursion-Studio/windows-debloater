# Windows Debloater - a clean start for Windows 11.
#
# Entry point. With no arguments it opens the window. The other modes are used by the
# window itself (-Worker), by tests (-Scan, -SelfTest) and for trying things out safely
# (-DryRun changes nothing, -Demo also pretends every item still needs doing).
# -Lang and -Theme override the saved preferences for one run.

param(
    [switch]$Worker,
    [string]$PlanPath,
    [ValidateSet('User', 'Admin')][string]$Scope = 'User',
    [switch]$Undo,
    [switch]$Scan,
    [switch]$DryRun,
    [switch]$Demo,
    [string]$Lang,
    [ValidateSet('', 'system', 'light', 'dark')][string]$Theme = '',
    [string]$SelfTest
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Debloater.Engine.psm1') -Force -DisableNameChecking

if ($Worker) {
    Invoke-DebloaterWorker -PlanPath $PlanPath -Scope $Scope -Undo:$Undo
    exit 0
}

if (-not $Lang) { $Lang = (Get-DebloaterSettings).lang }
if (-not $Lang) { $Lang = Get-DebloaterDefaultLanguage }
Initialize-DebloaterLanguage $Lang

if ($Scan) {
    # Prints what the tool sees on this PC as JSON. Changes nothing.
    $catalog = Get-DebloaterCatalog
    $state = Get-DebloaterState -Catalog $catalog
    $rows = foreach ($item in $catalog) {
        [pscustomobject]@{ id = $item.Id; state = $state[$item.Id].State; title = (Get-DebloaterItemTitle $item) }
    }
    ConvertTo-Json -InputObject @($rows) -Depth 4
    exit 0
}

. (Join-Path $PSScriptRoot 'Debloater.UI.ps1')
Show-DebloaterWindow -DryRun:($DryRun -or $Demo) -Demo:$Demo -SelfTestDir $SelfTest -Theme $Theme
