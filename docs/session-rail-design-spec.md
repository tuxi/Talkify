# Session rail：数据盘点与完整交互设计

状态：设计已确认，后端分批实现中；AgentKit 类型化接口与 macOS 六组首版已接入，完整 capability 尚未启用。日期：2026-11-15。

范围：第三步的 Session rail。六个分组均纳入正式实现范围；数据缺口由 code-agent 补齐，
不以客户端猜测、假数值或永远为空的占位行代替。本文确定最终内容和操作；实现进度见下方服务端提案。
聚合摘要接口确定为 `GET /v1/conversations/{id}/session-rail`，能力名 `session_rail_v1`。
服务端改造提案见 [session-rail-v1-proposal.md](runtime-integration/session-rail-v1-proposal.md)。

## 1. 定位与结构

Session rail 是“当前会话的环境、上下文、产物与执行状态”的常用入口，不是所有设置的集合。
固定顺序：Environment → Context → Connectors → Outputs → Changes → Background tasks。
每组独立展开/收起，不采用只能展开一项的手风琴；收起后仍保留摘要。

| 分组 | 收起时摘要 | 首次默认 |
|---|---|---|
| Environment | 项目名；有异常时显示状态 | 展开 |
| Context | 已用百分比；未测量时显示“未测量” | 展开 |
| Connectors | 已连接数、异常数 | 收起 |
| Outputs | 已确认产物数 | 展开 |
| Changes | 文件数；可用时显示新增/删除行数 | 展开 |
| Background tasks | 运行数、停止中数、最近完成数 | 展开 |

六组展开偏好由客户端保存，切换会话时保持；子列表、详情路径、选中文件按 Runtime 与会话隔离。
手动收起后，即使任务数量变化也不强行展开，只更新摘要。空组不消失，显示一行简短空状态。

布局：沿用参考图的轻量分区、细分隔线和紧凑行，避免每组套卡片。内容边距 12–16pt，
标题约 12–13pt，常规行至少 28pt；长文件名中间截断，完整名称可悬停或键盘聚焦查看。
数量、tokens 等数字右对齐，图标不单独承担状态语义。

停靠与悬浮复用内容和状态，不因切换呈现方式重新请求、清空折叠状态或滚动到顶部。
根页面不增加第二条 Session rail 标题栏；整条 rail 使用一个纵向滚动区，组内不嵌套滚动区。
长列表显示有限预览和“查看全部”，完整列表/详情由内部页面承载。

## 2. 已核对的数据能力

“部分具备”意味着有可复用事实，并不意味着已能完整支撑该组。

| 分组 | 已有事实与代码 | 必须补齐 |
|---|---|---|
| Environment | `/v1/runtime/info`；会话 ref/detail 的 workspace、execution_policy、worktree；Git branch list 返回 head/dirty/文件计数 | 会话范围统一摘要、路径能否在本机操作的判定；运行环境名与连接元数据合并 |
| Context | `/context` 的模型预算、上次请求 prompt tokens、压缩汇总、消息结构估算；`model_request` 的实际 tool_names 和字符量；`skill_loaded` 事件 | 请求级细分归因、完整来源清单、当前仍在上下文中的技能/指令、测量时间与快照关联 |
| Connectors | Runtime 的 workspace MCP manager、连接报告与有效工具注册表；插件清单中的 MCP 名称；客户端工具绑定 | 会话级只读清单、实时状态、来源、安全元数据、有效暴露工具数。插件启用不等于 MCP 已连接 |
| Outputs | 已加载时间线上的 tool assets；按 asset ID 的 preview/content/blob；preview artifact 事件 | 不依赖时间线分页的完整产物目录；生成/更新/读取的归类；版本与可用性 |
| Changes | Git branch list 的 dirty/文件数；macOS 本地 GitWorkingTreeReviewProvider；terminal 事件的 turn diffstat | Runtime 工作区净变更摘要、行数及远端差异读取。turn diffstat 是逐次写入累加，不能当 Git 净差异 |
| Background tasks | 会话 jobs 查询、按 owner 停止、job backlog/stream；客户端 BackgroundJobsModel | 完整历史计数/分页、起止时间、Runtime 重启后的未知状态表达。现有清单仅含全部活跃项和最近最多 20 个终态项 |

