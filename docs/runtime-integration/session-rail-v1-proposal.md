# Session rail v1：code-agent 补齐提案

状态：分阶段实现中，完整 capability 尚未启用。日期：2026-11-15。
配套 UI：[Session rail 完整设计](../session-rail-design-spec.md)。

目标：六组的事实由 Runtime 负责提供，AgentKit 负责 typed client，Talkify 负责展示与用户操作。
完整性包括本机与远端 Runtime；不从当前已加载聊天页面、工具名称前缀或配置文件存在性猜测数据。
设计确认后，code-agent 已开始落地；以下各节仍包含待实现要求，不能整体视为已支持。

### 当前实现进度

- 已注册 `GET /v1/conversations/{id}/session-rail`，复用现有认证和 envelope，返回六组状态。
- Environment 已接 Runtime、会话工作区、execution policy、needs_rebind、可用的 managed worktree 和 Git HEAD 信息。
- Context 已复用现有快照，区分 fallback 容量与 legacy 无来源测量；没有伪造测量时间或细分归因。
- Background tasks 已合并会话持久化 job bracket 与当前 registry，提供有界摘要。
- 已新增 `GET /v1/conversations/{id}/jobs/history?cursor=...&limit=...`，支持完整已记录历史分页；
  跨会话游标拒绝，目录排序/成员变化时返回 409 要求刷新。
- 原 `/jobs` 增量补充真实 `started_at` / `finished_at`；原停止协议保持兼容。
- Connectors 已接当前 workspace 的有效 MCP 来源、SDK 连接存活状态、工具注册/可用数量及会话注册的本机工具。
  新增 `/connectors` 和 `/connectors/{connector_id}`；读取不会初始化工作区或启动 MCP。
- Changes 已接相对 HEAD 的净差异、分支/detached/unborn、重命名、二进制、冲突、子模块和未跟踪状态。
  新增 `/changes` 和 `/changes/{snapshot_id}/{file_id}`，根摘要仅预览 3 个文件。
- 初始化和 MCP 热重载统一使用相同合并路径，修复 reload 漏掉插件 MCP 的问题。
- Outputs 已接跨轮写入/预览证据目录、分页、来源记录及旧数据的不完整标识；根摘要预览 5 项。
- Context 已记录最终请求中的估算组成、来源版本、工具定义及 origin，并将成功测量与组成绑定到同一 invocation。
  最新请求尝试单独标识；Connectors 的暴露数从有成功响应的请求记录计算，缺证据仍为 null。
- 来源详情读取 checkpoint 保存的加载版本，版本逐出返回 410，不读取磁盘新内容冒充旧版本。
- 外部命令/第三方工具产物声明、投影增量缓存仍待补齐；完整 `session_rail_v1` 尚未启用。
- AgentKit 已接类型化 DTO/facade 与来源隔离；Talkify macOS 已接六组首版，可用任务数据加载后迁移输入框任务入口。

当前任务历史统计范围为“当前会话已记录任务 + 当前实例 live registry”；仅有 started、无终态且无 live owner
的旧任务为 unknown。没有 registry 时 active/stopping count 为 null；未知不冒充零。
SQLite 使用按 kind 查询的持久化 bracket；旧 event store 的兼容回放及完整历史投影的增量缓存仍待完善，
客户端首版仅在 rail 可见且应用活动时按 5 秒（活动）/20 秒（空闲）受控读取，不宣称已有服务端增量订阅；正式高频刷新仍需先补齐投影缓存。

本批验证：`go test -race ./internal/server ./internal/jobs`、`go vet ./internal/server ./internal/jobs`、
`go build ./...` 通过。包含真实 SQLite 重开、超过 20 条记录、停止确认、分页和会话隔离测试。
扩大到 runtime 包的 race 测试有 5 个既有失败，在未修改 HEAD 的临时副本中同样复现：
4 个 Flux workflow 测试及 `TestEventStoreEmitterCapsToolStreamPersistence`；未在本批更改这些测试。

第二批验证：server/mcp/jobs 全包 race、conversation 包、Runtime 的 ConnectorSnapshot / WorkspaceMCP /
Job / Background 相关 race、改动包 vet 和所有构建目标通过。新增真实 SDK 连接/断连、插件 reload、
客户端会话隔离、实际 Git 合并冲突及本地子模块测试。

