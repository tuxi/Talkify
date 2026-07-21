# FileViewerKit 需求规格

> 版本: v1.0 | 日期: 2026-07-21 | 状态: 待开发  
> 目标：独立 Swift Package，为 Talkify 提供工作区文件系统的可视化能力

## 1. 概述

`FileViewerKit` 是一个独立、可复用的 Swift Package。它不依赖 `AgentKit`，不包含任何业务逻辑，只负责「文件系统数据的 UI 渲染」。所有数据通过协议层由宿主 app 注入。

### 1.1 核心约束

- **零业务依赖**：不依赖 `AgentKit`、`CoreKit`、`FeatureAuth`
- **单向依赖**：仅依赖 `DesignKit`（复用 AIBadge、CardStyle 等 UI 原子）
- **纯 UI 层**：不发起网络请求，不做文件 I/O，不持有文件系统状态
- **协议驱动**：所有数据通过 `FileContentProvider` 协议获取

### 1.2 平台要求

- iOS 17.0+
- macOS 15.0+
- Swift 6.2+

## 2. Package 结构

```
Packages/FileViewerKit/
├── Package.swift
├── Sources/FileViewerKit/
│   ├── Protocols/
│   │   ├── FileNode.swift             数据协议：文件系统节点
│   │   ├── FileContent.swift          数据协议：文件内容
│   │   ├── FileChange.swift           数据协议：文件变更/diff
│   │   └── FileContentProvider.swift  宿主实现的协议
│   │
│   ├── Views/
│   │   ├── FileTree/
│   │   │   ├── FileTreeView.swift      可展开的文件树
│   │   │   ├── FileRowView.swift       单行文件/目录
│   │   │   └── FileIconProvider.swift  文件图标映射
│   │   │
│   │   ├── Preview/
│   │   │   ├── FilePreviewHost.swift   统一预览入口（类型分发）
│   │   │   ├── CodePreviewView.swift   代码/文本查看
│   │   │   ├── ImagePreviewView.swift  图片预览（缩放+拖动）
│   │   │   ├── VideoPreviewView.swift  视频预览
│   │   │   └── BinaryPreviewView.swift 二进制文件信息
│   │   │
│   │   ├── Diff/
│   │   │   ├── DiffView.swift          变更对比视图
│   │   │   ├── DiffHunkView.swift      单个 diff hunk
│   │   │   └── DiffLineView.swift      单行 diff
│   │   │
│   │   ├── Cards/
│   │   │   ├── FileChangeCard.swift    消息流中的文件变更卡片
│   │   │   └── FileChangeCardStyle.swift 卡片样式配置
│   │   │
│   │   └── Browser/
│   │       └── WorkspaceBrowserView.swift  工作区浏览器
│   │
│   └── Utils/
│       ├── FileTypeDetector.swift       文件类型检测
│       └── SyntaxHighlighter.swift      基础语法高亮
│
└── Tests/FileViewerKitTests/
    └── ... (单元测试)
```

## 3. 核心协议

### 3.1 FileNode（文件系统节点）

```swift
/// 文件系统的单个节点（文件或目录）。
/// 由宿主 app 实现此协议，FileViewerKit 只消费，不持有。
public protocol FileNode: Identifiable, Hashable {
    /// 唯一标识，通常为完整路径
    var id: String { get }

    /// 文件名（不含路径）
    var name: String { get }

    /// 从工作区根目录开始的完整相对路径
    var path: String { get }

    /// true = 目录，false = 文件
    var isDirectory: Bool { get }

    /// 文件大小（字节），目录为 nil
    var size: Int64? { get }

    /// 最后修改时间
    var modifiedAt: Date? { get }

    /// 子节点，仅目录有效
    /// 返回 nil 表示「未加载」；返回 [] 表示「空目录」
    var children: [Self]? { get }
}
```

### 3.2 FileContent（文件内容）

