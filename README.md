# AI Plan Monitor

一个面向 macOS 的菜单栏应用，用来把 AI 官方订阅额度、模型使用窗口、第三方中转余额，以及本地桌面端账号状态统一收进一个地方。

[下载最新版本](https://github.com/Four-JJJJ/AI-Plan-Monitor/releases/latest) · [安装说明](docs/DOWNLOAD.md) · [支持的服务](docs/PROVIDERS.md) · [English](docs/README.en.md)

## 最新更新

### V1.8.1

1. 修复英文模式下任务预览与设置页倒计时仍显示中文的问题，统一改为 `3 d 23 h`、`23 h 54 m` 这类英文格式。
2. 统一菜单栏弹层与设置页的倒计时格式逻辑，避免不同页面在中英文切换后显示不一致。
3. 补充英文倒计时与共享 helper 的测试覆盖，降低后续多语言显示回归风险。

## 它解决什么问题

现在 AI 用量信息通常散落在很多地方：

- 官方产品各自有不同的额度页、重置周期和展示方式
- 第三方中转站经常需要自己处理 Cookie、Bearer、用户 ID、GroupId 或组织上下文
- 本地桌面端工具的使用状态，很多时候又不在公开网页里

AI Plan Monitor 的目标很直接：

- 在菜单栏里快速知道哪些额度快用完了
- 明确看到会话、5 小时、周、月等窗口何时重置
- 统一管理官方来源和第三方中转来源
- 提前发现登录态失效、鉴权过期、站点接口变更或连续失败
- 在需要时直接切换本地 Codex 账号，而不是手动翻配置文件

## 适合谁

- 同时使用多个 AI 官方产品，希望把额度状态常驻在菜单栏的人
- 依赖多个中转站点，希望统一查看余额和异常状态的人
- 经常在多个 Codex 本地账号之间切换的人
- 想要一套更接近真实使用场景，而不是只看单一网页余额的监控工具的人

## 核心思路

这个项目把来源分成三类统一处理：

### 1. 官方订阅与官方用量

适合能从官方 API、官方网页、官方 CLI 或本地官方会话中拿到真实状态的服务。

### 2. 本地桌面端账号状态

适合像 Codex 这类会把登录态、账号信息或本地使用记录落在本机的桌面端工具。

### 3. 第三方中转站点

通过模板化配置、浏览器兜底和更清晰的错误分类，减少用户手工拼接口和猜字段的成本。

## 核心能力

### 菜单栏实时监控

- 菜单栏直接显示额度、百分比、倒计时和刷新状态
- 支持单模型固定显示，也支持多模型轮换或多用量展示
- 状态栏外观支持跟随壁纸、强制深色、强制浅色

### 官方来源与第三方来源统一管理

- 一个应用里同时管理官方服务和中转站
- 每个 Provider 可单独启用、停用、设置阈值和显示策略
- 尽量统一“低额度、鉴权失效、连续失败、已缓存回退”等状态表达

### 更实用的中转站配置方式

- 内置已验证模板，减少手工填写接口路径和解析字段
- 支持 `Manual Preferred`、`Browser Preferred`、`Browser Only` 三种凭证策略
- 对常见失败原因做更明确的用户可读提示，而不是只返回一个模糊错误

### Codex 多账号与本地切换

- 自动识别当前本机 Codex 桌面端登录态
- 支持导入和保存多个 Codex 账号槽位
- 可在应用内直接切换本地 Codex 账号
- 非当前账号的额度窗口和倒计时也可以保留展示

### OAuth 导入与账号资料管理

- 支持 Codex 和 Claude 的 OAuth 导入流程
- 支持已导入账号的备注、显示名和槽位管理
- 尽量保留已识别账号与槽位之间的稳定对应关系

### 应用级能力

- 支持低额度提醒、鉴权失效提醒和连续失败提醒
- 支持开机自启动
- 支持 GitHub Release 驱动的应用内更新检测与版本说明展示

## 当前支持的服务

详细说明见 [docs/PROVIDERS.md](docs/PROVIDERS.md)。这里列出当前首页层面的支持范围。

### 官方来源

| 类型 | 服务 |
| --- | --- |
| 官方 / 本地桌面端 | Codex、Claude、Gemini、GitHub Copilot、Cursor、Windsurf |
| 官方 / API 或网页来源 | Kimi、Amp、Z.ai、OpenCode Go |
| 官方 / 本地数据来源 | JetBrains AI、Kiro |

### 第三方中转模板

| 模板 | 凭证方式 |
| --- | --- |
| `open.ailinyu.de` | Cookie |
| `platform.moonshot.cn` | Bearer 或 Cookie |
| `platform.xiaomimimo.com` | Cookie |
| `platform.minimaxi.com` | Cookie |
| `hongmacc.com` | Bearer |
| `platform.deepseek.com` | Bearer |
| `dragoncode.codes` | Relay Token |
| Generic New API | Bearer 或 Cookie |

说明：

- 第三方站点变化频率通常高于官方接口
- 模板能降低接入成本，但当站点响应结构变化时，仍可能需要模板更新

## 为什么这个项目和一般的“额度页封装”不一样

- 它不是只做单一官方产品，也不是只做一个 OpenAI 风格余额接口
- 它同时覆盖官方订阅、桌面端本地状态和第三方中转站
- 它不是只给出一个数值，而是尽量把“额度、窗口、刷新、异常状态、账号上下文”一起展示出来
- 它更偏向日常长期使用，而不是一次性查余额

## 安装

### 下载安装

1. 从 [Latest Release](https://github.com/Four-JJJJ/AI-Plan-Monitor/releases/latest) 下载最新的 `AI Plan Monitor.dmg`
2. 打开 DMG
3. 将 `AI Plan Monitor.app` 拖入 `Applications`
4. 第一次启动时，如果被系统拦截，右键应用并选择“打开”
5. 如果仍被拦截，到“系统设置 -> 隐私与安全性”里选择“仍要打开”

更完整的步骤见 [安装说明](docs/DOWNLOAD.md)。

### 系统要求

- macOS 14 或更高版本
- 非 App Store 分发，当前通过 GitHub Releases 提供安装包

## 数据与安全

- 应用中手动保存的凭证默认存放在 macOS Keychain
- 历史 `AIPlanMonitor` 钥匙串条目会迁移到新的 `AI Plan Monitor`
- 应用配置保存在 `~/Library/Application Support/AIPlanMonitor`
- 对于支持的中转站，应用可在浏览器优先模式下把浏览器登录态作为兜底来源

说明：

- 读取浏览器状态只用于支持的站点和对应配置模式
- 第三方站点接入能力会受到目标站点认证方式和返回结构变化的影响

## 从源码运行

### 环境要求

- macOS 14+
- Xcode / Swift 6 工具链

### 常用命令

运行应用：

```bash
swift run
```

运行测试：

```bash
swift test
```

打包通用 DMG：

```bash
./scripts/package_dmg.sh
```

打包产物默认输出到：

- `dist/AI Plan Monitor.dmg`
- `dist/AI-Plan-Monitor-macOS.zip`

## 项目结构

```text
Sources/AIPlanMonitor
├── App        # 应用生命周期、状态栏、窗口与更新流程
├── Models     # Provider、配置与共享数据模型
├── Providers  # 各服务的接入实现
├── Services   # 鉴权、刷新、账号管理、通知、更新等服务
├── UI         # SwiftUI 设置页与菜单内容
└── Resources  # 图标、模板与内置资源

Tests/AIPlanMonitorTests
docs/
scripts/
```

## 相关文档

- [安装说明](docs/DOWNLOAD.md)
- [支持的服务](docs/PROVIDERS.md)
- [English README](docs/README.en.md)

## 分发说明

- 当前公开版本通过 GitHub Releases 分发
- GitHub 分发的构建可能是 ad-hoc 签名，首次启动时可能需要右键打开
- 打包脚本已经支持 Developer ID 签名和 notarization；在提供 Apple 分发凭证时可接入正式公证流程

## 致谢

感谢以下项目带来的启发：

- [openusage](https://github.com/robinebers/openusage)
- [cc-switch](https://github.com/farion1231/cc-switch)
- [codexbar](https://github.com/rajasimon/codexbar)

## 许可证

MIT，详见 [LICENSE](LICENSE)。
