# chater Provider 管理迁移到 Runtime HTTP /v1/providers — 需求研究（Stage ③）

> 阶段：需求研究（只读，不实现）
> 范围：desktop（macOS Direct，codeagentd daemon）；iOS embedded 不在本阶段
> 前置设计：design-providers-grouped-config.md（runtime 已定案）、design-connection-injection-channel.md、design-runtime-models-wire-v2.md、prd-connection-flattening-v1.md

---

## 1. 现状：chater 的 provider 管理流

### 1.1 数据模型与存储

- **连接 = `ProviderConnection`**（Talkify/Providers/ProviderConnectionStore.swift:60-90）：`id / providerID / displayName / transport / authentication / baseURL / models: [ProviderModel] / isEnabled / allowsInsecurePrivateNetworkHTTP / modelSource`。
- **唯一事实源 = `ProviderConnectionRegistry`**（UserDefaults 本地存储，`ProviderConnectionStore.registry`，构造注入 `defaults`）。
- **目录 = `UnifiedModelCatalogStore`**（`catalog`，UserDefaults）聚合已启用连接的模型 → `[UnifiedModelDescriptor]` → `modelSettings.applyUnifiedCatalog`（Composer 可用模型）。
- **凭证 = `CompositeCredentialStore`**（第 78-88 行）：命名空间路由 `gateway → AppCredentialStore`（AuthManager token）、`llm → KeychainCredentialStore`（`KeychainCredentialStore(service: "com.objc.talkify.provider-credentials")`，第 80-82 行）。

### 1.2 写路径（save / remove / setEnabled / replaceModels）

- `save(connection, apiKey:isNew:)`（第 104-123 行）：`validate()` → 若 `.apiKey` 且传了 key，`credentialStore.set(Credential(kind:.bearer), for: .llm(id))` 写 Keychain → `registry.upsert` → `didMutateRegistry()`。
- `remove(connectionID:)`（第 146-153 行）：删除 Keychain 凭证 → `registry.remove` → `didMutateRegistry()`。
- `setEnabled(_:connectionID:)`（第 160-163 行）：`registry.setEnabled` → `didMutateRegistry()`。
- `didMutateRegistry()`（第 256-259 行）：`reloadCatalog()` + `onStructuralChange?()`。
- `onStructuralChange` 由 AppContainer 注入（Talkify/AppContainer.swift:235）→ `stageProviderConfigurationApply()` → 生成 `GeneratedRuntimeProviderConfiguration`（YAML）+ `AgentRuntime.shared.configureProviderConnections` → 等待空闲后 `stop()` + 重启（apply loop，Talkify/AppContainer.swift:583-677，`ProviderRuntimeActivityPolicy` 判定阻塞）。

### 1.3 如何与 runtime 通信（desktop）

- **Daemon**：`CodeAgentDaemon`（Talkify/CodeAgentDaemon.swift）启动捆绑的 `codeagentd`（`Contents/Resources/codeagentd`），loopback HTTP/WebSocket（`127.0.0.1:<port>`），每次启动生成 256-bit `accessToken`（第 34、76-77、229-235 行），通过 `CODEAGENT_SERVER_ACCESS_TOKEN` 环境变量传给 daemon。
- **HTTP 客户端**：AgentKit `RuntimeHTTPClient`（复用不变），对每次请求注入 `Authorization: Bearer <token>`，从 `CredentialStore.resolve(credentialTarget)` 取 token；desktop 路径走 `RuntimeServerCoordinator.injectBearerToken(for:token:)`（Talkify/AppContainer.swift:392-395，token = `daemon.accessToken`）。
- **注册为外部连接**：`ensureDaemonStarted()`（Talkify/AppContainer.swift:361-416）把 daemon 注册为 `RuntimeServerConnection.external(id: "talkify-local-daemon", authentication: .bearer)` 并设为 active；active 连接经 `runtimeServers.activeContext` 提供 `RuntimeServerActiveContext`（含 `modelCatalog`）。
- **模型目录消费**：`GET /v1/runtime/models` → `RuntimeServerModelCatalog`（v2：schema `runtime-model-catalog/v1|v2`，`connections[]` 分组 + `unavailable_reason`）→ `RuntimeServerActiveContext.modelCatalog` → `publishRuntimeServerModels`（已修复，见 Wave 3 提交 a327972，AppContainer.swift:430-466）从 `connections[]` 提取扁平 `[UnifiedModelDescriptor]`。

### 1.4 双数据源现状

- 本地 `ProviderConnectionRegistry`（UserDefaults）与 runtime `settings.json` 是两份数据；desktop 当前靠「本地改 + 重启注入」推进（`stageProviderConfigurationApply` → 重启用 configYAML/connectionsJSON 注入）。
- HTTP 面目前只读目录（`/v1/runtime/models`），无配置 CRUD。这正是 runtime 设计要消除的「客户端各存各的」。

