# OhMyUsage 重构方案

更新时间：2026-05-07

本文档是在当前仓库代码、目录结构、构建结果和测试结果基础上形成的详细重构方案。目标不是推倒重写，而是在保留现有行为和测试护栏的前提下，逐步把项目从“能跑但复杂度持续上升”的状态，重构为“可扩展、可维护、可验证”的桌面产品代码库。

当前基线：

- `swift build` 通过
- `swift test` 通过，466 个测试全绿
- 当前问题主要不是“不能运行”，而是架构耦合、扩展成本、重复实现、状态边界模糊

---

## 1. 重构目标

### 1.1 业务目标

- 保持现有核心能力不回退：
  - 菜单栏额度监控
  - 官方 Provider 监控
  - 第三方 Relay/NewAPI 监控
  - Codex / Claude 账号导入与切换
  - 历史用量读取
  - 通知、更新、权限管理
- 让未来新增 Provider、新增展示方式、新增账号体系时，不再需要改动多个大文件
- 让设置页、状态栏、刷新调度、Provider 抓取、持久化各自拥有明确边界
- 让关键失败路径可见，不再依赖静默 `try?`

### 1.2 技术目标

- 拆解 `AppViewModel` 和 `SettingsView` 两个单体中心
- 统一 Provider Runtime，消除官方 Provider 和 Relay Provider 的重复基础设施
- 降低字符串化元数据的业务承载比例
- 建立模块边界、CI 护栏、回归验证策略
- 引入可持续演进的目录结构和 SwiftPM target 划分

### 1.3 非目标

- 第一阶段不做 UI 全量视觉重做
- 第一阶段不做功能大扩张
- 第一阶段不追求把所有 Provider 全部换成全新实现
- 第一阶段不推翻现有测试体系

---

## 2. 当前问题总览

## 2.1 架构层

- `Sources/OhMyUsage/App/AppViewModel.swift` 超过 4000 行，同时承担：
  - 配置读写
  - Provider 刷新
  - 告警
  - 权限
  - 更新
  - Codex/Claude 账号管理与切换
  - 设置页行为
  - UI 可见状态
- `Sources/OhMyUsage/UI/SettingsView.swift` 接近 10000 行，存在大量 `@State`、`onChange`、`alert`、`sheet`、业务规则和 UI 混排
- 当前 `UI/Settings/*.swift` 多数只是空包装视图，没有形成真正的 feature 分层
- `ProviderFactory`、`AppViewModel`、`StatusBarController`、`MenuContentView`、`SettingsView` 都在持有或推导 Provider 相关元信息

## 2.2 Provider 层

- 官方 Provider 普遍重复实现：
  - 凭证发现
  - token 刷新
  - HTTP 请求
  - 缓存回退
  - 浏览器 Cookie 兜底
  - JSON 解析与文件回写
- `RelayProvider.swift` 已经膨胀成单独平台，集中了：
  - adapter 选择
  - 多通道抓取
  - 浏览器凭证恢复
  - 站点特化分支
  - 元数据拼装

## 2.3 数据模型层

- `UsageSnapshot` 使用 `extras` 和 `rawMeta` 字典承载跨层语义，类型约束不足
- Provider 解析广泛使用 `[String: Any]` 和 `JSONSerialization`
- UI、告警、状态栏、历史用量等逻辑对隐式 key 存在耦合

## 2.4 状态与错误处理

- 配置、账号档案、槽位、更新状态等大量写入路径使用 `try?`
- 用户可能在界面上完成操作，但持久化失败时没有明确反馈
- 部分并发路径依赖 `@unchecked Sendable` 和调用约定，而不是清晰的 actor / immutable 边界

## 2.5 交付与工程化

- 当前只有 release workflow，没有常规 PR/Push 构建测试 CI
- 项目仍是单一 executable target，模块边界无法由编译期约束
- 缺少“性能/能耗/刷新频率/失败率”的工程指标

---

## 3. 重构总体策略

采用渐进式 strangler 重构，而不是推倒重写。

核心原则：

