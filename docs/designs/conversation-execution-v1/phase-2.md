# 阶段 2 · macOS Tasks 与执行状态

2026-11-18。按已确认五态设计实现并完成自动化验收。产品改动位于相邻 AgentKit；本仓库保存设计和验收记录。iOS 原生样式、code-agent、消息补充与排队接口未改动。

## 实现结果

- Web Tasks 使用透明底、单层细边框，标题只保留 Tasks 和完成数量。取消视觉进度条、蓝色计数徽章、active 数量及重复当前项；保留完成数量的无障碍进度语义。
- 清单只来自已有权威 todo 数据。进行中默认展开，完成或本轮结束时默认收成一行；用户可再次展开。普通文本增长不覆盖用户手动折叠选择。
- 全部完成显示实际完成数量。结束时仍有未完成项，保留真实数量并显示“仍有未完成项”；展开后使用任务名称，避免继续显示“正在验证”等执行中措辞和活跃标记。
- 计划工具调用失败保留现有工具详情。最终回复交付不覆盖权威 Tasks 状态，不从失败调用参数猜测完成情况。
- 原先顶部时钟和底部 Thinking/Working 合为内容末尾的一个活动区域。已有运行工具摘要时，继续由工具摘要表达当前动作，活动区只显示轻量耗时；没有具体动作事实时显示“正在处理”或有依据的“正在思考”。
- Web LiveState 增加可选 waitingReason，复用 native snapshot 的审批、正式计划审批、提问及后台状态，分别显示等待确认、等待计划审批、等待回答、等待后台结果或后台需要处理。等待时隐藏活动时钟并停止计时刷新；操作仍由原生审批/提问组件处理，未在 Web 中复制按钮。
- 状态提示有独立读屏通知区域，秒级时钟不进入重复播报区域。等待元数据单独变化通过 setLive 更新，稳定历史 turn 不必替换。
- 正常结束后活动区域消失。已有失败/取消结果、工具过程、最终回复及辅助操作保留各自语义，没有增加重复结果卡片或新建一套生命周期。

## 验收范围

最终版本验证结果：TypeScript 类型检查和 Vite 资源构建通过；以下相关测试共 **87 项通过、0 失败**；Talkify-MacDirect / Debug-MacDirect 完整 macOS 构建通过（关闭代码签名）。本次涉及文件的 diff 空白检查通过，其他并行文件的既有空白问题未改动。

自动化涉及 ConversationWebDocumentTests、MacConversationAppearanceTests、MacToolGroupRenderTests、ExecutionReducerTests、TurnOutcomePresentationTests：

- 真实 WKWebView：进行中展开、手动折叠后继续流式更新、收到审批、部分完成且计划更新失败、全完成收起、手动展开已完成清单后继续更新。
- 控制状态：仅等待元数据变化时，稳定 turn 复用，只发送 setLive。
- 真实事件：先成功接收 todo_updated，再发生提交 completed 参数但工具失败，最后收到最终回复；live 和历史 replay 都保留原清单。
- 既有覆盖：无 Tasks 的正文、长历史及快速更新、工具按需展开、输出懒挂载、失败和取消展示、浅色/深色主题与窄窗口。
- 原有视觉断言按已确认方案同步：去掉 active 数量文字、时钟移到内容末尾、非运行清单显示任务名称。其他功能断言保留。

实际渲染验收截图位于本地忽略目录 `build/conversation-execution/`：`execution-running.png`、`execution-waiting.png`、`execution-partial.png`、`execution-complete.png`。使用真实页面和示例 snapshot，截图仅包含阅读区域，没有原生输入框和审批操作条。

本轮验收不等同于真实模型端到端执行；完整原生审批操作和用户日常会话体验仍需 App 内验收。离屏测试的系统键盘焦点限制沿用此前验收说明。滚动专项及 Instruments 测量仍属于阶段 3，没有基于此次样式改动宣称完整 App 性能提升。

沿用已有 40 组 × 120 工具的渲染基准：本轮最终运行只展开目标 1 组，输出节点未提前挂载，点击位置偏移 0，目标 DOM 就绪约 8ms。该单次基准仅用于检查回归，不代表完整 App 的帧率或延迟测量。

## 工作区边界

保留已有 BackgroundJobsView.swift、ConversationDetailView.swift 和 SessionRailView.swift 并行改动。本阶段没有修改这些文件，阶段提交不包含这些并行工作。
