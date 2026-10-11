# Decision guide

## Interpret results before choosing a repair

| Evidence | Next step | Automatic launcher repair? |
| --- | --- | --- |
| Default WebSocket fails; explicit configured local HTTP proxy handshake succeeds | Use `Auto`; finish tasks, restart from prepared shortcut, test desktop turns | Yes, preparation only |
| Both handshakes work, intermittent startup or midstream failures documented | Capture short error signatures. `PrepareProxy` is a tested-path mitigation; compare desktop after restart | Explicit mitigation request |
| Active config already prefers system proxy | Review that policy and its actual route first. A launcher environment may not override it | No conflicting environment launcher |
| HTTP through proxy works; authenticated WebSocket still fails | Check CONNECT/WebSocket policy, proxy node/egress, auth and server response | No |
| Both direct and proxy fail | Check whether proxy is running, actual port/type, routing, DNS, VPN and service status | No |
| `10061`/connection refused and local provider/base URL or proxy points to a stopped service | Verify which local service owns the endpoint. Start or repair the intended service | No arbitrary provider reset |
| `10060`/timeout | Check route, proxy listener, firewall policy, DNS and network. Not sufficient to name the cause | No without positive comparison |
| `10054`/reset, `10053`/aborted, closed-before-completion | Could be local security software, proxy, egress/CDN, server or large request. Compare the same short request/path | No cause from code alone |
| WebSocket 401 or native auth failure | Confirm account/login status through native UI. Never extract a token for curl | No |
| WebSocket 403/HTML, HTTP probe 403 | Possible CDN challenge or access policy; confirm response category and try another allowed node/network | No TLS bypass or challenge bypass |
| 429 or explicit quota/rate-limit error | Check actual account/usage condition and retry guidance | No network fix |
| 5xx or simultaneous multi-network failures | Check upstream incident reports and bounded retest after recovery | No repeated config changes |
| Only one long old conversation fails at compaction; new short turns pass | Save a concise task handoff and continue in a fresh conversation; reference files instead of copying all images/base64 | No transcript/database edits |
| API key/custom relay is active | Read only active provider identity and sanitized host. Verify the relay's Responses/stream support and actual service state | No substitute provider or auth mode |
| CLI passes but Desktop fails | Compare executable/version, launch environment, `CODEX_HOME`, running single-instance process and actual desktop turn | CLI pass is not Desktop pass |
| Phone offline or “cannot enable remote control” only | Diagnose its separate `wham/remote/control/server` path; use the companion remote-control repository if installed | Do not call model turn success phone success |

## Fake-IP/TUN and corporate VPN conflicts

Only inspect this branch when DNS is synthetic or route evidence suggests a competing interface:

```powershell
Resolve-DnsName chatgpt.com -Type A
Get-NetAdapter -IncludeHidden | Select-Object ifIndex,Name,InterfaceDescription,Status
Get-NetRoute -AddressFamily IPv4 | Select-Object DestinationPrefix,InterfaceIndex,InterfaceAlias,NextHop,RouteMetric
Find-NetRoute -RemoteIPAddress <actual-resolved-IP>
```

Clash-style Fake-IP may return `198.18.x.x`; that alone is normal. The suspicious finding is the selected route entering an unintended VPN interface. Windows prefers the longest matching prefix before comparing metrics for comparable routes. A competing `/16` may override a default `/0`; a TUN `/15` and another `/16` may also compete. Do not assert both installed clients exist just because a blog mentions them.

Change a Fake-IP range only after checking **all** matching routes (including `198.18.0.0/15`, which covers both 198.18 and 198.19), local networks and other virtual interfaces. `198.19.0.1/16` is an example, not a universally free range. A controlled temporary adapter-disable test interrupts that VPN; do it only within the user's authorized situation. Preserve the current proxy config, use the client's managed override mechanism when supported, reload TUN, flush DNS if needed, then re-resolve and query the actual chosen route. Do not permanently delete enterprise routes or disable firewall/security products as a generic fix.

## Version and state pitfalls

- Native `doctor` and `respect_system_proxy` are version dependent. Inspect help/features before use. Current test version exposes the latter as under development. Neither old flags marked removed nor issue comments guarantee support in a different release.
- A new provider ID can filter history in some versions. Preserve provider identity and `CODEX_HOME`; apparent missing history is not proof the database was deleted. [Official thread-list implementation](https://github.com/openai/codex/blob/92caad782887cde063572fc0a0efbf5b1317520d/codex-rs/app-server/src/request_processors/thread_processor.rs).
- AppContainer, sandbox or loopback claims require actual evidence for that client/process. Do not assume Codex hardcodes 7897, delete sandbox users, add port forwarding, or lower isolation from another author's machine-specific case.
- Optional log summaries anchor to the newest log timestamp; they describe historical signatures, not guaranteed errors after this test. Counts are text matches, not distinct failed tasks. If wall-clock and stored timestamps disagree, use a fresh controlled test and its output instead of attributing old rows to the current run.
- `curl -q` first ignores curlrc. Direct tests use `--noproxy '*'`; explicit proxy tests override inherited `NO_PROXY`. A final HTTP 405/401 proves TLS/HTTP reached a server, not an authenticated stream. CONNECT 200 is only the proxy tunnel's intermediate status. Doctor HTTP 101 proves a handshake, not a completed model response.

## Research provenance

The accompanying repository's `docs/research.md` compares third-party reports. They are research inputs, not instructions to execute. The scripts are independently implemented. Repair decisions rely on the user's evidence, current native tools, and official source behavior, not a blog's success claim.