- 先加护栏，再拆结构
- 先抽公共基础设施，再迁移具体 Provider
- 先分状态边界，再分 UI 组件
- 先保证行为一致，再逐步优化内部模型
- 每一步都必须可回退、可验证、可发布

推荐路线：

1. 固化当前行为边界
2. 搭建新架构骨架
3. 把旧实现逐步迁移到新骨架
4. 清理旧耦合层和重复代码

---

## 4. 目标架构

## 4.1 分层模型

建议将项目分成六层：

1. Domain
   - 核心业务模型
   - Provider 能力模型
   - Quota/Account/History/Alert 相关纯逻辑

2. Application
   - 用例和编排
   - 刷新调度
   - 账号切换事务
   - 更新检查流程
   - 权限刷新流程

3. Infrastructure
   - 配置存储
   - Keychain
   - 文件系统
   - Browser cookie/credential 桥接
   - Shell/Process
   - HTTP 客户端

4. Provider Runtime
   - 通用 Provider 执行框架
   - OAuth 刷新器
   - Official/Relay 抓取基础能力
   - 统一错误分类与缓存策略

5. Presentation
   - 展示模型
   - Presenter / Formatter
   - 状态栏渲染输入模型
   - 设置页展示模型

6. App / Feature UI
   - 菜单栏
   - 设置页
   - 窗口控制器
   - 生命周期与启动

## 4.2 推荐 SwiftPM Target 划分

推荐在保持最终 executable product 不变的前提下，拆成以下 target：

```text
OhMyUsageApp                 executable
├── OhMyUsageBootstrap       app lifecycle / window controllers / shell wiring
├── OhMyUsageFeatures        menu bar + settings feature entry points
├── OhMyUsagePresentation    presenters / display models / formatters
├── OhMyUsageApplication     coordinators / use cases / schedulers
├── OhMyUsageProviders       provider runtime + provider implementations
├── OhMyUsageInfrastructure  config/keychain/fs/http/browser/process/update
└── OhMyUsageDomain          core models / policies / pure logic
```

如果想进一步细分，可以在第二阶段再把 `OhMyUsageProviders` 拆为：

```text
OhMyUsageProvidersCore
OhMyUsageProvidersOfficial
OhMyUsageProvidersRelay
OhMyUsageProvidersLocal
```

第一轮不建议过度切 target，6-7 个目标足够。

## 4.3 推荐目录结构

```text
Sources/OhMyUsageApp/
Sources/OhMyUsageBootstrap/
Sources/OhMyUsageFeatures/
  MenuBar/
  Settings/
  Shared/
Sources/OhMyUsagePresentation/
  StatusBar/
  Menu/
  Settings/
  Localization/
Sources/OhMyUsageApplication/
  AppSession/
  Providers/
  Accounts/
  History/
  Alerts/
  Updates/
  Permissions/
Sources/OhMyUsageProviders/
  Core/
  Official/
  Relay/
  Local/
Sources/OhMyUsageInfrastructure/
  Config/
  Storage/
  Security/
  Browser/
  HTTP/
  Process/
  Filesystem/
Sources/OhMyUsageDomain/
  Provider/
  Usage/
  Account/
  Quota/
  Alert/
  Common/
```

---

## 5. 关键模型重构方案

## 5.1 ProviderDescriptor 拆分

当前 `ProviderDescriptor` 同时承担：

- 持久化配置
- 展示元数据
- Provider 类型判定
- 运行时控制

建议拆成三类对象：

### A. ProviderDefinition

静态定义，不持久化用户数据：

- `id`
- `type`
- `family`
- `displayName`
- `capabilities`
- `iconRef`
- `defaultPollingPolicy`
- `supportsAccountSwitch`
- `supportsHistory`

### B. ProviderSettings

用户可持久化设置：

- enabled
- poll interval policy
- threshold
- source mode
- web mode
- auth references
- relay overrides

### C. ProviderRuntimeState

运行时状态：

- latest snapshot
- latest error
- consecutive failures
- last refresh time
- last success time
- freshness
- active alerts

这样可以避免一个对象在配置、UI、运行时三种语义里来回穿梭。

## 5.2 UsageSnapshot 拆分

建议保留 `UsageSnapshot` 作为统一外观，但减少其字符串逃逸字段的承载职责。

