## Summary

把“查看项目（ProjectDetailView）”页面从当前“手算高度 + 全局忽略安全区”的布局，改为 SwiftUI 正常布局（safe area inset / overlay），解决内容溢出屏幕、界面显得乱的问题；同时保持现有“胶片卡片 + 拨动时间轴”的交互质感不变，并确保照片始终居中。

## Current State Analysis

### 入口与当前形态

- 查看项目页入口来自 [ProjectListView.swift](file:///Users/emma1wu/Desktop/app%20onepic/OnePic/OnePic/ProjectListView.swift#L145-L152) 的 `.navigationDestination`，展示 [ProjectDetailView.swift](file:///Users/emma1wu/Desktop/app%20onepic/OnePic/OnePic/ProjectDetailView.swift)。
- iOS 实际 UI 在同一文件内的 `FilmProjectDetailView`（[ProjectDetailView.swift:L60-L349](file:///Users/emma1wu/Desktop/app%20onepic/OnePic/OnePic/ProjectDetailView.swift#L60-L349)）。
- 当前结构是：背景 + `VStack` 顶部栏 + 中间胶片区域（`photoContent`）+ 底部信息条（在 `photoContent` 内渲染）。

### 溢出屏幕的根因（可复现、与机型/字体有关）

- `photoContent` 通过“估算 topBar/bottomBar 高度”去手算 `contentH`（[ProjectDetailView.swift:L240-L276](file:///Users/emma1wu/Desktop/app%20onepic/OnePic/OnePic/ProjectDetailView.swift#L240-L276)）：
  - `topBarH`、`bottomBarH` 是固定常量 + `safeAreaInsets`。
  - 但真实 `topBar` / `bottomInfoBar` 的高度会受 padding、字体、Material 渲染影响，往往比估算值更大。
  - 结果：中间内容用 `contentH` 占满“估算剩余高度”，底部栏再追加，整页高度超过屏幕 → 出现超出可视范围、视觉混乱。
- `FilmProjectDetailView` 整体 `.ignoresSafeArea()`（[ProjectDetailView.swift:L114](file:///Users/emma1wu/Desktop/app%20onepic/OnePic/OnePic/ProjectDetailView.swift#L114)），同时又到处用 `geo.safeAreaInsets` 做 padding；在不同机型/方向/动态字体下更容易出现“安全区重复/口径偏差”，放大溢出风险。

### 用户本次确认的目标与约束

- 继续保留“胶片卡片 + 左侧胶片条 + 拨动时间轴”的交互质感。
- 移除查看项目页右上角相机按钮（界面更干净；拍照入口保留在项目列表）。
- 需要同时兼容小屏 + 大字体，任何情况下不溢出屏幕；照片保持居中。

## Proposed Changes

### 1) 改造整体布局：背景全屏，内容遵循安全区

目标：不再用全局 `.ignoresSafeArea()`，只让背景忽略安全区；顶部/底部条使用系统“inset/overlay”固定到边缘，中间内容自然占据剩余空间。

具体修改（文件：ProjectDetailView.swift）

- 在 `FilmProjectDetailView.body`（[ProjectDetailView.swift:L80-L148](file:///Users/emma1wu/Desktop/app%20onepic/OnePic/OnePic/ProjectDetailView.swift#L80-L148)）中：
  - 把 `.ignoresSafeArea()` 从整个视图移除。
  - 将 `DynamicPhotoBackground(...)` 明确加 `.ignoresSafeArea()`，只让背景铺满。
  - 使用 `.safeAreaInset(edge: .top)` 放置 `topBar`，使用 `.safeAreaInset(edge: .bottom)` 放置 `bottomInfoBar`。
  - 中间内容区域用 `.frame(maxWidth: .infinity, maxHeight: .infinity)` 让其自然填充“inset 之后剩余空间”，避免手算高度。

预期效果：

- 顶部栏/底部栏永远在屏幕内，不会把中间内容挤出屏幕。
- 不依赖“魔法数字”，动态字体与小屏更稳定。

### 2) 拆分中间区域：用“中间 GeometryReader”计算 9:16，但只基于真实可用空间

目标：保留现有胶片 UI（左 strip + 右卡片），保留 9:16 适配逻辑，但不再扣 top/bottom 估算高度。

具体修改（文件：ProjectDetailView.swift）

- 重写 `photoContent(geo:)`（[ProjectDetailView.swift:L240-L276](file:///Users/emma1wu/Desktop/app%20onepic/OnePic/OnePic/ProjectDetailView.swift#L240-L276)）：
  - 移除 `topBarH`、`bottomBarH`、`contentH` 的整屏手算逻辑。
  - 让 `photoContent` 本身成为“中间区域容器”，内部包一层 `GeometryReader`（或将其提取为 `filmArea`），用该 geometry 的 `size` 作为真实可用宽高：
    - `stripW` 维持原值（72）以保证时间轴质感不变。
    - `photoW/photoH` 仍按 9:16 约束计算，但以“中间区域 size.height”作为最大高度来源。
  - `StackedCardStrip` 与 `mainPhotoArea` 保持原手势（`filmDragGesture`）与 `FilmScrollPhysics`，不改滚动算法，只改 frame 约束来源。
  - 在 `mainPhotoArea` 外层使用 `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)` 确保照片卡片始终居中。

预期效果：

- 中间胶片区域永远只占用 inset 后剩余空间，不会发生下方溢出。
- 照片居中稳定，拨动时间轴质感与速度/阻尼不变。

### 3) 将 bottomInfoBar 移出 photoContent，避免重复 padding/高度叠加

目标：底部信息条是“固定底部工具条”，不应该参与中间高度计算。

具体修改（文件：ProjectDetailView.swift）

- 从 `photoContent` 移除 `bottomInfoBar` 的渲染（目前在 [ProjectDetailView.swift:L272-L275](file:///Users/emma1wu/Desktop/app%20onepic/OnePic/OnePic/ProjectDetailView.swift#L272-L275)）。
- 改为在 `FilmProjectDetailView.body` 外层通过 `.safeAreaInset(edge: .bottom)` 放置 `bottomInfoBar`，padding 统一放在 inset 的 content 中。
- 保持底部条内的 `lineLimit(1)` / `minimumScaleFactor` 逻辑（已存在：[ProjectDetailView.swift:L207-L216](file:///Users/emma1wu/Desktop/app%20onepic/OnePic/OnePic/ProjectDetailView.swift#L207-L216)），避免大字体导致换行推高高度。

### 4) 顶部栏移除相机入口，减少干扰

目标：查看项目页更聚焦浏览/编辑；拍照从项目列表进入。

具体修改（文件：ProjectDetailView.swift）

- 在 `topBar`（[ProjectDetailView.swift:L150-L185](file:///Users/emma1wu/Desktop/app%20onepic/OnePic/OnePic/ProjectDetailView.swift#L150-L185)）中移除：
  - `NavigationLink(destination: CameraCaptureView(project: project)) { ... }`
- 顶部栏右侧保留留白（Spacer 已存在），整体高度与视觉更稳定。

## Assumptions & Decisions

- 本次仅解决“查看项目页溢出屏幕/布局混乱”的问题，不做“苹果相册时间轴布局 / 生成视频 / 设置页”等大改（这些属于你之前更大的优化清单，可另起计划）。
- 保留现有胶片交互：左侧条 + 右侧大卡片 + 拖动切换；不修改 `FilmScrollPhysics` 参数，避免质感变化。
- 只在 iOS 生效（当前文件已用 `#if os(iOS)` 包裹），macOS 继续显示占位文本。

## Verification Steps

- 小屏验证：在 iPhone SE / iPhone mini 模拟器打开任意项目的查看页，确认顶部栏、中间区域、底部条都完全在屏幕内，无任何内容被裁切或推到屏幕外。
- 大字体验证：把系统字体调到 “Accessibility Large” 级别，再进入查看页，确认不溢出；顶部标题保持单行并可缩放/截断合理，底部信息条仍为单行。
- 交互回归：拖动左侧胶片条/在主卡片区域拖动，切换照片的触感、惯性、选中反馈与现在一致；照片卡片始终保持居中。
- 空状态：项目无照片时，`EmptyFilmState` 仍居中显示且不被顶部/底部遮挡。