### 2.1 关键来源

- `../code-agent/internal/server/mux.go`：ContextSnapshot / contextSnapshotFromSession / 会话、context、资产和 runtime 路由。
- `../code-agent/internal/session/context_budget.go`：输入/输出预算以及结构估算口径。
- `../code-agent/internal/agent/loop.go`：实际 model request、工具暴露清单、provider 用量写回。
- `../code-agent/internal/agent/event.go`、`tool_batch.go`：skill_loaded、turn diffstat 等事实。
- `../code-agent/internal/session/builder.go`：SYSTEM、APPEND_SYSTEM、AGENTS/CLAUDE、skills index 的组合来源。
- `../code-agent/internal/runtime/workspace.go`、`../code-agent/internal/mcp/manager.go`：workspace MCP 生命周期与报告。
- `../code-agent/internal/server/skill_plugin_api.go`：以 session_id 解析项目范围的技能目录。
- `../code-agent/internal/server/asset_api.go`、`../code-agent/internal/assetref/ref.go`：按 ID 读取资源；当前 Ref 无强类型 output/input 字段。
- `../code-agent/internal/server/background_jobs.go`、`docs/background-job-control.md`：jobs 归属、终态与停止语义。
- `../AgentKit/Sources/AgentKit/Core/ConversationContext.swift`、`RuntimeClient.swift`：客户端现有 facade 与 DTO。
- `../AgentKit/Sources/AgentKit/Core/SkillPluginManagementModels.swift`：已有 SkillPluginManaging 能力，不重复创建管理客户端。
- `../AgentKit/Sources/AgentKit/Features/Conversation/ViewModels/ConversationViewModel.swift`：assetRefs 只投影当前 snapshot.timeline。
- `Talkify/Shared/GitWorkingTreeReviewProvider.swift`：当前 Changes 读取本机目录，而非远端 Runtime。

## 3. Environment：逐行设计

| 行 | 展示 | 点击行为 | 数据与约束 |
|---|---|---|---|
| 运行环境 | 图标、运行环境名称、本机/远端、断连状态 | 轻量弹层：Runtime 版本、profile、连接状态；明确的“管理环境”入口打开现有设置 | 复用 runtime info 与当前连接；不要把 client 所在 Mac 当作执行环境 |
| 项目 | 项目名、弱化的 display path | 菜单：复制路径、查看 Files；本机可访问时提供“在 Finder 中显示” | 以会话实际 runtime_cwd/工作树为准；远端路径不能传给本机 Finder |
| Git 分支 | 分支名；detached 时短 commit；非仓库显示“未使用 Git” | 菜单：复制分支/commit、查看 Git 信息、进入已有分支管理 | branch 管理是显式操作，仍遵守服务端 busy/dirty/managed-worktree 规则 |
| 隔离工作树（条件行） | “独立工作树”及基准项目名/状态 | 查看工作树详情与复制路径；本阶段不提供直接删除 | 仅 execution_policy/worktree 明确存在时展示，不能从路径名称猜测 |

环境弹层不自动切换 Runtime。项目菜单中的“在终端打开”待 Terminal 真正接入时启用；
未接入前不生成 shell 命令或假装已打开。参考图的 Save environment 是独立的环境模板功能，
当前没有对应模板契约，不把它作为一个不可用的装饰按钮放进 rail。

## 4. Context：逐行设计

