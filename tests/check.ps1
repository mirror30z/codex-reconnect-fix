$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = Split-Path $PSScriptRoot
$scripts = Join-Path $repo 'skills\codex-reconnect-fix\scripts'
. (Join-Path $scripts 'common.ps1')
$script:checks = 0
function Assert($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    $script:checks++
}
function Assert-Rejected([scriptblock]$Action) {
    $rejected = $false
    try { & $Action | Out-Null } catch { $rejected = $true }
    Assert $rejected 'Unsafe input was accepted.'
}
foreach ($file in Get-ChildItem -LiteralPath $repo -Filter '*.ps1' -Recurse) {
    $parseErrors = $null
    $tokens = $null
    [void][Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
    Assert ($parseErrors.Count -eq 0) ('Parse failed: ' + $file.Name)
}
foreach ($value in @('http://127.0.0.1:17891', 'http://localhost:8080', 'http://[::1]:1234', 'http://127.2.3.4:1234')) {
    Assert ((Get-LoopbackProxy $value).Port -gt 0) 'Valid loopback rejected.'
}
foreach ($value in @('http://user:secret@127.0.0.1:8080', 'http://example.com:8080',
    'https://127.0.0.1:8080', 'socks5://127.0.0.1:8080', 'http://127.0.0.1:8080/api',
    'http://127.0.0.1:8080?secret=x', 'http://127.0.0.1:8080#x', 'http://127.0.0.1:0', 'not a URL')) {
    Assert-Rejected { Get-LoopbackProxy $value }
}
$before = [Environment]::GetEnvironmentVariable('NO_PROXY', 'Process')
$environment = Get-ProxyEnvironment 'http://127.0.0.1:17891'
Assert ($environment.NO_PROXY -eq 'localhost,127.0.0.1,::1') 'Proxy bypass not restricted.'
Assert ($environment.HTTPS_PROXY -eq 'http://127.0.0.1:17891') 'Wrong HTTPS proxy scheme.'
Assert ([Environment]::GetEnvironmentVariable('NO_PROXY', 'Process') -eq $before) 'Parent environment changed.'
$listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0)
$listener.Start()
$port = $listener.LocalEndpoint.Port
try { Assert (Test-ProxyListener ([uri]('http://127.0.0.1:' + $port))) 'Live listener missed.' } finally { $listener.Stop() }
Assert (-not (Test-ProxyListener ([uri]('http://127.0.0.1:' + $port)))) 'Dead listener accepted.'

function New-Doctor([string]$Ws, [string]$Auth = 'ok') {
    [pscustomobject]@{available = $true;
        'config.load' = @{status='ok'}; 'auth.credentials' = @{status=$Auth};
        'network.websocket_reachability' = @{status=$Ws; summary=$(if($Ws -eq 'ok'){'Responses WebSocket handshake succeeded'}else{'timeout'})}}
}
$good = New-Doctor 'ok'
$bad = New-Doctor 'error'
$noAuth = New-Doctor 'error' 'error'
Assert ((Select-RepairAction $bad $good 'Auto' $true) -eq 'prepare-verified-proxy-launcher') 'Positive comparison not selected.'
Assert ((Select-RepairAction $good $good 'Auto' $true) -eq 'healthy-now-observe-desktop') 'Healthy default was modified.'
Assert ((Select-RepairAction $good $good 'PrepareProxy' $true) -eq 'prepare-verified-proxy-launcher') 'Explicit mitigation not supported.'
Assert ((Select-RepairAction $bad $bad 'Auto' $true) -eq 'proxy-not-verified-no-change') 'Failed proxy accepted.'
Assert ((Select-RepairAction $noAuth $good 'Auto' $true) -eq 'resolve-config-or-auth') 'Authentication failure ignored.'
Assert ((Select-RepairAction $bad $good 'Auto' $false) -eq 'check-proxy-dns-routes-service') 'Dead proxy accepted.'
Assert ((Select-RepairAction ([pscustomobject]@{available=$false}) $good 'Auto' $true) -eq 'manual-diagnosis-doctor-unavailable') 'Unsupported doctor treated as network failure.'
$systemPreferred = New-Doctor 'error'
$systemPreferred | Add-Member -NotePropertyName systemProxyPreference -NotePropertyValue enabled
Assert ((Select-RepairAction $systemPreferred $good 'Auto' $true) -eq 'system-proxy-preference-active-review') 'Launcher could inherit a conflicting system-proxy policy.'

$python = (Get-Command python.exe -ErrorAction Stop).Source
$values = @('', 'a b', 'quote"here', 'trailing space\ path\', '中文路径', '$(Write-Output secret)', '`literal`', "line`nbreak")
$echo = Invoke-BoundedProcess -File $python -Arguments (@('-c', 'import sys,json; print(json.dumps(sys.argv[1:]))') + $values)
$actual = ConvertFrom-Json -InputObject $echo.stdout
Assert ($actual.Count -eq $values.Count) 'Argument count changed.'
for ($i=0; $i -lt $values.Count; $i++) { Assert ($actual[$i] -ceq $values[$i]) 'Native quoting changed a literal value.' }
$echo = Invoke-BoundedProcess -File $python -Arguments @('-c', 'import os; print(os.environ.get("CODEX_RECONNECT_TEST", ""))') -Environment @{CODEX_RECONNECT_TEST='child-only'}
Assert ($echo.stdout.Trim() -eq 'child-only') 'Child environment not propagated.'
Assert (-not [Environment]::GetEnvironmentVariable('CODEX_RECONNECT_TEST', 'Process')) 'Child environment leaked to parent.'
$timeout = Invoke-BoundedProcess -File $python -Arguments @('-c', 'import time; time.sleep(3)') -TimeoutSeconds 1
Assert $timeout.timedOut 'Timeout did not stop the owned child process.'
Write-Output ("Passed {0} checks ({1})" -f $script:checks,$PSVersionTable.PSVersion)
