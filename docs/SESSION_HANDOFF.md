# flutter_jtt808_simulator 会话交接

## 当前状态

用户要求清理重复 UI 包装、对齐官方 Dialog，并明确侧边导航要左对齐、使用网上取得的真正彩色图标，而不是给原来的线性图标改色。当前已改用微软 Fluent Color 本地 SVG，所有修改及验证均已完成。读取本文件后先等待下一步要求，不要自行再重构界面。

工程：`/Users/marks/Developer/iov/flutter_jtt808_simulator`。工作区根目录与该工程此前均未发现 Git 仓库；避免假定存在可回滚的 Git 基线。

## 必须保留的用户约束

1. 业务组件使用 `shadcn_ui`。**Dialog 直接按库提供的示例实现**：`showShadDialog` 的 builder 返回 `ShadDialog`，确认框返回 `ShadDialog.alert`。
2. **禁止重新创建 Dialog 封装或别名**，包括 `SimDialog`、`ShadAppDialog`、`ShadAppDialogView`。这些实现和导出已移除；`lib/src/shared/widgets/ui/shadcn/shad_app_dialog.dart` 已删除。
3. Dialog 官方示例可直接读取当前包缓存：`/Users/marks/.pub-cache/hosted/pub.dev/shadcn_ui-0.56.3/example/lib/pages/dialog.dart`。不要再为修小问题手工拼标题栏、换一个名字继续包 Dialog，或隐藏原生关闭按钮后另造一套。
4. 用户认定界面核心问题是“内容少，尺寸大”。按实际内容决定空间：紧凑行、就近操作、内在高度、短报文窄弹窗；不要只缩字号，也不要用假数据填空白。
5. 原生 macOS/Windows/Linux 固定完整桌面导航；**最小尺寸和启动尺寸均为 1100×720**。不要按窗口宽度切成手机界面。Android/iOS 才使用移动端响应式导航。
6. macOS 保留原生红绿灯，不显示窗口栏标题，背景与应用框架衔接。不要恢复右侧 Windows 风格按钮。
7. 侧边导航文字必须显式左对齐；“彩色图标”指网上取得的成套真实彩色 SVG 图稿，不是给 Material 线性图标改色。当前使用微软 Fluent Color，资源位于 `assets/icons/navigation/`，保留原生多部件造型与渐变，不加 ColorFilter/ColorMapper。折叠栏与手机底栏使用同套资源，手机底栏文字仍居中。

## 产品与技术边界

- Flutter 本地 JT/T 808-2013 TCP 终端模拟器，五页：控制台、终端、线路任务、协议日志、设置。
- Riverpod、go_router、Hive、本地工作区、easy_localization 中英文。
- 启动不连接服务器、不恢复网络会话、不伪造在线设备/流量；WGS84 轨迹不是道路导航。
- 继续遵守 `AGENTS.md`、`PRODUCT.md` 和 `DESIGN.md`。原生工程配置不随手清理。

## 已完成的关键行为

- Dialog 的标题、说明、内容和操作分别放入官方 `title` / `description` / `child` / `actions` 插槽；删除逐窗 `padding` / `gap` / `actionsGap` 覆盖，使用默认标题与说明排版、普通尺寸的 `ShadButton` 操作区。`titlePinned` 与 `descriptionPinned` 均为 true，底部操作区使用库默认固定行为。
- 修复滚动条和关闭按钮重叠：标题固定，滚动区在其下方，关闭图标采用库内尺寸与位置。没有自定义 Dialog 类或手写标题行。
- `SimEditGuard` 是**独立业务关闭保护**，不是视觉 Dialog 封装。使用 PopScope 检查终端、线路、任务、工作区导入是否有实际修改；取消、关闭、Esc、遮罩均受保护。继续编辑保留输入；恢复原值不提示；保存中禁止误关；成功保存直接退出不提示。
- 编辑弹窗的库内 `ShadIconButton` 关闭回调使用 `Navigator.maybePop`，让业务保护有机会判断；成功保存刻意使用 `Navigator.pop`。库默认关闭回调直接 pop，不能在简化时无意绕过草稿保护。
- 日志进入时默认当前终端；手动选择 All 后普通刷新不重置。具体终端筛选、当前终端及原始帧发送目标同步。
- 报文详情根据 HEX 长度选用 440/560/680px 宽度并受视口限制；字段和值就近排列。HEX 使用 IBM Plex Mono，16 字节换行，复制仍保留原始 HEX/JSON。
- 空状态新增按钮位于说明下方；终端页有数据后才使用标题工具栏的新增按钮。
- 新建线路弹窗宽 640px，CSV 最少 5 行；有效预览产生后才显示地图，空态不占一个大预览框。
- IBM Plex Sans/Mono 字体及 OFL 许可已放在 `assets/fonts/` 并在 pubspec 注册。界面使用中性浅色/深色，主要按钮近黑/反白，蓝色用于数据/焦点。

