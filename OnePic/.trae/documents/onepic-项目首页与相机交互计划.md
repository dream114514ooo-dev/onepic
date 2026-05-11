## Summary
把 onepic 的启动首屏改为“项目列表”，并完善相机页交互：支持前后摄像头翻转自拍；拍照只保存到应用内；相机右上角提供 Ghost 叠加设置（开关/选哪张/需要时才弹出透明度滑杆）；相机左上角提供返回。

## Current State Analysis
### 入口与导航
- 当前启动后直接进入相机页：`ContentView` 在拿到 `selectedProject` 后直接展示 `CameraCaptureView(project:)`。[ContentView.swift](file:///Users/emma1wu/Desktop/app%20onepic/OnePic/OnePic/ContentView.swift#L21-L33)
- 目前的“项目选择”以 sheet 方式存在，并不是首屏项目列表。[ProjectPickerView.swift](file:///Users/emma1wu/Desktop/app%20onepic/OnePic/OnePic/ProjectPickerView.swift)

### 相机与保存
- 相机当前只配置后摄（`.back`），不支持前后翻转。[CameraController.swift](file:///Users/emma1wu/Desktop/app%20onepic/OnePic/OnePic/CameraController.swift#L26-L49)
- 拍照后会：
  - 写入日期水印并落盘到 Documents/Projects/...（应用内存储）[CameraCaptureView.swift](file:///Users/emma1wu/Desktop/app%20onepic/OnePic/OnePic/CameraCaptureView.swift#L180-L209)
  - 但同时还会保存到系统相册（不符合“只保存在应用内”）[CameraCaptureView.swift](file:///Users/emma1wu/Desktop/app%20onepic/OnePic/OnePic/CameraCaptureView.swift#L210-L241)

### Ghost 叠加
- 目前 Ghost 图片固定取该项目最新一张照片（`photos.first`），并在界面底部显示透明度滑杆。[CameraCaptureView.swift](file:///Users/emma1wu/Desktop/app%20onepic/OnePic/OnePic/CameraCaptureView.swift#L85-L94)
- 用户需求改为：右上角按钮进入设置：①需要时再弹透明度滑杆并“完成自动关闭”；②开关；③选哪张。

### 数据模型
- SwiftData 模型：`Project` + `Photo`。[Project.swift](file:///Users/emma1wu/Desktop/app%20onepic/OnePic/OnePic/Project.swift)、[Photo.swift](file:///Users/emma1wu/Desktop/app%20onepic/OnePic/OnePic/Photo.swift)
- `Photo` 里已存在 `projectID` 用于 Query 过滤。[Photo.swift](file:///Users/emma1wu/Desktop/app%20onepic/OnePic/OnePic/Photo.swift#L5-L28)

## Goal & Success Criteria
- App 启动首屏是“项目列表”（白底、简约 Apple 风格，可用玻璃材质）。
- 点击某个 Project 行：弹出底部操作面板（至少包含“拍照”“查看项目”）。
- 进入相机页：
  - 左上角有返回按钮可回到项目列表。
  - 必须支持前后摄像头翻转（自拍）。
  - 拍照后自动保存到应用内（本地落盘 + SwiftData 记录），不写入系统相册、不请求相册写入权限。
  - 右上角 Ghost 按钮：能开/关叠加；能选择叠加哪一张（同项目内照片）；需要调整透明度时才弹出滑杆，点击完成自动关闭。

## Proposed Changes
### 1) 新增首屏 ProjectListView（项目列表页）
**新增文件**
- `ProjectListView.swift`
  - `@Query` 拉取所有 `Project`（按 `lastOpenedAt` 倒序）。
  - List/卡片样式：白底，行背景使用 `.ultraThinMaterial` 做玻璃质感。
  - 行点击触发 `confirmationDialog`（底部弹层）：`拍照` / `查看项目` / 取消。
  - 顶部工具栏加 `+` 创建项目（VIP stub 逻辑沿用 `VIP.isVIP`/`VIP.maxFreeProjects`）。

**导航行为**
- `拍照`：push 到 `CameraCaptureView(project:)`
- `查看项目`：push 到 `ProjectDetailView(project:)`（见第 2 点）

### 2) 新增 ProjectDetailView（查看项目）
**新增文件**
- `ProjectDetailView.swift`
  - 展示该项目的照片（最小可行：grid 或 list，按 `shotAt` 倒序）。
  - 提供一个明显的“拍照”按钮（进入 `CameraCaptureView(project:)`）。
  - 后续 timeline/flipbook 会在下一阶段再加，这里先确保“可查看”不空。

### 3) 调整 ContentView：首屏为项目列表
**修改文件**
- `ContentView.swift`
  - 去掉启动直接进相机的逻辑，改为展示 `ProjectListView()` 作为根。
  - 保留现有 bootstrap（首次创建 Project 1）能力，但把它迁移到 `ProjectListView` 或抽成 `ProjectBootstrapper`（保持实现简单、避免白屏）。

### 4) 相机页：支持自拍翻转 + 不保存到相册 + 顶栏交互
**修改文件**
- `CameraController.swift`
  - 增加状态：当前摄像头位置（front/back）。
  - 增加方法：`toggleCamera()`，在 `sessionQueue` 内移除现有 input，换成另一侧 camera input，并保持 `photoOutput` 不变。
  - `configureIfNeeded()` 初始用后摄，用户点击后可切到前摄。

- `CameraCaptureView.swift`
  - 顶部左侧：自定义返回按钮（`dismiss()`），满足“左上角回退”。
  - 顶部右侧：两个按钮
    - Ghost 设置按钮（右上角主要按钮）
    - 翻转自拍按钮（例如 `arrow.triangle.2.circlepath.camera`）
  - 删除保存到系统相册的逻辑：移除 `Photos` 依赖、移除 `saveToPhotoLibrary` 调用与权限申请。
  - 保持拍照落盘 + SwiftData 记录 + streak 更新不变。

### 5) Ghost 设置：开关/选哪张/透明度滑杆（按需弹出）
**数据层（Project 存储）**
- `Project.swift` 新增字段（持久化到 SwiftData）：
  - `ghostEnabled: Bool`（默认 false）
  - `ghostOpacity: Double`（默认 0.4）
  - `ghostPhotoID: UUID?`（用户选择的叠加照片；为空表示“用最新一张”）

**UI 层**
- 新增 `GhostSettingsView.swift`（sheet）
  - Section 1：开关（Toggle）
  - Section 2：选择叠加照片
    - “无 / 关闭叠加”
    - “使用最新一张”
    - 最近若干张照片缩略图列表（从磁盘加载缩略图；必要时做简单缓存）
  - Section 3：调整透明度
    - 点击“调整透明度” -> 弹出一个小的 slider 面板（`.sheet`）
    - slider 调整 `project.ghostOpacity`
    - 点击“完成”自动关闭该 slider 面板（符合你的规则）

**相机叠加行为**
- 若 `ghostEnabled == false`：不显示叠加。
- 若 `ghostEnabled == true`：
  - 若 `ghostPhotoID` 有值：加载对应 Photo 的 `relativePath`。
  - 若 `ghostPhotoID == nil`：默认加载该项目最新一张 Photo（如果存在）。
- 叠加透明度使用 `project.ghostOpacity`。

### 6) 权限与 Info.plist 清理
**修改文件**
- `Info.plist`
  - 保留 `NSCameraUsageDescription`
  - 移除 `NSPhotoLibraryAddUsageDescription`（拍照不再写相册）
  - 备注：后续做导出 MP4 保存到相册时再加回来

## Assumptions & Decisions
- “查看项目”阶段 1 先做照片 grid/list（可滚动），不做 flipbook/时间线动画（那些是下一阶段的 timeline 功能）。
- Ghost 默认关闭；用户在相机右上角开启后才叠加。
- 模拟器依旧不支持真实相机采集：相机页在 Simulator 给出提示文案；真机可用。

## Verification Steps
- Simulator：
  - 启动首屏显示项目列表，点项目弹出操作面板。
  - 选择“查看项目”能看到应用内照片列表（首次为空也能正常显示）。
  - 选择“拍照”能进入相机页；Simulator 显示提示文案（不黑屏/不白屏卡死）。
- 真机：
  - 首屏项目列表 -> 选择项目 -> 拍照进入相机。
  - 翻转自拍可在前后摄之间切换。
  - 拍照后照片只出现在应用内的“查看项目”，不会出现在系统相册。
  - Ghost 设置可开关、可选照片、可调整透明度并“完成自动关闭滑杆”。