```swift
/// 文件内容的各种类型。
/// 由 FileContentProvider 返回，FileViewerKit 根据类型选择预览组件。
public enum FileContent {
    /// 文本/代码内容
    case text(String)

    /// 本地图片 URL（已缓存到本地）
    case image(URL)

    /// 本地视频 URL（已缓存到本地）
    case video(URL)

    /// PDF 文档 URL
    case pdf(URL)

    /// 二进制文件（不可预览）
    case binary(name: String, size: Int64)
}

/// 文件预览相关错误
public enum FilePreviewError: Error {
    case fileNotFound
    case unsupportedType(String)
    case loadFailed(Error)
}
```

### 3.3 FileChange（文件变更）

```swift
/// 描述 agent 对一个文件的变更
public struct FileChange: Identifiable {
    public var id: String { filePath }
    public let filePath: String
    public let status: ChangeStatus
    public let summary: String         // "添加了 12 行，删除了 3 行"
    public let hunks: [DiffHunk]
}

public enum ChangeStatus: String {
    case added
    case modified
    case deleted
}

/// Diff 中的一个连续的变更块
public struct DiffHunk: Identifiable {
    public var id: String { "\(oldStart)-\(newStart)" }
    public let header: String          // "@@ -12,3 +12,5 @@"
    public let oldStart: Int
    public let newStart: Int
    public let lines: [DiffLine]
}

/// Diff 中的单行
public enum DiffLine: Identifiable {
    case unchanged(String)
    case added(String)
    case removed(String)

    public var id: String {
        switch self {
        case .unchanged(let t): return "u:\(t.hashValue)"
        case .added(let t):     return "a:\(t.hashValue)"
        case .removed(let t):   return "r:\(t.hashValue)"
        }
    }
}
```

### 3.4 FileContentProvider（宿主实现）

```swift
/// 宿主 app 必须实现的协议。
/// FileViewerKit 的所有数据获取都通过此协议，不直接访问任何存储。
public protocol FileContentProvider: AnyObject {
    /// 获取文件的完整内容（用于全屏预览）
    func content(for path: String) async throws -> FileContent

    /// 获取文件的变更信息（与 baseRef 对比，nil = 与原始版本对比）
    func changes(for path: String, baseRef: String?) async throws -> FileChange?

    /// 获取目录下的直接子节点
    /// - Returns: 子节点数组，按目录优先 + 字母排序
    func children(of directoryPath: String) async throws -> [any FileNode]

    /// 检查文件类型是否支持内嵌预览
    func supportsPreview(for path: String) -> Bool
}
```

## 4. 组件规格

### 4.1 FileTreeView

| 属性 | 说明 |
|------|------|
| 用途 | 可展开/折叠的文件目录树 |
| 实现 | SwiftUI `OutlineGroup` + `DisclosureGroup` |
| 性能 | 懒加载子节点（`children` 属性为 nil 时不展开），目录默认折叠 |
| 限制 | 单目录超过 50 子项自动折叠 + "显示全部 (N)" 按钮 |

```swift
public struct FileTreeView<Node: FileNode>: View {
    /// 根节点列表
    let roots: [Node]

    /// 内容提供者
    let provider: any FileContentProvider

    /// 文件选中回调
    let onSelect: (Node) -> Void
}
```

**交互行为：**
- 点击目录 → 展开/折叠（箭头动画）
- 点击文件 → 触发 `onSelect` 回调
- 长按文件 → Context Menu: [预览] [查看变更] [复制路径]
- 文件行显示：图标 + 文件名 + 变更标记（M/A/D 色点）+ 文件大小

### 4.2 FileRowView

```swift
public struct FileRowView<Node: FileNode>: View {
    let node: Node
    let changeStatus: ChangeStatus?   // nil = 未变更
    let onTap: () -> Void
}
```

**显示规则：**

