# 参考依据与实现决定

## 已有模拟器

本实现核对了同工作区的 `../jtt808-simulator`，重点文件：

- `README.md`：线路、行程、位置与日志的产品工作流；声明只支持 2013，提醒百度坐标差异。
- `src/main/java/cn/org/hentai/simulator/task/SimpleDriveTask.java`：TCP 注册、位置体、里程附加项和文本下发。旧实现注册后直接上报位置，没有完成鉴权和心跳；Flutter 版本依据协议补齐，而不是复制此缺陷。
- `src/main/java/cn/org/hentai/simulator/task/AbstractDriveTask.java`：32 位报警/状态标志，初始状态 `0x00040003`（ACC、定位、GPS）。
- `src/main/java/cn/org/hentai/simulator/manager/RouteManager.java`：按速度、间隔生成行驶位置的概念。Flutter 版本采用可重复的折线插值；没有复制其随机停留、地图依赖或时间偏差。
- `src/main/java/cn/org/hentai/simulator/jtt808/JTT808Encoder.java` 与 `task/net/JT808MessageDecoder.java`：帧结构参考。旧接收器缺少可靠反转义及严格拒绝坏校验，因此重新实现严格编解码。
- `src/main/resources/templates/monitor.ftl`：单车状态、位置、位标志及日志交互。
- `src/main/resources/application.properties`：旧目标服务器 `127.0.0.1:7100`，沿用为新建终端表单的可编辑默认值。

没有复用旧项目的真实用户数据库、现成账号或地图密钥。没有把 README 的 10 万辆目标当作实测性能，也没有把已注释或未接通的按钮认定为已完成功能。

## 可公开核对的协议资料

1. [SmallChi/JT808](https://github.com/SmallChi/JT808)：帧头、XOR、转义、消息体长度上限，以及 README 中完整的 `0x0200` 十六进制样例。测试把该样例作为独立逐字节依据，而不是仅做本实现的编码/解码自洽测试。
2. [终端注册结构](https://github.com/SmallChi/JT808/blob/master/src/JT808.Protocol/MessageBody/JT808_0x0100.cs)：2013 的 5/20/7 字节身份字段与 GBK 车牌；明确区分 2019 的长度。
3. [位置体结构](https://github.com/SmallChi/JT808/blob/master/src/JT808.Protocol/MessageBody/JT808_0x0200.cs)：百万分之一度、0.1 km/h、方向、GMT+8 时间及状态位。
4. [EMQX：JT808 数据交换格式](https://docs.emqx.com/en/emqx/latest/develop/gateway/jt808_data_exchange.html)：注册、鉴权、心跳、参数与位置相关消息结构及版本区别。
5. [EMQX：JT808 网关](https://docs.emqx.com/en/emqx/latest/gateway/jt808.html)：注册与鉴权是独立环节，连接状态和应答超时具有实际互通意义。
6. [百度地图：坐标转换](https://lbsyun.baidu.com/index.php?title=jspopular/guide/coorinfo)：BD09、GCJ02、WGS84 的差异。已有百度线路不能不经确认直接作为卫星定位坐标。

本次没有取得并逐条审阅正式标准全文，因此不声称获得标准认证或实现了标准的所有消息。

## UI Skill 的使用

工作区没有预装用户点名的两个 Skill。已读取其公开原文和应用界面规范：

- [Impeccable](https://github.com/pbakaus/impeccable)：`SKILL.md`、`reference/operate.md`、`reference/craft-floor.md`（当前仓库位于 `.agents/skills/impeccable/`）。使用 Operate 任务型界面规则：克制配色、状态反馈、固定逻辑字号、原生操作习惯、错误恢复、真实渲染检查。
- [Taste Skill](https://github.com/Leonxlnx/taste-skill)：`skills/taste-skill/SKILL.md`、`references/app-screens.md`。采用应用界面而非营销页面规则：安静导航、平面容器、真实为零的数据、数字对齐、颜色只承担数据/状态/主要动作、手机折叠导航。

界面延续脚手架已有蓝色 `#204bc3`，没有假称运行了不可用的方向抽签、原生上下文加载器或基于 DOM 的浏览器检查脚本。Flutter 的布局/交互检查通过 widget tests 和渲染图完成。系统字体是 Impeccable 对原生任务型界面允许的选择。

## 明确的新设计值

- 心跳默认 30 秒、位置上报默认 5 秒；心跳是新增能力，旧项目的 30 秒注释不代表其已实现。
- 心跳与位置参数支持范围是 1–3600 秒，便于联调而非宣称标准只有此范围。
- 新建表单中的名称、SIM、终端号、型号、车牌和初始坐标是可修改的示例；程序不自动保存或连接它们。
- 路线 CSV 限制 2–10000 点，速度 1–200 km/h；手工位置可设 0 km/h。CSV 示例仅为折线，非道路导航。
- 内存报文日志最多保留最近 2000 条；导出由用户操作，不自动上传。
- 自动重连默认关闭；手动断开停止重连和定时任务。