目标形态：

```text
UsageSnapshot
├── summary
│   ├── remaining
│   ├── used
│   ├── limit
│   ├── unit
│   └── status
├── windows: [QuotaWindowSnapshot]
├── account: AccountContext?
├── provenance: SnapshotProvenance
├── diagnostics: SnapshotDiagnostics
└── extensions: [String: String]    // 仅保留为兼容层
```

新增模型：

- `AccountContext`
  - provider account id
  - slot id
  - display label
  - principal key
  - identity key

- `SnapshotProvenance`
  - source label
  - fetched via api/cli/web/local/browser
  - observed at
  - freshness
  - confidence

- `SnapshotDiagnostics`
  - fetch health
  - diagnostic code
  - user-facing note
  - internal debug labels

- `QuotaWindowSnapshot`
  - id
  - title
  - kind
  - used/remaining/limit
  - usedPercent/remainingPercent
  - reset metadata
  - confidence

第一阶段可以不立刻删除 `extras/rawMeta`，而是改为：

- 业务逻辑优先读 typed fields
- 旧路径继续写 `extras/rawMeta`
- 待 UI 和 Presenter 全量迁移后再缩减字典用途

---

## 6. 子系统级重构方案

## 6.1 App 状态中心

### 当前问题

- `AppViewModel` 既像 store，又像 service locator，又像 use case coordinator

### 目标结构

拆成一个顶层 `AppSessionStore` 和多个 feature coordinator：

```text
AppSessionStore
├── providerStore
├── accountStore
├── settingsStore
├── permissionStore
├── updateStore
├── menuBarStore
└── settingsUIStore
```

### 建议拆分对象

- `ProviderStateStore`
  - 管理 provider settings、runtime state、snapshot cache 映射

- `ProviderRefreshCoordinator`
  - 负责刷新计划、退避策略、前后台刷新优先级

- `AccountProfileStoreFacade`
  - 聚合 Codex / Claude profile state

- `AccountSwitchCoordinator`
  - 统一切换事务

- `PermissionCoordinator`
  - 通知、钥匙串、全盘访问的状态刷新与交互

- `UpdateCoordinator`
  - 更新检查、下载、安装缓冲和 release notes

- `SettingsDraftStore`
  - 设置页编辑态，不让 `SettingsView` 自己持有海量字典状态

### 实施要求

- 顶层 app store 只做聚合和路由
- 复杂副作用从 Observable ViewModel 移到 Coordinator / UseCase
- 每个 coordinator 对外暴露尽量小的 API

## 6.2 设置页重构

### 当前问题

- `SettingsView` 承担数据加载、草稿态、校验、提交、弹窗、导航、局部定时器、外观适配
- 现有 `UI/Settings/*.swift` 基本是空壳，名义拆分但没有真实边界

### 目标结构

按 feature 拆分，而不是按“容器名”拆分。

```text
Features/Settings/
├── SettingsRootView
├── SettingsNavigation/
├── Overview/
├── General/
├── MenuBar/
├── Permissions/
├── LocalData/
├── OfficialProviders/
│   ├── OfficialProviderListView
│   ├── OfficialProviderDetailView
│   ├── OfficialProviderEditorViewModel
│   └── OfficialProfileManagement/
├── RelayProviders/
│   ├── RelayProviderListView
│   ├── RelayProviderDetailView
│   ├── RelayProviderEditorViewModel
│   └── RelayDiagnostics/
└── Shared/
    ├── Form controls
    ├── Dialogs
    ├── Tokens
    └── Sections
```

### 状态设计

设置页应改为：

- root store 管导航
- tab-level view model 管 tab 级状态
- provider editor draft 自己维护输入态
- 弹窗改为独立 dialog state

建议用以下状态对象替代海量 `@State [String: T]`：

- `RelayProviderEditorDraft`
- `OfficialProviderEditorDraft`
- `CodexProfileEditorDraft`
- `ClaudeProfileEditorDraft`
- `SettingsDialogState`
- `SettingsSelectionState`

### 迁移顺序

