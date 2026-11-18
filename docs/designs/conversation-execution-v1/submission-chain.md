# 发送后立即展示：阶段 4 前置排查

2026-11-18。范围：AgentKit macOS 输入框、新对话提交、会话通道、RuntimeEngine 投影，以及 code-agent 接收、持久化、调度和启动事件。此次排查未修改发送逻辑，未对真实模型执行耗时采样。

## 结论

当前把本地提交、Runtime 接收和执行开始三个时刻绑定到了不同的 UI 更新上：macOS 编辑器保留内容直到接收确认，而详情只在 `turn_started` 时产生用户消息。因此输入框等待并非 Web 渲染本身卡住；即使接收确认已经到达，也可能出现输入框已清空、消息尚未进入详情的空档。

新对话还有额外等待：创建 Session、迁移草稿、准备文件/图片、拉历史及建立通道、刷新能力并提交之后，才切换到正式详情页面。

## 已完成对话再次发送

1. `DraftComposerPanelViewModel.send()` 保存原始编辑快照并设置 `isSending`，macOS 此时不清空文字。
2. `WorkspaceStore.sendUserMessage()` 先校验路径引用，再准备图片资源。没有引用时不会发路径校验请求；存在资源时可能需要本地导入等准备。
3. `ConversationViewModel.send()` 在每次新轮边界等待 `runtimeCapabilities()`；随后选择直接提交或客户端兼容性队列。能力刷新有 daemon 重启后的兼容目的，不能简单删除。
4. 直接提交路径写入 `markSubmissionPending`，`AgentWireSocket.submit()` 注册稳定 requestID 并分发。`send()` 返回 true 只代表交给该路径，不代表服务端已接受。
5. code-agent Router 验证输入并异步交给 TurnExecutor。执行器加载会话、修复历史、解析模型/effort，再通过 `ReserveTurnInput` 将输入和 `turn_accepted` 持久化；之后等待 scheduler。
6. AgentKit 收到 `turn_accepted` 后清理对应草稿/附件，维护 requestID 与 turnID 的关联。但 `ExecutionReducer` 对 accepted/queued 不创建图节点。
7. scheduler 放行后，服务端将用户消息与 running 状态持久化，创建 turn runtime；ServeRunBuilder 会处理模型/凭据、工作区配置、工具和 MCP 热更新等准备。Runner 才发布包含正文与附件的 `turn_started`。
8. AgentKit reducer 在 `turn_started` 创建 userInput，RuntimeEngine 投影出 ConversationTurn，Web 文档增量更新后显示用户消息。

这证明用户消息首次可见的时机取决于执行启动，而非用户点击提交。具体哪个准备步骤最慢，需要增加同一 requestID 的分段耗时记录才能判断。

## 新对话首条消息

`WorkspaceStore.commitDraft()` 的顺序为：标记 committing → 创建真实会话/可选 worktree → 创建 controller → 迁移草稿 → 引用与图片准备 → connect（先拉历史再建立通道）→ 构造 firstInput → 写 pending → send → 切换详情并移除 draft → 刷新列表。

现有 pending 快照直到创建会话和准备资源之后才建立，无法承担点击瞬间的展示。也不能仅把导航提前到创建成功处，因为创建会话/worktree 本身仍可能等待。

## 修正方向（已据此实现 macOS 前置修复）

采用持久的本地提交记录与待确认消息展示，复用现有 requestID 幂等及接收确认，而不把乐观消息伪造成服务端 `turn_started`。

- 通过本地同步检查后，先持久保存本次文字、引用、图片身份和模型选择，详情立即出现一条轻量“发送中”的用户消息，再异步准备、连接和提交。只清理提交对应的编辑内容；提交期间继续输入的草稿独立保留。
- 新对话使用本地 draft/submission 身份展示发送中的详情，获得真实 sessionID 后绑定与迁移；不把虚构 sessionID 发给服务端。创建失败时仍能找到本次消息与附件。
- `turn_accepted` 只确认 Runtime 已持久接收，不能解释成开始执行或模型已读取。当前 acceptSubmission 会清除 composer pending，需要另有提交记录承接 accepted 到 started 的展示，不能只读取输入框 pending。
- `turn_started` 到达后，以 requestID→turnID 关联接管原消息，保持同一可见身份，避免出现两条气泡、跳动或再次清理草稿。当前 reducer 的重复 started 分支会生成 `_v2` 节点，因此不能注入一个假的 started 来实现乐观展示。
- 拒绝/准备失败时，本地消息显示明确失败及重试入口，保留资源和后续草稿。重试是否复用同一 requestID 必须遵守不可变载荷规则；用户修改消息后应使用新身份。
- 排队与发送分开：已知排队项归队列；从空闲提交却被 Runtime 判定 queued 的竞争情形，需将同一条本地记录转交队列展示，不能同时表现为正在执行。队列最小 UI 留到阶段 5 接入。
- 不把未发送、已接收、queued、started、模型已读取混为一个“发送成功”。断线或重启时通过持久提交记录、Runtime 事件与现有幂等协议对账。

