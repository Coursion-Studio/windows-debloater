# Code signing, for the scripts that build a release. Dot-source it; it only defines
# functions.
#
# A signed program names its publisher when Windows asks whether to run it, and the
# trust that builds up belongs to that publisher and carries over to the next version.
# An unsigned one is "unknown publisher" and starts from nothing with every release.
#
# The certificate is not in this repository and cannot be: its key lives on a token
# or in the certificate authority's cloud, and Windows shows it in the personal
# certificate store of the person who holds it. All that is kept on disk is which
# certificate to use, in %APPDATA%\Coursion\keys\code-signing.json, written by
# scripts\set-code-signing.ps1. Without that file nothing is signed and everything
# still builds, which is how it is for anyone but the maintainer.
#
# The same choice can be given for one run with two environment variables, which is
# what Coursion's other Windows apps use as well:
#
#   CODESIGN_THUMBPRINT   the certificate's thumbprint (40 hex digits)
#   CODESIGN_TIMESTAMP    the time server; optional

$script:CodeSigningFile = Join-Path $env:APPDATA 'Coursion\keys\code-signing.json'

# Which certificate signs, and which server vouches for the time. Nothing when no
# certificate has been chosen.
function Get-CodeSigningSetup {
    if ($env:CODESIGN_THUMBPRINT) {
        $given = ([string]$env:CODESIGN_THUMBPRINT -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()
        if ($given.Length -ne 40) { throw 'CODESIGN_THUMBPRINT does not hold a certificate thumbprint (40 hex digits).' }
        $server = [string]$env:CODESIGN_TIMESTAMP
        if (-not $server) { $server = 'http://timestamp.digicert.com' }
        return [pscustomobject]@{ Thumbprint = $given; Timestamp = $server }
    }
    if (-not (Test-Path -LiteralPath $script:CodeSigningFile)) { return $null }
    $setup = Get-Content -LiteralPath $script:CodeSigningFile -Raw | ConvertFrom-Json
    $thumbprint = ([string]$setup.thumbprint -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()
    if ($thumbprint.Length -ne 40) { throw "$script:CodeSigningFile does not hold a certificate thumbprint. Run scripts\set-code-signing.ps1 again." }
    return [pscustomobject]@{ Thumbprint = $thumbprint; Timestamp = [string]$setup.timestamp }
}

# The certificates in the personal store that are meant for signing code and can be
# used right now, which for a token or a cloud certificate means it is connected.
function Get-CodeSigningCertificates {
    return @(Get-ChildItem -Path Cert:\CurrentUser\My -CodeSigningCert | Where-Object { $_.HasPrivateKey -and $_.NotAfter -gt (Get-Date) })
}

# Microsoft's own signing tool, if the Windows SDK is on this PC. It is preferred:
# it asks the time server in the current way, with SHA-256.
function Find-SignTool {
    $onPath = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    $kits = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    if (Test-Path -LiteralPath $kits) {
        $found = Get-ChildItem -LiteralPath $kits -Directory | Sort-Object Name -Descending |
            ForEach-Object { Join-Path $_.FullName 'x64\signtool.exe' } | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if ($found) { return $found }
    }
    return $null
}

# Says what is wrong with a file's signature, or nothing when it is as it should be:
# signed by the expected certificate, intact, and, where asked for, with a time on it.
# A time matters for a release: without it the signature stops counting on the day the
# certificate expires. -AllowUntrusted is for tests, whose certificate no PC trusts.
function Get-CodeSignatureProblem {
    param([string]$Path, [string]$Thumbprint, [switch]$RequireTimestamp, [switch]$AllowUntrusted)
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if (-not $signature.SignerCertificate) { return 'it is not signed' }
    if ($signature.SignerCertificate.Thumbprint -ne $Thumbprint) { return ('it is signed by another certificate: ' + $signature.SignerCertificate.Subject) }
    if ($signature.Status -eq 'HashMismatch') { return 'it was changed after it was signed' }
    if ($signature.Status -ne 'Valid' -and -not $AllowUntrusted) { return ('Windows does not accept the signature: ' + $signature.StatusMessage) }
    if ($RequireTimestamp -and -not $signature.TimeStamperCertificate) { return 'the signature has no time on it; the time server did not answer' }
    return ''
}

# Signs one file and checks the result. $Certificate is a thumbprint, for a
# certificate in the personal store, or the certificate itself.
function Add-CodeSignature {
    param([string]$Path, $Certificate, [string]$Timestamp, [string]$Description = 'Windows Debloater', [switch]$AllowUntrusted)
    $inStore = ($Certificate -is [string])
    if ($inStore) {
        $thumbprint = $Certificate
        $Certificate = Get-ChildItem -Path Cert:\CurrentUser\My | Where-Object { $_.Thumbprint -eq $thumbprint } | Select-Object -First 1
        if (-not $Certificate) { throw "The signing certificate $thumbprint is not in your certificate store. Is the token plugged in, or the cloud signing app signed in?" }
    }
    $signtool = $null
    if ($inStore) { $signtool = Find-SignTool }
    if ($signtool) {
        $arguments = @('sign', '/sha1', $Certificate.Thumbprint, '/fd', 'SHA256', '/d', $Description)
        if ($Timestamp) { $arguments += @('/tr', $Timestamp, '/td', 'SHA256') }
        $output = & $signtool @arguments $Path 2>&1
        if ($LASTEXITCODE -ne 0) { throw ("Signing {0} failed:`n{1}" -f (Split-Path -Leaf $Path), ($output -join "`n")) }
    } else {
        $settings = @{ FilePath = $Path; Certificate = $Certificate; HashAlgorithm = 'SHA256' }
        if ($Timestamp) { $settings.TimestampServer = $Timestamp }
        [void](Set-AuthenticodeSignature @settings)
    }
    $problem = Get-CodeSignatureProblem -Path $Path -Thumbprint $Certificate.Thumbprint -RequireTimestamp:([bool]$Timestamp) -AllowUntrusted:$AllowUntrusted
    if ($problem) { throw ("{0}: {1}." -f (Split-Path -Leaf $Path), $problem) }
}

# Signs every PowerShell script under a folder and says how many there were. The
# scripts are what does the work, some of it with administrator rights, so in a signed
# release they carry the publisher's signature as well: anyone can see that a script
# is the one that was shipped. It is done to the copies that go into the installer and
# the zip, never to the ones in src, because signing adds a block of text to the end
# of a file.
function Add-ScriptSignatures {
    param([string]$Folder, $Certificate, [string]$Timestamp, [switch]$AllowUntrusted)
    $found = @(Get-ChildItem -LiteralPath $Folder -Recurse -File | Where-Object { $_.Extension -in '.ps1', '.psm1' })
    foreach ($file in $found) {
        Add-CodeSignature -Path $file.FullName -Certificate $Certificate -Timestamp $Timestamp -AllowUntrusted:$AllowUntrusted
    }
    return $found.Count
}