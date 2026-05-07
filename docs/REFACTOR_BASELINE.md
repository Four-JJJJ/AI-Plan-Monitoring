# AIPlanMonitor Refactor Baseline

更新时间：2026-05-07

本文档记录 `oh-myusage` 重构工作区的工程起点，用于后续重构过程中核对行为、验证工程护栏，并标记哪些基线已经真实验证过。

## Workspace 基线

- 工作目录：`/Users/homelab/Desktop/Vibe Coding/oh-myusage`
- Git 分支：`oh-myusage`
- 基线提交：`5d4d1b6 docs: add refactor plan`
- 旧目录保留：`/Users/homelab/Desktop/Vibe Coding/AI余额监控`

## 当前工程护栏

- 新增常规 CI：`.github/workflows/ci.yml`
- 现有发布流程保留：`.github/workflows/release.yml`
- 当前仍以单一可执行 target 承载旧实现，但已补出新的目标架构骨架：
  - `AIPlanMonitorDomain`
  - `AIPlanMonitorInfrastructure`
  - `AIPlanMonitorProviders`
  - `AIPlanMonitorApplication`
  - `AIPlanMonitorPresentation`
  - `AIPlanMonitorFeatures`
  - `AIPlanMonitorBootstrap`

## 已验证命令

以下结果来自 `oh-myusage` 工作区的真实执行：

- `swift build`
  - 结果：通过
  - 参考耗时：约 47 秒（冷构建）
- `swift test`
  - 结果：通过
  - 参考结果：466 tests, 0 failures
  - 参考耗时：约 9.5 秒测试构建 + 6.1 秒测试执行

## 当前可确认的系统事实

- 当前代码仍主要集中在：
  - `Sources/AIPlanMonitor/App`
  - `Sources/AIPlanMonitor/Providers`
  - `Sources/AIPlanMonitor/Services`
  - `Sources/AIPlanMonitor/UI`
- `AppViewModel.swift` 和 `SettingsView.swift` 仍是主要复杂度中心
- 仓库当前已有发布 workflow，但在本次修改前没有常规 push/PR CI

## 尚未完成的基线能力

以下指标在当前阶段还没有代码级 instrumentation，只能作为下一步工作项：

- provider refresh latency
- settings open latency
- local usage scan latency
- provider failure-rate summary
- 菜单栏运行时资源消耗采样

## 下一步顺序

按当前方案，后续继续按以下顺序推进：

1. 保持 CI 绿线
2. 在新 target 骨架上逐步迁出公共模型和服务
3. 优先拆 `AppViewModel` 的刷新调度与状态聚合
4. 再拆 Provider Runtime
5. 最后拆设置页和菜单栏 Feature
