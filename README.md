# Codex 重连 5/5 排查与修复 Skill

**Windows Codex Reconnecting 1/5–5/5 / 正在重新连接 / stream disconnected before completion**：自动比较默认连接与实际本地代理，按证据准备可回滚的代理启动快捷方式。

![Codex 正在重新连接 5/5](assets/reconnecting-5-of-5.png)

适合“新对话开头经常重连、中途偶尔断流、浏览器正常而 Codex 不稳定”的情况。**5/5 是重试状态，不是唯一病因。** 本项目能自动处理经验证的 Windows 本地代理连接路径问题；认证、配额、服务故障、失效的第三方网关和超长旧会话需要走对应诊断分支。

作者：[mirror30z](https://github.com/mirror30z)。采用 MIT 许可。

## 解决什么问题

- 新开对话时反复显示 `Reconnecting 1/5` 到 `5/5`，等待后才开始回答。
- 回答过程中断流，出现 `stream disconnected before completion`。
- 代理客户端已运行，浏览器能访问，但 Codex 连接不稳定。

## 我的修复方法

**检测真实连接路径，验证可用代理，再为 Codex 创建专用启动入口。**

1. 找到实际运行的 Codex 和它使用的数据目录。
2. 读取实际配置的本地 HTTP/Mixed 代理地址，检查端口是否监听。
3. 对比默认路径与显式代理的 HTTP、认证 WebSocket 结果。
4. 在验证通过后生成代理快捷方式；重开 Codex，验证新对话与较长任务。

启动入口为 Codex 进程树设置代理，保留原有账号、provider 和聊天目录。端口根据本机配置读取，不要求固定端口；Store 更新后重新查找最新程序路径。

## 使用条件

- Windows，已安装 Microsoft Store 版 Codex。
- 代理客户端正在运行，提供本地 HTTP 或 Mixed 端口。
- Windows PowerShell 5.1 或 PowerShell 7；Codex 支持 `doctor --json`。

## 一行安装并执行

在 **Windows PowerShell** 中运行，无需管理员权限：

```powershell
irm https://raw.githubusercontent.com/mirror30z/codex-reconnect-fix/v1.0.1/install.ps1 | iex
```

这条命令安装 Skill 并执行 `Auto`：

- 默认 WebSocket 失败、显式本地代理 WebSocket 成功：生成桌面 **Codex - Verified Proxy** 快捷方式。
- 两者都成功：报告“当前通过”，不强行改配置。间歇性问题仍需重现与桌面验证。
- 代理、认证或原生诊断未通过：解释诊断结果，不伪报修复成功。

对于本项目案例这样的**间歇性问题**，希望先准备一个经过验证的代理启动入口，可以一行运行：

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/mirror30z/codex-reconnect-fix/v1.0.1/install.ps1))) -Mode PrepareProxy
```

它从当前代理环境或已启用的 Windows 系统代理读取地址。若无法识别，可加 `-ProxyUrl http://127.0.0.1:<你的HTTP或Mixed端口>`。不会把 7890、7897 或本案例端口当作通用默认值；不会把 SOCKS 端口或管理面板端口当作可用 HTTP 代理。

准备完成后，等当前任务结束，**完全退出 Codex，再用新快捷方式打开**。应用已经运行时，启动第二个入口通常无法替换原进程环境，因此启动器会阻止这种误操作。代理软件必须保持运行。

## 在 Codex 里使用 Skill

安装后开始新对话，输入：

```text
使用 $codex-reconnect-fix 排查我新对话开始时重连 5/5、中途偶尔断流的问题，执行有证据支持的修复并验证。
```

也可以让 Codex 从本仓库安装 `skills/codex-reconnect-fix`。本地安装默认路径是 `$CODEX_HOME/skills/codex-reconnect-fix`，未设置 `CODEX_HOME` 时使用 `~/.codex/skills/codex-reconnect-fix`。重复安装不会覆盖已被你修改的文件。

## 检查与验证

已安装时可在 PowerShell 使用以下命令；若设置了自定义 `CODEX_HOME`，将路径替换为该目录：

```powershell
# 只诊断，不创建启动器
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-reconnect-fix\scripts\reconnect.ps1" -Mode Diagnose

# 原生认证的真实最小模型请求：会消耗少量额度
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-reconnect-fix\scripts\test-model.ps1" -ProxyUrl http://127.0.0.1:<实际端口>

# 回滚启动器与快捷方式；保留 Skill
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-reconnect-fix\scripts\reconnect.ps1" -Mode Rollback
```

成功需要分层判断：

| 检查 | 能证明什么 | 不能证明什么 |
| --- | --- | --- |
| 代理端口监听 | 本地服务存在 | 是正确的 HTTP 代理 |
| curl 返回最终 401/405 等 HTTP 状态 | TLS/HTTP 路径可达 | 登录成功、WebSocket 可用 |
| 原生 doctor 返回 HTTP 101 | 认证 WebSocket 握手通过 | 长连接稳定、整轮任务完成 |
| 最小模型请求完成、零观察到的重试 | 当前隔离请求可以完成 | 桌面、原配置或大请求一定正常 |
| 桌面重开后的新短对话与普通长任务通过 | 实际体验得到验证 | 永久不会再断线 |

最小请求使用现有原生认证、内置 provider、临时会话及只读沙箱，排除用户配置以隔离连接；不读取令牌发 curl，不接管现有任务。自定义 provider/网关的真实行为应在原配置下另测。

## 适用范围与实现

- 自动执行支持 Windows PowerShell 5.1/7、`curl.exe`、支持 `doctor --json` 的 Codex，以及本地 HTTP/Mixed 代理；快捷方式支持 Store 的 `OpenAI.Codex` 安装。
- 可选 Python 只用于受限的只读日志分类；没有 Python 仍可执行连接诊断和准备启动器。
- `doctor` 或当前版本不支持时，返回未确定结果，转交 Skill 指导排查，不写未知配置项。
- 已启用 `respect_system_proxy` 优先策略时先人工核对，避免启动器环境被现有系统代理策略覆盖；显式代理探测会在支持时临时关闭该优先策略，文件保持不变。
- 代理变量仅进入启动器启动的 Codex 进程树；Codex 子进程也会继承。保留 `CODEX_HOME` 和 provider，不修改 `.env`、`config.toml`、聊天数据库、全局代理、TUN、路由、DNS、防火墙或证书设置。
- 启动时重新查找最新 Store 包，避免程序升级后固定可执行路径失效。
- 回滚校验管理文件哈希和快捷方式归属，发现改动就保留文件供检查；不递归删除目录。
- JSON 报告包含本机程序/主目录路径，分享前请审阅。可选日志输出只含错误标记与时间，不含对话、令牌、完整日志或线程 ID。

自动修复面向已验证的本地代理路径问题。其他操作系统、账号限制、服务故障或单个超长会话，应根据诊断结果分别处理。

## 实测与资料

- [我的排查文章：从 5/5 提示到可验证的修复](docs/article.md)
- [本机测试记录与尚待验证项](docs/local-validation.md)
- [Skill 诊断决策表](skills/codex-reconnect-fix/references/decision-guide.md)
- 相关手机远程控制问题：[codex-remote-control-troubleshooter](https://github.com/mirror30z/codex-remote-control-troubleshooter)

开发检查（不向模型发送请求）：

```powershell
powershell.exe -NoProfile -File .\tests\check.ps1
pwsh -NoProfile -File .\tests\check.ps1
python -m unittest discover -s tests -p test_*.py
```

Windows CI 运行两种 PowerShell 及日志测试。CI 不拥有用户认证，不验证真实模型/手机连接。