| 类型 | 图标 | 附加信息 |
|------|------|---------|
| 目录 | `folder.fill` (SF Symbol) | 无 |
| .swift | `swift` 色块图标 | 文件大小 |
| .md | `doc.text` | 文件大小 |
| 图片 | `photo` | 文件大小 |
| 视频 | `play.rectangle` | 文件大小 |
| 未知 | `doc` | 文件大小 |

**变更标记色点：**
- 🟢 绿色 = added
- 🟡 黄色 = modified
- 🔴 红色 = deleted
- ⚪ 无色 = 未变更

### 4.3 FilePreviewHost（统一预览入口）

```swift
public struct FilePreviewHost: View {
    let filePath: String
    let fileName: String
    let provider: any FileContentProvider

    /// 是否显示 diff 模式（变更对比）
    let showDiff: Bool

    /// diff 的对比基准
    let diffBaseRef: String?
}
```

**类型分发逻辑：**

```
FileContent 类型           → 渲染组件
─────────────────────────────────────────
.text(content)             → CodePreviewView
.image(url)                → ImagePreviewView
.video(url)                → VideoPreviewView
.pdf(url)                  → QuickLook 包装
.binary(name, size)        → BinaryPreviewView
```

**加载状态：** 显示 `ProgressView` + 文件名 + "正在加载..."
**错误状态：** 显示错误信息 + [重试] 按钮

### 4.4 CodePreviewView

| 属性 | 说明 |
|------|------|
| 用途 | 代码/文本文件的内容查看 |
| 字体 | 等宽系统字体 (SF Mono)，支持 Dynamic Type |
| 行号 | 可选显示（默认开启，可配置关闭） |
| 语法高亮 | 基础关键词高亮（swift/kotlin/python/js/json/markdown 等常见语言） |
| 搜索 | 支持页内文本搜索（iOS 原生 find interaction） |

```swift
public struct CodePreviewView: View {
    let content: String
    let language: String?        // 文件扩展名，用于选择高亮规则
    let showLineNumbers: Bool    // 默认 true
}
```

### 4.5 ImagePreviewView

| 属性 | 说明 |
|------|------|
| 用途 | 图片文件的预览查看 |
| 手势 | 双指缩放 (pinch to zoom)，双击放大/还原，拖动 |
| 背景 | 纯黑背景，图片居中 |
| 加载 | 异步加载，显示进度 |

```swift
public struct ImagePreviewView: View {
    let url: URL                // 本地图片 URL
}
```

### 4.6 VideoPreviewView

| 属性 | 说明 |
|------|------|
| 用途 | 视频文件的播放预览 |
| 实现 | `AVPlayerViewController` 包装 (SwiftUI `VideoPlayer`) |
| 控制 | 标准播放控件（播放/暂停/进度条/音量） |

```swift
public struct VideoPreviewView: View {
    let url: URL                // 本地视频 URL
}
```

### 4.7 BinaryPreviewView

| 属性 | 说明 |
|------|------|
| 用途 | 二进制文件的信息展示（无法预览内容） |
| 显示 | 文件图标 + 文件名 + 大小 + 类型说明 |
| 操作 | [📤 分享] 按钮（`UIActivityViewController`） |

```swift
public struct BinaryPreviewView: View {
    let fileName: String
    let fileSize: Int64
}
```

### 4.8 FileChangeCard

| 属性 | 说明 |
|------|------|
| 用途 | 嵌入在对话消息流中，展示 agent 对文件的变更 |
| 折叠态 | 图标 + 文件名 + 变更摘要（"+12 -3"） |
| 展开态 | 内嵌 `DiffView` 展示完整变更 |
| 动画 | `withAnimation(.easeInOut)` 折叠/展开过渡 |

```swift
public struct FileChangeCard: View {
    let change: FileChange
    let provider: any FileContentProvider

    /// 用户请求查看完整文件
    let onViewFile: (String) -> Void   // 参数: filePath

    /// 用户请求查看 diff
    let onViewDiff: (String) -> Void   // 参数: filePath
}
```

**状态变化流程：**

