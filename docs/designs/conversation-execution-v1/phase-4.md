# 阶段 4：消息投递契约与执行边界

状态：文本补充已接通服务端、AgentKit 和 macOS 调试入口，并完成一次真实会话的接收/应用验证；持久用户队列开始存储层实现，尚未接入接收接口或自动消费。以下逐批记录保留各批次当时的范围与限制，不代表完整阶段 4 已交付。

## 第一批实现记录

code-agent 新增可选 SupplementStore 契约及显式构造的 SQLite SupplementInbox，不改变现有 Store 必选接口，不与后台 RuntimeInput 混用，也未接入 HTTP/Wire 或循环。显式边界只允许对应的持久 running 轮次打开，拒绝归档会话；运行中实际任务类型和权限授权仍需由后续执行器入口检查，不能仅凭数据库 running 就宣称可补充。

接收事务保存完整载荷与 SHA-256 身份校验、分配单调 sequence，保证同 ID 同载荷幂等、同 ID 改载荷冲突。接收与封闭边界通过同一 SQLite 写事务串行裁决：接收先成功则 seal 返回 pending 并回滚；封闭先成功则新接收被拒绝。封闭的边界不能因重试打开而重新激活。查询及 pending 列表在数据库重开后保留身份与顺序。

三项定向测试涵盖持久恢复/幂等/顺序、20 次关闭竞争、12 个并发重复接收及无效目标/空输入；`go test -race` 通过。session、session/sqlite、conversation 包回归、session 静态检查及离线完整 `go build ./...` 均通过。

此批尚无应用事务，因此 pending 消息不会被自动消费；没有配置生产入口或宣告新能力。下一批必须先补齐一致上下文追加和应用回执，随后才能与轮次结束裁决接通。AgentKit 接入及两端联调仍待后续步骤。代码尚未提交。

## 第二批：上下文追加和应用回执

补充收件箱新增 `ApplySupplements(ctx, session, targetTurnID, finalize)`：供持有 session 的串行执行者在工具调用/结果配平的边界调用。未配平的工具历史、关闭的边界、非 running 轮次及归档会话均拒绝应用。它是边界事务接口，尚未接入生产 Agent 循环或 transport，也未宣告能力。

在同一 SQLite 写事务内按 sequence 追加用户消息、将输入标记 applied、保存 session 上下文和 Runtime-only 元数据回执，并写入 `user_supplement_applied` 事件。返回值包含 request_id、目标 turn_id、接收 sequence 和已持久事件序号，只有事务提交成功才能广播；applied 仍只表示已加入上下文，不声称模型请求已经发出或已理解。

收到补充的 finalize 会应用并保留开放边界，调用方必须继续模型处理；只有未应用补充为空时才封闭。与并发接收使用同一写锁，保证接收先成功则会被本次应用，或封闭先成功则拒绝接收。该批不改变既有步数预算或工具执行方式。

应用回执保存在 session 元数据，避免向 provider 消息 JSON 注入内部标记。已持久 applied 的消息若不在调用者元数据回执中，返回 stale-context 错误，不能拿旧 session 再次覆盖新检查点；恢复应先加载已保存的 session。补充不填写首条用户消息专用的 OriginTurnID，目标归属由独立回执和事件携带，保留每轮首条用户消息的唯一索引约束。

新增验证覆盖重复应用及数据库重开、保存失败时上下文/状态/事件全部回滚且调用者内存不变、工具结果完成前拒绝应用、20 次 finalize/接收竞争。后续仍需 Agent 循环与执行器接线、应用事件解码、接收/查询接口和 AgentKit 状态恢复；本批不是完整运行中补充能力交付。

第二批验证结果：七项 Supplement 测试在 race 检测下通过；session、session/sqlite、conversation 包回归通过，session 静态检查与离线完整构建通过。扩展运行 internal/agent 回归时，既有 `TestRunTurnWithAssetsPreservesUserGatewayAsset` 失败；单独重复三次及将原始 HEAD 导出到临时目录运行均复现同一失败。未修改该测试，也未将 internal/agent 整组计为通过。相关日志位于本次工作环境的 `/tmp/supplement-application-*.log` 与 `/tmp/supplement-agent-baseline.log`。

## 第三批：Runner 循环边界接线

Runner 新增可选 Supplements 端口，在每次普通模型请求前应用补充；正常答复准备结束时执行 finalize。若结束边界应用了新补充，原答复发布为中间说明并继续，不能先发 turn_finished。应用回调只收到已持久化的回执，不能再经普通 emitter 重复写入同一应用事件。下一步由执行器将该回调接至已持久事件发布通道。

