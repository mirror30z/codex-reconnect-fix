[CmdletBinding()]
param(
    [ValidateSet('Diagnose', 'Auto', 'PrepareProxy', 'Rollback')][string]$Mode = 'Diagnose',
    [string]$ProxyUrl,
    [string]$CodexPath,
    [string]$ReportPath
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
if ($env:OS -ne 'Windows_NT') { throw 'The executable repair supports Windows only.' }
$installRoot = Join-Path $env:LOCALAPPDATA 'CodexReconnectFix'
$shortcutPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Codex - Verified Proxy.lnk'
$manifestPath = Join-Path $installRoot 'managed.json'

if ($Mode -eq 'Rollback') {
    if (-not (Test-Path -LiteralPath $manifestPath)) { throw 'No managed launcher found; no files removed.' }
    $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
    if ($manifest.owner -ne 'mirror30z/codex-reconnect-fix') { throw 'Unknown owner; rollback stopped.' }
    # Validate every fixed absolute target and hash before any deletion. No recursive deletion.
    $targets = @('common.ps1', 'launch.ps1', 'settings.json')
    foreach ($name in $targets) {
        $path = Join-Path $installRoot $name
        if (-not (Test-Path -LiteralPath $path) -or (Get-FileHash -LiteralPath $path).Hash -ne $manifest.hashes.$name) {
            throw 'Managed files changed since installation; preserve them and review rollback manually.'
        }
    }
    if (Test-Path -LiteralPath $shortcutPath) {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        if ($shortcut.Arguments -ne $manifest.shortcutArguments -or $shortcut.TargetPath -ne $manifest.shortcutTarget) {
            throw 'Shortcut changed; rollback stopped.'
        }
        Remove-Item -LiteralPath $shortcutPath
    }
    foreach ($name in $targets) { Remove-Item -LiteralPath (Join-Path $installRoot $name) }
    Remove-Item -LiteralPath $manifestPath
    if (@(Get-ChildItem -LiteralPath $installRoot -Force).Count -eq 0) { Remove-Item -LiteralPath $installRoot }
    [pscustomobject]@{action = 'launcher-removed'; note = 'Use the original Codex shortcut. Skill remains installed.'} | ConvertTo-Json
    return
}

$CodexPath = Find-CodexExecutable $CodexPath
$codexRoot = if ($env:CODEX_HOME) { [IO.Path]::GetFullPath($env:CODEX_HOME) } else { Join-Path $env:USERPROFILE '.codex' }
$version = (Invoke-BoundedProcess -File $CodexPath -Arguments @('--version') -TimeoutSeconds 10).stdout.Trim()
$baseline = Read-Doctor -CodexPath $CodexPath
$features = Invoke-BoundedProcess -File $CodexPath -Arguments @('features', 'list') -TimeoutSeconds 10
if (-not $ProxyUrl) { $ProxyUrl = Find-LocalProxy }
$listening = $false
$viaProxy = [pscustomobject]@{available = $false; reason = 'no-verified-proxy'}
$proxyHttp = $null
if ($ProxyUrl) {
    $uri = Get-LoopbackProxy $ProxyUrl
    $ProxyUrl = $uri.AbsoluteUri.TrimEnd('/')
    $listening = Test-ProxyListener $uri
    if ($listening) {
        $proxyHttp = Test-HttpPath $ProxyUrl
        $proxyOverrides = @()
        if ($features.stdout -match '(?m)^respect_system_proxy\s+(?!removed\b)') {
            $proxyOverrides = @('-c', 'features.respect_system_proxy=false')
        }
        $viaProxy = Read-Doctor -CodexPath $CodexPath -Environment (Get-ProxyEnvironment $ProxyUrl) -Overrides $proxyOverrides
    }
}
$systemComparison = $null
if ($features.stdout -match '(?m)^respect_system_proxy\s+(?!removed\b)') {
    $systemComparison = Read-Doctor -CodexPath $CodexPath -Overrides @('-c', 'features.respect_system_proxy=true')
}
$action = Select-RepairAction $baseline $viaProxy $Mode $listening
$report = [ordered]@{
    schemaVersion = 1; utc = [DateTime]::UtcNow.ToString('o'); mode = $Mode; codexVersion = $version;
    codexPath = $CodexPath; codexHome = $codexRoot;
    proxyDetected = [bool]$ProxyUrl; proxyListening = $listening;
    baseline = $baseline; explicitProxy = $viaProxy; systemProxyOverride = $systemComparison;
    directHttp = (Test-HttpPath ''); proxyHttp = $proxyHttp;
    action = $action; launcherPrepared = $false; desktopRetestRequired = $true
}
$python = Get-Command python.exe -ErrorAction SilentlyContinue
if ($python) {
    try {
        $logs = Invoke-BoundedProcess -File $python.Source -Arguments @((Join-Path $PSScriptRoot 'log-summary.py'), $codexRoot) -TimeoutSeconds 10
        $report.logSignatures = $logs.stdout | ConvertFrom-Json -ErrorAction Stop
    } catch { $report.logSignatures = @{available = $false; reason = 'optional-log-summary-unavailable'} }
}

if ($Mode -in @('Auto', 'PrepareProxy') -and $action -eq 'prepare-verified-proxy-launcher') {
    if ((Test-Path -LiteralPath $installRoot) -and @(Get-ChildItem -LiteralPath $installRoot -Force).Count -eq 0) {
        Remove-Item -LiteralPath $installRoot
    }
    if (Test-Path -LiteralPath $installRoot) {
        # Reuse exactly matching installation; preserve any edited or unrelated files.
        if (-not (Test-Path -LiteralPath $manifestPath)) { throw 'Installation directory already exists without a manifest.' }
        $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
        if ($manifest.owner -ne 'mirror30z/codex-reconnect-fix') { throw 'Unknown installation owner.' }
        foreach ($name in @('common.ps1', 'launch.ps1', 'settings.json')) {
            $path = Join-Path $installRoot $name
            if (-not (Test-Path -LiteralPath $path) -or (Get-FileHash -LiteralPath $path).Hash -ne $manifest.hashes.$name) {
                throw 'Existing launcher was edited; no files overwritten. Review or rollback first.'
            }
        }
        $settings = Get-Content -Raw -LiteralPath (Join-Path $installRoot 'settings.json') | ConvertFrom-Json
        if ($settings.proxyUrl -ne $ProxyUrl -or $settings.codexHome -ne $codexRoot) {
            throw 'Existing launcher uses different settings. Rollback before changing it.'
        }
        if (-not (Test-Path -LiteralPath $shortcutPath)) { throw 'Managed shortcut is missing. Rollback, then prepare again.' }
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        if ($shortcut.Arguments -ne $manifest.shortcutArguments -or $shortcut.TargetPath -ne $manifest.shortcutTarget) {
            throw 'Managed shortcut was edited; no files overwritten.'
        }
    } else {
        if (Test-Path -LiteralPath $shortcutPath) { throw 'Shortcut name is already in use; no files overwritten.' }
        $package = Get-AppxPackage -Name OpenAI.Codex | Sort-Object { [version]$_.Version } -Descending | Select-Object -First 1
        if (-not $package -or -not (Test-Path -LiteralPath (Join-Path $package.InstallLocation 'app\ChatGPT.exe'))) {
            throw 'Store Codex application not found. Launcher supports OpenAI.Codex AppX installations.'
        }
        New-Item -ItemType Directory -Path $installRoot | Out-Null
        foreach ($name in @('common.ps1', 'launch.ps1')) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $installRoot $name) }
        Write-Utf8File (Join-Path $installRoot 'settings.json') (@{proxyUrl = $ProxyUrl; codexHome = $codexRoot} | ConvertTo-Json)
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $shortcut.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ' +
            (ConvertTo-NativeArgument (Join-Path $installRoot 'launch.ps1'))
        $shortcut.WorkingDirectory = $installRoot
        $shortcut.IconLocation = (Join-Path $package.InstallLocation 'app\ChatGPT.exe') + ',0'
        $shortcut.Save()
        $hashes = @{}
        foreach ($name in @('common.ps1', 'launch.ps1', 'settings.json')) { $hashes[$name] = (Get-FileHash -LiteralPath (Join-Path $installRoot $name)).Hash }
        Write-Utf8File $manifestPath (@{owner = 'mirror30z/codex-reconnect-fix'; hashes = $hashes;
            shortcutTarget = $shortcut.TargetPath; shortcutArguments = $shortcut.Arguments} | ConvertTo-Json -Depth 5)
    }
    $report.launcherPrepared = $true
    $report.shortcut = $shortcutPath
    $report.note = 'After active tasks finish, fully quit Codex and reopen using the new shortcut. Verify real desktop turns.'
}
$json = $report | ConvertTo-Json -Depth 10
if ($ReportPath) { Write-Utf8File ([IO.Path]::GetFullPath($ReportPath)) $json }
$json