## 主要代码位置

- `lib/src/features/simulator/presentation/widgets/sim_ui.dart`：业务 UI helpers、SimEditGuard、simConfirm；这里已没有 SimDialog。
- `widgets/terminal_editor.dart`、`route_editor.dart`、`task_editor.dart`、`workspace_transfer_dialog.dart`：直接 ShadDialog + 业务保护。
- `widgets/log_detail_dialog.dart`：直接 ShadDialog、自适应详情宽度、显示 HEX 格式化。
- `screens/protocol_logs_page.dart`：当前终端筛选与原始帧目标同步。
- `screens/simulator_screen.dart`：按平台决定导航。
- `lib/src/services/desktop_window_service.dart`：统一最小与启动尺寸。
- `lib/src/theme/shad_theme.dart`：保留应用配色与 IBM Plex 字体，恢复库内 `large` / `muted` 排版；macOS 在主题层关闭 Dialog 内部 SafeArea，避免重复加入页面的原生拖拽栏留白。
- `test/simulator_ui_test.dart`：多数界面交互回归；另外有平台窗口、协议、控制器等测试。

## UI 包装清理（2026-10-27）

按用户“多余的东西清理掉”的要求，完成以下清理，没有改动协议和模拟器业务组件：
- 删除整个 `lib/src/shared/widgets/ui/`：Material/Cupertino 的 `App*` 包装、`ShadApp*` 镜像、组件展示页与所有相关导出。空目录也已移除。
- 主题适配原样迁到 `lib/src/theme/shad_theme.dart`，经 `theme_constants.dart` 导出；测试与预览工具使用新位置。
- 删除旧登录、注册、找回密码、引导、占位首页及其 mock 账号服务、状态和监听包装；路由只保留本地模拟器 `/`，对应翻译也已删除并重新生成。
- 删除自定义 Toast 组件栈、无调用的 Dialog/Sheet/SnackBar helpers 和 UI 专用枚举。现有共享操作的 `showGlobalToast` 直接使用 `ShadToaster` / `ShadToast`。
- 移除 `smooth_page_indicator` 和 `flutter_animate` 的直接依赖；`flutter_animate` 仍是 `shadcn_ui` 所需的传递依赖。
- 同步 `AGENTS.md`、`CLAUDE.md`、`DESIGN.md`，明确直接使用库组件，禁止重新生成完整镜像包装。
- 新增仅保留模拟器路由、共享 Toast 正常/错误反馈和导航挂载前安全调用回归；原有 Dialog、草稿保护、跨平台窗口与协议回归均保留。

## Dialog 与官方示例一致（2026-10-27）

- 已读取当前包的 `example/lib/pages/dialog.dart` 和 `ShadDialog` 实现；普通弹窗与确认弹窗均直接使用官方组件，没有增加新包装或手写标题栏。
- 终端、线路、任务、工作区导入/导出及报文详情均补齐独立的简短中英文 `description`。标题和说明固定，正文独立滚动。
- 去掉每个 Dialog 的外观间距覆盖；操作区直接使用默认尺寸的 `ShadButton` / `.outline` / `.destructive`。保存中按钮禁用并显示“正在保存”，原有草稿与保存关闭保护保留。
- 编辑弹窗关闭按钮使用库内 `ShadIconButton`，尺寸、位置、颜色及悬浮/按下状态与默认实现一致，仅回调改用 `maybePop` 以保护草稿。
- 报文详情保留按内容选择的 440/560/680px 宽度，底部只留 JSON/HEX 复制，使用库自带 X 关闭；避免默认按钮尺寸下第三个冗余按钮造成横向溢出。确认框使用库默认的 512px 最大宽度。
- macOS 页面通过 MediaQuery 加入原生拖拽栏留白，但居中弹窗已位于该区域下方；主题层关闭 macOS Dialog 内部 SafeArea，避免标题上方重复增加 32px。其他平台仍保留库默认安全区行为，未改原生窗口配置。

## 真实彩色导航图标（2026-10-27）

