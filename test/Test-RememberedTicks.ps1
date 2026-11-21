# Checks that the window opens with the ticks it was closed with.
#
# Run-Tests.ps1 runs this in a process of its own, with DEBLOATER_DATA pointing at a
# scratch folder. It loads the window's code without showing a window, stands in for
# the few things that need one, and plays several sittings one after the other: each
# starts the way the window does, by reading what the one before wrote down. The
# window's own walk cannot check this, because a test never writes settings.

$ErrorActionPreference = 'Stop'
if (-not $env:DEBLOATER_DATA) { throw 'DEBLOATER_DATA is not set; this would touch the real settings.' }

$src = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
Import-Module (Join-Path $src 'Debloater.Engine.psm1') -Force
Initialize-DebloaterLanguage 'en'
. (Join-Path $src 'Debloater.UI.ps1')

# What needs a window is replaced by something that does not.
function Update-Chrome { }
function Update-Bars { }
function Build-Home { }
$script:Window = [pscustomobject]@{ WindowState = 'Normal'; ActualWidth = 1140; ActualHeight = 780; RestoreBounds = $null }

function Assert {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

# The window opens: everything on this made-up PC is still to do, and the choice is
# whatever the settings file holds.
function Start-Sitting {
    $script:Demo = $false
    $script:SelfTestDir = ''
    $script:DryRun = $true
    $script:Catalog = @(Get-DebloaterCatalog)
    $script:ById = @{}
    $script:State = @{}
    foreach ($item in $script:Catalog) {
        $script:ById[$item.Id] = $item
        $script:State[$item.Id] = [pscustomobject]@{ State = 'todo' }
    }
    $script:PageVms = @{}
    $script:AppliedIds = @{}
    $script:Selected = @{}
    $script:Wanted = @{}
    $script:Choice = @{ Kind = 'recommended'; Name = '' }
    $script:ChoiceReady = $false
    $script:ChoiceDirty = $false
    $script:SavedSelections = $null
    $script:PickOpen = $false
    $script:CurrentPage = 'apps'
    $script:Mode = 'browse'
    $script:Theme = 'dark'
    $script:UpdatesOn = $true
    $script:UpdateChecked = ''
    $script:StoredChoice = (Get-DebloaterSettings).selection
    Initialize-Selection
}

$recommended = @(Get-DebloaterCatalog | Where-Object { $_.Recommended })
$optional = @(Get-DebloaterCatalog | Where-Object { -not $_.Recommended })

# 1. The very first time: the recommended list.
Start-Sitting
Assert ($script:Choice.Kind -eq 'recommended' -and @(Get-SelectedIds).Count -eq $recommended.Count) 'the first sitting did not start from the recommended list'

# 2. One recommended thing unticked and one optional thing ticked, by hand, then closed.
Set-ItemsSelected @($recommended[0]) $false
Set-ItemsSelected @($optional[0]) $true
Assert ($script:Choice.Kind -eq 'custom') 'ticking by hand did not make the selection the person''s own'
Assert ($script:ChoiceDirty) 'ticks made by hand were not marked to be written down'
Save-UiSettings
Start-Sitting
Assert ($script:Choice.Kind -eq 'custom') 'the next sitting forgot that the ticks were made by hand'
Assert (-not $script:Selected[$recommended[0].Id]) 'what had been unticked came back ticked'
Assert ([bool]$script:Selected[$optional[0].Id]) 'what had been ticked came back unticked'
Assert (@(Get-SelectedIds).Count -eq $recommended.Count) 'the next sitting ticked a different number of things'

# 3. Saved under a name: the name and the list are both there next time.
Save-SelectionAs 'Gaming PC' @($script:Wanted.Keys)
$script:Choice = @{ Kind = 'saved'; Name = 'Gaming PC' }
Save-UiSettings
Start-Sitting
Assert ($script:Choice.Kind -eq 'saved' -and $script:Choice.Name -eq 'Gaming PC') 'the saved selection in use was not in use next time'
Assert (@(Get-SavedSelections).Count -eq 1 -and -not $script:Selected[$recommended[0].Id] -and [bool]$script:Selected[$optional[0].Id]) 'the saved selection did not keep its list'
Assert ((Get-ChoiceTitle) -eq 'Gaming PC') 'the box would not show the name of the saved selection'

# 4. One of the tool's own lists, chosen from the list. Choosing writes it down at once.
Set-Choice 'everything'
Start-Sitting
Assert ($script:Choice.Kind -eq 'everything' -and @(Get-SelectedIds).Count -eq $script:Catalog.Count) 'choosing everything was not remembered'

# 5. A demo's ticks are not real, so they are not written down.
$script:Demo = $true
Set-Choice 'recommended'
Save-UiSettings
Start-Sitting
Assert ($script:Choice.Kind -eq 'everything') 'a demo changed what the real window remembers'

# 6. Deleting the saved selection that is in use leaves its ticks, without the name.
Set-Choice 'saved' 'Gaming PC'
Set-SavedSelections @()
Start-Sitting
Assert ($script:Choice.Kind -eq 'custom' -and -not $script:Selected[$recommended[0].Id] -and [bool]$script:Selected[$optional[0].Id]) 'a saved selection that was deleted took its ticks with it'

'OK'
