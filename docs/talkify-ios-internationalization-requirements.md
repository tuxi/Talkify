# Talkify iOS 2.0 国际化与主题适配需求

> 状态：需求草案，供客户端实现与排期使用  
> 目标版本：Talkify 2.0 正式版  
> 范围：`/Users/xiaoyuan/Documents/work/git/chater`

## 1. 背景与目标

Talkify 2.0 当前工程已经保留 19 个 `.lproj` 语言目录和 Xcode `knownRegions` 配置，但其 `Localizable.strings` 大多来自旧 Chater 产品。新建的 Talkify 2.0 页面仍有大量硬编码中文，因此“存在翻译文件”不等同于“2.0 已国际化”。

本需求按阶段完成国际化，避免一次性改动全部界面带来支付、登录和 Agent 工作流回归：

1. 先完成系统权限提示与发布基础设施；
2. 再完成核心用户路径；
3. 最后扩展到全部设置页、开发者工作区和长尾界面。

语言适配不改变服务端计费、StoreKit 商品 ID、购买行为或用户数据。主题适配以现有“跟随系统深/浅色”为基线；用户手动选择主题是独立可选项，不与第一阶段耦合。

## 2. 当前基线

### 2.1 语言资源

当前目录为 `Talkify/Resources/Localization`，包含：

`en`、`en-GB`、`zh-Hans`、`zh-Hant`、`ja`、`ko`、`de`、`fr`、`es`、`it`、`pt-BR`、`nl`、`pl`、`tr`、`uk`、`nb`、`ca`、`eu`、`be`。

`/Users/xiaoyuan/Documents/work/git/chater_副本` 可作为旧资源文件和 key 覆盖范围的参考，但**不得直接把旧产品文案原样带入 Talkify 2.0**。

### 2.2 已确认的技术决策

1. **业务 UI 使用 String Catalog。** 新增 `Talkify/Resources/Localization/Localizable.xcstrings`，阶段 1 只放 Talkify 2.0 的新 key。旧 `Localizable.strings` 保留且不再新增 key；阶段 2 完成静态引用检查后再删除旧 Chater/Mastodon/Timeline 等僵尸条目。
2. **主 Target 使用 `Talkify-Info.plist`。** Debug 与 Release 均配置 `INFOPLIST_FILE = Talkify-Info.plist`，并非自动生成的独立 plist。当前其中已经声明相机、麦克风、照片库新增、语音识别和网络 usage description。
3. **麦克风和语音识别要保留在阶段 0。** 它们由 ClientToolsKit 工具使用；即使调用代码位于 package，iOS 仍要求宿主 App 的 plist 声明对应 usage description，`InfoPlist.strings` 也必须本地化这些 key。
4. **FeatureAuth 只服务 Talkify。** FeatureAuth 与 ClientToolsKit 中的用户可见文本统一显式使用宿主 `Bundle.main` 的 Talkify catalog，不另建 package catalog。封装一个可注入 bundle 的本地化 helper，单元测试可传测试 bundle；禁止依赖 package 默认资源 bundle 的隐式行为。
5. **服务端流水以新 `ledger_event` 作为稳定展示契约。** `change_type`、`biz_type`、`remark` 是内部/兼容字段，客户端不得再把它们作为最终 UI 文案或穷举契约。

### 2.3 当前技术问题

- 大量 SwiftUI 标题、按钮、空状态、错误与无障碍文案直接写为中文；新页面没有统一 key。
- 当前 `InfoPlist.strings` 未完整覆盖主 App 实际声明的权限键，且存在旧 Chater 语义。
- 部分金额、日期、流水显示固定使用 `zh_CN`，不适合其他地区。
- 账单、点数和 Agent API 中有服务端返回的展示文本；客户端不能把不可本地化的服务端 remark 当作最终 UI 文案。
- 现有界面多数会根据 `colorScheme` 跟随系统深/浅色，但暂未发现全局持久化的“系统 / 浅色 / 深色”用户选择。

## 3. 范围与非范围

### 本次范围

- 主 App 的系统权限提示本地化。
- 统一业务 UI 的本地化 key、回退语言与格式化规范。
- Talkify 2.0 核心路径的多语言 UI。
- 深色/浅色模式下的多语言布局、可读性与截断验证。
- 数字、日期、货币及复数字符串按设备 Locale 显示。

### 非范围

- 翻译用户输入、模型回答、网页内容、Git 内容或服务端日志。
- 变更 App Store Connect 的商品本地化（该项由发布流程单独维护）。
- 自动机器翻译线上用户内容。
- 第一阶段新增手动主题切换。

