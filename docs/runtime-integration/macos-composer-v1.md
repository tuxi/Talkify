# macOS Composer HTTP v1

2026-11-17。代码位于同级 `code-agent` 与 `AgentKit`；macOS 宿主通过现有 RuntimeClient/AgentTransport 接入。以下为已实现的接口，不是 Agent Wire 新字段。消息提交继续使用已有可靠提交协议。

## 身份与作用域

所有端点均经过现有 Bearer 中间件，且要求 `ServerAuth.Enabled`。未启用管理鉴权返回 401。已有对话使用 `session_id`，工作区由服务端读取，禁止同时用 `workspace_path` 覆盖；需要 rebind 的会话拒绝读取。

新任务尚无 session，可以传 `workspace_path`，仅 full_desktop profile 接受；路径必须为存在的绝对目录，服务端解析真实路径。此操作不创建会话、不创建 Worktree、不修改文件。sandboxed/embedded profile 不接受客户端指定的任意草稿根目录，客户端应保留普通文本输入并降级补全。

## POST /v1/composer/query

请求示例：

```json
{
  "workspace_path": "/path/to/project",
  "kind": "reference",
  "query": "README",
  "revision": 7
}
```

已有对话改用 `session_id`，省略 workspace_path。kind 为 `command` 或 `reference`，query 最多 512 bytes，请求最多 16 KiB。响应沿用 `{trace_id, code, msg, data}`：

```json
{
  "schema": "composer-query/v1",
  "revision": 7,
  "items": [{
    "id": "file:stable-digest",
    "kind": "file",
    "label": "README.md",
    "detail": "README.md",
    "insert_text": "\"README.md\"",
    "action": "insert",
    "relative_path": "README.md"
  }],
  "truncated": false
}
```

客户端以 workspace/session + revision 丢弃旧结果，120 ms 防抖并取消旧查询。最多返回 40 项，文件搜索最多访问 5,000 个目录项；跳过符号链接、.git、node_modules、.build、.codeagent、.next 和 vendor，不读文件正文。truncated 为 true 时应提示继续输入缩小范围；当前不是分页协议。

引用结果包含文件、目录及同工作区最多三个最近对话。会话项带 session_id，选择后再读取快照，列表阶段不加载全部对话历史。命令结果包含 model、permissions、effort、skills 客户端入口及 runtime 已启用、未被覆盖且解析有效的技能；不展示尚无执行语义的命令。

action=model/permissions 打开客户端控件，effort 共用模型菜单；action=skills 打开技能设置；action=insert 插入正文。技能当前插入可读的“使用技能 <name>”指令，由既有技能机制处理，不新增任意字符串执行入口。

## POST /v1/composer/reference

```json
{
  "workspace_path": "/path/to/project",
  "source_session_id": "referenced-session"
}
```

已有目标对话使用 session_id 替代 workspace_path。source_session_id 必须与所选工作区的 canonical root 相同；不接受跨工作区读取。响应：

```json
{
  "session_id": "referenced-session",
  "history_revision": "16",
  "label": "输入框讨论",
  "context_text": "Conversation … — recent completed message excerpts (reference data):\n[…]"
}
```

只读取索引中的 turn_started/turn_finished，到最后一个成功完成事件为止，最多六条消息，每条最多 500 个 Unicode 字符。它是最近对话片段，不是全历史或模型摘要。没有已完成交换返回 409，不支持按事件类型读取的存储返回 501。

客户端将快照、来源 ID、revision 与 token 一起持久化，选中后正文只显示名称，悬停说明引用范围。快照不会随其他会话的新消息自动改变；重新选择可更新。发送时以参考资料附加到既有文本输入，当前没有独立的 Agent Wire reference 字段；因此 runtime 保存的用户消息仍包含展开的参考资料。macOS 当前设备将原始正文与路径引用随本地状态保存，接受后绑定到实际轮次，并校验模型输入摘要；匹配时历史界面显示正文及引用卡片。缺少本地展示记录时保留完整原文，不猜测裁剪引用段。最多三个会话引用，正文及展开引用合计最多 100,000 字符。

## POST /v1/composer/paths/validate

```json
{
  "session_id": "final-session",
  "paths": ["README.md", "docs", "/explicit/external/file.pdf"]
}
```

