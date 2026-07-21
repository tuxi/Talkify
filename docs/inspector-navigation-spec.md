# InspectorNavigationView 需求规格

> 版本: v1.1 | 日期: 2026-07-21 | 状态: 待开发  
> 目标：为 iOS 和 macOS 提供带 NavigationStack 的 Inspector 容器，替代平铺切换模式

## 1. 背景

### 1.1 现有问题

当前 `InspectorView`（来自 AgentKit）在 macOS 上作为 `NavigationSplitView` 的第三列工作，通过 `selection: InspectorSelection` 绑定切换内容：

```swift
// 现有模式 — 平铺切换
InspectorView(selection: store.inspectorSelection)
// 用户只能"切换看不同的 inspector 项"，无法"从一项 push 到相关项"
```

这种**平铺切换模式**的问题：
1. 没有导航栈，用户无法追踪浏览路径
2. 从 tool call 查看 tool result 需要「跳出再回来」
3. 从 tool result 查看文件预览需要另一个入口
4. 不符合 iOS 用户对 NavigationStack 的交互预期

### 1.2 设计目标

- **NavigationStack 驱动**：用 path-based 导航替代平铺 selection
- **向后兼容**：保留 `InspectorSelection` 作为初始入口，不破坏现有 API
- **多级导航**：支持 tool call → tool result → file preview 的深度导航链路
- **跨平台**：iOS 在 Sheet 中呈现（detents），macOS/iPad 在 NavigationSplitView 的 inspector 列中使用
- **原生体验**：NavigationStack 自动 back button，符合各平台交互预期

## 2. 架构设计

### 2.1 导航链路

```
InspectorSelection (初始入口，平铺)
│
├── .toolCall(id) ─────────→ ToolCallDetailView
│                               │
│                               ├── push → ToolResultDetailView
│                               │              │
│                               │              ├── push → FilePreviewHost
│                               │              │
│                               │              └── push → DiffDetailView
│                               │
│                               └── push → AgentStateDetailView
│
├── .conversationInfo ──────→ ConversationInfoView
│                               │
│                               └── push → ...
│
└── .agentState ────────────→ AgentStateDetailView
```

### 2.2 与现有 InspectorView 的关系

```
现有 InspectorView(selection:)    新 InspectorNavigationView(initialSelection:)
─────────────────────────────     ─────────────────────────────────────────
平铺切换，单层                     NavigationStack，多层
selection: InspectorSelection      initialSelection: InspectorSelection?
改变 selection → 切换内容          改变 selection → 切换根内容
无 push/pop                       root + navigationDestination
macOS 侧栏 / iOS 无固定入口        跨平台：iOS Sheet / macOS inspector 列
```

**不修改 AgentKit 的 `InspectorView`**。新建 `InspectorNavigationView` 是一个包装层，内部仍使用 `InspectorView` 作为根视图。

## 3. 核心类型定义

### 3.1 InspectorDestination（导航目标）

```swift
/// Inspector 内的导航目标。
/// 用于 NavigationStack path，支持 Hashable 以便 push/pop。
public enum InspectorDestination: Hashable {
    /// Tool 调用结果详情
    case toolResult(toolCallID: String)

    /// 文件预览（在 Inspector 内嵌或 push 全屏）
    case filePreview(filePath: String)

    /// 文件变更对比
    case diffPreview(filePath: String, baseRef: String?)

    /// Agent 状态详情
    case agentStateDetail
}
```

### 3.2 InspectorNavigationView（容器视图）

```swift
/// 带 NavigationStack 的 Inspector 容器。
///
/// ## 使用方式
/// ```swift
/// // 在 Sheet 中呈现
/// .sheet(isPresented: $showInspector) {
///     InspectorNavigationView(
///         initialSelection: store.inspectorSelection,
///         fileProvider: fileContentProvider
///     )
///     .environment(store)
/// }
///
/// // 或作为 NavigationSplitView 的 detail
/// NavigationSplitView {
///     SidebarView()
/// } detail: {
///     InspectorNavigationView(initialSelection: store.inspectorSelection)
/// }
/// ```
public struct InspectorNavigationView: View {
    /// 初始 inspector 选择（等同于现有 InspectorSelection）
    let initialSelection: InspectorSelection?

    /// 文件内容提供者（用于 filePreview / diffPreview destination）
    let fileProvider: (any FileContentProvider)?