步数预算保持硬上限：工具批次耗尽预算时不额外应用新补充并声称已处理，而是先尝试封闭；存在 pending 则明确返回错误并保留输入供后续恢复。该策略不增加工具预算，也不强停正在执行的工具。

接线发现一个集成前置条件：RuntimeInputs 和 Supplements 分别具有独立的 finalize 事务，任何先后调用都可能让一个先封闭而另一个要求继续。当前 Runner 对同时配置两个端口显式拒绝，不启用此生产组合；默认 nil 的旧路径不变。完整启用前必须由共同的持久结束边界统一裁决，不能通过忽略 closed 错误或重新打开已封闭边界掩盖竞争。

新增三个真实 Runner + SQLite 测试：首次模型请求包含已有补充，模型在途到达的补充阻止过早结束且下一次请求可见，回调时应用回执已可查询并有持久事件序号，硬预算保留 pending，独立双 finalize 配置在调用模型前拒绝。三项测试在 race 检测下通过。运行中接收入口、执行器/builder 注入、共同结束事务、Wire 事件解码和 AgentKit 仍未接通，阶段 4 尚未完成。

## 第四批：共同结束边界与执行器注入

新增可选 TurnDeliveryStore，将后台结果检查点与用户补充应用提取为可复用的事务内部操作。共同入口在同一 SQLite 写事务中处理两类输入和后台回执、保存上下文与应用事件；有任何新交付时两侧均保持开放，双方均为空才在同一事务关闭。仅确认回执时也校验补充检查点，不能用旧上下文覆盖已应用消息。硬预算下不交付新内容，仍有任一类 pending 则保留并明确返回 pending 错误。

Runner 配置共同入口后不再调用两个独立 finalize；保留旧 nil 路径和独立端口的兼容实现。执行器新增 setup-only 的 SetTurnDeliveryInbox 注入点，对普通交互执行配置 Runner，managed/cross-session 域不自动加入。后台续接重建 Runner 时也恢复该注入：只有当前 active 续接、未封闭边界和 running/waiting_background 输入才能通过条件更新重新进入 running，不能复活 cancelled 输入。

应用回执增加持久应用时间，持久事件具有与 agent.Event 一致的字段及 supplement_application 数据。执行器沿用该时间和 EventSequence 通过 EmitPersisted 发布，不二次追加；测试直接对照实时事件和数据库重放的 requestID、序号和时间。

该批仍为显式配置：未在 daemon 默认启动时自动开启，不宣告运行中补充能力。服务端接收/查询、Wire 编解码、能力协商、完整恢复与 AgentKit 接入仍待后续批次，不能据此认为已能从 App 发送补充。

验证包括两类在途输入共同续轮、单次结束、跨收件箱保存失败整体回滚、仅回执路径拒绝旧检查点、持久事件不重复追加以及续接不复活取消轮次；保留既有补充与后台输入测试。

## 第五批 A：文本补充接收、查询与 Wire

服务端新增显式文本能力 `user_supplement_text_v1`。只有 NewMux 的 EnableTextSupplements 开关开启、执行器存在且配置了共同持久边界时才宣告；REST runtime capabilities 与 WebSocket hello 从同一布尔值生成，手填能力字符串不能绕过检查。默认仍关闭，不表示媒体补充或持久用户队列已实现。

- `POST /v1/conversations/{id}/supplements`：仅接受 request_id、expected_turn_id、text。严格 JSON、请求体大小限制、未知字段及尾随数据检查；媒体/模型变更等未支持字段明确拒绝。session 身份来自 URL，不从正文接受重定向。
- 成功返回 HTTP 202 及持久 SupplementReceipt；重复请求返回同一收件记录，修改原载荷返回 409 request_conflict；目标关闭返回 409 target_turn_closed。不将 202 解释成已应用。
- `GET /v1/conversations/{id}/supplements/{request_id}`：按会话和请求身份查询持久状态，覆盖确认丢失或应用后恢复；其他会话的同名查询返回 404。
- 两个路由位于现有 NewMux ServerAuth 包装内；未安装能力时返回 501 supplement_unsupported。接收确认通过 HTTP 和查询提供，本批未增加独立的 accepted 流事件。
- Wire 映射新增 `supplement_application`，仅挂在 user_supplement_applied 上，保持顶层 seq 与内层接收 sequence 各自语义；无关事件不附加该字段。实时和重放复用既有 toWire。

测试使用真实 SQLite + 执行器服务经过 HTTP handler 验证接收、幂等、冲突、媒体拒绝、查询隔离和应用后恢复；另测能力未安装时关闭、应用回执 Wire 编码及无关事件字段隔离。AgentKit 请求、事件解码与恢复仍为随后批次；未将本批文本接口描述成完整阶段 4 或完整媒体/队列能力。

