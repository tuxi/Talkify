# macOS 对话详情 V1 实现与验收

2026-11-17，按已确认设计实施。产品代码位于相邻的 `AgentKit` 包，本仓库保留设计与验收说明。尚未提交代码。

## 已实现

- 新增 `Web/ConversationWorkbench/src/conversation-appearance.css` 作为阅读外观层，集中管理浅色/深色配色、字体与间距。现有工具展开和懒加载机制继续使用原实现。
- 正文 15/25、标题 16/24、工具信息 13.5/22、辅助信息 12/20、代码 12.5/21。段落 14、工具外部间距 20、轮次间距 36。
- 用户消息使用无描边浅灰气泡，内边距 14/16、圆角 14；回复直接显示于页面。长消息保留展开功能。
- 时间和复制操作在悬停/键盘焦点时出现，辅助行预留几何空间。用户消息复制复用原生动作桥接，动作令牌加入增量文档保留逻辑。
- 仅正文 Markdown 中的长行内代码、文件路径自然折行，避免扩宽阅读区域或改变工具命令的单行显示。
- 保持最大 760 外框、左右各 16 内容边距，实际正文最大 728，与输入框的既有对齐规则一致。
- macOS 移除常驻“下次发送”“最近 Turn 路由”“最近实际响应”。输入框底部的模型选择入口保留。
- 原生内容背景、WKWebView 背景和底部输入区域共享 `MacConversationAppearance` 画布颜色，浅色 #FFFFFF、深色 #1F2023。底部改为实色背景，移除该处 material、渐变遮罩与装饰分隔线。
- 用户消息组件增加 memo，回复流式变化且用户消息属性未变时不重复渲染用户消息。

## 回归中修正的滚动顺序

500 轮长对话连续尾部更新时，下一次更新可能在上一次 React 布局完成、但延迟滚动恢复任务尚未执行时到达。此时读取几何距离会把内容增长误认为用户离开底部。

新更新在捕获视口前完成前一次待恢复视口事务；继续使用现有 interactionEpoch 和手势优先检查。用户向上滚动、选择工具或停留历史内容时仍优先保留阅读位置。没有更换时间线或工具展开架构。

## 自动化验证

最终资源生成后：

- `npm run typecheck`：通过。
- `npm run build`：通过，已更新打包的 CSS/JS。
- `ConversationWebDocumentTests`、`MacToolGroupRenderTests`、`MacConversationAppearanceTests`：共 **56 项通过，0 失败**。
- 新增实际 WKWebView 验证覆盖：浅色转深色、728 内容宽度、520 窄窗口无横向溢出、长路径折行、DOM 聚焦与几何稳定、无关历史 DOM 复用、消息复制令牌跨版本保留。
- 现有验证覆盖：500 轮长对话、连续尾部更新、向上滚动后保持阅读位置、工具分组展开、输出懒挂载及失败状态展示。
- `Talkify-MacDirect / Debug-MacDirect` 完整 macOS 构建：通过，`CODE_SIGNING_ALLOWED=NO`。
- `git diff --check`：通过。

旧渲染测试的正文 14px 断言按已确认设计更新为 15px，其余断言保留。

## 实际渲染截图

使用真实 AgentKit 文档构建器和打包的 WKWebView 页面，内容为验收示例，没有调用模型服务。截图只显示对话阅读区域，不包含 sidebar、toolbar 或原生输入框。

本地构建产物（不纳入版本控制）：

- `build/conversation-appearance/conversation-light.png`
- `build/conversation-appearance/conversation-dark.png`
- `build/conversation-appearance/conversation-narrow.png`

## 性能证据与限制

同一设备、同一 40 组 × 120 工具的展开场景，改动前和最终验收均测得同步点击约 1ms、目标组 DOM 就绪约 16ms、点击位置偏移 0。只展开目标 1 组，没有提前挂载输出节点。这是小型渲染基准，不能据此声称整 App 帧率或内存有提升。

底部少一层 material/渐变遮罩合成，用户消息避免重复渲染；没有进行 Instruments 帧率、峰值内存或真实输入延迟测量。

离屏 SwiftPM 测试窗口无法取得 WindowServer 的系统键盘焦点。测试始终验证按钮 DOM 聚焦及聚焦前后布局不移动；只有宿主实际具有系统焦点时才验证 `:focus-within` 的显示效果。真实 Tab/鼠标悬停显示仍需在 App 中体验验收。

本次面向 macOS；iOS 样式和底部背景逻辑保留现状。没有修改已有的 `SessionRailView.swift` 并行改动。
