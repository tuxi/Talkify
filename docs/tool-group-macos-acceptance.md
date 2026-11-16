# macOS 工具组改版实施与验收记录

日期：2026-11-16。

设计基线：[工具组展示设计文档](tool-group-display-design.md)。本批只实施 macOS；iOS 展示未启用这套改版，等待 macOS 用户体验验收后再做。

## 已实现

- 桌面 Web 时间线保留正文、工具组与最终答复的原始顺序，执行完成时不再增加整轮过程折叠。
- 工具组与工具详情默认收起；用户展开/收起状态在追加工具、完成、分页与同会话重置时保留，并按会话和轮次隔离。
- 取消组最大高度、组滚动与组内追尾。列表自然进入对话布局；长输出使用最大 280pt、且不超过视口高度 40% 的独立滚动区；长输入头部最大 160pt、且不超过视口高度 30%，两者分别滚动。
- 普通工具类型图标与每行耗时已移除。保留组级执行指示、异常数、行状态和变更统计；思考行去掉左侧图标，文字与普通工具行对齐，展开箭头紧随标题。组标题取消左右内边距，与正文齐平。
- 工具行优先使用调用提供的操作描述；缺少描述的通用命令使用短命令预览，避免整列都显示“运行命令”。组头保持短动作概括，不拼入命令全文或思考原文。
- 命令、文件路径、查询范围等关键输入直接可见；输入与输出分别复制。巨型命令保留完整内容并在头部滚动；复制入口位于滚动区外，敏感参数检查覆盖完整命令。普通工具卡不再显示原始详情区。
- 运行中没有输出不显示空输出框；完成无输出、失败无输出分别给出明确文案；有效结构化结果、产物与资产不误判为无输出。
- 相邻同任务等待压缩为一条工具行，原始记录仍可查看，不再增加等待组的展开层级。
- 打开工具后暂停对话追尾；输出首次展开从开头阅读，用户滚到输出底部后可以跟随更新，向上阅读/选中文字时不抢位置。
- 完整输出入口复用 Inspector；按所属轮次解析唯一节点身份，避免后端复用 call_id 时打开较早轮次的记录。
- AppKit/TextKit 回退路径同步默认收起、无类型图标、独立输出滚动、复制与完整详情入口；保留旧式非活动组的导出/详情兼容行为。

## 计时口径与限制

桌面实时接收的节点单独记录首次/最近观测时间；连续活动以起点、组边界和最后结束事件计算墙钟间隔，不累加并行工具耗时。实时组每秒显示持续时长，完成后固定。

历史事件当前只保留服务端的整轮起止时间，缺少可恢复的组级起止时间。历史导入不记录“回放接收时间”为活动时间；此类组隐藏时长。同一组混合了缺少起止事实的旧记录时，也不推算时长。后续若要完整恢复历史组时长，需要从协议解码保留更细的时间事实。

## 工程验证

验证在独立副本准备完成后同步到实际 `../AgentKit`，同步前逐文件检查初始哈希，保留其他任务的无关修改。

- Web TypeScript 检查通过，Vite 构建通过；捆绑的 Web JS/CSS 已重新生成。
- Talkify `Talkify-MacDirect` / `Debug-MacDirect` 整应用编译通过，调试构建位于 `build/DerivedDataToolGroupMac/Build/Products/Debug-MacDirect/Talkify.app`。已核对应用包中的 Web JS/CSS 与最终测试源码生成物完全一致，280pt 输出高度已实际打包。构建日志：[macOS app build](../build/tool-group-macos/logs/tool-group-review2-app-build.log)。
- 新增 macOS 渲染/语义测试 13 项，覆盖长列表、默认收起、输出高度、输入/输出分离、空输出、失败、流式更新、完成后状态、原生滚动区、计时、计数文案和完整输出身份隔离。
- 与本改动直接相关的最终回归：100 项，0 失败。包括既有 Web 文档/渲染、工具语义、原生 transcript 测试；旧 UI 断言按已确认设计更新。
- 完整可通过范围回归：737 项，8 项条件跳过，0 失败。另明确排除下述 7 个在原始版本中复现的失败用例，不将其算作通过。
- 原始版本 `fb563f8` 的独立副本对照：731 项，8 项条件跳过，8 个失败测试用例（10 个失败断言）。其中一个原生状态文字用例在本次最终范围中通过，其余 7 个保持原状。

保留的 7 个原有失败用例：