第二批边界：

- `connected` 仅证明 SDK 会话未关闭，`health=not_probed`；不额外 ping，不把启动报告永久当在线状态。
- 目录可见数量与实际请求暴露数量分开；第三批已从成功响应对应的请求计算暴露数，附带快照 ID，缺少证据时仍为 null。
  本机能力仅证明已注册，权限/实际可用性未知；已禁用插件的完整配置来源诊断仍待补齐。
- Git 快照暂要求会话目录为仓库/工作树根；嵌套子目录返回 `workspace_not_git_root`，避免读取父项目的变化。
- Git 读取限定 5 秒、每次命令输出上限 8 MiB；每 mux 最多保留 8 个会话快照，2 秒摘要缓存，5 分钟详情有效期。
  快照被新版本替换、逐出或过期时，详情返回 409 `stale_snapshot`；旧详情不重读当前文件。
- 行数仅累计可统计文本项，二进制/未跟踪/冲突/子模块以 null 行数和 `uncounted_files` 明确标识。
  根摘要与详情使用同一个 snapshot ID；同样内容不会仅因 observed_at 更新而改变 Git revision。

第三批补齐了 Outputs/Context 的事件证据与查询，当前范围是已记录写入和预览产物，不宣称捕获所有外部进程的文件系统写入。
旧会话仅回收可证明的 diffstat 路径写入，标为 `legacy_incomplete`；不会把截断的文件总数或只读资产当完整目录。
Context 的测量与组成绑定同一请求；最新失败尝试另列 ID，不替换上一次测量。来源正文按 checkpoint 中的加载版本读取，逐出后返回 410。

第三批验证：server/session/mcp/conversation/jobs 全包 race、agent 包 race（仅排除已在未修改 HEAD 复现的旧
`TestRunTurnWithAssetsPreservesUserGatewayAsset`）、相关 Runtime 回归通过；改动包 vet 和全部构建目标通过。
新增产物引用不改变模型图像输入。客户端首版已接入，产物声明及增量缓存仍是完整能力开启前的工作。

## 1. 复用，不另起语义

| 复用接口/事实 | 用途 | 不能替代的内容 |
|---|---|---|
| GET `/v1/runtime/info`、capabilities | Runtime 身份、版本、profile、能力 | 不等于客户端所在设备 |
| GET `/v1/conversations/{id}` | 会话工作区、隔离策略、worktree | 不接受 UI 传入另一个目录覆盖会话范围 |
| GET `/v1/conversations/{id}/context` | 保留旧预算、测量与压缩契约 | structure 的总估算和字符量不是细分 tokens |
| `model_request` | 上次实际暴露的工具名、消息数、system/tools 字符量 | 缺少每工具归因、schema 成本、连接状态 |
| `skill_loaded` | 证明某技能曾成功加载（服务端有 source/version） | 不能证明清理/压缩后其正文仍在上下文；客户端事件还需保留 source |
| GET `/v1/runtime/skills?session_id=` | 有效技能库存及来源 | 不等于当前加载正文 |
| GET `/v1/runtime/plugins` | 插件来源和关联 MCP 名称 | enabled 不等于 connected |
| GET `/v1/conversations/{id}/assets/{asset_id}/preview|content|blob` | 受会话约束的资源读取 | 没有完整 Outputs 目录，也不能直接区分读入与生成 |
| workspace Git branch list | HEAD、dirty、文件计数 | 没有工作区新增/删除行数和远端 diff |
| terminal turn 的 `diffstat` | 本轮编辑工具写入事实 | 逐次累加，可能截断，不能当作 Git 净变化或完整产物清单 |
| GET `/v1/conversations/{id}/jobs` | 全部 live jobs 和最多 20 个最近终态 | 不是完整历史分页；不能由返回长度推断历史总数 |
| POST `/v1/conversations/{id}/jobs/{job_id}/cancel` | 复用 owner 校验与停止协议 | 202/停止请求不等于已经停止 |
| GET `/v1/jobs/{id}/events` 与 stream | 单任务日志、回放 | 不为 rail 的每一行都打开一条流 |