## 第五批 B：AgentKit 文本补充状态与恢复

新增独立 TextSupplementClient 端口，CodeAgentTransport/DefaultAgentClient 接入 HTTP 接收和查询；旧 transport 不具备端口时明确 unsupported。请求只含 request_id、expected_turn_id、text，不通过普通 send 路径降级新建轮次。HTTP 能力接口沿用现有 envelope，补充接口按服务端原始 receipt 解码。

TextSupplementDeliveryCoordinator 将冻结的请求、Runtime origin、投递状态及接收序号持久保存到会话本地状态。网络响应丢失时保留 unconfirmed；恢复只查询同一 origin 和同一 requestID，不自动 POST、不换 ID，不将 404 当作确定未投递。明确 400/409/501 拒绝与网络不确定性分开。未知服务端状态保留原始字符串，不当作 applied。

请求/查询均在发送前及响应后核对冻结的 Runtime origin，防止动态地址切换造成串投。补充应用事件核对 envelope 的 requestID/turnID 和内层回执身份及正序号；匹配本地请求后将状态推进 applied，迟到 HTTP pending_apply 不能覆盖应用状态。执行图 reducer 不为该回执创建新轮次。

ConversationViewModel 提供内部受活动轮次校验的提交端口；连接后触发查询恢复，直播与历史回放均接入应用回执。macOS 输入框未开放新操作，没有加入队列 UI；媒体补充、持久用户队列以及真实两端联调仍待后续。

新增测试覆盖丢响应后查询恢复、Runtime origin 隔离、能力缺失不发送、应用先于接收响应、未知状态、Wire 身份不匹配、HTTP 正文与端点及 SQLite 重开恢复。验收区分这些受控客户端测试与运行中的 daemon/App 实际联调，不能据此宣称完整阶段 4 已完成。

本批最终 107 项客户端相关回归通过，Talkify-MacDirect 完整构建通过。HTTP 测试按服务端契约区分能力 envelope 与原始补充 receipt，并支持 URLSession 将请求正文转换为 InputStream 的情况。尚未启动真实 daemon/App 的补充联调，未宣告媒体或队列支持，代码尚未提交。

## 第六批：真实启动装配与默认隐藏的联调入口

codeagentd 新增显式环境开关 `CODEAGENT_EXPERIMENTAL_TEXT_SUPPLEMENTS=1`，要求 SQLite Store，启动时构造共同收件箱、配置执行器并启用 NewMux 文本能力。不支持的存储在显式启用时启动失败，不虚构持久保证。普通旧客户端/自动化的非持久请求不注入该边界；只有具备 requestID 且已持久启动的普通交互轮次启用，managed/cross-session 保持原范围。

macOS Debug 构建中另设 `TALKIFY_DEBUG_TEXT_SUPPLEMENTS=1`：输入框上方出现“补充联调…”，打开原生调试面板。面板先查询能力并固定当时的运行轮次，提供文本提交、原请求状态查看及仅查询的恢复操作；服务端未开启或当前无可用轮次时不可提交。此入口仅用于人工联调，不替代正式输入框交互，不支持媒体或队列管理。

新增真实 NewMux + TurnExecutor + SQLite + Runner 集成测试：模型首个请求保持在途，HTTP 接收补充，再释放模型响应，验证第二次模型请求包含补充、查询 applied、持久历史只有一次应用及一次结束。使用受控模型替身，不访问真实模型或修改用户项目。该测试在 race 下通过；daemon/server/conversation 回归、静态检查、完整 Go 构建及 65 项客户端回归、Talkify-MacDirect 构建通过。

人工验收：重新构建并重启 daemon，在 GoLand/启动环境加入 daemon 开关；在 Xcode Scheme 的 Run 环境加入 App 开关，使用 Debug-MacDirect 重启 App。先发起只读且持续足够时间的任务，运行中打开联调面板，确认能力开启和目标轮次，再提交“最终回答追加指定句子”等不改变权限的要求。查询应从 pending_apply 变为 applied，最终模型回答应体现要求，且没有第二个执行轮次。若面板阻挡审批，先关闭面板完成正常审批，再打开查询；补充本身不代表审批答案。

后续专项：相同请求断线恢复不重复执行、目标刚结束时明确拒绝、后台等待与补充共同续接。面板重开后可查原记录；关闭与重开面板不自动重发。实际 App + 真实模型的人工作业验收仍待反馈。撤销两个开关后恢复默认入口和启动行为，不代表删除已持久投递记录。代码尚未提交。

## 两种意图

