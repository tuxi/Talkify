# Talkify iOS 交互架构设计

> 版本: v1.0 | 日期: 2026-07-21 | 状态: 设计中

## 1. 产品定位

Talkify iOS 的定位是**工作区优先的 Agent 终端**，与 ChatGPT 等通用聊天应用的核心差异：

| 维度 | ChatGPT iOS | Talkify iOS |
|------|------------|-------------|
| 对话模型 | 聊天记录 | 工作区操作记录 |
| 文件角色 | 消息附件 | 一等公民，agent 直接操作 |
| 侧栏职责 | 历史会话列表 | 工作区控制中心 |
| Inspector | 无 | 工具调用/文件变更详情面板 |
| 会话模式 | 单一模式 | 工作区对话 + 自由聊天 |

## 2. 整体架构

### 2.1 层级结构

```
ChatRootViewController (UIKit 抽屉容器，帧动画)
│
├── WorkspaceHubViewController (抽屉面板，320pt 宽)
│   ├── WorkspaceHeader          工作区选择器 + 状态指示
│   ├── QuickFileList            最近变更 + 已固定文件 (≤ 20 条)
│   ├── ConversationListView     会话列表 (来自 AgentKit)
│   ├── GlobalSearchView         搜索会话 + 文件名 + 代码片段
│   └── BottomBar                [新对话] [设置]
│
├── ChatViewController (主内容区，可滑动)
│   ├── ConversationDetailView   对话详情 (来自 AgentKit)
│   │   ├── 消息流
│   │   ├── FileChangeCard       文件变更卡片 (FileViewerKit)
│   │   └── ToolCallCard         工具调用卡片 → Inspector
│   ├── Inspector toggle         NavBar 右侧按钮 → InspectorSheet
│   └── FilePreview              全屏文件预览 (FileViewerKit)
│
├── WorkspaceBrowser (全屏，NavigationStack 驱动)
│   ├── Level 1: 所有工作区列表
│   └── Level 2: 工作区详情 (对话列表 + 文件树)
│
└── 模态层
    ├── InspectorSheetView       bottom sheet, NavigationStack 导航
    ├── FilePreviewSheet         fullScreenCover (FileViewerKit)
    ├── SettingsView             sheet
    └── FreeChatView             fullScreenCover (独立于工作区)
```

### 2.2 Package 依赖关系

```
                    ┌─────────────┐
                    │   AgentKit  │  (外部 SDK)
                    │ Workspace   │
                    │ Store,      │
                    │ Inspector,  │
                    │ Router      │
                    └──────┬──────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
    ┌─────────▼──┐  ┌─────▼──────┐  ┌──▼───────────┐
    │  CoreKit   │  │ DesignKit  │  │ FileViewerKit │
    │  网络/认证  │  │ UI 组件库   │  │ 文件树/预览    │
    │  存储/OSS  │  │ 按钮/卡片   │  │ diff/卡片      │
    └─────────┬──┘  └─────┬──────┘  └──┬───────────┘
              │            │            │
              └────────────┼────────────┘
                           │
                    ┌──────▼──────┐
                    │   Talkify   │
                    │   宿主 App   │
                    │   桥接层     │
                    │   (所有      │
                    │   Package    │
                    │   的胶水层)  │
                    └─────────────┘
```

**关键设计原则：**
- `FileViewerKit` 不依赖 `AgentKit`，通过协议接收数据
- `FileViewerKit` 依赖 `DesignKit`，复用 UI 原子组件
- Talkify 作为胶水层，负责 `AgentKit 数据 → 协议适配 → FileViewerKit`

## 3. 交互流程

### 3.1 默认状态：Chat 主屏，Drawer 关闭