```
折叠态 (默认)
┌─────────────────────────────┐
│ 📄 UserProfile.swift        │
│ +12 行  -3 行  [展开变更 ▼]  │
└─────────────────────────────┘
          ↓ 点击 [展开变更] 或整张卡片
展开态
┌─────────────────────────────┐
│ 📄 UserProfile.swift        │
│ +12 行  -3 行  [收起变更 ▲]  │
│ ────────────────────────── │
│   import Foundation         │
│ + import CoreKit            │
│                             │
│   struct UserProfile: ... { │
│ +   let displayName: String │
│ -   let username: String    │
│   }                         │
│ ────────────────────────── │
│ [预览完整文件] [查看 Diff]    │
└─────────────────────────────┘
```

### 4.9 DiffView

| 属性 | 说明 |
|------|------|
| 用途 | 完整的文件变更对比视图 |
| 模式 | 统一视图 (unified) — 所有行在一个列表中 |
| 高亮 | 绿色背景 (新增行) / 红色背景 (删除行) / 无色 (未修改行) |
| 行号 | 显示新旧行号 |

```swift
public struct DiffView: View {
    let hunks: [DiffHunk]
    let oldFilePath: String?
    let newFilePath: String?
}
```

**行渲染规则：**

```
DiffLine 类型    前景色    背景色        行号
──────────────────────────────────────────────
.unchanged     .primary   .clear        旧行号 + 新行号
.added         .green     .green.opacity(0.15)  新行号
.removed       .red       .red.opacity(0.15)    旧行号
```

### 4.10 WorkspaceBrowserView

| 属性 | 说明 |
|------|------|
| 用途 | 跨工作区浏览：查看所有工作区，进入某个工作区查看对话和文件 |
| 导航 | NavigationStack 两级：列表 → 详情 |
| 入口 | Drawer Header 右侧 [›]，或快捷文件 Tab 底部 [查看全部文件 →] |

```swift
public struct WorkspaceBrowserView: View {
    /// 工作区数据源
    let workspaces: [WorkspaceItem]

    /// 文件内容提供者
    let fileProvider: any FileContentProvider

    /// 选择工作区
    let onSelectWorkspace: (WorkspaceItem) -> Void

    /// 在文件树中选中文件
    let onSelectFile: (String) -> Void      // 参数: filePath
}

/// 工作区列表项
public struct WorkspaceItem: Identifiable {
    public let id: String
    public let name: String
    public let conversationCount: Int
    public let fileCount: Int
    public let uncommittedChanges: Int
    public let lastActiveAt: Date?
}
```

**Level 1: 所有工作区**

- 列表行显示：工作区名称 + 对话数/文件数 + 最后活跃时间
- 搜索栏（按名称过滤）
- "+ 创建新工作区" 按钮（回调给宿主）
- 点击工作区行 → NavigationLink push 到 Level 2

**Level 2: 工作区详情**

- 顶部区域："💬 N 条对话" → 可点击，宿主负责跳转到对话列表
- 主体区域：`FileTreeView` 展示该工作区的完整文件树
- 点击文件 → 触发 `onSelectFile` 回调

## 5. Package.swift

```swift
// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "FileViewerKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "FileViewerKit",
            targets: ["FileViewerKit"]
        ),
    ],
    dependencies: [
        .package(path: "../DesignKit"),
    ],
    targets: [
        .target(
            name: "FileViewerKit",
            dependencies: ["DesignKit"],
            path: "Sources/FileViewerKit"
        ),
        .testTarget(
            name: "FileViewerKitTests",
            dependencies: ["FileViewerKit"],
            path: "Tests/FileViewerKitTests"
        ),
    ]
)
```

## 6. Talkify 桥接层（宿主实现）

Talkify app 需要实现以下桥接类，将 AgentKit 的数据适配到 FileViewerKit 的协议：