    @State private var path: [InspectorDestination] = []

    public init(
        initialSelection: InspectorSelection?,
        fileProvider: (any FileContentProvider)? = nil
    ) {
        self.initialSelection = initialSelection
        self.fileProvider = fileProvider
    }
}
```

### 3.3 InspectorPathEnvironment（环境值，可选）

```swift
/// 环境中的导航栈控制。
/// Inspector 内部的子视图可以通过此环境值 push 新的 destination。
@Observable
public final class InspectorPathState {
    public var path: [InspectorDestination] = []

    public func push(_ destination: InspectorDestination) {
        path.append(destination)
    }

    public func popToRoot() {
        path.removeAll()
    }
}
```

## 4. 各 Destination 视图规格

### 4.1 ToolResultDetailView

| 属性 | 说明 |
|------|------|
| 用途 | 展示 tool 调用的完整返回结果 |
| 数据 | toolCallID → 查询 tool 调用记录 + 结果 |
| 内容 | tool 名称、参数、状态、耗时、完整结果文本/JSON |
| 操作 | [📋 复制结果] [📄 查看涉及的文件] |
| 导航 | 可 push 到 FilePreview 或 DiffPreview |

```swift
struct ToolResultDetailView: View {
    let toolCallID: String
    @Environment(InspectorPathState.self) var inspectorPath
}
```

**布局：**
```
┌──────────────────────────────┐
│ ← 返回    Tool Result        │
│──────────────────────────────│
│ 🔧 tool_name                 │
│ ──────────────────────────── │
│ 参数                         │
│ ┌──────────────────────────┐ │
│ │ key: value               │ │
│ │ key: value               │ │
│ └──────────────────────────┘ │
│                              │
│ 状态: ✅ 成功 · ⏱ 234ms      │
│                              │
│ 结果                         │
│ ┌──────────────────────────┐ │
│ │ (完整结果文本)             │ │
│ │                          │ │
│ └──────────────────────────┘ │
│                              │
│ [📋 复制] [📄 查看文件]       │
└──────────────────────────────┘
```

### 4.2 DiffDetailView

| 属性 | 说明 |
|------|------|
| 用途 | 全屏展示文件变更对比 |
| 复用 | 使用 FileViewerKit 的 `DiffView` |
| 数据 | filePath + baseRef → `FileContentProvider.changes(for:baseRef:)` |
| 操作 | [查看完整文件] [原始版本] |

```swift
struct DiffDetailView: View {
    let filePath: String
    let baseRef: String?
    let provider: any FileContentProvider
}
```

### 4.3 AgentStateDetailView

| 属性 | 说明 |
|------|------|
| 用途 | 展示 agent 当前状态详情 |
| 内容 | agent 模式、活跃 tool、运行时长、token 消耗、状态日志 |
| 数据 | 来自 WorkspaceStore 的 agent 状态 |

## 5. 在 Talkify 中的集成

### 5.1 iOS：Sheet 呈现

```swift
// 在 ChatDetailWrapper 中
struct ChatDetailWrapper: View {
    @State private var showInspector = false
    let fileProvider: any FileContentProvider