| 行 | 展示 | 点击行为 | 统计范围 |
|---|---|---|---|
| 用量摘要 | “已用 39%”和 `393.7k / 1M`；未测量或压缩待测量时显示相应状态 | 点击用量/进度条打开上下文详情；悬停只显示同一摘要，不要求靠悬停完成操作 | provider 上次请求测量，带时间和 request snapshot 标识 |
| Messages | 消息/工具结果/摘要等普通消息的估算 tokens 与约占窗口比例 | 查看组成与消息数量；本阶段不定位到具体消息 | 排除已独立归类的技能正文和 Memory，防止重复计算 |
| MCP tools | 本次请求实际暴露的 MCP schema 估算 tokens、工具数 | 小箭头展开前 8 项；“查看全部”进入可搜索工具目录；单工具查看名称、说明和参数 | 不是历史调用次数，也不是所有配置工具数量 |
| System tools | 当前暴露的内建与客户端工具 schema 估算 tokens | 查看工具列表；标明 Runtime/本机执行，以及是否当前对模型可见 | 排除 MCP；hidden 工具不计入模型请求 schema 占用 |
| System prompt | 基础指令及运行时附加指令估算占用 | 查看来源摘要，不默认展开整段原始提示词 | 不再重复包含已单列的 Skills、Memory、MCP instructions |
| Skills | 已加载正文数、可用数与估算占用；两种数值明确区分 | 查看“当前已加载 / 可用技能”；已有管理入口作为明确的“管理技能”操作 | inventory、曾加载事件、当前仍在上下文三者不是一回事 |
| Memory files | 实际注入的指令文件数与估算占用 | 展开来源列表；点击查看只读加载版本；已变更文件标注“磁盘内容已变化” | 只列实际加载的 AGENTS/CLAUDE/其他明确注入项，不扫描所有 md 文件 |
| MCP server instructions（条件行） | 服务端实际注入时的估算占用 | 查看各 server 指令来源摘要 | 未注入则不展示此行，不能默认假设存在 |
| Other（条件行） | 尚未归因的估算占用 | 查看解释 | 不把 measured 与 estimated 的差额伪装为精确 Other |
| 预算说明 | 输入预算、输出预留、压缩阈值、剩余输入空间 | 在上下文详情中展开，不让根页面再堆多行数字 | input/output budget 与压缩阈值分别展示；不能把 output reserve 叫作 autocompact buffer |
| 压缩状态 | 压缩次数；需要时显示“压缩后待测量” | 查看已有压缩详情；“压缩上下文”是独立操作，复用现有 idle-only 接口 | 无历史显示“尚未压缩”，不等同于功能不支持 |

### 4.1 数字口径（实现前必须固定）

1. 顶部使用 `provider_reported` 的上次请求 prompt_tokens；它不是本会话累计费用，也不保证等于当前待发送 prompt。
2. 新消息、tool result、压缩发生后，显示“内容已更新，等待下次测量”，保留上次测量并标注时间；不能把旧数值说成当前精确值。
3. 根进度条先表达测量总量与窗口容量；组成表中的估算值统一加 `≈`，并说明“组成估算不等于上次测量总量”。
4. 如使用彩色组成条，必须绑定同一 prompt snapshot 的估算总量并明确标“估算”；不能把估算段强行缩放成测量值制造精确感。
5. 对每段内容只归类一次；技能全文虽然以 tool result 进入 history，也不能同时计入 Messages 与 Skills。
6. 未测量用 `null/unknown`，不显示“0%”；旧 context 的 fallback 容量与真正模型声明容量应区分来源。
7. 免费空间、模型输出预算、输入安全余量、压缩阈值不是同一个概念；不照搬参考图中的固定 33k buffer。
8. `model_request` 已有实际工具名称、消息数、system/tools 字符量，可用于来源核对，但字符量不是 tokens；`skill_loaded` 只能证明曾加载。

## 5. Connectors：逐行设计