## 4. 阶段 0：InfoPlist.strings 与发布基础（P0）

### 目标

让用户在任一已声明语言下看到准确、完整的 iOS 系统权限说明；不改业务页面逻辑。

### 实现要求

1. 保留并校验每个 locale 的 `InfoPlist.strings`，以英文 `en` 为完整回退源；主 Target 的源 plist 为根目录 `Talkify-Info.plist`。
2. 每个已支持 locale 必须覆盖主 Target 当前声明的以下 key：

   - `CFBundleName`
   - `NSCameraUsageDescription`
   - `NSMicrophoneUsageDescription`
   - `NSPhotoLibraryAddUsageDescription`
   - `NSSpeechRecognitionUsageDescription`
   - `NSNetworkClientUsageDescription`

3. 文案必须描述 Talkify 2.0 的真实用途。不得沿用“保存拍摄和接收媒体”等旧 Chater 语义；产品负责人确认英文源文案后再翻译。相机/照片库、麦克风、语音识别应分别描述其实际工具用途，不可泛化为“完整功能”。
4. 审计主 App、Share Extension 和未来新增 Target 的 plist；某 Target 未声明权限时不强行添加对应文案或权限。主 App 已声明的麦克风和语音识别 key 必须保留。
5. 确认所有 `.lproj` 目录都进入对应 Target 的 Bundle。当前工程使用 file-system-synchronized group，仍须通过 Archive/Runnable bundle 实测验证。
6. 不新增权限、不改变弹窗触发时机，只改系统展示文案。

### 验收

- 在英语、简体中文、繁体中文、日语、韩语、德语、法语、西班牙语、葡萄牙语（巴西）下触发已使用权限时，系统弹窗无英文/中文错配。
- 其他已声明语言至少能回退为英文，不能因缺 key 显示 key 本身或空白。
- `InfoPlist.strings` 编译、Archive 和 TestFlight 安装均正常。

## 5. 阶段 1：国际化基础设施与核心路径（P0）

### 目标

让首次使用、登录、购买和 Agent 执行路径在主要语言中完整可用。

### 语言策略

英文 (`en`) 为开发和回退语言。首批完整人工校对语言：

- English (`en` / `en-GB`)
- 简体中文、繁体中文
- 日语、韩语
- 德语、法语、西班牙语
- 葡萄牙语（巴西）

其余现有 locale 保留资源目录，可先英文回退；完成翻译并通过 QA 后再声明为“完整支持”。

### 实现规范

1. 主 App 新增并维护 `Talkify/Resources/Localization/Localizable.xcstrings`，作为 Talkify 2.0 业务 UI 的唯一新增来源。旧 `Localizable.strings` 只做历史兼容，阶段 1 不修改；阶段 2 删除前必须完成引用扫描和回归。
2. FeatureAuth、ClientToolsKit 等当前仅服务 Talkify 的 package，其 UI 文案显式使用 `Bundle.main` 的 Talkify catalog；使用可注入 bundle 的 helper 支持单元测试。不得依赖 package 默认资源 bundle 或隐式查找。
3. key 使用稳定的语义命名，不以中文或英文整句作为 key，例如：

   ```text
   common.action.cancel
   auth.sign_in_with_apple
   workspace.empty.title
   billing.subscription.title
   billing.points.validity
   billing.points.purchase_success
   agent.execution.failed
   settings.appearance.title
   ```

4. SwiftUI 使用可本地化 key；ViewModel、Toast、错误和无障碍文案使用 `String(localized:)` 或等价封装。仅用户内容、模型输出、文件名和代码块使用 `Text(verbatim:)`。
5. 含变量的文本必须使用可翻译格式字符串；禁止字符串拼接。复数使用 String Catalog plural variation。
6. 所有日期、货币、数字与百分比使用 `Locale.current`。移除 UI 中固定 `zh_CN` / `zh-CN` 格式化器，除非该格式是协议、文件或服务端明确要求。
7. 保留业务 code 与原始数值，再在客户端映射展示。特别是点数流水、订阅权益和 Agent 扣费原因：不要直接把服务端 `remark` 当作最终本地化标题。
8. 不翻译 Product ID、模型 ID、代码、命令、文件路径和用户创建的工作区名称。

### 核心覆盖页面

- 启动、匿名注册、登录、Sign in with Apple、账户错误。
- 会话首页、创建/导入/切换工作区、空状态、删除/归档/恢复确认。
- Agent 运行、取消、失败、用量不足和权限相关提示。
- 设置主入口及账户、使用情况与计费入口。
- 订阅中心、订阅详情、点数中心、购买成功、点数流水、恢复/同步购买记录。