    var body: some View {
        NavigationStack {
            ConversationDetailView(conversation: store.selectedConversation)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showInspector = true
                        } label: {
                            Image(systemName: "sidebar.trailing")
                        }
                    }
                }
        }
        .sheet(isPresented: $showInspector) {
            InspectorNavigationView(
                initialSelection: store.inspectorSelection,
                fileProvider: fileProvider
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .environment(store)
        }
    }
}
```

### 5.2 触发方式

| 触发点 | 行为 |
|--------|------|
| NavBar 右侧 [🔍] | 打开 InspectorSheet，显示当前 selection |
| 消息流中的 ToolCallCard → [Inspector] | 打开 InspectorSheet，当前 selection = `.toolCall(id)` |
| FileChangeCard → [查看变更] | 直接 push 到 DiffDetailView |
| 长按消息 → Context Menu → "查看详情" | 打开 InspectorSheet |

### 5.3 macOS：替换 inspector 列

macOS/iPad 上不再使用 `InspectorView(selection:)`，改为在 `.inspector()` 中直接放置 `InspectorNavigationView`：

```swift
// WorkspaceView.swift — standardLayout (iPad/macOS)
NavigationSplitView(columnVisibility: $columnVisibility) {
    SidebarView(showSettings: $showSettings)
} detail: {
    NavigationStack(path: $router.path) {
        ConversationDetailView(conversation: store.selectedConversation)
            .withAgentNavigationDestinations(router: router, dependencies: dependencies)
    }
    .inspector(isPresented: $store.isInspectorPresented) {
        InspectorNavigationView(
            initialSelection: store.inspectorSelection,
            fileProvider: fileProvider
        )
        .platformInspectorColumnWidth()  // 保持现有宽度设置
        .environment(store)
    }
}
```

**与现有实现的差异：**
- 原来：`InspectorView(selection: store.inspectorSelection)` — 单层替换
- 现在：`InspectorNavigationView(initialSelection: store.inspectorSelection)` — 带导航栈的容器
- `platformInspectorColumnWidth()` 和其他 modifier 保持不变
- NavigationStack 的 back button 自动出现在 inspector 列顶部

### 5.4 平台行为对比

| 行为 | iOS (compact) | iOS (regular) / macOS |
|------|---------------|----------------------|
| 容器 | Sheet | NavigationSplitView inspector 列 |
| 呈现方式 | `.sheet(isPresented:)` | `.inspector(isPresented:)` |
| detents | `.medium` / `.large`，push 时自动 `.large` | 无（inspector 列本身可调整宽度） |
| 关闭方式 | 下拉 dismiss / back to root | 切换 `isInspectorPresented` |
| back button | NavigationStack 自动 | NavigationStack 自动 |
| `initialSelection` 变更 | 重置导航栈 | 重置导航栈 |

## 6. 文件清单

所有代码建议放在 AgentKit 或 Talkify 中（根据依赖关系决定）：

| # | 类型 | 文件名 | 说明 |
|---|------|--------|------|
| 1 | 枚举 | `InspectorDestination.swift` | 导航目标定义 |
| 2 | 视图 | `InspectorNavigationView.swift` | NavigationStack 容器 |
| 3 | 环境 | `InspectorPathState.swift` | 导航栈环境值 |
| 4 | 视图 | `ToolResultDetailView.swift` | Tool 结果详情 |
| 5 | 视图 | `ToolCallDetailPlaceholder.swift` | Tool 调用详情（或复用现有） |
| 6 | 视图 | `DiffDetailView.swift` | Diff 全屏对比 |
| 7 | 视图 | `AgentStateDetailView.swift` | Agent 状态详情 |

## 7. 与 FileViewerKit 的交互

`InspectorNavigationView` 的 `filePreview` 和 `diffPreview` destination 可以复用 `FileViewerKit` 的组件：

```swift
case .filePreview(let filePath):
    if let provider = fileProvider {
        FilePreviewHost(
            filePath: filePath,
            fileName: (filePath as NSString).lastPathComponent,
            provider: provider,
            showDiff: false,
            diffBaseRef: nil
        )
    }

case .diffPreview(let filePath, let baseRef):
    if let provider = fileProvider {
        FilePreviewHost(
            filePath: filePath,
            fileName: (filePath as NSString).lastPathComponent,
            provider: provider,
            showDiff: true,
            diffBaseRef: baseRef
        )
    }
```

## 8. 验收标准

- [ ] `InspectorNavigationView` 的 `initialSelection` 改变时，自动重置导航栈到根视图
- [ ] 从 Tool Call → Tool Result → File Preview 的深度导航链路可正常工作
- [ ] `NavigationStack` 的自动 back button 出现在所有 push 层级
- [ ] **iOS**: Sheet detents 在 push 后自动切换到 `.large`
- [ ] **macOS**: inspector 列内的导航不影响 sidebar/detail 列的布局和状态（`NavigationSplitView` 列宽不变）
- [ ] **macOS**: 导航栈在 inspector 列内独立运作，不影响 `AgentRouter` 主导的 detail 列导航
- [ ] 在 iPad（regular size class）上与 macOS 体验一致
- [ ] `ChatDetailWrapper`（iOS drawer 布局）中通过 Sheet 正确呈现 InspectorNavigationView
- [ ] 不破坏现有 `InspectorView(selection:)` 的任何功能（AgentKit 侧不变）
- [ ] 不破坏 `WorkspaceView.swift` 中现有 `.inspector()` 绑定和 `isInspectorPresented` 逻辑
- [ ] SwiftUI Preview 可用
