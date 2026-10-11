---
name: codex-reconnect-fix
description: "Diagnose Windows Codex Desktop Reconnecting 1/5 through 5/5, startup WebSocket retries, and interrupted model streams. Compare native doctor, real proxy paths and recent error signatures; prepare a verified process-scoped proxy launcher when appropriate. Distinguish service, authentication, provider, route and long-conversation failures."
---

# Codex Reconnect Fix

Resolve the affected client's connection with evidence. Support Windows PowerShell 5.1/7, a local HTTP/Mixed proxy, and Store-installed `OpenAI.Codex` for launcher repair. Other platforms get diagnosis guidance, not a claim of tested automatic repair.

## Diagnose

Use context to distinguish new conversations failing at startup, midstream disconnects, one old conversation failing during compaction, mobile Remote Control, and SSH/WSL connections. Model Responses and mobile Remote Control are separate transports.

Run the bundled entrypoint with its absolute path:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\scripts\reconnect.ps1" -Mode Diagnose
```

It prioritizes the running Codex binary, detects configured loopback proxies without guessing ports, compares authenticated native `doctor --json` handshakes under the same configuration, probes HTTP without credentials, and optionally reduces SQLite logs to error markers using Python. `CODEX_HOME` is preserved. An unsupported doctor is an inconclusive result, not a failed connection. Inspect only relevant statuses; unrelated doctor warnings do not block a working network.

If detection fails, inspect the proxy client's HTTP/Mixed port and pass `-ProxyUrl http://127.0.0.1:<actual-port>`. A listening dashboard or SOCKS-only port is insufficient. Never publish raw configuration, auth files, environment values, transcripts, or full logs. Reports contain local executable/home paths and should be reviewed before sharing.

For branch selection, consult [decision-guide.md](references/decision-guide.md). Check current [OpenAI service status](https://status.openai.com/) and current client version when failures affect several environments. Online status is supporting evidence, not proof against a narrow incident.

## Repair

When the user requests a fix, authorized reversible repairs may proceed. Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\scripts\reconnect.ps1" -Mode Auto
```

`Auto` prepares a launcher only when config/auth are ready, the default authenticated WebSocket fails and the explicitly proxied authenticated WebSocket succeeds. If both pass, it reports healthy now and makes no launcher change. Do not infer the historical failure has disappeared.

For documented intermittent startup/midstream failures, a user-requested mitigation can use `-Mode PrepareProxy`. This still requires a listening local HTTP proxy and a successful authenticated doctor handshake through it. The script prepares a desktop shortcut; it does not restart or kill the current app. If current tests cannot verify the proxy, stop this repair and follow the relevant diagnostic branch.

The launcher pins the same `CODEX_HOME`, sets HTTP/HTTPS/ALL/WS/WSS proxy variables and a local-only `NO_PROXY` in the child process, and passes Chromium proxy settings with QUIC disabled. These are compatibility measures, not proof that every Codex version reads every variable. It resolves the newest Store package on each launch and refuses to launch over an already-running Codex/ChatGPT process. It does not edit the provider, `.env`, `config.toml`, database, Windows proxy, TUN, firewall, routes, certificates or security policy.

If temporary `respect_system_proxy=true` succeeds while the baseline fails, describe it as an alternative tied to that version. Only merge that feature into TOML after confirming support and the actual improvement, backing up and validating the narrow change. The bundled repair does not persist this flag. Removed WebSocket feature flags and arbitrary custom HTTP providers are not default repairs.

## Verify and roll back

If the user requested a local functional test, the authorized minimal probe uses the existing native auth without extracting tokens:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\scripts\test-model.ps1" -ProxyUrl http://127.0.0.1:<actual-port>
```

It consumes a small model request, uses the built-in provider with user config excluded, is ephemeral and read-only, and checks completion plus a fixed reply with zero observed retry messages. This isolates connectivity; it does not reproduce a custom provider, Desktop renderer, large turn, or hours-long connection. Do not run model requests when the user requested read-only diagnosis only.

After active tasks finish, have the user fully quit Codex and reopen via **Codex - Verified Proxy**. Test at least a new short desktop turn and an ordinary longer turn, retaining the same history and provider. Only then assess whether startup and midstream retries improved. A failed stream after a passing handshake remains unresolved; compare node/egress, client version, fresh conversation, and current incident reports.

Rollback uses fixed managed files and hash guards:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\scripts\reconnect.ps1" -Mode Rollback
```

It removes the managed launcher and shortcut, preserves changed files instead of overwriting them, and leaves the Skill installed. Return to the original shortcut. Report decisive evidence, exactly what changed, verification scope, remaining desktop test, and rollback path. Never promise that installing a Skill fixes every 5/5 error.