范围是当前会话实际使用的 Runtime 与 workspace 的有效 MCP 配置合集：插件、宿主注入、
用户级配置、当前项目配置、本机覆盖配置，以及明确开启继承时的 Claude 用户级服务。
不枚举其他工作区，也不把 `./code-agent` 源码目录下的配置自动算作当前工作区配置。
同名 server 整项覆盖，优先级从高到低：项目 `.mcp.local.json` → 项目 `.mcp.json` →
`~/.codeagent/.mcp.json` → 可选 Claude 用户配置 → 宿主注入 → 插件。
服务行显示最终来源；低优先级同名来源只在详情说明，不重复计数。
失败、停用、profile 不支持的服务显示原因，不能只列连接成功的服务；配置解析失败单独显示来源诊断。
code-agent 作为 Runtime 不单独伪装成 MCP server。本机能力在同组独立列出并标注“本机能力”。


| 行 | 展示 | 点击行为 | 数据与约束 |
|---|---|---|---|
| 每个 MCP server | 图标、名称、已连接/连接中/断开/失败/停用/未知、当前可用工具数 | 打开详情弹层：范围、来源、检查时间、可用/已注册工具数、可读错误摘要、工具目录 | 使用 workspace manager 的实际状态；不能把启动成功报告永久当实时在线 |
| 本机连接能力（条件行） | 例如“本机电脑控制”，及注册/可用/权限状态 | 查看该能力的说明和已有权限/设置入口 | 从客户端能力 manifest 和注册状态来，不硬编码某个产品的能力名 |
| 管理连接 | 低强调文字入口 | 打开与当前来源匹配的连接管理界面 | plugin 来源可复用现有插件管理；独立 MCP 来源需要对应设置承载，不能误导为“插件已启用即已连接” |

连接详情不直接展示命令、env 值或凭据。配置来源展示安全别名/相对位置。
Context 的工具占用回答“模型请求里有什么”；Connectors 回答“连接本身是否可用”。两处通过相同 connector/tool ID 关联。
重新加载必须是明确操作，不能因展开分组而发 MCP reload 或触发新进程。

## 6. Outputs：逐行设计

统计范围固定为**当前会话跨所有轮次的累计产物**，不是只显示最后一轮。
根页面按最近生成/更新时间倒序展示 5 项；“查看全部 N 个产物”进入完整目录。
同一工作区文件的多次更新合并成最新行，详情保留来源轮次及历史；不可变产物仅按明确 lineage 合并最新版本。
不能按 basename 合并不同目录的文件；没有 lineage 的独立产物保持独立。
N 统计逻辑产物，不是写入次数，也不是整个工作区文件数。新一轮没有产物时保留已有列表。

参考验证（2026-11-15）：实际查看 Claude 的“P1-F ui_preview 只读验收”。根列表显示 5 项，
Show more 展开到 9 项；其中报告、replay-summary.json 与多张截图可在第一轮交付消息中找到，
当前最后一轮仍保留这些条目。这证明观察到的列表跨轮保留；不能据此推断 Claude 内部索引实现、
所有写入的收录规则或精确排序。上面的排序和去重是本产品明确采用的规则。


| 行 | 展示 | 点击行为 | 数据与约束 |
|---|---|---|---|
| 产物行（根页面最多 5 条） | 类型图标、文件/产物名、生成/更新标记；必要时显示失效状态 | 工作区文件进入 Files 并选中；不可变产物进入已有资产/预览详情 | 必须有来源事件及可靠的生成/更新证据 |
| 查看全部 N 个产物 | 可分页总数 | 打开当前会话产物目录，按最新产出排序，可查看同名产物历史版本 | 不能只用当前已加载 timeline 计算完整 N |
| 无产物 | “尚无生成产物” | 无假按钮 | 读取过的文件、上传的输入附件、失败写入不算生成产物 |

产物身份区分 live workspace file 与 immutable artifact revision。同一路径的更新可合并到最新行，
但不得把不同 workspace、无明确 lineage 关联的 immutable revision 或仅同名文件混为同一产物。
现有 assetRefs 可复用为预览引用，不能直接改名为 Outputs 的完整数据源。

## 7. Changes：逐行设计