---

## 2. 需求：chater 通过 /v1/providers 管理（desktop）

### 2.1 操作映射

| 设置页操作 | 当前实现（ProviderSettingsView / Store） | 改为 HTTP |
|---|---|---|
| 添加连接（`ProviderEditorRequest.create`） | `store.save(connection, apiKey:, isNew: true)` | `PUT /v1/providers/{id}`（upsert） |
| 编辑连接（`.edit`） | `store.save(connection, apiKey:, isNew: false)`（整体替换） | `PUT /v1/providers/{id}`（模型数组整体替换） |
| 删除连接 | `store.remove(connectionID:)` | `DELETE /v1/providers/{id}` |
| 启用/禁用（`setEnabled`） | `registry.setEnabled` → 注入 | **存在 = 启用；删除 = 禁用**（runtime 设计 §5 映射）。UI 的 toggle 需要映射为「模型存在性」而非独立布尔 —— 需要决定禁用语义：保留定义但移除模型，还是 PUT 不带该 provider？**需 runtime 澄清** |
| 默认模型 | `catalog.setDefaultModel(id:)` → `onStructuralChange` | 当前 `/v1/providers` 无 default_model 字段；沿用注入/现有目录机制（保持现状） |

**关键转变**：`ProviderConnectionStore` 从「本地唯一事实源」降级为「HTTP 结果的本地缓存」或直接移除改为每次 HTTP 查询。`ProviderConnection`（本地 DTO）仍可作为 UI 模型，但**持久化落到 runtime settings.json**。

### 2.2 写后刷新（stored-but-not-yet-effective）

runtime 设计 §4.2：PUT/DELETE 落盘后调 `Reconfigure`（热生效）；结构性变更（api 类型变）需重启。设计承诺「落盘→生效失败时回滚磁盘 + 返回明确错误，或标记『已存未生效需重启』」。

chater 需求：
- **成功 + 已生效**：`PUT`/`DELETE` 返回后 `re-GET /v1/providers`（刷新本地缓存）+ `GET /v1/runtime/models`（刷新目录，UI 立即反映新分组）。
- **成功但需重启**（结构性变更）：runtime 返回「已存未生效」标记 → chater UI 显示「配置已保存，重启后生效」，不把半生效配置当成可用。**需 runtime 响应 DTO 增加 `effective`/`requires_restart` 字段**（或复用现有 `Reconfigure` 返回值语义）。
- **失败（回滚）**：runtime 返回明确错误，chater 显示错误 + 不更新本地缓存（保持磁盘/运行态一致）。

### 2.3 定义 vs 凭证的拆分

- **定义**（base_url / api / credential ref / headers / models[]）走 `HTTP /v1/providers`（非 secret，GET 剥离 headers/credential 细节）。
- **凭证值**（API key）继续走 **secretsJSON / Keychain 注入**，不经过 HTTP：
  - `/v1/providers` 的 `credential` 只是引用（`{namespace, name}`），值仍在 Keychain（`KeychainCredentialStore`）+ 经 `ensureStarted`/`reconfigure(connectionsJSON:secretsJSON:)` 注入（Wave 3 已接线）。
  - 这与现有 `save(connection, apiKey:isNew:)` 一致：**定义写 HTTP，key 写 Keychain**。建议保留 `credentialStore.set` 调用，仅把 `registry.upsert` 换为 HTTP PUT。
- **一致性**：PUT 时 chater 先写 Keychain（值），再 PUT 定义（引用）；失败回滚需考虑「Keychain 已写但 HTTP 失败」的顺序（先 PUT 后写 Keychain，或 PUT 支持 pending）。

### 2.4 鉴权：Bearer token 从哪来

- desktop：`CodeAgentDaemon.accessToken`（`CodeAgentDaemon.swift:34`），经 `RuntimeServerCoordinator.injectBearerToken(for: "talkify-local-daemon", token: daemon.accessToken)`（AppContainer.swift:392-395）存入 runtime credential store。
- 实现：chater 直接读 `CodeAgentDaemon.shared.accessToken`，或复用 `RuntimeHTTPClient`（它对每次请求从 `credentialStore.resolve(credentialTarget)` 取 bearer）。GET/PUT/DELETE `/v1/providers` 都用该 token（runtime 设计 §4.3：均 Bearer）。

---

## 3. 范围边界

**IN SCOPE（本阶段）**
- macOS Desktop（MacDirect scheme）设置页：「提供商」页从本地 UserDefaults 改为 HTTP `/v1/providers`。
- 定义写 HTTP + 凭证值写 Keychain 的拆分；写后 re-GET 刷新 UI。
- `ProviderConnectionStore` 降级为 HTTP 结果缓存（或移除本地持久化）。