1. 先抽 Dialog state
2. 再抽 Provider editor draft
3. 再抽 tab view model
4. 最后把 `SettingsView` 变成 root composition view

## 6.3 菜单栏与状态栏

### 当前问题

- `StatusBarController` 同时负责 status item、panel、监听器、壁纸亮度缓存、外部点击关闭、定时刷新
- `MenuContentView` 仍承载较多业务推导

### 目标结构

```text
MenuBarFeature
├── MenuBarCoordinator
├── StatusItemController
├── MenuPanelController
├── WallpaperAppearanceService
├── OutsideClickMonitor
├── MenuDashboardViewModel
└── MenuContentView
```

### 建议

- `StatusItemController` 只管状态栏文本/图像输出
- `MenuPanelController` 只管浮层显示、定位、关闭和大小
- `WallpaperAppearanceService` 单独负责壁纸亮度采样与缓存
- `MenuDashboardPresenter` 负责把 runtime state 转成菜单栏展示模型

这样状态栏 UI 不再直接依赖全量 `AppViewModel`

## 6.4 Provider Runtime

### 当前问题

- 官方 Provider 和 Relay Provider 在重复造基础设施
- 抓取、鉴权、刷新、缓存、回退、浏览器凭证获取缺少统一抽象

### 目标结构

```text
Providers/Core/
├── ProviderExecutable
├── ProviderContext
├── ProviderPipeline
├── ProviderErrorClassifier
├── ProviderCache
├── ProviderHTTPClient
├── BrowserCredentialGateway
├── OAuthTokenRefresher
├── SnapshotFallbackPolicy
└── JSONValueReader
```

### 官方 Provider 统一基类能力

提取通用组件：

- `OfficialCredentialLocator`
- `OfficialTokenRefreshService`
- `OfficialSnapshotCache`
- `OfficialWebOverlayService`
- `OfficialSnapshotMerger`

让 `CodexProvider` / `ClaudeProvider` / `KimiOfficialProvider` / `GeminiProvider` 只保留：

- 凭证路径特化
- 接口 endpoint 特化
- 响应解析特化
- overlay 合并策略差异

### Relay 统一能力

提取：

- `RelayAdapterResolver`
- `RelayCredentialResolver`
- `RelayRequestExecutor`
- `RelayResponseExtractor`
- `RelayRecoveryPolicy`
- `RelayChannelComposer`

目标是把 `RelayProvider.swift` 从巨型“平台文件”拆成：

```text
Relay/
├── RelayProvider
├── RelayAccountChannelExecutor
├── RelayTokenChannelExecutor
├── RelayCredentialResolver
├── RelayAdapterResolver
├── RelayResponseInterpreter
├── RelayDiagnosticsBuilder
└── Adapters/
```

## 6.5 配置与持久化

### 当前问题

- `ConfigStore` 很强，但职责已经接近“配置恢复引擎”
- 上层大量 `try? save`，错误上浮断裂

### 目标结构

```text
Infrastructure/Config/
├── AppConfigStore
├── AppConfigMigrationService
├── AppConfigRecoveryService
├── AppConfigRepository
└── ConfigWriteResult
```

### 改造原则

- 读取层继续保留现有容错能力
- 写入层统一返回显式结果
- UI 操作必须知道：
  - 是否保存成功
  - 是否部分成功
  - 是否需要用户重试

### 配套动作

- 清点所有 `try? configurationRepository.save(...)`
- 改为统一入口：
  - `saveSettings(...) -> SaveOutcome`
  - `resetAppData() -> ResetOutcome`
  - `saveProfile(...) -> ProfileSaveOutcome`

## 6.6 账号与切换事务

### 当前问题

- Codex 与 Claude 各自演化，结构相似但没有共用事务框架

### 目标结构

```text
Application/Accounts/
├── AccountProfileRepository
├── AccountSlotRepository
├── AccountSnapshotPrefetcher
├── AccountIdentityMatcher
├── AccountSwitchTransaction
├── AccountSwitchCoordinator
└── Providers/
    ├── CodexAccountAdapter
    └── ClaudeAccountAdapter
```

### 统一事务阶段