最多 32 个去重路径，每个最多 4096 bytes，请求最多 64 KiB。相对路径必须位于工作区内，解析符号链接后仍校验边界；绝对路径在 full_desktop/headless 可以作为引用提交；sandboxed 和未知 profile 只接受 canonical 工作区内的目标。预检只检查存在性和文件元数据，不打开文件正文、不上传、不递归处理目录；实际工具读取外部路径仍经过 PathAccessApprover、权限模式和受保护路径规则。headless 是部署方式，不代表拒绝所有外部路径。成功返回 `{ "valid": true }`；缺失/不可读返回 409，越界或不允许的外部路径返回 403。

macOS 在最终 session/Worktree 已创建后调用，再发送首条消息；已有对话在提交前调用。工作区变化后的旧引用拒绝静默改绑；合法的源工作区相对引用可以映射到新 Worktree，并以最终目录重新校验。

## POST /v1/conversations/{id}/composer/suggestion

```json
{ "turn_id": "completed-runtime-turn-id" }
```

客户端观察到轮次完成后异步请求，服务端复用既有辅助模型配置，不提供工具、不创建新轮次、不改变历史。模型配置不可用时返回 501，客户端恢复普通占位。

```json
{
  "session_id": "session",
  "turn_id": "completed-runtime-turn-id",
  "history_revision": "18",
  "text": "继续验证输入框的键盘操作"
}
```

仅允许最新已成功完成的轮次。生成前、生成后和缓存返回前均检查来源；来源已变化返回 409。每次调用有 20 秒超时、512 output tokens 预算，输出最多 240 个 Unicode 字符。同一会话/轮次合并请求，缓存最多 128 项；服务繁忙/生成失败返回 503。关闭客户端页面不会把已开始的生成重复发起为另一次调用。

客户端验证 session_id/turn_id，且只在空正文、无附件/引用、未运行和未提交时显示。建议不写入草稿；Tab 变为普通正文，可撤销，不发送；Esc 隐藏当前轮次建议。IME 组字及补全菜单优先。

## 图像与兼容性

图像仍通过既有 `local_assets` 交付；runtime 读取工作区内规范化图片并构造 provider 多模态 content parts。新 Composer 不调用 OSS 上传。旧云资产的历史展示保留；未提交的旧云附件在本地资源可用时迁回本地暂存，已在途请求保留原始身份。

旧服务端 404/501 时，补全和建议降级，普通文本与既有图片协议继续工作；需要路径预检的新引用不会绕过失败静默发送。当前验证面为 macOS Direct；embedded/sandboxed 的草稿授权以及 iOS 交互需要后续适配。

图像引用与普通路径分开：`assets` 是旧 Gateway/OSS 资产；macOS 本地图片由 `prepareUserAssets` 在最终工作区准备为 `local_assets`。普通文件和目录才进入路径清单。视觉模型的 provider 请求由 runtime 将本地图片读取为 image content parts，不能仅用路径文本代替图片输入。

macOS 根据有效模型目录决定图片交付方式：支持视觉时使用 `local_assets`；明确不支持视觉时，草稿保留原图片，当前提交将其作为普通路径引用，既不使用 Gateway `assets`，也不发送多模态 `local_assets`。该意图与草稿持久化，并纳入可靠提交快照及接受后的附件清理。

## 模型冻结与本地媒体输入

`follow_default` 是偏好状态，不再等于 Composer 在 wire 上省略 model。提交前将当前显示的有效模型解析为 provider/model，和图片交付方式一起冻结到该次请求。之后目录刷新只影响下一次发送；创建会话时继续保留原来的默认偏好。Runtime 对未知的显式路由应拒绝，不静默退回其他默认模型。

macOS 为 analyze_local_image、extract_video_frames 注入 Host 只读授权回调。外部绝对路径必须来自当前 session/turn 已接受的结构化引用：文件只授权该文件；目录授权 canonical 边界内的后代，符号链接不能越界。此授权不允许写外部输出。抽帧输出仍使用工作区相对路径，后续图片工具应使用成功结果中的真实路径。inspect_ui_image 支持工作区内部绝对输入，并将证据来源规范化为相对路径。

OCR 完整分析失败时尝试 fast OCR，并返回 analysis_status=fast_ocr_fallback 或 metadata_only 与 warnings；后者 success=false，不包含伪造的 grounding/compact。文件元数据不构成对画面内容的确认。