## 2. 新增只读摘要入口（P0）

建议：GET `/v1/conversations/{id}/session-rail`。
能力名建议：`session_rail_v1`。仅在必需分组的语义实现完成后宣告；各细项支持情况仍独立返回。
使用现有 `{trace_id, code, msg, data}` envelope，不创建第二套认证或 Runtime URL 解析路径。

摘要契约建议：

```json
{
  "schema": "session-rail/v1",
  "server_id": "server_opaque",
  "runtime_instance_id": "instance_opaque",
  "conversation_id": "session_opaque",
  "workspace_id": "workspace_opaque",
  "snapshot_id": "snapshot_opaque",
  "generated_at": "2026-11-15T08:00:00Z",
  "sections": {
    "environment": {"state": "ready", "revision": "env_1", "observed_at": "2026-11-15T08:00:00Z", "data": {}},
    "context": {"state": "ready", "revision": "context_1", "observed_at": "2026-11-15T08:00:00Z", "data": {}},
    "connectors": {"state": "ready", "revision": "connections_1", "observed_at": "2026-11-15T08:00:00Z", "data": {}},
    "outputs": {"state": "ready", "revision": "outputs_1", "observed_at": "2026-11-15T08:00:00Z", "data": {}},
    "changes": {"state": "ready", "revision": "git_1", "observed_at": "2026-11-15T08:00:00Z", "data": {}},
    "background_tasks": {"state": "ready", "revision": "jobs_1", "observed_at": "2026-11-15T08:00:00Z", "data": {}}
  }
}
```

上面的空 data 仅演示 envelope，各分组必需字段见后文，不是允许以空对象交付的实现。
`state` 为 loading/ready/empty/stale/unavailable/error，error 使用稳定 code 和可读摘要。
有效的非 Git、零产物、零任务是有数据含义的 empty，不是 unavailable。

- summary 为六个来源的有界组合，不宣称全局原子事务；每组携带来源版本/时间。
- context 内部的测量和组成必须引用明确 request snapshot，不能用顶层 generated_at 冒充测量时间。
- scope 永远从会话加载；不提供任意 workspace_path 参数来绕过归属。
- 单组失败允许 200 + 对应组状态，其余组可用；认证失败、会话不存在不能伪装成局部空数据。
- server_id 标识数据源；runtime_instance_id 区分进程生命周期，特别用于 job live 状态。
- ETag/有界缓存可以复用，不在每次轮询里遍历完整事件和计算所有文件 diff。

## 3. 各组后端工作

### R1. Environment（P0）

摘要包含 Runtime 身份、workspace anchor、execution policy、worktree 状态、当前 HEAD。
路径须区分 display_path、runtime_cwd、可供宿主操作的 local access 信息；远端路径不冒充本机路径。
UI 根据连接类别与本机访问检查决定是否显示 Finder，不能仅判断绝对路径格式。

HEAD 支持 branch/detached/unborn/not_git/unknown。不把 managed worktree 路径当基础项目目录。
复用现有 branch 服务；不为只读信息调用 create/checkout。

### R2. Context 请求快照与来源（P0）

保留旧 `/context` 字段兼容；在 session-rail 摘要中提供扩展投影，或新增可独立协商的 context detail DTO。
要求从实际组装后的 model.Request 记录，而不是让 HTTP handler 重建一次可能不同的 prompt。
读取不触发模型调用、加载技能或重连 MCP。

必需字段：

- 当前 effective model 的配置身份、窗口容量及其来源（configured/fallback）、input/output budget、compact threshold。
- measurement：state、prompt_tokens（可空）、measured_at、turn_id、invocation_id/request snapshot ID。
- pending/current revision：是否有新输入/工具结果/压缩使上次测量不再代表待发送内容。
- breakdown：同一快照的 categories、estimated_tokens、estimation_method、total_estimated_tokens。
- 每项 category 互斥：messages、mcp_tools、system_tools、system_prompt、skills、memory_files；
  mcp_instructions/other 只在真正存在时返回。未知归因不制造精确数。