| 行 | 展示 | 点击行为 | 数据与约束 |
|---|---|---|---|
| 工作区变更概览 | “N 个文件 · +A −D”；明确“相对 HEAD” | 进入 Changes 工具根页 | 这是工作区净变更，不标成“本会话修改” |
| 文件预览行（最多 3 条） | 相对路径、状态图标、可用时的新增/删除行数 | 进入 Changes 并选中对应 diff | 二进制、未跟踪或无法统计项显示相应状态，不能捏造 0 行 |
| 查看全部变更 | 总文件数 | 进入完整 Changes 列表 | 与概览使用同一 workspace snapshot |
| 非 Git / 无变更 | “未使用 Git” / “工作区无变更” | 非 Git 不提供假的 diff；仍可进入 Files | unknown、错误、加载中与 clean 必须区分 |

turn diffstat 可在任务详情显示“编辑类工具本轮写入”，不能跨轮求和代替净 Git diff。
当前本地 GitWorkingTreeReviewProvider 可保留作本机适配器；远端 Runtime 必须提供等价只读快照和 diff，
不能在客户端运行远端路径下的 git。参考图中的 Create PR 留给独立的 PR 工作流，不在此处挂空按钮。

## 8. Background tasks：逐行设计

| 行 | 展示 | 点击行为 | 数据与约束 |
|---|---|---|---|
| 活跃任务（根页面最多 3 条） | 命令的可读摘要、运行/停止中、耗时 | 进入该 job 的只读详情与日志；不切换主对话 | 以当前 Runtime registry 的 owner 校验结果为准 |
| 停止操作 | 独立的停止按钮，有 tooltip/键盘名称 | 复用已有 cancel API；收到请求后显示“停止中”，等待权威终态 | 行点击不隐式停止；不能用进程名 kill，也不请求模型替用户操作 |
| 最近完成 | 完成/失败/取消图标与时间摘要 | 查看相应日志和退出结果 | 不把 job_wait 返回或 turn 结束当 job 终止 |
| 查看全部任务 | 运行数、历史数 | 完整任务页，区分活跃与历史，支持分页 | 最近 20 项不是完整历史计数 |
| 历史状态未知 | “上次运行记录，当前状态未知” | 可查看已保存日志；没有 live owner 时不提供停止 | Runtime 重启/断连不能伪装成任务已完成或已取消 |

本阶段 Background tasks 的明确对象是后台命令 job。子 Agent、workflow、Automation 不冒充 job，
后续如统一任务类型，必须增加 typed task kind 和各自稳定身份。

### 8.1 从输入框上方迁移

Session rail 上线时，macOS workspace 移除 `ConversationDetailView` 输入框上方的
`BackgroundJobsEntry`，由 rail 的 Background tasks 统一承接列表、停止、详情与日志。
复用现有 `ConversationViewModel.backgroundJobs` / `BackgroundJobsModel`，不复制数据模型或轮询。
迁移与可用 rail 同批交付，在 rail 完成前不先移除现有入口；没有 rail 的 iOS 保留原入口。

`BackgroundContinuationBanner` 是“当前轮等待后台结果”的会话控制提示，与 job 列表不同：
该提示的等待状态与取消当前轮操作整合到既有运行/停止状态处，不另留一块输入框上方的任务面板。
待审批、提问、计划确认等必要交互仍按各自会话流程承载，不误删为后台任务。
rail 收起时，顶部 Session rail 按钮显示简洁的活跃任务数量/异常标识，点击打开该组；
不强制展开 rail，也不把任务面板重新塞回输入框上方。

## 9. 点击目的地与返回

- 简短信息/操作菜单：Environment、连接概要、Context 用量详情采用轻量弹层。
- 长目录和任务详情：在 Inspector 内进入有返回的详情页；不用弹窗套弹窗。
- 文件/diff：切换已有 Files/Changes 并选中目标，关闭工具恢复 rail；保留原组展开和滚动状态。
- 悬浮 rail 中的短详情尽量在浮层内部导航，避免外部点击关闭父浮层时连带丢失子详情。
  如需打开独立 sheet，由外壳先结束 transient popup，再呈现 sheet，不能留下不可操作的遮挡。