### 验收

- 首批完整语言在上述路径中无硬编码中文、无 key 外露、无英语和中文混杂。
- 德语、法语等长文本不截断关键 CTA；中日韩显示不重叠。
- StoreKit 价格继续使用本地化 `displayPrice`，不硬编码美元格式。
- 切换 iOS Per-App Language 后重启 App，语言切换稳定且不影响登录、购买和本地数据。

## 6. 阶段 2：全量业务与设置页（P1）

### 范围

- 全部 Settings 子页、开发者工作区、文件预览、Git、插件、浏览器与电脑操控界面。
- 分享扩展的界面和错误提示。
- 可访问性 label、hint、VoiceOver 操作名称。
- 所有 Alert、Sheet、Toast、上下文菜单和空状态。

### 验收

- 静态扫描不再出现未经豁免的业务中文/英文 UI literal。
- 每个新增 key 在英文中有值；完整支持语言均有人工校对值。
- 跨语言切换下不会影响导航路径、任务状态、文件操作或支付状态机。

## 7. 主题适配要求

### 2.0 基线

当前应继续支持系统深色/浅色模式。国际化开发必须在两种模式中验收：文字对比度、卡片背景、图标、渐变、禁用态与错误态不能因语言长度变化而失真。

### 可选独立需求：手动主题

若产品需要设置页选择主题，单独实现：

- 选项：`system`、`light`、`dark`。
- 使用 `AppStorage` 或统一偏好存储持久化。
- 在 `TalkifyApp` 根视图通过 `preferredColorScheme` 注入。
- 登录页、Sheet、Share Extension 与第三方登录 SDK 都需回归。
- 不得在本地化阶段顺手大规模重构颜色体系。

## 8. 服务端协作要求

- API 应优先返回稳定业务字段、code、金额、时间和状态，不强依赖中文展示句。
- 产品名称可保持品牌统一的 `100 Talkify Points`；价格由 StoreKit 决定。
- 点数/用量流水新增 `ledger_event` 字段，作为**稳定、只增不改**的客户端展示枚举；建议首批取值：

  ```text
  point_pack_purchase
  subscription_grant
  membership_period_grant
  agent_usage_reserve
  agent_usage_settle
  agent_usage_release
  point_expire
  order_reclaim
  admin_adjust
  daily_checkin
  register_reward
  anonymous_merge
  ```

- `change_type`、`biz_type`、`remark`、`display_title` 和 `display_description` 保留给兼容、审计和旧客户端；新客户端不以它们做本地化分支。
- `display_category` 可继续用于颜色/图标等粗粒度视觉分类，但不代表完整业务语义。
- 客户端遇到未知 `ledger_event` 时显示本地化的通用“点数余额变动”，保留方向、数额和时间，并在 Debug/分析系统记录未知值；不得将原始 code 直接暴露给用户。
- 如必须由服务端生成可见文案，需明确 `Accept-Language` / locale 参数、回退规则与测试用例；首选客户端映射以降低服务端语言维护成本。

## 9. 测试矩阵与上线门槛

### 最小矩阵

- 语言：首批完整语言全部覆盖；其余 locale 做资源存在与英文回退检查。
- 外观：浅色、深色。
- 设备：至少一台小尺寸 iPhone、一台大尺寸 iPhone、iPad。
- 字体：默认字号和最大辅助功能字号。
- 功能：登录、匿名升级、订阅购买、点数购买、恢复/同步、Agent 调用失败、工作区导入/删除。

### 上线门槛

1. 不存在错误 key、空白权限文案或非预期中文硬编码。
2. 语言切换不改变支付/登录/Agent 行为。
3. 主流程没有截断、重叠、不可点击 CTA 或错误的数字/货币格式。
4. App Store 本地化、应用内点数说明和实际 12 个月有效期口径一致。
5. 每个阶段独立提交、独立 TestFlight 验收；不要把全量翻译与大规模 UI 重构合并到一个提交。

## 10. 建议排期

| 阶段 | 内容 | 建议投入 |
|---|---|---|
| 阶段 0 | InfoPlist、Target 审计、权限弹窗 QA | 0.5–1 天 |
| 阶段 1 | 基础设施、核心路径提取、首批语言翻译与 QA | 4–7 天 |
| 阶段 2 | 全量设置/工作区/扩展与全部语言完善 | 5–10 天，按页面拆分 |
| 手动主题（可选） | 主题偏好、全局注入与回归 | 1–2 天 |

上述时间不包含人工翻译审校等待；若使用专业翻译，建议先冻结英文源文案再送审，避免每轮 UI 改动导致 19 语言反复返工。