- prepare
- capture current state
- write target credentials
- restart/apply
- verify
- finalize
- rollback if possible

### 目标收益

- Codex/Claude 共享切换事务骨架
- 仅保留 provider 特有的 apply / verify 实现
- UI 可以统一展示切换阶段和失败原因

## 6.7 历史用量

### 当前问题

- 读取逻辑已经有基础，但展示态和缓存态仍与设置页耦合

### 目标结构

```text
Application/History/
├── LocalUsageHistoryRepository
├── LocalUsageScanner
├── LocalUsageCacheStore
├── LocalUsageFingerprintService
├── LocalUsageRefreshCoordinator
└── LocalUsageDisplayMapper
```

### 原则

- repository 负责缓存与查询
- scanner 负责 provider-specific 原始读取
- fingerprint 决定是否需要重新扫描
- UI 永远先拿缓存，再异步刷新

## 6.8 权限、更新、系统交互

建议从 `AppViewModel` 中拆出：

- `PermissionCoordinator`
- `LaunchAtLoginCoordinator`
- `AppUpdateCoordinator`
- `PostUpdateReleaseNotesCoordinator`
- `SingleInstanceCoordinator`

其中：

- `RuntimeGuards.swift` 里的单实例和激活桥接属于 bootstrap
- `SettingsWindowController` / `ReleaseNotesWindowController` 属于 app shell
- `AppUpdateService` 继续做 infrastructure service，不直接暴露给 UI
- 更新检查必须保持现有 Release 附件 `latest.json` 流程：应用请求 `/releases/latest/download/latest.json`，发布 workflow 生成并上传同名 manifest；重构只允许移动职责边界，不改变 manifest schema 或更新来源

## 6.9 本地化与设计 Token

当前本地化体系能用，但分散在：

- `Localizer`
- `viewModel.localizedText`
- view 内嵌双语文本

建议改为：

- 统一 `L10nKey`
- 临时双语字符串逐步收口到 `Localizer`
- 设置页视觉 token 从 `SettingsView` 顶部常量拆到：
  - `SettingsTheme`
  - `SettingsSpacing`
  - `SettingsTypography`

---

## 7. 分阶段实施计划

## 7.1 Phase 0：建立护栏

目标：在不改业务行为的前提下，为后续拆分建立安全边界。

### 任务

- 新增常规 CI：
  - `swift build`
  - `swift test`
- 为以下高风险模块补回归测试或快照测试：
  - `AppViewModel` 关键流程
  - `SettingsQuotaPresenter`
  - `StatusBarDisplayRenderer`
  - `CodexProvider`
  - `ClaudeProvider`
  - `RelayProvider`
- 引入基础指标采样：
  - provider refresh latency
  - refresh failure rate
  - settings open latency
  - local usage scan latency
- 记录现有性能基线和能耗基线

### 产出

- PR/Push CI workflow
- 基线测试报告
- 性能基线文档

### 验收

- 所有主分支改动都有自动 build/test
- 能描述当前最慢的 provider 刷新和设置页打开耗时

## 7.2 Phase 1：搭建新骨架

目标：先建目标结构，不迁移所有实现。

### 任务

- 调整 `Package.swift`，拆出基础 target
- 创建新目录与骨架类型
- 先不删除旧实现，用 facade 接旧逻辑
- 建立：
  - `AppSessionStore`
  - `ProviderStateStore`
  - `ProviderRefreshCoordinator`
  - `SettingsDraftStore`
  - `ProviderDefinition`
  - `ProviderSettings`
  - `ProviderRuntimeState`

### 产出

- 新 target 结构可编译
- 旧应用仍可运行

### 验收

- 主程序仍通过所有测试
- 新旧结构可以并存，不阻断开发

## 7.3 Phase 2：抽离 Provider Runtime Core

目标：把共享抓取基础设施从具体 Provider 中剥离。

### 任务

- 抽出统一：
  - HTTP client
  - credential locator
  - OAuth refresher
  - cache/fallback policy
  - browser credential gateway
  - fetch health classifier
- 先迁移官方 Provider 中结构最接近的一组：
  - Codex
  - Claude
  - Kimi Official
  - Gemini

### 产出