- 本阶段可复用只读详情与工具切换；“定位到消息”“消息反向定位 rail”留到第四步，来源 ID 现在就保存。

## 10. 更新与异常

一个会话级 coordinator 统一加载六组数据，不让每组各建轮询或 WebSocket。
作用域至少包含 server_id、客户端连接 generation、conversation_id 和 workspace_id。
切换会话/Runtime 后取消旧请求，迟到响应不能写进新会话。

- 首次可见：加载摘要；列表按点击懒加载。一次失败不清空其余五组。
- rail 实际可见且有活动：复用现有事件，约 3s 合并刷新；空闲降频，Git 用缓存摘要，不逐 token 计算 diff。
- 折叠：保留并更新头部摘要，暂停长列表细节请求。未展开的新异常只更新摘要，不强制展开。
- 隐藏：停止 rail 专属轮询。第二步会保留隐藏视图，所以不能仅靠 onAppear/onDisappear 判断可见性，必须由外壳传入实际 presentation。
- 后台任务：复用 BackgroundJobsModel 的归属/刷新机制，不再建第二套轮询；关闭 rail 不会停止任务。
- 每组统一区分 loading、ready、empty、stale、unavailable、error。失败保留上次值并标“未更新”，不能退成 0。
- 不支持：显示“服务端需升级”，开发期作为后端必补项；不是删掉必需分组的理由。

## 11. 实现落点与顺序

1. 本文 UI、统计口径与后端提案已确认。后端摘要契约和任务历史已开始落地，尚未达到整体交付条件。
2. code-agent 补齐只读快照、请求级归因/来源、连接清单、产物目录、工作区变更和任务历史语义；先契约测试。
3. AgentKit 增加 typed DTO 与 RuntimeClient facade；复用技能管理、资产预览、jobs 的已有能力。
4. Talkify 实现 SessionRailModel、六组视图、独立组展开状态及目的地路由，接入现有 MacWorkspaceSessionRail。
5. 端到端验收，再进入各入口深化与第四步双向联通。

## 12. 验收条件

- 六组可独立收起/展开；收起仍有真实摘要；停靠/悬浮切换不重置状态。
- 没有把“未知”显示成 0、没有把 inventory 数量当已加载数、没有把配置存在当连接成功。
- 用量显示测量时间；估算带标识；压缩待测量与精确 0 正确区分。
- 历史加载不完整时 Outputs 和任务总数仍来自服务器完整投影，而非当前时间线长度。
- 远端 workspace 的目录、变更、日志始终由所属 Runtime 读取；Finder 只操作已确认本机可访问的路径。
- Changes 数值与同一快照的 diff 一致，不使用 turn diffstat 充数。
- 切换对话、重连、切换 Runtime、关闭浮层后不发生串数据或重复轮询。
- 组展开、列表展开、读取快照不会启动模型、执行工具、重连 MCP 或修改工作区。

## 13. 客户端首版落地（2026-11-15）

AgentKit 提供 `SessionRailReading`、六组 DTO、HTTP facade 与共享 `SessionRailModel`。
每个请求固定会话与 Runtime origin；摘要另校验 schema、server/instance/workspace 身份。
动态路径段逐段编码，来源和 diff 使用打开时的 snapshot ID；409/410 提示返回刷新，不替换成当前磁盘内容。
单组 data 解码失败只使该组报错；未知计数保留 null，未知状态不会被当作有效数据。

macOS 的停靠与悬浮都使用 `SessionRailView`。根页不新增标题栏，六组独立折叠，偏好持久化；
详情在 rail 内前进/返回，切换会话或 Runtime 清理旧详情。隐藏或应用非活动时停止 rail 专属刷新。
当前为可见时受控全量读取：有活动 5 秒、空闲 20 秒；不是服务端增量投影接口。

已接 Environment 只读详情、Context 测量/组成/加载来源/工具检索、Connectors 明细、
Outputs 目录分页与版本详情、Changes 快照 diff，以及任务历史/日志/原有停止操作。
产物资产交给现有预览入口；HTML viewer 使用原有认证读取与安全校验，在隔离 WebView 展示。