用户明确指出“彩色图标”不是给原 Material 线性图标改色，必须上网取得实际的成套图标资源。
- 已搜索并核对微软官方 Fluent Color 图标目录，下载 `@fluentui/svg-icons@1.1.344` 的 SVG 图稿；来源为 https://github.com/microsoft/fluentui-system-icons ，详细记录见 `assets/icons/navigation/SOURCE.md`，MIT 全文在同目录 `LICENSE` 并随资源打包。
- 控制台使用 `board`，终端使用 `phone_laptop`，线路任务使用 `location_ripple`，协议日志使用 `code_block`，设置使用 `arrow_clockwise_dashes_settings`，均为官方 24px color 版本，保留原生部件和渐变。
- `_nav` 已改为本地 SVG 路径，删除 `_navIconColor` 及原来的导航 Material 图标。通过已有 `flutter_svg` 渲染，不加颜色过滤器或颜色映射，不新增 Flutter 依赖。
- 侧栏/折叠栏显示 20px 图稿，手机底栏显示 22px 图稿。文字仍左对齐，行高 34px、184px 侧栏、选中/悬浮的中性背景及可访问语义保持。
- `pubspec.yaml` 已显式注册 `assets/icons/navigation/`。图标随应用离线打包，不依赖运行时 CDN。
- 当时生成了浅/深主题导航渲染预览；历史图片现已清理，不再随项目保留。此前仅给线性图标染色的截图不代表当前实现。

## 最近验证（2026-10-27）

在完成真实 SVG 导航图标接入后，使用项目 FVM Flutter 3.47.8：
- `fvm flutter analyze --no-pub` 无问题。
- 通过 Dart MCP 显式指定项目 SDK，全量 **113 项测试通过**。
- 另有 **2 项临时导航渲染测试通过**，使用完整应用、真实 bundled 字体与原始 SVG，保存上述浅/深主题预览；临时测试入口已删除。
- `fvm flutter build macos --debug --no-pub` 构建通过。
- 导航回归覆盖源 SVG 的多种颜色和渐变、MIT notice 打包、禁止 ColorFilter/ColorMapper、浅深主题与切换各页后的资源一致性、文字左对齐及紧凑行高。
- 之前的 Dialog 统一和 390/1100 宽度、macOS/Windows/Linux/Android/iOS 真实应用变体、草稿保护、保存关闭、多终端和 HEX 复制回归均保留并通过。此前两项临时 Dialog 渲染测试也已通过，截图仍在 `/tmp/iov-dialog-{light,dark}-{terminal,detail,confirm}.png`。
- 预览是 widget 层渲染证据，不代表原生系统窗口截图，也不代表完成 Windows/Linux 原生构建或 VoiceOver 人工审计。

## 环境注意

- 最近实际使用 FVM Flutter **3.47.8 / Dart 3.13.7**。全局 `flutter` 是 OpenHarmony 版 3.41.10、Dart 3.11.1，不满足项目 SDK 要求。
- FVM 2.x 的 `.fvm/fvm_config.json` 最近指向 3.47.8；`.fvmrc` 曾仍为 3.44.8。先用 `fvm flutter --version` 确认，不擅自切换全局鸿蒙 SDK。
- 用户 `~/.zshrc` 的 PUB_HOSTED_URL 已改为 `https://pub.dev`。旧镜像 `https://pub-web.flutter-io.cn/` 曾返回 554 并长时间卡住。已打开的 Cursor 进程可能仍继承旧变量，工具命令可显式加 `PUB_HOSTED_URL=https://pub.dev`。
- 测试优先使用 Dart MCP 测试工具并确保指向项目 SDK。直接工具仍可能调用全局 3.41.10-ohos 并超时；此前已终止该错误 SDK 的测试子进程。可复用 `/tmp/iov_mcp_tests.py` 临时桥接脚本，显式指定 3.47.8 的 Flutter/Dart SDK；当前全量 113 项测试已通过。不要并发启动多个同目标 Flutter 测试进程。
- macOS 构建会提示旧 CocoaPods 与 Swift Packages 集成共存；这是现存警告，不要顺手修改原生配置。

## 评审记录

`.impeccable/critique/2026-10-27T01-49-56Z__resentation-screens-simulator-screen-dart-f8b63fcf.md` 是历史 28/40 评审，四项重点问题已修复并关闭该待办。没有重新打分，不要声称分数已提高。

原生 Flutter 不能用网页 DOM 检测器证明视觉正确。此前 Flutter 检查器截图对模态层不可靠；保持如实区分渲染证据、源码判断和自动化测试。
