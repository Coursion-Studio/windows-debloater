# Opens Windows Debloater inside Windows Sandbox: a throwaway copy of Windows where the steps that
# really change things can be tried safely. Nothing done in the sandbox reaches this PC.
#
#   powershell -ExecutionPolicy Bypass -File scripts\open-sandbox.ps1
#
# When the sandbox starts it first runs test\Sandbox-ApplyTest.ps1, which applies and
# then undoes every setting for real and shows the result. After that the app opens so it
# can be tried by hand. The project folder is mapped read-only and the sandbox has no
# network. The only thing written back to this PC is the test report and run logs, in
# test\out\sandbox.
#
# Windows Sandbox comes with fewer preinstalled apps than a normal install, so this is a
# full test for settings and undo, and only a partial one for app removal.

param(
    # Only write the sandbox configuration file and print its path; do not open the sandbox.
    [switch]$ConfigOnly
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$sandbox = Join-Path $env:SystemRoot 'System32\WindowsSandbox.exe'

if (-not $ConfigOnly -and -not (Test-Path -LiteralPath $sandbox)) {
    Write-Host 'Windows Sandbox is not turned on.'
    Write-Host 'Turn it on under "Turn Windows features on or off" > Windows Sandbox, restart,'
    Write-Host 'then run this script again. It needs Windows 11 Pro, Enterprise or Education.'
    exit 1
}

$output = Join-Path $root 'test\out\sandbox'
[void](New-Item -ItemType Directory -Force -Path $output)

$command = 'cmd.exe /c "set DEBLOATER_DATA=C:\DebloaterOut&& powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Debloater\test\Sandbox-ApplyTest.ps1 & C:\Debloater\WindowsDebloater.cmd"'
$lines = @(
    '<Configuration>',
    '  <Networking>Disable</Networking>',
    '  <MappedFolders>',
    '    <MappedFolder>',
    ('      <HostFolder>' + [Security.SecurityElement]::Escape($root) + '</HostFolder>'),
    '      <SandboxFolder>C:\Debloater</SandboxFolder>',
    '      <ReadOnly>true</ReadOnly>',
    '    </MappedFolder>',
    '    <MappedFolder>',
    ('      <HostFolder>' + [Security.SecurityElement]::Escape($output) + '</HostFolder>'),
    '      <SandboxFolder>C:\DebloaterOut</SandboxFolder>',
    '      <ReadOnly>false</ReadOnly>',
    '    </MappedFolder>',
    '  </MappedFolders>',
    '  <LogonCommand>',
    ('    <Command>' + [Security.SecurityElement]::Escape($command) + '</Command>'),
    '  </LogonCommand>',
    '</Configuration>'
)
$config = Join-Path $env:TEMP 'WindowsDebloater.wsb'
[IO.File]::WriteAllText($config, ($lines -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))

if ($ConfigOnly) {
    Write-Host "Wrote $config"
    exit 0
}

Write-Host 'Opening Windows Sandbox. The test starts on its own after the sandbox desktop appears.'
Write-Host "Results will be written to $output"
Start-Process -FilePath $config