1. `ActivityProjectionTests.testFailureAndRunningCountsAndUnknownCommandsAreFactual`
2. `ActivityProjectionTests.testMixedActivityPreservesOrderAcrossInvocationsAndEmptyNarration`
3. `BackgroundJobPresentationTests.testWaitReturnUsesRecordedStatusWithoutCompletingTheJob`
4. `BackgroundJobPresentationTests.testWaitRunsRequireAdjacentCallsAndAnExplicitMatchingJobID`
5. `TimelineProjectionTurnsTests.testConsecutiveToolsMergeIntoGroup`
6. `TimelineProjectionTurnsTests.testMixedToolsShareActivity`
7. `PreviewWorkbenchRenderTests.testViewerFailureShowsErrorFallbackAndRetry`

原始版本日志：[baseline](../build/tool-group-macos/logs/tool-group-baseline-tests.log)。范围回归日志：[737 项](../build/tool-group-macos/logs/tool-group-review2-broad-tests.log)。最终关键回归日志：[100 项](../build/tool-group-macos/logs/tool-group-review2-final-tests.log)。Web 检查日志：[typecheck / build](../build/tool-group-macos/logs/tool-group-review2-web.log)。

实际 WebKit 截图：[工具组展开与长输出](../build/tool-group-macos/tool-group-macos.png)。截图来自真实捆绑渲染器和本地测试记录，用于核对组件布局，不代表已经完成真实会话的用户验收。

## 首轮用户反馈修正

用户提出的四项调整已完成，覆盖 macOS Web 与原生回退路径：

1. 思考行去掉类型图标，标题与普通工具行对齐，展开箭头紧随文字。
2. 组头左右 padding 均为 0，标题与正文齐平；运行指示放在左侧空隙，不覆盖标题。
3. 长命令不再截成若干行预览；完整输入内容在最大 160pt / 30vh 的头部滚动，输出保持单独的 280pt / 40vh 上限。短输入自然显示，复制按钮不随输入滚走。
4. 普通工具卡移除原始详情区域；重复等待也不再在卡内展示原始参数记录区，保留各次完整输出入口。

这一轮额外验证了 400 行长命令的完整内容、短命令自然高度、思考行对齐与箭头距离、组头零内边距，以及输入/输出独立滚动。超长命令的敏感参数检查覆盖超过原先紧凑预览窗口的部分。

最终回归 100 项、0 失败；完整可通过范围 737 项、8 项条件跳过、0 失败，继续仅排除上列 7 项原有失败。macOS Direct 重新编译成功，已核对应用包中的 JS/CSS 与最终测试生成物一致。

本轮实际 WebKit 截图：[思考行与长命令头部](../build/tool-group-macos/tool-group-macos-review2.png)。

## 命令自动换行背景修正

针对中文路径命令换行后的最后一行超出头部背景的反馈，命令头部改用明确的命令列与复制按钮列；命令文本以块级布局参与高度计算，避免文本折行与头部高度计算使用不同的宽度。三行命令按实际高度撑开背景，超过输入上限后仍按原规则滚动。

已使用截图中的 `find` / `du` 命令及其路径链接验证，并覆盖 12 组窗口宽度与代码字号组合，检查最后一行落在输入视口和背景内部。相关回归 101 项、0 失败；Web 类型检查、构建与 macOS Direct 整应用编译通过，已核对应用内 CSS 与最终修正一致。

截图：[三行中文路径命令](../build/tool-group-macos/tool-command-wrap.png)。测试日志：[101 项](../build/tool-group-macos/logs/tool-group-wrap-tests.log)。应用构建日志：[macOS build](../build/tool-group-macos/logs/tool-group-wrap-app-build.log)。

## 工具组标题与操作汇总优化

根据用户确认的新规则，macOS Web 主路径与原生回退共用以下展示：

- 执行中收起：优先显示当前工具的动作说明，无说明时使用语义标题和简短命令预览；并行时保留额外运行数量。
- 展开时：显示按实际操作分类的汇总；结束后收起也显示同一汇总。删除泛化的「N 项操作 · 正在执行/已结束」标题。
- 命令、读取、修改、创建、搜索、目录、Git、网页、技能、委派、会话、后台任务、项目查询、任务清单、规划、工作流与记忆操作分别归类。最多三段；超过三类显示两个主要类别，剩余统一为「另有 N 次工具调用」。
- 全部未知时显示「调用 N 次工具」，未知名称中的 read/run 子串不会被误判。后台等待不计入命令数；同一路径重复读取按次数显示，不虚增文件数量。单次读取带文件名。
- 组级失败提示保持独立，实时更新不覆盖用户的展开选择。iOS 暂不调整。