- sources：实际注入来源 ID、kind、scope、安全 display path、loaded revision/hash、当前是否仍在上下文、估算成本。
- tools：实际对模型暴露的工具、origin/connector ID、执行端、schema 估算成本、catalog/request revision。
- skills：可用技能、曾加载事实、当前仍在上下文的正文三个状态分别表示；复用已有 inventory 和加载事件。

建议按点击懒加载：

- GET `/v1/conversations/{id}/context/sources?kind=memory|skill|system&snapshot_id=...`
- GET `/v1/conversations/{id}/context/sources/{source_id}/content?snapshot_id=...`
- GET `/v1/conversations/{id}/context/tools?origin=mcp|system&snapshot_id=...&cursor=...&limit=...`

返回加载时的版本或明确告知版本已不可用，不把磁盘当前内容冒充模型已读内容。
全局指令可以在 workspace 外，但只允许通过实际加载过的 source ID 访问，不开放任意路径读取。

模型调用组装时需保留 source ledger：基础 prompt、APPEND_SYSTEM、项目指令、技能索引/正文、动态附加项。
provider 测量与 estimator 是两种量，不要求分类估算之和等于 provider 总量，更不能按比例伪造精确归因。
压缩/清理后更新 active_in_context；如果只能证明曾加载，显式 unknown。

### R3. 会话级连接清单（P0）

建议：GET `/v1/conversations/{id}/connectors` 和 GET `/v1/conversations/{id}/connectors/{connector_id}`。

字段至少包括 connector_id、kind（mcp/client capability）、display_name、scope、source、
status、last_checked_at、registered_tool_count、exposed_tool_count、safe error、tools revision。
status 区分 connected/connecting/disconnected/failed/disabled/unknown；缺少实时证据时使用 unknown。

清单范围为当前 Runtime + conversation.workspace 的有效合并配置，包括插件、宿主注入、
可选继承的 Claude 用户配置、code-agent 用户配置、项目配置和项目本机覆盖配置。
同名整项覆盖，优先级由高到低：`.mcp.local.json` > 项目 `.mcp.json` >
`~/.codeagent/.mcp.json` > 可选 Claude 用户配置 > 宿主注入 > 插件。
保留安全来源标识；其他项目、其他 Runtime 的服务不进入此会话清单。
code-agent 是执行 Runtime，不因它提供此 API 就额外伪造一个名为 code-agent 的 MCP server。
配置解析失败必须返回来源诊断；profile 禁止的 transport 标为不可用及原因，不能静默消失或算作已连接。
有效配置中的失败/停用服务仍展示；被同名覆盖的低优先级条目仅作为来源说明，不重复计数。
本机能力属于同组的独立 client capability 类型，仅展示实际 manifest 注册和权限证据支持的能力。

实现复用 WorkspaceInstance.MCPMgr/ToolReg 与客户端注册元数据，补只读快照接口。
当前 Manager.Report 是连接结果报告，不能原样永久当 heartbeat。
观察现有 instance，不因读取快照调用会初始化 MCP 的 Get/build 路径；没有 live instance 时显示对应状态。
模型可见工具必须来自实际有效 registry/filter/plan mode，不通过名称前缀猜测 origin。

管理与重连仍为独立操作。只读清单不返回 command、env 值或凭据；插件启用状态不能替代连接状态。

### R4. 完整 Outputs 目录（P0）

建议：GET `/v1/conversations/{id}/outputs?cursor=...&limit=...`，摘要带确切 total_count 与最近 5 项。
范围固定为完整当前会话，返回 `scope=conversation`、`sort=updated_at_desc` 和稳定分页游标。
以持久化事件/结构化写入报告/preview artifact 建立可分页投影，不依赖客户端历史加载范围。
新的轮次不清空历史产物；根摘要最近 5 项与完整目录采用同一逻辑产物口径。
同一 workspace + 规范路径的 live 文件合并为最新状态；不可变产物只有明确 lineage 身份时才合并为最新 revision。
旧 revision 保留供详情读取，total_count 统计逻辑产物，不把每次写入重复计数。
相同更新时间以稳定 output_id 排序；分页绑定目录 revision，变化时返回明确的新版本/刷新语义。

每项至少有 output_id、asset reference、kind、title、operation（created/updated）、
workspace identity、relative path 或 immutable artifact identity/revision、available/state、
source turn/call/event sequence、created/updated time、content mode（live_workspace/immutable）。