| 意图 | 必要身份 | 效果 | 禁止的隐式行为 |
| --- | --- | --- | --- |
| 补充当前轮 | session_id、request_id、expected_turn_id | 在目标轮的安全边界加入用户输入 | 目标结束后自动变成另一轮的补充或新任务 |
| 排队下一轮 | session_id、request_id | 持久排队，满足推进条件后开始新轮 | 一入队即全部交给 scheduler 等待执行 |

本地提交仍可立即显示，但本地显示不代表服务端接收。request_id 在载荷冻结前建立；同 ID 同载荷返回既有结果，同 ID 不同载荷返回冲突。意图、目标轮次、内容、附件及冻结的执行上下文属于身份校验范围。修改后重新提交使用新请求身份。

## 权威身份与状态

- 服务端接收事务分配会话内单调 sequence，并返回消息身份、意图、状态和对应 revision。客户端时间及网络到达时间不决定消费顺序。
- 补充：accepted → pending_apply → applied；不可应用的内容进入明确的 failed/cancelled 状态并保留查询证据。applied 指持久加入目标轮上下文，不声称模型已理解。
- 排队：queued → claimed → started。claimed 时原子绑定唯一执行请求与 turn_id，执行后的结果复用现有 TurnInput 生命周期；队列消费状态与执行成功/失败分开。
- 队列控制：enabled / paused。失败或取消暂停后续自动领取，保留条目和原因；释放执行名额不解除暂停。未来恢复操作需要服务端确认。
- 本地未确认状态独立于上述服务端状态。断线不等于失败，更不等于未发送。

## 补充边界

1. 接收与目标轮关闭必须通过同一可串行裁决机制。先检查 session/目标轮、任务是否允许补充及权限范围，再持久接收，不能只在 HTTP 层检查一次。
2. 工具执行中可接收并等待边界，不强行取消工具。不将用户指令写入仅承载后台结果的 RuntimeInput。
3. 在工具批次一致、即将构造下一次模型请求的边界按 sequence 应用；用户输入、上下文和应用回执必须原子持久化，崩溃后不能重复追加。
4. 模型准备结束时与补充接收再次裁决：接收先赢则不能遗漏补充而直接宣布轮次结束；结束先赢则返回 target_turn_closed，不自动改换意图。
5. 等待审批、提问、后台结果不是成功结束。补充不代表审批答案或权限授权，不解除等待；仅在明确安全且属于该轮的边界应用。
6. 除序列、目标轮和资源外，还要保留补充来源的用户身份。未知任务类型、特殊执行域不具备安全应用点时明确拒绝，不默认可补充。

## 队列领取与结束竞争

- 先持久保存用户队列，再由消费器选择队首。执行许可仍归 scheduler；两层职责分开，复用 TurnInput 存储与幂等，不新增另一套执行历史。
- 领取需要同 session 串行控制，并检查队列 enabled、当前轮真正结束、没有待处理审批/提问/后台续接，以及服务端可用的执行上下文。
- 领取、执行身份绑定和恢复证据必须可对账。启动后才移出待处理列表，不能先删除再启动。事件广播失败不回滚已持久接收的事实。
- started 回执丢失时，客户端查询既有请求；进程在领取/启动之间退出时，恢复原执行身份，不重新创建另一个请求。
- 成功结束允许消费下一项；失败、取消与领取竞争时，终态和暂停必须形成一致裁决，不能先释放 permit 而让下一项抢跑。
- 阶段 6 的编辑/移除/提前发送只允许作用于未领取状态，预留 revision/条件更新边界，本阶段不提前开放管理 UI。

## 上下文与附件

- 补充沿用目标轮的模型、effort、工作区和授权范围；不夹带设置变更，不能借补充扩大权限。
- 下一轮在入队时固定用户选择的模型/effort 和工作区身份，执行时复核模型可用性、身份凭据、权限与环境。复核失败保留条目并暂停，不偷偷切换默认模型或提升授权。
- 图片等模型输入在入队前持久导入本地受控资源，记录身份、hash、类型与大小。原文件删除后仍可使用已确认的快照；资源由提交和消费生命周期共同持有。
- 普通文件和目录保持按路径读取的语义，不冻结或上传其全部内容。删除、内容变化及访问授权变化按引用规则处理，不能称为不可变内容快照。
- 恢复必须使用该 session 的合法凭据；不把其他用户的排队资源送入 daemon 的默认身份。

## 查询、事件与兼容

逻辑操作：submitSupplement、enqueueNext、getDelivery(request_id)、listQueue(cursor/revision)。事件至少覆盖接收、补充已应用、队列变更、领取/启动关联及失败/暂停。所有状态可通过查询重建，通知只提供变更线索。

分页需要稳定顺序与版本语义，多端修改后的过期页不能与新页静默拼接。事件应携带 request_id、消息身份、session_id、关联 turn_id、sequence/revision；applied 另带目标轮身份。重放事件不重复创建用户气泡或覆盖较新的状态。

