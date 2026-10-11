[CmdletBinding()]
param([string]$ProxyUrl, [string]$CodexPath, [string]$Model)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$exe = Find-CodexExecutable $CodexPath
$help = Invoke-BoundedProcess -File $exe -Arguments @('exec', '--help') -TimeoutSeconds 10
foreach ($flag in @('--ephemeral', '--ignore-user-config', '--json')) {
    if (-not $help.stdout.Contains($flag)) { throw 'This CLI does not support the isolated model probe. Update or test a desktop turn manually.' }
}
$environment = @{}
if ($ProxyUrl) { $environment = Get-ProxyEnvironment $ProxyUrl }
$arguments = @('exec', '--ignore-user-config', '--ephemeral', '--skip-git-repo-check', '--sandbox', 'read-only', '--json')
if ($Model) { $arguments += @('-m', $Model) }
$arguments += @('Connectivity health check only. Do not use tools or read files. Reply exactly CODEX_CONNECTIVITY_OK.')
$result = Invoke-BoundedProcess -File $exe -Arguments $arguments -Environment $environment -TimeoutSeconds 45
$completed = $false
$matched = $false
$toolCalled = $false
$retries = 0
foreach ($line in ($result.stdout -split "`n")) {
    try {
        $event = $line | ConvertFrom-Json -ErrorAction Stop
        if ($event.type -eq 'turn.completed') { $completed = $true }
        if ($event.type -eq 'item.completed' -and $event.PSObject.Properties['item']) {
            if ($event.item.type -eq 'agent_message') { $matched = $event.item.text.Trim() -eq 'CODEX_CONNECTIVITY_OK' }
            elseif ($event.item.type -notin @('reasoning', 'plan')) { $toolCalled = $true }
        }
        if ($event.PSObject.Properties['message'] -and $event.message -match '(?i)reconnect') { $retries++ }
    } catch {}
}
$retries += ([regex]::Matches($result.stderr, '(?i)Reconnecting|retrying sampling request')).Count
[pscustomobject]@{schemaVersion = 1; utc = [DateTime]::UtcNow.ToString('o'); explicitProxy = [bool]$ProxyUrl;
    completed = $completed; expectedReply = $matched; toolCalled = $toolCalled; retryMessages = $retries;
    exitCode = $result.exitCode; timedOut = $result.timedOut;
    passed = ($completed -and $matched -and -not $toolCalled -and $retries -eq 0 -and $result.exitCode -eq 0);
    isolatedBuiltinProvider = $true; desktopRetestRequired = $true} | ConvertTo-Json