- 复用现有资产预览/读取协议及 UI preview 的 revision 绑定；不复制第二套大内容到摘要里。
- 明确区分 input、read/reference、generated/updated；无法确认的旧记录不能自动变成产物。
- 写入失败不入目录；纯读取的 asset 和上传附件不入 Outputs。
- shell 写文件的完整识别需要 Runtime 的结构化产物登记或明确产物事件，不能靠解析模型自然语言猜测。
- 文件删除、权限变化、产物版本失效要返回可读状态，不能悄悄打开其他同名版本。
- 版本去重按来源语义定义，不能只按文件 basename；历史 origin ID 保留，供第四步消息联通使用。

### R5. Runtime 工作区 Changes 与远端只读文件适配（P0）

建议：GET `/v1/conversations/{id}/changes`，以及基于 snapshot_id/file_id 的只读 diff 内容接口。
对比基准明确为当前工作区相对 HEAD（含 staged/unstaged，未跟踪项标识清楚）。

摘要包含 baseline、HEAD、snapshot_id、is_git_repository、文件计数、可统计行数、
二进制/无法统计项计数和前 3 个文件预览。不可统计的行数用 null，不假填 0。
文件列表与 diff/补充上下文行读取使用同一快照；过期快照返回稳定 stale-snapshot 错误或新版本标识。

Runtime 负责本机/远端统一事实，客户端复用 FileReviewProvider 适配器，不能把远端路径交给本地 Process。
若 Files 承接远端产物，还需会话范围的目录/文件只读接口，建议：

- GET `/v1/conversations/{id}/workspace/files?path=<relative-path>`：目录列表。
- GET `/v1/conversations/{id}/workspace/file?path=<relative-path>`：受限内容与类型信息。

复用 Runtime 的现有 workspace 路径解析、可见性和授权规则，防止越界/symlink 绕过；
资产读取仍优先使用已有 asset ID 接口。完整 Files 工具深化在第三步对应入口实施，不让 rail 产生一个空跳转。

### R6. Background tasks 摘要、时间与历史（P0）

复用现有 live jobs 和 owner cancel 机制，不重写控制面。

- jobs DTO 补充 started_at/finished_at、runtime instance identity 等时间/生命周期信息。
- 摘要中的 active_count、stopping_count、terminal_count 具有明确统计范围；不取 recent 数组长度充当完整总数。
- 建议 GET `/v1/conversations/{id}/jobs/history?cursor=...&limit=...` 读取持久历史；
  不把旧 `/jobs` 忽略的查询参数当成已支持分页，新增能力须协商。
- 存活状态来自 registry；历史 job 在重启后不在 registry 中时标记 live_state=unknown/unavailable，
  不宣称 canceled/completed；只读持久日志仍可查看。
- 返回来源 turn/call/job IDs 供现有日志页和第四步联通，停止仍要求 session+owner 匹配且 Runtime origin 未变。

## 4. 测试与交付门槛

- 会话/Runtime 隔离、空工作区、非 Git、远端路径、切换中的迟到响应均有契约测试。
- context 的 measured/estimated、未测量、压缩待测量、字段缺失不混淆；来源不重复计费或归类。
- MCP 配置存在但连接失败、插件启用但未加载、plan mode 减少暴露工具、客户端工具撤销均正确反映。
- UI read 不启动模型、技能读取、MCP 子进程或 shell/git 写操作。
- Outputs 在历史分页、重放、同名文件、重复事件、更新/删除、只读资源输入等情况下数量和身份正确。
- Changes 的净差异与本轮 diffstat 分开验证；未跟踪/二进制/重命名和过期快照有明确状态。
- 任务历史超过 20 条、停止与退出竞争、Runtime 重启、控制归属失配均有覆盖。
- 聚合数据按组部分失败；401/403/404 不被吞成 ready/empty。

建议实施次序：冻结字段和口径 → code-agent 契约/实现/包内测试 → AgentKit DTO/facade →
Talkify 六组与展开/路由 → 本机与远端端到端验收。分包验证遵守 code-agent 的 AGENTS.md，
不在本设计阶段直接执行全仓测试或更改业务逻辑。
