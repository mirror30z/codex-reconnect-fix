[CmdletBinding()]
param([switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
try {
    $settings = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'settings.json') | ConvertFrom-Json
    $uri = Get-LoopbackProxy $settings.proxyUrl
    if (-not (Test-ProxyListener $uri)) { throw 'Local proxy is not listening. Start your proxy client or use the original Codex shortcut.' }
    $package = Get-AppxPackage -Name OpenAI.Codex | Sort-Object { [version]$_.Version } -Descending | Select-Object -First 1
    if (-not $package) { throw 'OpenAI.Codex Store package not found.' }
    $exe = Join-Path $package.InstallLocation 'app\ChatGPT.exe'
    if (-not (Test-Path -LiteralPath $exe)) { throw 'Codex application executable not found.' }
    if ($CheckOnly) {
        [pscustomobject]@{appVersion = [string]$package.Version; appFound = $true;
            proxyListening = $true; codexHomePreserved = (Test-Path -LiteralPath $settings.codexHome)} | ConvertTo-Json
        return
    }
    # Electron single-instance forwarding cannot replace an already-running process environment.
    if (Get-Process -Name ChatGPT,codex -ErrorAction SilentlyContinue) {
        throw 'Codex/ChatGPT or CLI is still running. Finish tasks, fully quit the app/CLI, then open this shortcut again.'
    }
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $exe
    $info.UseShellExecute = $false
    $info.WorkingDirectory = $env:USERPROFILE
    $info.Arguments = '--proxy-server=' + $uri.AbsoluteUri.TrimEnd('/') + ' --disable-quic'
    $environment = Get-ProxyEnvironment $settings.proxyUrl
    $environment.CODEX_HOME = [IO.Path]::GetFullPath($settings.codexHome)
    foreach ($key in $environment.Keys) { $info.EnvironmentVariables[$key] = $environment[$key] }
    [void][Diagnostics.Process]::Start($info)
} catch {
    if ($CheckOnly) { throw }
    Add-Type -AssemblyName System.Windows.Forms
    [void][Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Codex Reconnect Fix')
    exit 1
}