这一轮相关回归 **107 项、0 失败**，包括真实 WebKit 运行态/展开态/完成态切换，混合分类、未知工具、等待调用计数及此前长命令换行测试。新增测试沿用现有「修改文件」文案。

整应用编译时发现同时进行的 Files 导航扩展跨文件写入 `private(set) inspectorSelection`。以现有 `dismissInspector()` 替换该直接赋值，随后沿用原逻辑打开文件入口；没有放宽属性可见性。

macOS Direct 整应用重新编译成功，并核对应用内 Web 资源与正式源码生成物一致。构建日志：[macOS build](../build/tool-group-macos/logs/tool-group-summary-app-build.log)。

截图：[完成后组摘要](../build/tool-group-macos/tool-group-summary.png)。测试日志：[107 项回归](../build/tool-group-macos/logs/tool-group-summary-tests.log)。

## 命令工具行单行与标题去重

针对收起工具时长命令占据多行、展开后重复完整命令的反馈：

- 移除窄窗口中允许 `.tool-title` 换行的样式。标题始终单行省略，状态与相邻展开箭头保留空间。
- 动作说明优先显示，去除换行及多余空白，不再添加「运行命令 · 完整预览」。已有明确的读取/搜索语义继续使用。
- 缺少动作说明时，显示短命令名与能够明确识别的子命令，例如「运行 git diff」「运行 swift test」；复杂脚本只显示短命令名，不推测整段脚本的意图。
- 展开后的输入区继续保留完整命令、复制入口和输入高度上限；输出区规则保持原样。原生回退工具行也采用单行截断。

Web 类型检查和构建通过；相关回归 **110 项、0 失败**。新增 WebKit 用例覆盖 360、490、740 三种窗口宽度的单行、省略与箭头可见性，验证完整命令不丢失；另覆盖说明优先、空白归一化、复杂脚本保守降级和原生截断。旧的原生标题断言按本次明确要求改为验证 Web/原生短标题一致。

macOS Direct 整应用编译成功；已核对正式文件与测试文件一致、应用内 JS/CSS 与最终生成资源一致。构建日志：[macOS build](../build/tool-group-macos/logs/tool-command-compact-app-build.log)。

截图：[紧凑命令工具行](../build/tool-group-macos/tool-command-compact-rows.png)。日志：[110 项回归](../build/tool-group-macos/logs/tool-command-compact-tests.log)。

## 后台运行合并到活动工具组

用户确认紧凑工具行后，进一步要求后台运行入口也进入工作组。macOS 现将后台任务作为有独立身份的组内入口，与普通工具、thinking 按活动顺序排列，不再因任务入口而拆出多组。任务启动工具在原位置替换为对应任务入口，避免重复计数并保持组身份；实际助手正文、子代理、图片、workflow 和产物仍保留各自边界。

- 后台任务行无图标，单行显示短动作与「后台」标记，取消行内总耗时。状态文案本地化，正常完成保持安静；失败、取消、不可用可以区分。
- 任务行点击继续打开原任务 Inspector，保留完整输出及控制入口。父时间线不重复包含任务日志与结果。原生回退同步支持组内入口和任务详情定位。
- 后台命令计入命令数，发起工具不重复计数；失败加入组头，取消不记作失败。任务状态由任务生命周期决定，等待返回不将仍运行的任务改为完成。
- 组内任务可以在模型轮次结束后继续显示运行；组的默认收起及用户展开选择不受任务启动、完成或失败影响。历史记录没有可信时间时仍不补造时长。
- iOS 暂时沿用独立后台任务入口，未启用本次 macOS 分组策略。

相关回归 **136 项、0 失败**。随后完整可通过范围验证 **756 项、8 项条件跳过、0 失败**，仍仅排除前文已记录的 7 项旧基线失败。覆盖发起位置替换与去重、组身份稳定、实际正文边界、任务独立状态、失败和取消、WebKit 组内顺序/分隔线/单行/图标、默认收起和更新后保持展开、Inspector 动作跨修订保留。旧测试对「后台任务必须是独立块」的要求按本次用户要求调整，生命周期断言保留。

整应用构建时，正在进行的 FileViewerKit 审阅会话改动存在 `catch` 局部错误变量遮蔽状态属性的问题；仅将该处赋值改为 `self.error = error.localizedDescription`，保留原有错误处理逻辑。随后宿主 Git 审阅错误描述 getter 缺少完整返回，将单分支 `if case` 改为穷尽的 `switch`，未改变返回文案。