**OUT OF SCOPE（本阶段，保持现状）**
- **iOS embedded**：无磁盘 `<root>/.codeagent/settings.json`，无 `/v1/providers` 写路径（runtime 设计 §4.4）。保留「本地 registry + `buildConnectionsJSON`/secretsJSON 注入」为唯一路径。
- 运行时注入通道（`buildConnectionsJSON`、3-arg `reconfigure`、`ProviderRuntimeActivityPolicy`、apply loop）：desktop 若 HTTP 写路径取代 registry 写，这些是否仍需要取决于「HTTP 写是否已含 Reconfigure 生效」。**desktop 热生效后，apply loop 可能不再需要**（runtime 自己 Reconfigure），需在实施时评估收敛。
- MCP（独立 `.mcp.json`）、gateway web_search（web 段）：不合并（runtime 设计 §8 范围边界）。
- runtime 端的 `/v1/providers` 实现：runtime 已定案，chater 只消费。

---

## 4. 风险

| 风险 | 说明 | 缓解 |
|---|---|---|
| **迁移：现有 UserDefaults 连接 → settings.json** | 存量用户 `ProviderConnectionRegistry`（含 Wave 3 已存的 deepseek 等）需一次性迁移到 runtime providers 段，否则 HTTP 写路径看不到旧连接 | 启动时检测：若 registry 非空且 settings.json providers 空 → 把连接 PUT 到 `/v1/providers`（复用 `buildConnectionsJSON` 的映射逻辑）；标记迁移完成 |
| **双写过渡期** | 迁移完成前本地 registry 与 HTTP 都可能被写，容易不一致 | 一次性迁移 + 迁移后 registry 降级只读缓存；避免双写窗口 |
| **凭证值不在 HTTP** | GET `/v1/providers` 剥离 credential 值 → chater 无法从 HTTP 知道「该 provider 是否已配 key」 | 用现有 `credentialExists(for:)`（读 Keychain）判断；`/v1/runtime/models` 的 credential status 可作为辅助 |
| **重启 vs 热生效** | 结构性变更（api 类型）需重启；用户预期「保存即生效」 | UI 明确「已保存未生效」状态；依赖 runtime 返回 requires_restart 语义 |
| **daemon 离线/未启动** | 设置页在 daemon 不可达时（未启动/崩溃）无法读写 | 设置页显示「Runtime 不可达」降级态；回退到 embedded？——注意 desktop 失败回退 embedded 的现有逻辑（ensureDaemonStarted 第 407-413 行）可能把 active 切走，需保证设置页感知 active 后端 |
| **锁/并发** | runtime 跨进程文件锁保护 settings.json；chater 只经 HTTP 单写入者，风险主要在 runtime 侧 | 无 chater 侧并发写；但迁移期间 CLI grant/verify 可能并发写 settings，依赖 runtime 文件锁 |
| **DELETE 悬空引用** | 删除被 default_model 引用的 provider → 拒绝或回退（runtime 设计 §7②） | chater 捕获 4xx 并提示；回退默认模型逻辑在 runtime |

---

## 5. 需要 runtime/AgentKit 澄清的点

1. **`requires_restart` / `effective` 语义**：PUT 响应当区分「已生效」vs「已存未生效」——chater UI 依赖它。
2. **`isEnabled` 的磁盘映射**：providers 段存在即启用；禁用是否 = 移除 provider（会丢模型数组）还是另有字段？影响 `setEnabled` 的 UI 映射。
3. **GET `/v1/providers` 响应形状**：是否含 models[] 完整数组 + credential 状态（`configured/missing`）——chater 设置页展示「已连接」徽章依赖它。
4. **PUT 时 credential ref 校验**：PUT 先写 Keychain 还是先 PUT？设计 §7②「ref 存在性校验」决定顺序。
5. **迁移路径**：`codeagent migrate` 是否已把扁平 models → providers；chater 启动迁移是否与它冲突。

---

## 6. 实施顺序建议（后续阶段）

1. **只读对齐**：chater 设置页读 `GET /v1/providers` + `GET /v1/runtime/models` 展示（替代本地 registry 读）——先读后写，风险最低。
2. **定义写路径**：PUT/DELETE 落到 HTTP；凭证仍 Keychain；保留 `buildConnectionsJSON` 注入（embedded 兼容）。
3. **迁移 + 缓存降级**：一次性迁移 UserDefaults → settings.json；registry 降级为缓存。
4. **评估收敛**：desktop 下 apply loop / `stageProviderConfigurationApply` 是否仍需要（HTTP 写已触发 runtime Reconfigure）。
