# Files 工作台：macOS 首批实现

## 已确认的交互

- Files 宽度达到 520 点时，内容在左、目录在右；未选择文件时仅宽布局显示预览占位。
- 窄布局打开文件后，在原面板宽度内切换到内容，通过外壳“返回目录”返回。文件选择保留，目录展开状态保留。
- 窄布局的目录/内容切换与宽布局的目录显示偏好独立；展开 Files 复用现有 Workspace 聚焦布局。
- 一次只选一个文件。顶部文件名胶囊的 × 关闭文件；外壳最右侧 × 关闭 Files 面板，保留文件会话。
- Markdown 默认阅读模式，可切换源码；文本源码使用原生 NSTextView 编辑，支持光标、撤销、换行和行号。
- 停止输入约 650ms 后自动保存；切换/关闭文件先保存，失败或冲突时阻止替换当前草稿。
- 关闭面板、切换工作区、窗口失焦或进入后台会尝试保存。冲突保留当前编辑，支持复制草稿和确认后重新加载。

## 职责和数据边界

FileViewerKit 独立拥有 FileWorkspaceSession、FileDocumentState、文件树、搜索、Markdown 渲染和编辑/保存协议。Talkify 只负责窗口布局、文件标题胶囊、会话缓存及轻量 Git 状态注入。FileViewerKit 不依赖 AgentKit。

LocalFileContentProvider 提供根目录约束、UTF-8 文本快照和带版本校验的写入。写入前重新读取文件并校验 SHA-256，使用协调写入和原子替换，保留 UTF-8 BOM 与 POSIX 权限。保存串行执行；I/O 期间产生的新输入不会被旧结果覆盖。编辑文件上限为 2 MB，其他文件沿用预览分发。

文件名搜索递归查找相对路径；以 `?` 开头搜索文本内容，结果可定位到行。搜索有取消、时间、扫描数量和结果上限，跳过 `.git`、`.build`、`node_modules` 和符号链接；内容搜索检查不超过 256 KB 的 UTF-8 文本。

Markdown 使用 swift-markdown 解析。原始 HTML 转义，禁止页面脚本，外链只响应用户点击；相对文件链接和图片经同一文件 Provider 解析。图片读取受大小限制。

## 本批范围

- macOS 本地和内嵌 Runtime 工作区接入新的 Files 工作台。
- 远程连接暂不使用本机同名路径，显示不可用提示；后续需要远程文件 Provider 支持读取、版本校验写入和搜索。
- iOS 保留原有文件浏览交互，新共享代码保持 iOS 编译兼容；本批未进行 iOS 新编辑交互适配。
- 未保存草稿保存在会话内存中。本批不提供崩溃恢复或退出应用时的持久草稿恢复。

## 验证记录

- FileViewerKit 52 项测试：包含保存串行化、输入去抖、保存失败阻止切换/关闭、异步选择乱序、输入法提交、外部冲突、BOM/权限保留、路径边界、递归搜索及 Markdown 安全渲染。
- Talkify-MacDirect Debug-MacDirect 完整构建。
- Talkify Debug iOS Simulator 完整构建，保留原有 iOS 页面。
- 隔离临时文件的原生窗口验收：宽布局左右结构、410 点窄布局、返回目录保留选择、Markdown 源码/阅读切换、编辑后实际落盘、关闭当前文件。
- 主应用外壳中的视觉和整体交互由用户重新运行 macOS Talkify 后验收。

## Outputs、对话文件与 Files 联通

统一入口为 AgentKit 的 `WorkspaceStore.openWorkspaceFile`，宿主消费带工作区上下文的 `WorkspaceFileOpenRequest`，由 FileViewerKit 的 `openLocation` 校验实际文件位置和类型。只有安装了 Files 导航的 macOS 宿主启用该路由；iOS 保留现有预览交互。

- Outputs 的 `live_workspace` 项直接打开 Files；目录型项展开并定位目录，带行号的资源定位到对应行。
- `immutable` 版本、远程下载地址和 MCP 资源保留原有资源/版本预览。已删除产物保留详情说明，不尝试读取当前同名文件。
- 对话文件路径、文件型产物和 `file://` 链接使用同一打开入口；无法匹配到产物的路径也不再只是复制到剪贴板。
- Changes 差异页和 Session rail 的变更详情提供“在 Files 中打开当前文件”。
- 文件替换仍受自动保存和冲突保护约束。文件不存在或超出 Provider 根目录时显示错误，保留当前文件与草稿。目录定位保留当前文件，展开祖先节点并滚动到目标。
- 普通打开复用 Files 宽度并显示对话，不会反复切换为关闭或自动进入聚焦模式。重复打开同一个文件可重新定位行号；关闭 Files 保留选择和浏览位置。
- 请求按 conversation 隔离并携带 Runtime/工作区上下文；切换上下文、关闭面板或打开明确的资源版本后，旧请求不能覆盖新选择。

联通批验证：FileViewerKit 55 项测试；AgentKit 文件路由、Inspector、Session rail 与中文长命令 WebKit 渲染 26 项测试；生产 Workspace 布局代码及其测试在独立 harness 中运行 17 项测试。macOS 与 iOS Simulator 完整构建。主应用中从 Outputs 点击进入 Files 的整体视觉与操作体验，待重新运行 Talkify 验收。