能力位区分用户补充与持久队列，只有存储、执行、查询和事件均可用才宣告；AgentKit 不依据某个方法名称存在就猜测支持。旧端沿用普通发送，新端对不支持的补充/排队明确报错，不静默降级。未知状态保留原始值并查询，不当成成功。

## 两端实施顺序

1. code-agent：完成持久状态、身份/顺序、目标轮关闭与应用边界的事务语义及测试；明确仓储可选接口，避免破坏外部 Store 实现。
2. code-agent：接收与查询接口、受能力门控的事件；通过真实接收链路验证排队消费和恢复，不只测状态结构。
3. AgentKit：请求/响应与事件模型、能力门控、本地提交与服务端消息关联、查询恢复；保留现有即时发送和草稿保护。
4. 联调：运行中补充、两条连续排队、断线/重启、失败暂停及媒体资源恢复。通过后才进入阶段 5 的 macOS 操作入口。

## 必须通过的验收矩阵

| 场景 | 必须结果 |
| --- | --- |
| 接收成功、回执丢失、同 ID 重发 | 一条持久消息，一个应用/执行关联 |
| 同 ID 改正文、目标或附件 | 明确冲突，原提交不变 |
| 相同正文、不同 ID | 两条不同消息，按接收顺序处理 |
| 目标轮恰好结束 / 已切换下一轮 | 原子应用或明确拒绝，不误投下一轮 |
| 正在执行工具、审批或等待后台 | 不强停工具、不代替授权、不提前消费下一轮 |
| 应用上下文或领取启动时崩溃 | 持久回执与历史一致，恢复同一身份 |
| 当前轮失败/取消与队列领取竞争 | 暂停生效，后续条目保留且不能抢跑 |
| 多端入队/查询/重连 | 服务端排序和 revision 一致，客户端不重复显示 |
| 原图片删除 / 引用文件失效 | 图片快照可恢复；路径引用给出真实结果 |
| 权限收紧、模型不可用、凭据缺失 | 不扩大授权、不切默认；保留并暂停 |
| 旧 Runtime 或未知状态 | 明确兼容返回，不虚构新能力 |

验收证据分别记录服务端单测、AgentKit 单测、真实两端联调和未覆盖项。协议整理、源码盘点及静态截图均不算阶段 4 功能交付完成。

## 联调启动修正（2026-11-18）

macOS Direct 由 Talkify 的 `CodeAgentDaemon` 启动打包的守护进程，并非要求用户另外通过 GoLand 启动。该启动器重新读取 shell 环境，原来不会继承 Xcode Scheme 的补充开关。现在 Debug 启动器把 App 的 `TALKIFY_DEBUG_TEXT_SUPPLEMENTS=1` 映射到子进程的 `CODEAGENT_EXPERIMENTAL_TEXT_SUPPLEMENTS=1`；共享 Talkify-MacDirect Scheme 已为本轮联调启用 App 开关。需要通过 Xcode 此 Scheme 重新运行，直接从 Finder 打开 App 不会读取 Scheme 环境。退出联调时可取消 Scheme 环境变量勾选。

普通运行中 macOS 输入框允许聚焦、编辑并保存下一份草稿；普通发送仍由 `canSend` 的运行中限制保护，回车不会隐式排队或补充，右侧按钮仍是停止。审批、提问与归档限制保留；补充操作从专用联调面板提交。

## 第七批 A：持久用户队列存储基础

真实补充验收证据：chater 工作区会话 `20261118-091348-a1254f8a` 中，请求 `F2A9059A-8E09-4DCB-8657-5B0D691CE05A` 由 pending_apply 推进为 applied；持久历史在 2026-11-18 17:24:47（本地时间）记录应用事件，用户已在 App 查询确认。用户随后反馈对话完成。最终答复是否遵循“三个优化点”、重启后相同身份恢复不重复，尚未独立核验，不能将其计为已通过。目录枚举误注入图片由另一个 Thread 修复，本 Thread 不重复修改该实现。

code-agent 新增可选 UserQueueStore 及显式构造的 SQLite UserQueue，第一批仅支持文本：入队、按会话/requestID 查询、带会话与 revision 的有界分页。暂未装配生产、未开放 HTTP、未宣告队列能力，不改变普通发送、RuntimeInput 或 scheduler，也不提前创建 TurnInput 或追加用户上下文。

入队在同一 SQLite 写事务中验证会话存在、未归档及工作区快照一致，保存冻结载荷和 SHA-256 身份、分配会话内 sequence 并推进 revision。同 ID 同载荷返回原接收回执，不增加 revision；同 ID 改正文、模型、effort、工作区、权限模式或授权身份范围均冲突。同正文不同 ID 是独立消息。已归档后允许查询/对账此前接收的原请求，但拒绝新增消息；会话删除在同一删除事务中清理队列，避免遗留正文及未来同身份误恢复。

