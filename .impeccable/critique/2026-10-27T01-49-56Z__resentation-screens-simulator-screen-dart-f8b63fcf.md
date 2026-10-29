---
target: flutter_jtt808_simulator 全界面（桌面最小窗口）
total_score: 28
max_score: 40
na_heuristics:
p0_count: 0
p1_count: 1
target_identity: "file:/Users/marks/Developer/iov/flutter_jtt808_simulator/lib/src/features/simulator/presentation/screens/simulator_screen.dart"
target_fingerprint: "sha256:7a4c3adddcb1f09c99ab6bb6c4c7035dd26a64b751730c22f10d6edb3731c1cf"
target_path: /Users/marks/Developer/iov/flutter_jtt808_simulator/lib/src/features/simulator/presentation/screens/simulator_screen.dart
timestamp: 2026-10-27T01-49-56Z
slug: resentation-screens-simulator-screen-dart-f8b63fcf
closed: true
---
Method: design review only (detector not applicable, native platform)

## 结论

现在更需要按内容和任务调整布局，而不是继续整体缩小字号或窗口。大空卡片已经收掉了，但短内容弹窗、空状态操作位置和跨页终端上下文还有改进空间。

本轮实际查看了 macOS 1100 × 720 下的五个深色空工作区页面，并核查了编辑器、报文详情和日志筛选代码。有数据的连线流程、浅色模式、手机端和 VoiceOver 未纳入本轮人工可视评分；弹窗部分结论以源码为依据。原生 Flutter 不适用网页检测器，本轮未运行网页扫描。

## 设计健康度：28 / 40

| 检查项 | 分数 | 主要判断 |
|---|---:|---|
| 系统状态可见性 | 3/4 | 连接、任务与收发数量有真实状态来源。 |
| 符合领域习惯 | 3/4 | 终端身份、WGS84、协议报文的用词明确。 |
| 用户控制与退出 | 2/4 | 可以取消，但长表单缺少未保存修改保护。 |
| 一致性与平台规范 | 3/4 | shadcn 组件和桌面导航已统一。 |
| 错误预防 | 3/4 | 有字段校验、删除确认和工作区覆盖确认。 |
| 识别优于记忆 | 3/4 | 主要入口可见，但跨页终端范围不连续。 |
| 高频操作效率 | 2/4 | 有批量连接和导入复制，但缺少操作快捷入口。 |
| 简洁与视觉层级 | 3/4 | 空状态紧凑了，部分短内容仍使用固定宽弹窗。 |
| 错误诊断与恢复 | 3/4 | 校验靠近字段，部分通用错误仍不够具体。 |
| 帮助与说明 | 3/4 | 支持范围和格式限制清楚，部分说明占据主操作区。 |
| 合计 | 28/40 | 基础良好，下一轮应集中解决具体流程与尺寸问题。 |

## 整体判断

协议名、终端身份、坐标和报文让它具有明确的专业工具特征；视觉语言已经统一。下一步最有价值的是让“选择终端 → 操作 → 查看对应报文”成为连续流程，而不是再次更换整套外观。

确定性扫描：not applicable (native platform)。本轮未创建浏览器覆盖层。

目前做得好的地方：
- 桌面边界清楚。最小窗口、带文字导航和 macOS 原生窗口行为已经形成稳定框架。
- 空数据表达真实。没有为了填满窗口添加假设备、假流量或无意义图表。
- 设置页更符合内容量。主题与语言不再被拉成两个巨大输入框，分组也能快速扫读。

## 优先问题

### [P1] 从控制台进入日志时，当前终端范围没有延续

源码显示：控制台保留了当前终端，但日志页自己的筛选状态初始为空，因此会默认显示“全部终端”。原始帧发送区又可以继续使用控制台选中的终端。

影响：多终端联调时，查看范围与发送目标可能不同，增加误判报文归属的风险。当前空工作区无法直接复现多终端场景，这是代码路径核查结论。

建议：从某个终端进入日志时默认筛选该终端，并保留明确的“全部终端”切换。
对应命令：/impeccable adapt 日志终端上下文
位置：lib/src/features/simulator/presentation/screens/protocol_logs_page.dart；console_page.dart。

### [P2] 空状态的说明与主要操作距离太远

控制台的空状态文字在左侧，“新增终端”却靠近工作区右边缘；终端管理页又把同一操作放到右上角。用户读完说明后，需要重新寻找按钮。

建议：空工作区把“新增终端”紧接在说明下方；有记录后，再使用右上角工具栏。空白本身可以保留，无需靠大卡片或额外内容填满。
对应命令：/impeccable layout 空状态与主要操作
位置：lib/src/features/simulator/presentation/widgets/sim_ui.dart；screens/console_page.dart；screens/terminals_page.dart。

### [P2] 短报文详情仍使用固定 760px 宽弹窗

报文详情代码对短心跳、事件消息和长报文使用同一个宽度。短报文中，左侧标签与右侧值可能相距很远。

建议：短记录采用更窄的详情布局；长 HEX 内容单独扩展或滚动，避免几项短值决定整个大弹窗。
对应命令：/impeccable layout 报文详情弹窗
位置：lib/src/features/simulator/presentation/widgets/log_detail_dialog.dart。

### [P2] 长表单缺少未保存修改保护

线路 CSV 和终端参数都可能需要较长编辑时间，但当前弹窗可以直接取消或点击遮罩关闭，未见脏数据检查。

建议：仅在实际修改后询问是否放弃；未修改时继续允许直接退出，避免每次多一次确认。
对应命令：/impeccable harden 编辑弹窗
位置：lib/src/features/simulator/presentation/widgets/terminal_editor.dart；route_editor.dart；sim_ui.dart。

## 认知负担与使用过程

认知负担为中等，主要有两处：跨页需要记住终端范围，以及终端注册区同时呈现 7 个参数。后者包含必要的协议复杂度，适合通过基础/高级参数分组缓解，而不是一味隐藏字段。

从使用过程看，首次创建入口是明确的；真正容易造成挫败的是编辑后意外丢失草稿，以及查报文时发现范围与刚才操作的终端不一致。

## 不同使用者的风险

- 高频联调工程师（Alex）：需要反复切页核对同一终端，缺少连接、上报、定位当前报文的快捷路径。
- 键盘或辅助功能使用者（Sam）：控件已有语义标签，但完整键盘顺序和 VoiceOver 状态播报仍需人工验证；自动化测试通过不能替代这一项。
- 边界测试使用者（Riley）：长 CSV 编辑后误关弹窗、多终端下切换日志范围，是应优先验证的情境。

## 次要观察

- “不会预置在线设备”等解释可以移到首次使用说明，不必长期占据控制台操作区。
- 顶部与底部重复显示“本地工作区”，可以保留一处。
- 原始 HEX 更适合等宽字形和按字节分组，便于逐字节比对。

本次评审没有修改界面源码。用于评审的原生应用会话已恢复主题覆盖设置并退出。模态层截图未可靠生成，未据该失败截图作视觉判断。

## 待确认的设计问题

1. 短报文详情采用随内容收缩的弹窗，还是可与列表同时比对的右侧详情栏？
2. 控制台跳转日志默认当前终端，还是保持全部终端并突出当前终端标识，或记住上次手动筛选范围？