- `Providers/Core` 初版
- 官方 Provider 基于新 runtime 跑通

### 验收

- 对外行为不变
- 迁移后的 Provider 文件体积明显下降
- 凭证刷新和缓存回退逻辑集中到公共层

## 7.4 Phase 3：拆 Relay Provider

目标：把第三方中转系统从一个超大文件拆成可维护子系统。

### 任务

- 拆出：
  - adapter resolver
  - token channel executor
  - balance channel executor
  - credential resolver
  - diagnostics builder
  - recovery policy
- 将站点特化逻辑从主流程中移出
- 定义统一的 adapter contract

### 产出

- Relay 子系统目录结构
- 现有内置模板迁移到新 adapter contract

### 验收

- 第三方模板现有测试保持全绿
- `RelayProvider.swift` 不再承担所有职责

## 7.5 Phase 4：拆 AppViewModel

目标：把当前状态中心拆成聚合 store + coordinator 结构。

### 任务

- 新建：
  - `AppSessionStore`
  - `ProviderStateStore`
  - `AccountStore`
  - `UpdateStore`
  - `PermissionStore`
- 把以下逻辑迁出：
  - provider refresh
  - config save/reset
  - account switch
  - permission refresh
  - update flow
- `AppViewModel` 临时保留为 compatibility facade

### 产出

- `AppViewModel` 规模显著下降
- UI 开始依赖 feature store 而不是所有状态全集

### 验收

- `AppViewModel` 从 4000+ 行降到一个可控壳层
- 状态刷新与副作用位置变清晰

## 7.6 Phase 5：重构设置页

目标：把设置页从超大单文件变成 feature 组合。

### 任务

- 抽离对话框状态
- 抽离 provider editor 草稿态
- 抽离 tab 级 view model
- 拆分：
  - Overview
  - General
  - MenuBar
  - Permissions
  - LocalData
  - OfficialProviders
  - RelayProviders
- 提炼 shared section / form controls / token style

### 产出

- 新 settings feature 结构
- 旧 `SettingsView.swift` 仅保留 root composition 或彻底退役

### 验收

- 任一 tab 的逻辑都可在独立文件夹内定位
- 不再依赖几十个散落的 `@State [String: T]`

## 7.7 Phase 6：菜单栏、状态栏与展示层

目标：分离状态栏显示控制与展示推导。

### 任务

- 抽出 `MenuDashboardPresenter`
- 抽出 `StatusItemController`
- 抽出 `MenuPanelController`
- 抽出 `WallpaperAppearanceService`
- 梳理菜单首页信息架构

### 产出

- 菜单栏 feature 独立
- 状态栏逻辑不再与应用总状态深耦合

### 验收

- 状态栏渲染仅消费 display model
- 弹层控制和状态栏控制可以独立测试

## 7.8 Phase 7：清债与优化

目标：完成兼容层收口和工程化完善。

### 任务

- 减少 `extras/rawMeta` 使用范围
- 清理旧 facade 和重复 helper
- 增加能耗/性能 smoke test
- 完善开发文档
- 评估是否继续拆更细 target

### 验收

- 旧大文件退役或显著瘦身
- 新增 Provider 和新设置项有明确接入路径

---

## 8. 测试与验证策略

## 8.1 测试金字塔

- Domain / Presenter：纯单测
- Provider Runtime：协议级测试 + fixture 测试
- Application Coordinator：流程测试
- UI Presentation：重点 presenter / renderer 测试
- App Shell：最小 smoke test

## 8.2 必补测试

- 配置写入失败后的 UI 反馈
- 账号切换事务阶段流转
- Provider fallback 优先级
- Relay adapter 兼容性
- Settings draft 保存/取消/切换 provider
- 菜单栏多 provider 展示模型

## 8.3 回归红线

以下能力不能在重构中退化：

- 官方 Provider 抓取成功率
- 现有账号切换链路
- 设置页保存能力
- 状态栏展示逻辑
- 本地历史用量缓存和读取

---

## 9. 风险与应对

## 9.1 最大风险