冻结上下文保存 wire/resolved 模型、effort、工作区可移植身份及路径、approval mode 和 authorization scope；这些字段不是权限授权，也不保存密钥。后续服务端接收入口必须从已认证上下文解析并校验，消费前必须复核模型、工作区和权限，不能直接信任客户端提交的快照或静默切换默认模型。媒体与普通文件引用尚未接入此文本类型。

分页在同一读事务中读取 revision 与有序条目；后续页只接受同会话、同 revision 的游标，有新入队时返回 revision-changed，由调用方重新加载，不能静默混合新旧列表。控制记录预留 enabled/paused 和原因；本批没有暂停/恢复、领取或启动的可调用实现。

后续批次：先实现成功结束/失败取消与领取的共同裁决、唯一执行身份绑定、启动对账恢复，再接查询/事件发布与服务端能力，最后接 AgentKit 和正式 macOS 输入框。不可将当前存储基础描述成已经能从 App 排队。

第七批 A 验证：5 项 UserQueue 定向测试在 race 下通过，覆盖并发去重与排序、冻结载荷冲突、数据库重开、稳定分页与过期 revision、事务失败整体回滚、会话隔离、归档及删除清理、无效输入和工作区不匹配；session 全部子包及 conversation 回归、session 静态检查、完整 Go 构建均通过。测试使用临时数据库，未启动真实队列消费、未修改用户会话，代码未提交。

## 第七批 B：共同终态、领取身份与存储恢复

新增可选 UserQueueDeliveryStore：FinishUserQueueTurn 在同一 SQLite 写事务中校验 session/request/turn 与终态事件身份、持久终态事件及 TurnInput 状态、保存终态裁决、暂停或领取队首。输入身份或已有终态冲突明确拒绝；完成与取消并发时先提交的终态胜出，后到者不能反转它。若领取或暂停写入失败，终态事件、状态和队列变化一并回滚。调用方必须先成功保存最终 session 检查点；本批尚未接入执行器，不替代现有终态发布路径，也不能绕过检查点保存错误。

成功结束后至多存在一个 active claim，绑定原排队 requestID、独立的 execution requestID、turnID、前驱 requestID 及持久领取事件。原消息保留 claimed，领取本身既不创建 TurnInput，也不启动模型，不将调度名额视为消息队列。缺少持久结束证据、其他活动输入、归档、后台续接、未交付 RuntimeInput、未封闭或仍有 pending 的补充边界都会阻止新领取；waiting_background 不能作为成功完成提交。已失败或取消的终态暂停队列并保留后续条目，无自动恢复操作。

ReconcileUserQueue 使用同一写事务返回已提交 claim 的原执行身份，重复查询和数据库重开不分配新身份、不重复追加领取事件。对于结束事件已持久而状态/队列投影未更新的窗口，恢复从真实终态事件补齐原关联，并复用其事件序号，避免重跑已完成任务。不能只依据 TurnInput.completed 推断成功；事件缺失时阻止推进，失败/取消事件先于状态投影持久时仍暂停。已有 claim 遇到竞争的手动活动输入也暂不返回可推进项。

已绑定执行有真实启动证据且结束时，归档其领取关联并允许成功后领取下一条；若尚在等待执行名额就取消，保留 claimed 消息并暂停，不能标成 started 或从待处理列表移走。当前仅实现存储裁决：started 的及时回执、执行前模型/权限/工作区复核、原身份接入 TurnInput 接收与调度、执行器恢复及提交后事件广播仍在下一批。连续执行测试经现有 ReserveTurnInput/StartTurnInput API 显式模拟桥接，不代表生产已能自动消费。

本批未新增 HTTP/客户端队列能力、自动消费入口或媒体支持，也未修改另一个 Thread 的图片资源处理。删除 session 时同步清理新增终态与领取表。后续必须将普通、失败、取消及后台续接的结束链路统一接入共同裁决，才能启用生产能力；不能把当前接口存在当作能力已可用。

第七批 B 验证：新增 13 项边界/恢复测试，连同前批共 18 项 UserQueue 测试在 race 下通过；覆盖 16 轮完成/取消竞争、12 个并发恢复、唯一领取、原身份重开恢复、顺序执行关联、终态/领取/暂停写入回滚、未启动取消保留、后台与补充阻塞、终态事件缺失及投影滞后修复。session 子包、conversation、server 回归通过，session 静态检查及完整 Go 构建通过。仅使用临时数据库和受控调用，未运行真实队列消费，代码未提交。