```swift
// Talkify/Bridge/WorkspaceFileContentProvider.swift

final class WorkspaceFileContentProvider: FileContentProvider {
    private let store: WorkspaceStore  // 来自 AgentKit

    init(store: WorkspaceStore) {
        self.store = store
    }

    func content(for path: String) async throws -> FileContent {
        // 通过 store 的工具通道读取文件内容
        // AgentKit → WebSocket → Runtime → 文件系统 → 返回内容
    }

    func changes(for path: String, baseRef: String?) async throws -> FileChange? {
        // 通过 store 获取文件的 diff
    }

    func children(of directoryPath: String) async throws -> [any FileNode] {
        // 通过 store 获取目录列表
    }

    func supportsPreview(for path: String) -> Bool {
        // 根据扩展名判断
        let ext = (path as NSString).pathExtension.lowercased()
        return ["swift", "kt", "py", "js", "ts", "json", "md", "txt",
                "png", "jpg", "jpeg", "gif", "mp4", "mov", "pdf"].contains(ext)
    }
}
```

## 7. 交付清单

| # | 组件 | 文件 | 状态 |
|---|------|------|------|
| 1 | `FileNode` 协议 | `Protocols/FileNode.swift` | 待实现 |
| 2 | `FileContent` 枚举 | `Protocols/FileContent.swift` | 待实现 |
| 3 | `FileChange` + `DiffHunk` + `DiffLine` | `Protocols/FileChange.swift` | 待实现 |
| 4 | `FileContentProvider` 协议 | `Protocols/FileContentProvider.swift` | 待实现 |
| 5 | `FileTreeView` | `Views/FileTree/FileTreeView.swift` | 待实现 |
| 6 | `FileRowView` | `Views/FileTree/FileRowView.swift` | 待实现 |
| 7 | `FileIconProvider` | `Views/FileTree/FileIconProvider.swift` | 待实现 |
| 8 | `FilePreviewHost` | `Views/Preview/FilePreviewHost.swift` | 待实现 |
| 9 | `CodePreviewView` | `Views/Preview/CodePreviewView.swift` | 待实现 |
| 10 | `ImagePreviewView` | `Views/Preview/ImagePreviewView.swift` | 待实现 |
| 11 | `VideoPreviewView` | `Views/Preview/VideoPreviewView.swift` | 待实现 |
| 12 | `BinaryPreviewView` | `Views/Preview/BinaryPreviewView.swift` | 待实现 |
| 13 | `DiffView` | `Views/Diff/DiffView.swift` | 待实现 |
| 14 | `DiffHunkView` | `Views/Diff/DiffHunkView.swift` | 待实现 |
| 15 | `DiffLineView` | `Views/Diff/DiffLineView.swift` | 待实现 |
| 16 | `FileChangeCard` | `Views/Cards/FileChangeCard.swift` | 待实现 |
| 17 | `WorkspaceBrowserView` | `Views/Browser/WorkspaceBrowserView.swift` | 待实现 |
| 18 | `FileTypeDetector` | `Utils/FileTypeDetector.swift` | 待实现 |
| 19 | `SyntaxHighlighter` | `Utils/SyntaxHighlighter.swift` | 待实现 |
| 20 | Package + 测试骨架 | `Package.swift` + `Tests/` | 待实现 |

## 8. 验收标准

- [ ] 所有公共 API 通过协议定义，不暴露具体类型
- [ ] `FileTreeView` 在 1000+ 节点的目录树上展开/折叠无可见延迟
- [ ] `FilePreviewHost` 能正确分发 4 种文件类型到对应预览组件
- [ ] `FileChangeCard` 折叠/展开动画流畅（≥ 30fps）
- [ ] `DiffView` 在 500+ 行 diff 上滚动流畅
- [ ] `CodePreviewView` 支持 Dynamic Type（从 xSmall 到 xxxLarge）
- [ ] 所有组件支持 Dark Mode
- [ ] `WorkspaceBrowserView` 的 `NavigationStack` 导航行为正确
- [ ] 协议层的 mock 实现可用于 SwiftUI Preview