- 同时拆状态和 UI，容易造成大面积回归
- 先动 Provider，容易影响线上最核心可用性
- 过早删除 `extras/rawMeta` 会引发隐性展示错误
- 过细切 target 会让迁移初期复杂度反而上升

## 9.2 应对策略

- 先保留兼容 facade，再逐步迁移调用方
- Provider runtime 先迁官方，再迁 relay
- 旧字段先保留，typed model 逐步接管
- target 拆分先粗后细

## 9.3 禁止事项

- 禁止直接重写所有 Provider
- 禁止第一轮同时重构 UI 和业务模型和持久化格式
- 禁止在没有测试护栏时大规模搬动行为逻辑
- 禁止把新架构做成另一套更大的单体

---

## 10. 迭代节奏建议

## 10.1 单人推进建议

如果 1 名工程师主导，建议分 7-10 周推进：

- 第 1 周：Phase 0
- 第 2-3 周：Phase 1
- 第 3-5 周：Phase 2
- 第 5-6 周：Phase 3
- 第 6-7 周：Phase 4
- 第 7-9 周：Phase 5
- 第 9 周：Phase 6
- 第 10 周：Phase 7

## 10.2 小团队并行建议

如果 2-3 名工程师并行：

- A 线：Provider Runtime + Official Providers
- B 线：Settings Feature + Presentation
- C 线：App State / Config / Account Switch / CI

并行前提：

- 先完成 Phase 0 和 Phase 1
- 明确目录 ownership
- 避免多人同时改 `AppViewModel` 同一块旧逻辑

---

## 11. 建议的近期执行顺序

建议按以下顺序开工：

1. 新增 CI workflow
2. 新建 `REFACTOR_PLAN.md` 并冻结重构原则
3. 调整 `Package.swift`，拆基础 target
4. 新建 `AppSessionStore`、`ProviderStateStore`、`ProviderRefreshCoordinator`
5. 把 `AppViewModel` 的 provider refresh 逻辑先迁出
6. 抽 official provider runtime core
7. 迁 Codex / Claude Provider
8. 拆 settings draft state
9. 拆 settings provider editor
10. 再拆剩余 settings tabs 和 relay runtime

---

## 12. 第一批可立即创建的任务清单

### Epic A：工程护栏

- 新增 `ci.yml`
- 为设置页草稿保存和配置失败补测试
- 记录 provider refresh 和 settings open 基线

### Epic B：架构骨架

- 拆 SwiftPM target
- 创建 `Domain` / `Application` / `Infrastructure` / `Presentation` / `Features`
- 引入 `AppSessionStore`

### Epic C：Provider Runtime

- 建立 `ProviderHTTPClient`
- 建立 `OAuthTokenRefresher`
- 建立 `BrowserCredentialGateway`
- 建立 `SnapshotFallbackPolicy`

### Epic D：状态拆分

- `ProviderStateStore`
- `UpdateStore`
- `PermissionStore`
- `AccountStore`

### Epic E：设置页拆分

- `SettingsNavigationState`
- `SettingsDialogState`
- `OfficialProviderEditorDraft`
- `RelayProviderEditorDraft`

---

## 13. 最终验收标准

重构完成后，应达到以下状态：

- `AppViewModel` 不再是超大单体
- `SettingsView` 不再承载核心业务规则和海量输入态
- 新增一个官方 Provider，不需要复制一整套 OAuth/缓存/回退基础设施
- 新增一个 Relay 模板，不需要修改巨型主流程文件
- 所有关键持久化写入都能返回明确结果
- 菜单栏和设置页只消费展示模型，不直接拼复杂业务规则
- 项目有常规 CI，不只在 release 时验证
- 能明确说清每个模块“负责什么，不负责什么”

---

## 14. 结论

这个项目不应该推倒重写，应该基于现有测试和功能资产做分层重构。

最关键的不是“换一套漂亮结构”，而是先把四个核心结点拆掉：

- `AppViewModel`
- `SettingsView`
- 官方 Provider 重复基础设施
- `RelayProvider` 巨型主流程

只要这四个点拆开，后续无论是继续做菜单栏优化、浏览器桥接、NewAPI 账本、后台刷新还是多账号体验，都能在更低风险下推进。