## 第七批 C1：领取到 TurnInput 的原子接收桥接

新增可选 UserQueueAdmissionStore / ReserveUserQueueClaim。共同事务中重新检查队列是否可推进、领取项和原执行身份、当前 session 工作区，并比较由可信服务端重新解析的 Current 上下文与冻结上下文。模型、effort、权限模式、授权范围或工作区不一致时，持久暂停为 execution_context_changed，保留原消息，不创建替代执行身份，也不切换默认模型。该端口的 Current 不是来自客户端即可受信的数据；实际身份解析与能力验证仍须由后续执行器服务完成。

提取现有 ReserveTurnInput 的事务内部实现，普通入口继续自行提交，队列桥接在自己的事务中复用同一接收实现，保留 managed admission、continuation、验证契约及 turn_accepted 的既有逻辑。使用领取时保存的 execution requestID/turnID 接收；重开或重试核对完整正文、模型、资源/来源及原 accepted 事件里的 queue_context/queue_request_id，返回原 accepted sequence，不追加第二个接受事件。accepted 事件保存冻结 effort 与授权上下文，不把接收成功标成 started。

专项测试验证原身份重开恢复、重复接收不重复事件、模型/effort/权限/授权范围/工作区变更暂停、接受事件写入失败时 TurnInput 整体回滚及原身份重试。生产配置尚未构造或调用队列桥接，不向 App 宣告能力。

本批调查确认普通 executeRecoveredTurn 目前传入空 effort，不能直接用于队列消费。后续 C2 必须接可信上下文复核、冻结 effort 恢复、取得调度名额后的再次校验和实际启动回执，再统一结束/恢复调用。C1 只完成持久接收桥接，未完成整个执行器自动消费，不可据此开启生产队列。

## 第七批 C2：显式执行入口、effort 与启动边界

新增 TurnExecutor.ExecuteUserQueueClaim 显式入口，要求队列存储及可信宿主提供的 QueueContextResolver；缺失时拒绝，不把客户端快照当授权。第一次解析后经 C1 原身份接收，复用现有 driveTurn、scheduler 与 Runner。在取得调度名额、重载会话后再次调用 resolver；回调必须从真实当前模型/effort、凭据范围、工作区和权限解析，不得直接回显冻结值。该可信服务的生产装配仍未开启，本批测试使用受控解析器验证调用边界，不声称已实现所有宿主的身份解析。

队列执行通过内部 context 绑定恢复冻结 effort，不回退到会话 sticky effort；要求 ModelResolver 存在、解析模型与冻结 resolved model 相同，显式 effort 范围仍有效。模型解析或可信复核失败时持久暂停；current 与冻结设置不一致时也暂停，不启动模型。普通 RecoverTurnInputs 和 Resume 识别队列 accepted 事件后拒绝走无复核的普通恢复，必须经显式队列入口恢复。已接收但未启动的消息可通过此入口使用原身份再次进入；已 running 的中断任务尚未开放队列专用续跑，不能自动重启，后续需接已有暂停/后台恢复的同等复核。

StartUserQueueClaim 在同一 SQLite 事务中核对 active claim、enabled 队列、未归档工作区、accepted/queued 输入与冻结设置，复用普通启动的事务内部实现，保存用户上下文、running 状态、started 消费状态和 user_queue_started 持久事件。已 running 或终态拒绝再次启动。提交后沿原事件序号和时间通过 EmitPersisted 发布，不二次持久化。启动回执失败时上下文和输入状态一并回滚，调用者 effort 也不提前更新。

验证：真实 SQLite + TurnExecutor 的两个受控场景分别确认 high effort 覆盖旧 low 会话值、调度后的第二次复核发现 effort 变化时暂停且不构造 Runner；存储专项确认 started 回执写入失败整体回滚、原身份重试及重复启动拒绝。UserQueue 与 QueueExecutor 定向测试在 race 下通过；session 子包、conversation、server 回归、session/conversation 静态检查和完整 Go 构建通过。

尚未装配生产自动消费、可信解析器或 HTTP 能力，App 无队列入口变化；结束后调用共同终态、连续自动消费、队列专用中断续跑及服务端身份/权限解析装配仍待后续。代码未提交。

## 第七批 C3：执行结束与显式顺序推进

队列 driveTurn 不再通过普通 SetTurnInputState 分开更新终态。最终 session 检查点保存成功、后台续接结束处理之后，读取该轮真实持久终态事件并交给 FinishUserQueueTurn，在共同事务中更新输入终态、领取关联及下一条。复用已有终态事件序号，不追加第二个结束事件。检查点保存失败或缺少持久终态时返回错误并暂停，不继续推进；执行器提前失败或调度取消也通过外层补上暂停。

