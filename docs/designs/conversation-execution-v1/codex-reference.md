# 阶段 4：本地 Codex 实现对照

2026-11-18，只读检查 `/Users/xiaoyuan/Documents/work/git/codex`，commit `86ac0916597244a2e67a197822a5483924660ff1`，工作区干净。结论限定于此版本；阅读了实现与测试源码，未编译或执行 Rust 测试。阶段 4 运行逻辑暂未修改。

## 结论与调整

原方向成立：补充当前轮、排队下一轮、客户端待确认投递必须分开。Codex 的实现提供了直接参考，但其失败推进与附件存储策略不完全适合本项目，不能整套移植。

1. **补充需要目标轮次前置条件。** `TurnSteerParams.expected_turn_id` 必填；Core 在持有 active-turn 锁时检查目标身份与任务类型，拒绝无活动轮次、身份不匹配以及 review/compact。我们应要求 expected_turn_id，并在关闭补充边界与接收补充之间做原子裁决。晚到消息保留为明确的未应用/可排队状态，不静默补到下一轮。
2. **接收、待应用、正式历史是不同阶段。** Core 将补充放入 pending input，TUI 保留 pending_steers 并等待 committed user message 回执，以 client_id 对账。我们的“已接收”不能变成“模型已读取”；建议应用回执说明“已加入本轮上下文”，若要表示模型请求已发出则另有证据，不能承诺模型已经理解。
3. **未确认不是未发送。** TUI 的 MessageDelivery 明确区分 Unsent 与 Unconfirmed，并有专门的恢复路径。我们应保留本地不确定记录，按 requestID 查询/重放对账，禁止重连时给所有未确认项换新 ID。相同文字也可能是两次不同指令，不能以正文去重。
4. **用户队列与执行调度分层。** Codex 有 SQLite 队列、QueueStore、QueuedItemService 和显式 start_if_idle，不是简单把每一项都送进调度器等待。我们可复用 TurnInput 的身份/持久输入及 scheduler 的资源许可，但用户队列在领取前保持可管理，不能一入队就全部成为 scheduler 的运行请求。
5. **启动后再移除，忙时保留。** QueueService 对同线程使用 dispatch guard，只有 StartIfIdle 返回 Started 才删除项；忙、不能启动、启动错误均不据此删除。我们的客户端也必须以服务端确认为准。该源码的启动与队列删除属于两个步骤，仅据此不能推导跨进程崩溃的 exactly-once；我们的领取、执行关联和幂等需要专门的重启测试。
6. **接收顺序独立于落盘/展示顺序。** Core 为补充分配 acceptance_order，retained_context 测试覆盖延迟记录与 checkpoint 重放。我们应在持久接收时分配会话内单调顺序，并在消费和回放时沿用，避免按客户端时间或事件到达顺序重新排序。
7. **附件在入队时建立稳定快照。** Codex 会把本地图片/音频变成可独立恢复的输入，测试会删除原文件后验证队列内容。本项目继续使用本地受控资源与引用：图片持久导入并记录 hash/身份；普通文件路径是按需读取引用，不能把它承诺为文件内容快照。文件被删除、修改、权限撤销时需要明确结果。不能照搬内联大块媒体到队列 JSON 的策略。
8. **轻量变化通知与有版本的查询。** QueueStore 支持 change_version/changes_since，服务端发 queue changed 通知；测试覆盖分页和跨连接变化。我们应由服务端提供 revision/cursor 和查询恢复，客户端事件通知只作刷新线索，避免将一个内存数组或漏过的通知当作队列真相。

## 明确保留的产品差异

- Codex 的 `interrupted_turns_pause_queued_messages_but_failed_turns_drain_them` 测试明确允许失败后推进；本项目保留失败或取消后保存队列并暂停自动推进。不能以 idle 或释放 scheduler permit 作为消费充分条件。
- Codex 某些被 hook 拒绝的队列项会被消费而不阻塞后续。本项目的失败保留/可恢复规则独立设计，不能无提示丢弃用户排队任务。
- Core 的 RegularTask 会在尚有 pending input 时继续 run_turns，并在 terminal error 时返回；这并不证明所有模型流或工具都应立即中断。我们继续以一致的模型/工具边界应用补充，不增加无条件停止工具行为。
- 参考实现的 queue API 有 experimental handshake 门槛。本项目同样按可用能力开放新语义，旧服务端不支持时明确返回，不能悄悄把补充降级为新轮次。
- 队列载荷不等于完整执行授权。我们仍需单独固定和复核模型、effort、工作区、权限与资源访问，不因为持久队列可恢复就恢复旧授权。

## 对阶段 4 的具体影响

先确定四项协议：带目标轮次的补充接收、补充应用回执、持久队列查询/变更版本、原子领取与执行关联。随后以 code-agent 为权威实现，AgentKit 接入状态与恢复；阶段 5 再开放产品操作。

必须加入验收矩阵：目标轮次刚结束、非可补充任务、相同正文不同消息 ID、接收后断线、消费时重启、启动成功而回执丢失、删除源附件、失败后暂停、队列多端变化、审批/后台等待期间的补充。现有 RuntimeInput 仍只表示后台结果，不直接承载用户指令。

## 源码索引

- 补充协议：[turn.rs](/Users/xiaoyuan/Documents/work/git/codex/codex-rs/app-server-protocol/src/protocol/v2/turn.rs:321)
- 服务端补充校验：[turn_processor.rs](/Users/xiaoyuan/Documents/work/git/codex/codex-rs/app-server/src/request_processors/turn_processor.rs:1084)
- 原子目标轮次检查：[turn_input.rs](/Users/xiaoyuan/Documents/work/git/codex/codex-rs/core/src/session/turn_input.rs:894)
- 客户端不同队列：[input_queue.rs](/Users/xiaoyuan/Documents/work/git/codex/codex-rs/tui/src/chatwidget/input_queue.rs:24)
- 未发送与未确认：[user_messages.rs](/Users/xiaoyuan/Documents/work/git/codex/codex-rs/tui/src/chatwidget/user_messages.rs:69)
- 正式回执与本地媒体对账：[chatwidget.rs](/Users/xiaoyuan/Documents/work/git/codex/codex-rs/tui/src/chatwidget.rs:1367)
- 持久队列接口：[queue_store.rs](/Users/xiaoyuan/Documents/work/git/codex/codex-rs/thread-store/src/queue_store.rs:14)
- 条件启动与消费：[service.rs](/Users/xiaoyuan/Documents/work/git/codex/codex-rs/ext/queue/src/service.rs:368)
- 入队附件快照：[service.rs](/Users/xiaoyuan/Documents/work/git/codex/codex-rs/ext/queue/src/service.rs:493)
- 失败推进差异测试：[queue_service.rs](/Users/xiaoyuan/Documents/work/git/codex/codex-rs/ext/queue/tests/queue_service.rs:503)
- 源附件删除测试：[queue_service.rs](/Users/xiaoyuan/Documents/work/git/codex/codex-rs/ext/queue/tests/queue_service.rs:845)
- 接收顺序与重放测试：[retained_context_tests.rs](/Users/xiaoyuan/Documents/work/git/codex/codex-rs/history/src/retained_context_tests.rs:380)
- 队列端到端测试：[thread_queue.rs](/Users/xiaoyuan/Documents/work/git/codex/codex-rs/app-server/tests/suite/v2/thread_queue.rs:66)
