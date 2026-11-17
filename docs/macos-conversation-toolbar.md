# macOS 对话 Toolbar

2026-11-17。保留当前分栏标题栏布局；使用 AppKit 原生名称编辑框、SwiftUI 系统按钮和系统菜单。依据 `inspector-ui/对话详情/toolbar` 中全部七张参考图。仅覆盖 macOS。

## 视觉与操作

- 标题栏保持 46 pt 高，标题使用 14 pt 系统字体，与侧栏入口和右侧工具按钮垂直对齐。
- 新对话标题“新对话”使用次级文字颜色，不可编辑，没有会话菜单。
- 已有会话标题单行、左对齐；长名称按可用空间截断，悬停可查看全文。名称右侧紧邻下拉箭头，菜单始终可达。
- 点击名称或菜单的 Rename 进入同一个原位编辑状态。使用 NSTextField / 系统 field editor，全选真实原名，支持中文、emoji、复制和系统编辑快捷键。
- Enter 或失焦保存；Esc 放弃本次修改。中文组字候选优先，不把确认候选误当成保存。
- 首尾空白在提交时去除；空名称或内部换行明确报错。名称未变化则结束编辑，不发请求。
- 保存时防止重复提交，成功后更新标题、侧栏、当前 controller 元数据；不重新连接、不重载历史。失败保留编辑内容，并可重新聚焦重试。
- 切换会话时按会话 ID 隔离编辑状态；迟到响应只更新原会话，不能把当前选中会话切回去。

## 会话菜单

顶层仅包含：

1. Open in → Show in Finder。
2. Rename。
3. Delete（破坏性操作，与上方项目分隔）。

不添加 Fork、Archive 或其他参考产品菜单项。面板工具继续使用右侧原有工具入口。

Show in Finder 使用会话实际 `workspacePath`，包括最终 Worktree checkout。仅本地 Runtime 开放；远程环境不将服务器路径映射到本机同名目录。执行时检查目录可访问性，失败给出提示；正常渲染标题不进行目录检查。

Delete 复用现有运行状态限制、Worktree keep/remove 语义及服务端删除能力：

- 活跃、等待审批或其他不允许删除的状态禁用 Delete。
- 删除前系统确认；普通删除保留工作区文件。
- 托管 Worktree 明确选择“保留 Worktree”或“删除任务和 Worktree”。脏 Worktree 冲突需要第二次显式强制确认，绝不自动 force。
- 删除当前页面成功后回到可用的新对话；请求期间若用户已切换页面，完成时不改变新页面。

## 实现与验证

- AgentKit：MacConversationToolbarTitle、MacConversationNameField、MacConversationTitleEditor；WorkspaceStore 共用重命名协调，侧栏使用同一个入口。
- 重命名同时更新活跃和归档列表。ConversationRef 的相等性只比较 ID，因此标题显式观察列表 presentation revision。
- chater：MacWorkspaceShell 接入标题组件，WorkspaceView 提供本地 Finder 能力。
- 使用已有 PATCH/DELETE、Worktree 清理协议；未新增服务端接口，未执行真实用户数据删除。
- 相关 72 项 Swift 测试通过，macOS Direct 构建通过。验证包含名称校验/重试、防重复、原生全选/IME/Esc、重命名不重连、归档名称更新、会话切换竞态、删除当前页面导航，以及原输入框/草稿回归。
- 宽/窄/深色标题栏已生成并查看原生组件渲染图。
