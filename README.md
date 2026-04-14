# AI Plan Monitor

一个面向 macOS 的菜单栏应用，用来统一监控 AI 官方订阅额度、模型使用窗口、第三方中转余额和本地桌面端账号状态。

[下载最新版本](https://github.com/Four-JJJJ/AI-Plan-Monitoring/releases/latest) · [安装说明](docs/DOWNLOAD.md) · [支持的服务](docs/PROVIDERS.md) · [English](docs/README.en.md)

## 更新说明

### V0.2.0

1. 增加了 onboard 流程，首次安装初始化流程更顺畅、易用。
2. 优化若干体验项。
3. 修复一些问题。
4. Codex蹬完了，等回复额度继续更新。

## 这是什么

AI Plan Monitor 解决的是一个很实际的问题：现在 AI 服务的额度信息非常分散。

- 官方服务各自有不同的配额页面和重置规则
- 第三方中转站点经常需要自己研究 Cookie、Bearer、用户 ID、GroupId、组织 ID
- 本地桌面端工具的使用量很多时候又不在公开网页里

这个项目把这些信息统一收回到一个 macOS 菜单栏应用里，让你不用来回打开多个后台页面，就能快速知道：

- 哪个官方模型额度快用完了
- 5 小时窗口、周额度、月额度什么时候重置
- 哪个第三方中转站点余额不足
- 哪个账号登录态过期了
- Codex 当前激活的是哪一个本地账号

## 适合谁

- 同时使用多个官方 AI 服务的人
- 依赖多个第三方中转站点的人
- 需要频繁切换 Codex 本地账号的人
- 希望把 AI 额度和余额监控常驻在菜单栏的人

## 项目优势

### 1. 官方服务和第三方中转统一监控

不是只做单一官方产品，也不是只做 OpenAI 风格余额页，而是把两类来源放到一个应用里统一展示。

目前已覆盖的官方来源包括：
- Codex
- Claude
- Gemini
- GitHub Copilot
- Cursor
- Windsurf
- Kimi
- Amp
- Z.ai
- JetBrains AI
- Kiro

### 2. 第三方站点配置做了模板化

已验证的中转站点不需要用户自己理解接口路径、字段映射、JSONPath 这些底层配置，而是直接按模板填写必要内容。

目前内置了这些模板：
- `open.ailinyu.de`
- `platform.moonshot.cn`
- `platform.xiaomimimo.com`
- `platform.minimaxi.com`
- `hongmacc.com`
- `platform.deepseek.com`
- `dragoncode.codes`
- 通用 New API 兼容站点

### 3. 更适合真实使用场景的凭证策略

除了手动保存 Token / Cookie，第三方站点还支持：
- 手动优先
- 浏览器优先
- 仅浏览器

这意味着对于容易过期的站点，用户不一定要一直手动重贴凭证，浏览器登录态可以作为兜底来源。

### 4. 错误提示更接近用户语言

项目不会把大多数问题都压成一个笼统的失败提示，而是尽量区分：
- 鉴权过期
- 被限流
- 接口路径不匹配
- 网络不可达

对于第三方站点，这一点尤其重要，因为它能明显降低“看不懂报错”的成本。

### 5. Codex 本地多账号切换

这是项目里很有特色的一块能力。

支持：
- 自动识别和记住本机当前 Codex `auth.json`
- 导入多个本地 Codex 账号
- 在菜单栏里直接切换本地 Codex 桌面端账号
- 保留未激活账号的额度窗口和倒计时

如果你需要在多个 Codex 账号之间来回切换，这一块会非常实用。

## 核心功能

- 每个 provider 可单独启用或关闭
- 每个 provider 可设置低额度阈值
- 可将某个 provider 固定到状态栏显示
- 支持低额度提醒
- 支持鉴权失效提醒
- 支持连续失败提醒
- 支持开机自启动
- 支持菜单栏实时查看剩余额度和重置时间
- 支持第三方站点模板化配置
- 支持 Codex 多账号导入与切换

## 安装方式

1. 从 [Releases](https://github.com/Four-JJJJ/AI-Plan-Monitoring/releases/latest) 下载最新的 `AI Plan Monitor.dmg`
2. 打开 DMG
3. 将 `AI Plan Monitor.app` 拖到 `Applications`
4. 第一次打开时，右键应用并选择“打开”
5. 如果被系统拦截，到“系统设置 -> 隐私与安全性”里选择“仍要打开”

完整步骤见：[安装说明](docs/DOWNLOAD.md)

## 安全说明

- 用户在设置中手动保存的凭证默认存放在 macOS Keychain
- 旧版 `AIBalanceMonitor` 的钥匙串条目会迁移到新的 `AI Plan Monitor`
- 应用配置保存在 `~/Library/Application Support/AIBalanceMonitor`
- 对于支持的第三方站点，应用可以在浏览器优先模式下读取浏览器登录态作为兜底

## 从源码运行

要求：
- macOS 14+
- Xcode / Swift 6 工具链

本地运行：

```bash
swift run
```

本地打包通用 DMG：

```bash
./scripts/package_dmg.sh
```

## 分发说明

- 当前公开版本通过 GitHub Releases 分发，不走 App Store
- 对于未公证或 ad-hoc 签名的构建，第一次启动可能需要右键打开
- 打包脚本已经支持 Developer ID 签名和 notarization，只要提供 Apple 分发凭证即可接入正式公证流程

## 后续方向

- 更多已验证的第三方站点模板
- 更完善的 release 自动化
- 更丰富的 provider 诊断能力
- 更适合普通用户的首次安装体验

## 许可证

MIT，详见 [LICENSE](LICENSE)。