服务端已具备本次立即展示所需的主要身份与确认基础，不必等待阶段 4 全部完成才改善点击反馈。阶段 4 仍需核对 accepted/queued/started/rejected 的完整事件字段、查询恢复能力和补充读取语义；是否扩展事件需兼容旧端。

## macOS 前置修复实现记录

- AgentKit 新增 LocalMessageSubmission：文字、模型/effort、文件引用、附件身份、最终载荷、requestID/turnID 和展示身份独立保存。编辑器清理与记录落盘在同一次本地状态更新中完成；资源快照使用独立 `submission:` 命名空间，不会被恢复成新建任务草稿。
- 在路径、图片准备、能力接口及 Session 创建之前建立本地记录。新建任务页面先呈现相同的消息详情表面；创建成功后迁移到真实会话，不向服务端发送临时 sessionID。
- 待发送内容只经过 Web 展示投影，不进入 RuntimeEngine；发送中、已接收及失败/重试均保持一个气泡。正式轮次到达后沿用同一 presentationID，实测复用同一 DOM 节点。投递字段纳入文档增量更新，正文不变时也会刷新状态。
- 新草稿和提交期间的新输入独立保存；延迟接收确认不会清理下一条文字或文件，包含新旧文字完全相同、下一条文字尚未完成自动保存的情形。迁移时重绑定保存目标，旧任务异步完成不会抢回其他会话的导航。
- 未确认的重试复用原请求及准备完成的载荷，恢复时保留 localAssets 与 reasoningEffort；已知终止但尚未形成正式用户消息的失败轮次重试使用新 requestID，展示身份和资源快照继续沿用。附件准备失败保留资源供重试。
- 已被正式消息接管的提交记录不会在历史分页时重新追加；重复接收确认不覆盖后续 queued/failed 状态。正式消息已存在时，以 Runtime 历史为展示来源。
- 本轮复用 code-agent 现有协议，未修改服务端。queued 继续使用既有排队提示，不新增队列列表，也不宣称阶段 4 的补充读取或阶段 5 的队列 UI 已完成。

## 验证与后续验收

已有 `ComposerDraftAcceptanceTests` 三项通过，确认接收后清理原始多行草稿、拒绝保留原文、接收不覆盖新草稿；它们未覆盖点击到首帧的等待。

code-agent 已有定向测试通过：requestID 重启幂等、并发重复请求只构建一次、排队取消、持久输入去重、accepted 恢复、running 缺失 started 恢复。它们证明可复用基础，不代表完整真实客户端时延验收。

实现时必须覆盖：延迟会话创建、能力接口、资源准备及 Runtime 构建时仍及时展示；接收与开始之间无空档；拒绝/失败可恢复；新输入不丢失；started 与重放不重复气泡；会话切换/重启恢复；队列分类竞争。耗时分段以 requestID 关联点击、首次展示、准备完成、分发、接收、启动和首个模型输出，区分 UI 响应与执行等待。

实现后 156 项相关回归通过，覆盖本地状态、草稿、附件、多会话、Web 文档及工具渲染；完整 Talkify-MacDirect 构建通过。新增测试用阻塞的创建/能力接口验证消息先可见，用 SQLite 重开验证落盘与迁移，并通过真实 WKWebView 检查发送中、失败、已接收到执行开始的 DOM 接管。实际渲染截图已检查，状态行收紧气泡下的留白。

这些是自动化控制延迟及真实渲染验证，不是生产 Runtime 的端到端耗时测量。实际 App 的文件/图片、网络断线重连和服务端重启仍需按同一矩阵体验；完整可查询的投递/补充/队列恢复契约继续在阶段 4 核对。

用户已反馈本轮 App 测试通过，并确认提交。该反馈未逐项声明上述完整异常矩阵均已覆盖。
