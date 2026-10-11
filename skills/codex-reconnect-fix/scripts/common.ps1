# Windows PowerShell 5.1 and PowerShell 7. No external modules required.
Set-StrictMode -Version Latest

function ConvertTo-NativeArgument([string]$Value) {
    # CommandLineToArgvW quoting, including trailing backslashes before a quote.
    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') { return $Value }
    '"' + [regex]::Replace([regex]::Replace($Value, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1') + '"'
}

function Invoke-BoundedProcess {
    param([string]$File, [string[]]$Arguments, [hashtable]$Environment = @{}, [int]$TimeoutSeconds = 60)
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $File
    $info.Arguments = ($Arguments | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' '
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    foreach ($key in $Environment.Keys) { $info.EnvironmentVariables[$key] = $Environment[$key] }
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $info
    try {
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $finished = $process.WaitForExit($TimeoutSeconds * 1000)
        if (-not $finished) { $process.Kill(); $process.WaitForExit() }
        [pscustomobject]@{ exitCode = $process.ExitCode; timedOut = -not $finished;
            stdout = $stdout.Result; stderr = $stderr.Result }
    } finally { $process.Dispose() }
}

function Get-LoopbackProxy([string]$Value) {
    $uri = $null
    if (-not [uri]::TryCreate($Value, [UriKind]::Absolute, [ref]$uri)) { throw 'Invalid proxy URL.' }
    $address = $null
    $hostName = $uri.DnsSafeHost.Trim('[', ']')
    $local = $hostName -eq 'localhost' -or
        ([Net.IPAddress]::TryParse($hostName, [ref]$address) -and [Net.IPAddress]::IsLoopback($address))
    if ($uri.Scheme -ne 'http' -or -not $local -or $uri.Port -lt 1 -or
        $uri.UserInfo -or $uri.Query -or $uri.Fragment -or $uri.AbsolutePath -ne '/') {
        throw 'Use a credential-free loopback HTTP/Mixed proxy, e.g. http://127.0.0.1:<actual-port>.'
    }
    $uri
}

function Get-ProxyEnvironment([string]$ProxyUrl) {
    $value = (Get-LoopbackProxy $ProxyUrl).AbsoluteUri.TrimEnd('/')
    @{ HTTP_PROXY = $value; HTTPS_PROXY = $value; ALL_PROXY = $value;
       WS_PROXY = $value; WSS_PROXY = $value; NO_PROXY = 'localhost,127.0.0.1,::1' }
}

function Test-ProxyListener([uri]$Proxy) {
    $client = New-Object Net.Sockets.TcpClient
    try {
        $task = $client.ConnectAsync($Proxy.DnsSafeHost.Trim('[', ']'), $Proxy.Port)
        return ($task.Wait(1500) -and $client.Connected)
    } catch { return $false } finally { $client.Dispose() }
}

function Find-LocalProxy {
    # Use explicit configuration, never guess a port or mistake a dashboard for a proxy.
    foreach ($key in @('HTTPS_PROXY', 'HTTP_PROXY', 'ALL_PROXY')) {
        $value = [Environment]::GetEnvironmentVariable($key, 'Process')
        if ($value) { try { return (Get-LoopbackProxy $value).AbsoluteUri.TrimEnd('/') } catch {} }
    }
    try {
        $reg = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
        if ($reg.PSObject.Properties['ProxyEnable'] -and $reg.ProxyEnable -eq 1 -and $reg.PSObject.Properties['ProxyServer']) {
            $value = [string]$reg.ProxyServer
            if ($value -match '=') {
                $pairs = @{}
                foreach ($pair in $value.Split(';')) {
                    if ($pair -match '^\s*(https|http)\s*=\s*(.+?)\s*$') { $pairs[$matches[1]] = $matches[2] }
                }
                if ($pairs.ContainsKey('https')) { $value = $pairs.https }
                elseif ($pairs.ContainsKey('http')) { $value = $pairs.http }
                else { return $null }
            }
            if ($value -notmatch '://') { $value = 'http://' + $value }
            return (Get-LoopbackProxy $value).AbsoluteUri.TrimEnd('/')
        }
    } catch {}
    return $null
}

function Find-CodexExecutable([string]$ExplicitPath) {
    if ($ExplicitPath) {
        $item = Get-Item -LiteralPath $ExplicitPath -ErrorAction Stop
        if ($item.PSIsContainer -or $item.Extension -ne '.exe') { throw 'CodexPath must be an executable file.' }
        return $item.FullName
    }
    $paths = @(Get-Process -Name codex -ErrorAction SilentlyContinue | ForEach-Object { $_.Path } |
        Where-Object { $_ } | Sort-Object -Unique)
    if ($paths.Count -eq 1) { return $paths[0] }
    if ($paths.Count -gt 1) { throw 'Multiple running Codex versions found. Supply -CodexPath for the affected client.' }
    $command = Get-Command codex.exe -ErrorAction SilentlyContinue
    if (-not $command) { throw 'Codex executable not found. Supply -CodexPath.' }
    $command.Source
}

function Read-Doctor {
    param([string]$CodexPath, [hashtable]$Environment = @{}, [string[]]$Overrides = @())
    $result = Invoke-BoundedProcess -File $CodexPath -Arguments ($Overrides + @('doctor', '--json')) -Environment $Environment
    if ($result.timedOut) { return [pscustomobject]@{ available = $false; reason = 'doctor-timeout' } }
    try {
        $data = $result.stdout | ConvertFrom-Json -ErrorAction Stop
        if (-not $data.PSObject.Properties['checks']) { throw 'No checks' }
        $reduced = [ordered]@{ available = $true }
        $network = $data.checks.PSObject.Properties['network.env']
        if ($network -and $network.Value.PSObject.Properties['details']) {
            $preference = $network.Value.details.PSObject.Properties['respect system proxy']
            if ($preference -and $preference.Value -in @('enabled', 'disabled')) {
                $reduced.systemProxyPreference = $preference.Value
            }
        }
        # Keep status/summary only. Never emit raw doctor details, auth, or config.
        foreach ($name in @('config.load', 'auth.credentials', 'network.provider_reachability', 'network.websocket_reachability')) {
            $property = $data.checks.PSObject.Properties[$name]
            if ($property) {
                $check = $property.Value
                $reduced[$name] = [pscustomobject]@{status = $check.status; summary = $check.summary}
            }
        }
        [pscustomobject]$reduced
    } catch { [pscustomobject]@{ available = $false; reason = 'doctor-json-unavailable-or-unsupported' } }
}

function Test-DoctorWebSocket($Doctor) {
    $property = $Doctor.PSObject.Properties['network.websocket_reachability']
    return ($Doctor.available -and $property -and $property.Value.status -eq 'ok' -and
        $property.Value.summary -match 'handshake succeeded|HTTP 101|websocket connected')
}

function Test-DoctorPrerequisites($Doctor) {
    foreach ($name in @('config.load', 'auth.credentials')) {
        $property = $Doctor.PSObject.Properties[$name]
        if (-not $property -or $property.Value.status -ne 'ok') { return $false }
    }
    return $true
}

function Test-HttpPath([string]$ProxyUrl) {
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if (-not $curl) { return [pscustomobject]@{available = $false; reason = 'curl-missing'} }
    $arguments = @('-q', '--silent', '--output', 'NUL', '--connect-timeout', '5', '--max-time', '10',
        '--write-out', '%{http_code}', '--url', 'https://chatgpt.com/backend-api/codex/responses')
    if ($ProxyUrl) { $arguments += @('--proxy', $ProxyUrl, '--noproxy', 'diagnostic.invalid') }
    else { $arguments += @('--noproxy', '*') }
    $r = Invoke-BoundedProcess -File $curl.Source -Arguments $arguments -TimeoutSeconds 15
    $code = 0
    [void][int]::TryParse($r.stdout.Trim(), [ref]$code)
    [pscustomobject]@{available = $true; httpStatus = $code; exitCode = $r.exitCode; timedOut = $r.timedOut;
        tlsHttpReachable = ($r.exitCode -eq 0 -and $code -gt 0);
        blockedOrChallenged = ($code -eq 403); proxyAuthRequired = ($code -eq 407)}
}

function Select-RepairAction($Baseline, $ViaProxy, [string]$Mode, [bool]$ProxyListening) {
    if (-not $Baseline.available) { return 'manual-diagnosis-doctor-unavailable' }
    if (-not (Test-DoctorPrerequisites $Baseline)) { return 'resolve-config-or-auth' }
    $preference = $Baseline.PSObject.Properties['systemProxyPreference']
    if ($preference -and $preference.Value -eq 'enabled') { return 'system-proxy-preference-active-review' }
    if (-not $ProxyListening) {
        if (Test-DoctorWebSocket $Baseline) { return 'healthy-now-observe-desktop' }
        return 'check-proxy-dns-routes-service'
    }
    if (-not (Test-DoctorPrerequisites $ViaProxy) -or -not (Test-DoctorWebSocket $ViaProxy)) {
        return 'proxy-not-verified-no-change'
    }
    if ($Mode -eq 'PrepareProxy') { return 'prepare-verified-proxy-launcher' }
    if (Test-DoctorWebSocket $Baseline) { return 'healthy-now-observe-desktop' }
    return 'prepare-verified-proxy-launcher'
}

function Write-Utf8File([string]$Path, [string]$Text) {
    # BOM keeps Chinese paths/text readable by Windows PowerShell 5.1.
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($true)))
}
