[CmdletBinding()]
param([ValidateSet('Auto', 'Diagnose', 'PrepareProxy', 'InstallOnly')][string]$Mode = 'Auto', [string]$ProxyUrl)
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'This installer supports Windows only.' }
$source = $null
if ($PSScriptRoot -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'skills\codex-reconnect-fix\SKILL.md'))) {
    $source = Join-Path $PSScriptRoot 'skills\codex-reconnect-fix'
} else {
    # Download a versioned release. No administrator rights or hidden application restart.
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $cache = Join-Path ([IO.Path]::GetTempPath()) ('codex-reconnect-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $cache | Out-Null
    $archive = Join-Path $cache 'release.zip'
    Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/mirror30z/codex-reconnect-fix/archive/refs/tags/v1.0.0.zip' -OutFile $archive
    Expand-Archive -LiteralPath $archive -DestinationPath $cache
    $source = Join-Path $cache 'codex-reconnect-fix-1.0.0\skills\codex-reconnect-fix'
}
$codexRoot = if ($env:CODEX_HOME) { [IO.Path]::GetFullPath($env:CODEX_HOME) } else { Join-Path $env:USERPROFILE '.codex' }
$destination = Join-Path $codexRoot 'skills\codex-reconnect-fix'
if (Test-Path -LiteralPath $destination) {
    foreach ($file in (Get-ChildItem -LiteralPath $source -File -Recurse)) {
        $relative = $file.FullName.Substring($source.Length).TrimStart('\', '/')
        $existing = Join-Path $destination $relative
        if (-not (Test-Path -LiteralPath $existing) -or (Get-FileHash -LiteralPath $file.FullName).Hash -ne (Get-FileHash -LiteralPath $existing).Hash) {
            throw 'An existing Skill differs from this release. Preserve it and review/update manually; no files overwritten.'
        }
    }
} else {
    New-Item -ItemType Directory -Path (Split-Path $destination) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Recurse
}
Write-Host ('Skill installed: ' + $destination)
if ($Mode -ne 'InstallOnly') {
    & (Join-Path $destination 'scripts\reconnect.ps1') -Mode $Mode -ProxyUrl $ProxyUrl
}