```
┌─────────────────────────────────────────┐
│ [☰]  ConversationTitle        [🔍] [⋯] │  NavBar
│─────────────────────────────────────────│
│                                         │
│          ConversationDetailView          │
│  ┌─────────────────────────────────────┐│
│  │ 用户: 帮我重构 UserProfile           ││
│  ├─────────────────────────────────────┤│
│  │ Agent: 好的，我来分析...             ││
│  │                                     ││
│  │ ┌─────────────────────────────────┐ ││
│  │ │ 📄 UserProfile.swift  +12 -3   │ ││  FileChangeCard
│  │ │ [展开查看变更] [预览文件]        │ ││  (FileViewerKit)
│  │ └─────────────────────────────────┘ ││
│  │                                     ││
│  │ ┌─────────────────────────────────┐ ││
│  │ │ 🔧 read_file                    │ ││  ToolCallCard
│  │ │ [查看结果] [Inspector]          │ ││  → InspectorSheet
│  │ └─────────────────────────────────┘ ││
│  └─────────────────────────────────────┘│
│                                         │
│ ┌─────────────────────────────────────┐ │
│ │ 输入区域                             │ │
│ └─────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

**触发动作：**

| 动作 | 结果 |
|------|------|
| [☰] 或右滑手势 | 打开 Drawer |
| 点击 FileChangeCard | 打开 FilePreview (fullScreenCover) |
| 点击 ToolCallCard 的 [Inspector] | 打开 InspectorSheet (bottom sheet) |
| NavBar [🔍] | 打开 InspectorSheet |
| 点击遮罩或左滑 | 关闭 Drawer |
| 点选抽屉中的会话 | store.select + 关闭 Drawer |

### 3.2 Drawer 打开状态

```
│← Chat 右移 320pt →│
┌──────────────┐ ┌─────────────────────────┐
│ WorkspaceHub │ │ Chat (dimmed + masked)  │
│──────────────│ │                         │
│ my-ios-proj › │ │  半透明遮罩覆盖          │
│ 3变更·2活跃   │ │  点击遮罩 → 关闭        │
│──────────────│ │                         │
│[💬][📄][🔍]  │ │                         │
│──────────────│ │                         │
│ 会话列表      │ │                         │
│ ┌──────────┐ │ │                         │
│ │🟢 重构..│ │ │                         │
│ │🟡 修复..│ │ │                         │
│ │⚪ 添加..│ │ │                         │
│ └──────────┘ │ │                         │
│──────────────│ │                         │
│[💬新对话][⚙️]│ │                         │
└──────────────┘ └─────────────────────────┘
```

**Drawer 动作：**

| 动作 | 结果 |
|------|------|
| Header 右侧 [›] | push WorkspaceBrowser (全屏，Level 1) |
| 点击会话行 | 选中会话 + 关闭 Drawer |
| Tab [💬 会话] | ConversationListView（AgentKit 完整功能） |
| Tab [📄 快捷文件] | QuickFileList（最近变更 + 已固定） |
| Tab [🔍 搜索] | GlobalSearchView |
| BottomBar [💬 新对话] | beginDraft() + 关闭 Drawer |
| BottomBar [⚙️ 设置] | SettingsView sheet |

### 3.3 Drawer — 快捷文件 Tab

```
┌──────────────┐
│ my-ios-proj › │
│──────────────│
│[💬][📄][🔍]  │
│──────────────│
│              │
│ 📁 最近变更   │  ← agent 操作过的文件 (≤ 10 条)
│ ┌──────────┐ │
│ │🟡 User..│ │  ← 2分钟前修改
│ │🟢 AppD..│ │  ← 5分钟前新增
│ │⚪ Setti..│ │  ← 昨天修改
│ └──────────┘ │
│              │
│ 📁 已固定     │  ← 用户手动固定 (≤ 10 条)
│ ┌──────────┐ │
│ │📄 Pack..│ │
│ │📄 README│ │
│ └──────────┘ │
│              │
│ [查看全部 47 个文件 →] │  → WorkspaceBrowser Level 2
│──────────────│
│[💬新对话][⚙️]│
└──────────────┘
```

**设计理由：不在 Drawer 中放置完整文件树。**
- 性能：Drawer 频繁开关，大目录树的数据构建和状态管理有开销
- 交互：320pt 宽的空间不足以展示深层嵌套的目录树
- 职责：Drawer 专注"快速访问"，WorkspaceBrowser 专注"沉浸浏览"

### 3.4 WorkspaceBrowser (全屏浏览器)

**入口：** Drawer Header 右侧 [›]，或快捷文件 Tab 的 [查看全部文件 →]

```
LEVEL 1: 所有工作区列表                       LEVEL 2: 工作区详情
┌──────────────────────────┐      ┌──────────────────────────┐
│ ← 返回       工作区       │      │ ← 返回   my-ios-project  │
│──────────────────────────│      │──────────────────────────│
│ 🔍 搜索工作区...          │      │                          │
│──────────────────────────│      │ ┌──────────────────────┐ │
│                          │      │ │ 💬 13 条对话       › │ │
│ 📁 my-ios-project     ›  │ ───→ │ └──────────────────────┘ │
│   13对话 · 47文件         │      │                          │
│   agent活跃: 2分钟前      │      │ ┌──────────────────────┐ │
│                          │      │ │ 📁 Sources           │ │
│ 📁 backend-service    ›  │      │ │   📁 Talkify         │ │
│   5对话 · 23文件          │      │ │     📁 TalkifyIOS    │ │
│   4个未提交变更           │      │ │       📄 Drawer...   │ │
│                          │      │ │       📄 ChatView... │ │
│ 📁 design-docs        ›  │      │ │   📁 Packages        │ │
│                          │      │ │ 📁 Resources         │ │
│ + 创建新工作区            │      │ │ 📄 README.md         │ │
│                          │      │ └──────────────────────┘ │
└──────────────────────────┘      └──────────────────────────┘
```

**性能策略：**
- 文件树使用 `OutlineGroup` + 懒加载子节点
- 目录默认折叠，展开时才加载子内容
- 超过 50 个文件的目录自动折叠 + "显示全部 (N)" 按钮
- 文件列表使用 SwiftUI `List`（自带 cell 复用）
- 后台线程构建节点树，主线程只做 UI 更新

### 3.5 InspectorSheet (bottom sheet)

```
LEVEL 1: Tool 详情                           LEVEL 2: Tool 结果
┌──────────────────────────┐      ┌──────────────────────────┐
│          ═══             │      │ ← 返回    Tool Result    │
│                          │      │                          │
│ 🔧 read_file             │      │ ┌──────────────────────┐ │
│ ──────────────────────── │      │ │ // UserProfile.swift │ │
│ 参数:                     │      │ │                      │ │
│   path: UserProfile.swift│      │ │ struct UserProfile   │ │
│                           │ ───→ │ │   : Codable {       │ │
│ 状态: ✅ 成功              │      │ │   let id: String    │ │
│ 耗时: 234ms               │      │ │   ...               │ │
│                           │      │ └──────────────────────┘ │
│ 结果:                      │      │                          │
│ ┌───────────────────────┐ │      │ [📋 复制] [📄 查看文件]  │
│ │ (前 200 字符预览...)   │ │      │                          │
│ └───────────────────────┘ │      │                          │
│                           │      │                          │
│ [查看完整结果 →]          │      │                          │
└──────────────────────────┘      └──────────────────────────┘
```

**关键设计：NavigationStack 驱动，支持 push/pop。**
- Sheet detents: `.medium` (tool 摘要) / `.large` (tool 详情)
- 从 tool 详情可 push 到 tool 结果、文件预览、agent 状态等
- 返回由 NavigationStack 自动处理
- 复用 AgentKit 的 `InspectorView` + `InspectorSelection`，不破坏现有 API

### 3.6 FilePreview (全屏文件预览)

```
┌──────────────────────────────────────────┐
│ ← 返回          UserProfile.swift        │
│──────────────────────────────────────────│
│                                          │
│  import Foundation                       │
│  import CoreKit                          │
│                                          │
│  struct UserProfile: Codable {           │
│      let id: String                      │
│  +   let displayName: String             │  ← 绿色高亮 (新增)
│  +   let avatarURL: URL?                 │
│      let email: String                   │
│  -   let username: String                │  ← 红色高亮 (删除)
│  }                                       │
│                                          │
└──────────────────────────────────────────┘

NavBar 右侧: [📋 复制] [📤 分享] [🔄 查看原始文件]
```

### 3.7 自由聊天模式 (非工作区)

```
┌──────────────────────────┐
│ ← 关闭    自由聊天        │
│──────────────────────────│
│                          │
│  ConversationDetailView   │
│  (无 workspace context)   │
│  (无文件系统 tools)        │
│  (可选保存为临时会话)      │
│                          │
└──────────────────────────┘
```

**入口：** 工作区选择器底部，或 WorkspaceBrowser 的"自由聊天"入口。
**依赖：** 需要 runtime 支持 `FreeSession` 类型（区别于 `WorkspaceSession`）。

## 4. WorkspaceHubViewController 设计

### 4.1 从 DrawerViewController 的演化

| 属性 | DrawerViewController (旧) | WorkspaceHubViewController (新) |
|------|--------------------------|-------------------------------|
| 内容 | `ConversationListView` 单一视图 | Tab 切换: 会话 / 快捷文件 / 搜索 |
| Header | 无 | 工作区选择器 + mini status |
| 工作区感知 | 只有当前工作区 | 可切换 + 可跳转 WorkspaceBrowser |
| 文件访问 | 无 | QuickFileList + 入口到全屏浏览器 |
| BottomBar | [聊天] [设置] | [新对话] [设置] |

### 4.2 Tab 定义

```swift
enum WorkspaceHubTab: String, CaseIterable {
    case conversations   // 会话列表 (AgentKit ConversationListView)
    case quickFiles      // 快捷文件 (最近变更 + 已固定)
    case search          // 全局搜索
}
```

### 4.3 WorkspaceHeader

显示内容：
- 当前工作区名称（可自定义）
- Mini status（未提交变更数、agent 活跃状态）
- 右侧 [›] → push WorkspaceBrowser

### 4.4 QuickFileList

显示内容：
- **最近变更**：agent 最近操作过的文件，按时间倒序，≤ 10 条
- **已固定**：用户手动固定的常用文件，≤ 10 条
- **入口**：[查看全部 N 个文件 →] 跳转 WorkspaceBrowser

文件行交互：
- 点击 → 关闭 Drawer + 打开 FilePreview (fullScreenCover)
- 左滑 → [取消固定] [预览]
- 长按 → Context Menu: [预览] [添加到对话] [查看 diff] [定位到文件夹]

## 5. 实施优先级

### P0 — 骨架搭建
- [ ] `WorkspaceHubViewController` Tab 结构 + WorkspaceHeader
- [ ] `WorkspaceBrowser` 两级导航视图
- [ ] `FileViewerKit` Package 创建 + 核心协议定义
- [ ] `InspectorNavigationView` 组件交付

### P1 — 核心功能
- [ ] Talkify 桥接层: `WorkspaceFileContentProvider`
- [ ] `FileChangeCard` 集成到消息流
- [ ] InspectorSheet 在 iOS 上的触发 + Sheet 容器
- [ ] FilePreview 全屏预览（Code + Image + Video）

### P2 — 增强体验
- [ ] `DiffView` 并排对比 + 语法高亮
- [ ] 自由聊天模式 (需 runtime 配合)
- [ ] 工作区 mini status 实时更新

### P3 — 生态集成
- [ ] GlobalSearchView 跨会话 + 文件内容搜索
- [ ] Widget 桌面小组件
- [ ] Spotlight 集成 (`CSUserActivity` + `CoreSpotlight`)
- [ ] Share Extension (从其他 app 分享内容到工作区)

## 6. 相关文档

- [`file-viewer-kit-spec.md`](./file-viewer-kit-spec.md) — FileViewerKit 需求规格
- [`inspector-navigation-spec.md`](./inspector-navigation-spec.md) — InspectorNavigationView 需求规格
