# 相关博客、GitHub Skill 与方案取舍

检索日期：2026-10-12。本文归纳方案，不复刻作者文章或脚本。社区案例只是线索，适用性需要当前版本与本机证据。

## 先看博客：相同提示，不同原因

| 文章 | 作者记录的处理方向 | 本项目如何使用 |
| --- | --- | --- |
| [Leonsux：解决 Codex 响应慢、频繁 Reconnecting 5/5](https://leonsux.github.io/posts/codex-reconnecting-proxy-fix/) | 在 Codex `.env` 中配置实际本地 HTTP 代理并完全重启 | 采用显式代理思路，但用独立进程环境避免覆盖现有 `.env`，先验证再准备 |
| [ZRONG：一到压缩上下文，Codex 就重连 5/5？](https://blog.zengrong.net/post/fix-codex-reconnect-5-of-5-not-network/) | 新对话正常、旧图像长会话压缩失败时，整理迁移摘要并减少大块图像上下文 | 作为条件分支；不把“开新会话”当作新会话也失败的通用解法 |
| [ai345：Codex 重连 5 次怎么办](https://www.ai345.info/ai-guide/codex-reconnecting-5-fix) | 汇总 `.env`、HTTP 传输与 TUN 三类思路 | 保留可选排查方向；不采用“基本都能解决”的保证，不直接切换 provider |
| [clashapp.org：Fix Codex Reconnecting Loops with a Clash Proxy](https://clashapp.org/en-US/clash-blog/codex-reconnecting-clash-proxy-fix.html) | 先看服务状态，再比较应用、代理规则与长连接路径 | 采用分层验证；该页面为第三方资料，不作为 OpenAI 官方结论 |

新对话起始失败和长旧会话压缩失败可以表现相似。博客描述的端口、操作系统、模型和恢复效果都不能直接移植成另一台电脑的根因。

## 再看 GitHub Skills

| 项目 | 已有重点 | 本项目补充或不同选择 |
| --- | --- | --- |
| [zhenyangLab/Codex-Connectivity](https://github.com/zhenyangLab/Codex-Connectivity) | Windows 进程代理、Store 升级、保留历史与移动远控 | 额外以原生认证 WebSocket 做门槛，区分自动修复和间歇故障准备； independently implemented |
| [DAnonyvinciT/codex-fix-reconnecting5-5](https://github.com/DAnonyvinciT/codex-fix-reconnecting5-5) | 对照 doctor 验证 `respect_system_proxy`，保留 provider | 本项目也做临时对照，但不把 under-development 开关永久写入所有机器 |
| [zhuimengFIRE/codex-reconnect-fix-skill](https://github.com/zhuimengFIRE/codex-reconnect-fix-skill) | 检测端口并刷新 `.env` | 本项目不改 `.env`；仅有 TCP 监听不足以认定代理协议和 WebSocket 正常 |
| [howtimeschange/fix-codex-reconnecting-skill](https://github.com/howtimeschange/fix-codex-reconnecting-skill) | 代理环境、provider 与 HTTP 传输排查 | 本项目默认保留传输/provider 身份，避免用自定义 provider 掩盖路由故障 |
| [9398-haha/codex-reconnect-repair](https://github.com/9398-haha/codex-reconnect-repair) | 按客户端上下文诊断、分支修复、受保护回滚 | 采用证据优先和报告边界；Windows 无 Python 也能完成本项目核心代理诊断 |
| [DeepVite/skill-fix-codex-reconnecting](https://github.com/DeepVite/skill-fix-codex-reconnecting) | 在 HTTP-only 自定义 provider 与默认模式之间切换 | 只保留为高级排查线索；不是本项目默认自动修复 |

还检索到 [LiZuchen 的 Windows 代理排查](https://github.com/LiZuchen/codex-windows-proxy-troubleshooting) 与 [lijinghai 的 loopback/CC-Switch 排查](https://github.com/lijinghai/ljh-codex-desktop-loopback-repair-skill)。后者包含沙箱、防火墙、端口转发及配置管理器相关操作。这些需要精确的当前进程与策略证据，不适合作为所有 5/5 故障的一键操作。本项目不执行降低隔离、删除沙箱用户、防火墙清理或第三方数据库重写。

以上是阅读公开 Skill 的功能比较，未安装或运行其第三方修复脚本；没有证据证明本项目在所有环境中胜过这些项目。

## 用官方资料核对技术依据

- [OpenAI Codex #24045](https://github.com/openai/codex/issues/24045)：报告新建或恢复会话时 WebSocket 预热重试、随后 HTTP/SSE 恢复。属于用户报告，和本案例症状相近，不等于根因确认。
- [OpenAI Codex #29958](https://github.com/openai/codex/issues/29958)：Windows 系统代理与显式环境变量行为存在版本差异的报告。这也是必须做本机对照的原因。
- [OpenAI Codex #18960](https://github.com/openai/codex/issues/18960)：相似断流提示下包含代理、失效端点、长会话及服务端方向的不同报告，不能拿评论里的单一办法包治全部。
- [OpenAI Codex #52271](https://github.com/openai/codex/issues/52271)：近期 Windows 断流及 CLI/桌面差异报告；第三方 HTTP provider 未给该报告带来持久恢复。仍为开放问题，不能当作已确认的统一缺陷。
- [官方排错文档](https://learn.chatgpt.com/docs/reference/troubleshooting)：CLI/桌面可包含不同版本；分享日志前审阅敏感信息，卡住时可用更小的新对话辅助隔离。
- [官方 WebSocket 说明](https://developers.openai.com/api/docs/guides/websocket-mode)：持久连接和恢复与普通单次 HTTP 请求不同。API 指南不保证每个 Codex 桌面版本的具体配置行为。
- [官方 HTTP proxy route 源码](https://github.com/openai/codex/blob/92caad782887cde063572fc0a0efbf5b1317520d/codex-rs/http-client/src/outbound_proxy.rs) 与 [WebSocket dialer](https://github.com/openai/codex/blob/92caad782887cde063572fc0a0efbf5b1317520d/codex-rs/websocket-client/src/dialer.rs)：该提交处理环境代理、NO_PROXY 与 WebSocket 代理路线。源码版本和本机版本可能不同，最终仍以原生测试为准。

本项目不安装未知网络补丁、不移除 TLS 验证，也不把 HTTP 401/405、CONNECT 200 或 doctor 的 HTTP 101 写成任务已成功。将“发现问题 → 核对路径 → 准备可逆修复 → 实际桌面任务完成”作为完整交付链。