Web 类型检查、资源构建和 macOS Direct 整应用编译通过。已核对正式文件与测试源码一致、应用包内 JS/CSS 与最终生成资源一致。构建日志：[macOS build](../build/tool-group-macos/logs/tool-group-jobs-app-build.log)。截图：[后台任务进入同一工具组](../build/tool-group-macos/tool-group-background-jobs.png)。日志：[相关回归](../build/tool-group-macos/logs/tool-group-jobs-tests.log)、[完整可通过范围](../build/tool-group-macos/logs/tool-group-jobs-full-tests.log)。

## 编辑前自检纳入活动工具组

macOS 的 `preMutation` 不再以独立系统消息打断活动组，改为组内「编辑前自检」单行，无图标、默认收起，点击可展开完整自检内容。保留原事件文本及元信息，不伪造工具调用；自检独立计数，不计入命令次数。自检先到、随后追加编辑工具时组身份不变，用户展开自检后再追加工具也不会收起内容。原生回退与 Web 同步；iOS 保留原规则。

Web 类型检查与资源构建通过；相关回归 **148 项、0 失败**，继续仅排除对应范围中前文已记录的旧基线失败。新增覆盖自检/工具顺序、单独自检组到追加工具的稳定身份、自检独立计数、原生完整内容折叠，以及实际 WebKit 的组内对齐、无图标、默认收起和追加后保持展开。原先要求自检作为独立系统块的断言按本次用户要求更新，其他系统消息断言保留。

macOS Direct 整应用编译通过，已核对正式源码与测试文件一致、应用内资源与最终生成物一致。构建日志：[macOS build](../build/tool-group-macos/logs/tool-group-pre-edit-app-build.log)。

截图：[组内编辑前自检](../build/tool-group-macos/tool-group-pre-edit-check.png)。日志：[148 项回归](../build/tool-group-macos/logs/tool-group-pre-edit-tests.log)。

## 命令敏感值局部遮盖与误判修正

用户确认将「关键词命中即整条隐藏」改为明确凭证位置的局部遮盖。macOS 命令展开、紧凑预览、后台任务预览与原生回退统一使用显示层 redactor，iOS 保留原策略。

- 普通源码搜索、文件名、提交说明、GOCACHE/CLANG_MODULE_CACHE_PATH/MAX_TOKENS 等配置不因 token/password 等单词被隐藏；参数中的变量引用保持可读。
- 凭证选项、敏感环境变量、HTTP 认证头与 Cookie、带凭证的 URL/查询参数、明确的密钥前缀和 JSON 凭证字段按位置遮盖。Cookie 头值作为一个凭证值处理；转义 JSON 无法精确定位时可遮盖该数据参数，保留命令其余部分。
- 保留引号、空格、Unicode、命令分隔及 URL 等非敏感结构。完整扫描长命令，不再拆成固定窗口丢失引号上下文。
- 完整命令中的敏感值使用「••••••」，旁边显示「敏感值已隐藏」，不再显示「命令预览已隐藏（含敏感参数）」；这不是因长度产生的预览截断。
- Web 与原生「复制命令」使用同一显示文本；执行记录与 Inspector 可用的原始参数不被改写。

完整可通过范围 **771 项、8 项条件跳过、0 失败**，仍仅排除前文已确认的 7 项旧基线失败。新增覆盖普通命令误判、引号与空白保持、URL/Header/环境变量/JSON/短认证参数、超出 8192 字符后的凭证、Unicode 与转义值、重复遮盖稳定性、命令分隔边界、Web/原生复制，以及真实 WebKit 头部与标签切换。旧测试要求整条隐藏的断言按用户确认的新规则更新，凭证值不得出现的断言保留。

Web 类型检查、资源构建和 macOS Direct 整应用编译通过，已核对正式文件与测试源码一致、应用内 JS/CSS 与生成物一致，并确认中文提示已打包。构建日志：[macOS build](../build/command-redaction/command-redaction-app-build.log)。截图：[命令局部遮盖](../build/command-redaction/command-redaction-macos.png)。日志：[完整可通过范围](../build/command-redaction/command-redaction-full-tests.log)。

## 用户体验验收

待用户在 macOS 真实会话中确认：

1. 执行中组始终默认收起，必要时可以主动展开。
2. 多轮模型调用的工具顺序与正文关系容易理解，工具行能区分各自操作。
3. 展开长组后只需滚动对话；查看长输出时命令始终留在输出区上方。
4. 完成时已打开的工具不消失、不重排，流式更新不抢阅读位置。
5. 并行、失败、空输出与重复后台等待的表达清楚。
6. 复制命令、复制输出、打开完整输出及 Inspector 返回路径顺手。

工程验证与用户体验验收分开记录。macOS 体验验收通过、确认效果后，才启动 iOS 展示改造。