新增显式、有界的 DrainUserQueue（每次 1–100 条），复用 ExecuteUserQueueClaim、既有 scheduler 和每轮两次可信复核。只有本轮返回成功且不是 WaitingBackground 才计为推进完成；背景等待停止本次 drain，不视为完成。会话内执行入口增加进程内消费排他键，避免同一执行器并发消费同一会话。此排他并非多 daemon 的执行租约，生产仍未开启，不宣称多进程模型执行去重已经完成。

真实 SQLite + TurnExecutor + scheduler、受控 Runner 集成测试验证两条消息顺序执行各一次、再次推进空队列不重跑、首条失败时后续保留并暂停，以及最终检查点保存失败时第二条不被领取或执行。原 C2 测试 Runner 补齐真实执行器要求的持久 turn_finished 行为，保留原断言。未调用真实模型、未操作用户会话。

本批仍不安装生产消费者、不新增 HTTP/AgentKit 队列能力。可信宿主解析器、外部入队/查询及能力门控、已 running 任务中断后的专用续跑仍未完成。中断/挂起不能被缺少终态的本次 drain 当成成功；当前暂停保留，后续专用恢复需继续遵循原身份和复核。代码未提交。

## 第七批 C4：服务端文本接收/查询与可信上下文解析准备

新增 server 内部 queueContextService，复用 ConversationRepository、ModelResolver 与 PermissionService，要求宿主提供按 session 认证的 provider scope。接收只允许 request_id/text/model/reasoning_effort；工作区身份、解析模型、有效默认 effort、有效权限及授权范围由服务端读取，不信任客户端声明。复核端口重读这些依赖，显式 effort 按模型支持范围校验；缺少 scope 或依赖即拒绝。scope 的生产凭据来源装配仍待下一步，Server Access Token 不等于 provider 身份。

新增严格文本路由实现：POST /v1/conversations/{id}/queue、GET /v1/conversations/{id}/queue/{request_id}、GET /v1/conversations/{id}/queue（limit、revision、after_sequence）。未知字段、尾随 JSON、超大正文和无效游标拒绝；查询和分页按当前授权范围核对。默认 effort 请求额外保留原始 selection_effort 作为用户选择身份，同 ID 重试先查询原记录，不因后来默认 effort/权限变化重冻设置；同 ID 改正文、模型或原始 effort 冲突。并发相同请求遇到服务端配置变化时也尝试返回已接收的原记录，而非创建第二条。

当前 registerUserQueueRoutes 仅通过隔离测试 mux 验证；尚未挂载生产 NewMux，也没有 REST/hello 队列能力位。内部 readiness 同时要求显式 enabled、完整存储/解析依赖及 consumerReady；生产没有设置 consumerReady。不能将该准备层描述成正在运行的 daemon 已可接收队列。后续需将 scope 解析与可信凭据、生产消费者及中断恢复装配后，再接统一认证的 NewMux 和一致能力宣告。

测试覆盖真实 SQLite HTTP 接收、默认 effort 冻结、设置变化后原请求恢复、载荷冲突、拒绝客户端权限/工作区/媒体字段、effort 范围、分页 revision 过期、授权范围变化以及不完整装配关闭。仍未接 AgentKit 和 App 队列入口，代码未提交。

## 第七批 C5：本机 daemon 实验入口

codeagentd 在 CODEAGENT_EXPERIMENTAL_USER_QUEUE=1 时装配 SQLite 队列和 NewMux。启动条件是已认证的 loopback 监听。REST 和 WebSocket hello 对本机 Runtime 所有者宣告 user_queue_text_v1，共享设备的查询与写入被拒绝。授权范围绑定稳定的 Runtime ServerID，使用本机配置的 provider。单独注入会话凭据或设置了会话审批覆盖的会话暂不支持该入口。

入队、普通任务成功保存后的调度名额释放、后台续接结束和本机会话重连均可唤醒同一会话消费者。消费者合并重复唤醒并复用既有调度器。模型可用性、工作区、effort 和有效审批模式在接收及启动阶段复核。

重启后通过同一领取身份恢复尚未启动的消息。已启动的队列任务若在重启时被识别为中断，队列暂停。只有持久的最终 done 检查点允许恢复成功终态，即使已写出结束事件也不会把还未保存检查点的轮次当作成功。已启动任务的交互续跑仍待后续。

真实 NewMux、SQLite、执行器和受控模型的集成测试验证普通轮进行中连续入队两条消息，原轮结束后按顺序执行。另验证本机认证、共享设备能力隔离及检查点缺失时的重启暂停。定向 race、相关包回归、静态检查和完整 Go 构建通过。AgentKit 和 Talkify 队列入口尚待接入。