后台任务区只在当前会话收到可用 rail 任务数据后从输入框移走；旧 Runtime 不支持接口时保留原入口。
任务等待续跑控制进入 rail，顶部入口显示活动数量。iOS 继续原入口。

验证：8 个新增契约/竞态测试通过；包含真实 Go 路由响应、单组错误、null/0 区分、认证、路径编码、
请求前后 Runtime 切换和会话迟到响应。相关回归 172 项，5 项跳过，其余通过。
macOS `Talkify-MacDirect / Debug-MacDirect` 与 iOS Simulator `Talkify / Debug` 完整构建通过。
原生示例验收窗口验证六组排版、连接详情、产物目录/详情与返回后折叠状态；不等于用户真实会话的端到端验收。
后台任务时间线分组的两条既有文案断言在原始 HEAD 临时副本中同样失败，本批未改动。

后续：外部产物声明与服务端增量投影仍需补齐；独立 MCP 管理、真实会话与远端验收、更多入口联通继续深化。
完整 `session_rail_v1` 仍保持关闭，不把本批页面接入解释为整个 Session rail 计划已全部完成。

### 首轮页面验收修正

六组标题使用统一的整行按钮，标题、空白与摘要区域均可展开/收起；保留键盘和辅助功能语义。
Context 根页显示上次测量占用百分比、已用 tokens / 对应模型窗口容量，各组成显示估算数量与百分比。
自动压缩预留仅在同一窗口有有效 compact_threshold 时计算；Free space 扣除已测占用与已知预留。
没有用量测量时显示“尚未测量”，没有窗口容量时不计算百分比。旧测量与当前模型窗口不一致时明确提示。
输入区的后台任务迁移保持现状。

## 14. Context 交互与旧轨迹移除

本批完成 Context 第二轮交互，以及轨迹清理、后台任务行补齐：

- MCP / System tools 可按需展开前 8 项预览，进入完整可搜索目录；工具定义来源固定到请求快照。
- Skills、System prompt、Memory 等组成进入各自来源列表，正文读取加载版本。
  Skills 将请求中的技能正文、注入的技能索引和当前配置目录分开展示；当前目录仅在明确点击后读取。
  目录 API 的 workspace_id 使用独立命名空间，以 Runtime origin、session_id 与 resolved 作用域核验归属。
- Context 详情提供预算、自动压缩阈值、历史压缩结果及显式压缩操作。
  新 typed POST 固定 Runtime origin，在请求前后校验；与输入框共用会话级互斥，运行中不可压缩，
  压缩后标明等待下次测量，不将旧测量伪装成压缩后的精确用量。
- Environment 的管理入口、Skills 的管理入口进入宿主已有设置，分别打开运行环境、自定义页面。
- 删除会话顶部、原生页脚、Web 菜单中的旧轨迹入口与专属 Inspector。
  Web 不再序列化逐调用详情；时间线不再重复聚合思考正文和执行工具列表。
  供模型标识、费用和耗时使用的轻量请求/用量记录保留。
- 后台任务行右侧显示运行时长、状态，运行中显示独立停止按钮；首次点击可先确认 registry owner。
  复用现有取消协议与 pending/terminal 语义；确认期间禁止重复操作，失败保留错误提示。
  任务终态优先于另一份列表中的旧运行状态，终态到达后移除停止按钮，显示服务端确认耗时。
  秒级计时局限于可见任务行，不用计时触发 rail 或对话历史刷新。

验证：相关回归 188 项通过；另有 3 项旧文案测试的 4 条断言在未修改基线同样失败，单独排除，未改断言。
macOS 与 iOS Simulator 完整构建、Web TypeScript 检查与资源构建通过。
独立原生示例窗口验证已加载来源、按需技能目录、压缩后待测量、停止中禁用按钮及最终取消状态。
这仍不代替用户真实会话与远端 Runtime 的端到端验收；外部产物声明和服务端增量投影未在本批改动。
