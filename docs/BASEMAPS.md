# 底图配置与图源调研

调研日期：2026-10-30。本文区分官方公开服务与社区流传的内部瓦片地址；能下载图片不等于获准在第三方地图引擎中使用。

## 使用方式

提供「填入影像底图 · 免 Key」快捷预设，使用 Esri World Imagery，自动填入 WGS84 与服务来源。它替换了此前不可达的 OSM 标准快捷地址；手动 OSM 连接保留。需要点击应用后才保存，也可继续编辑自定义地址。不同缩放级别的图片实测与许可边界见 [KEYLESS_SERVICES.md](KEYLESS_SERVICES.md)。

1. 在「设置 → 地图底图」选择图源。新工作区及缺少底图字段的旧工作区默认开启天地图，需配置自己的地图服务 Key，自动加载 `vec_w` 底图与 `cva_w` 中文注记；没有 Key 时不请求瓦片，并提示设置位置。已明确保存的图源、地址、Key 和开关保留。国内配置与实网验收见 [CHINA_ACCESS.md](CHINA_ACCESS.md)。
2. 天地图、高德和百度分别提供可空的独立 Key/AK 字段；高德/百度底图仍需允许第三方地图引擎使用的授权 HTTPS 瓦片模板，可先留空保存。普通 Key 不会自动变成瓦片地址。本项目不附带内部瓦片地址或公共 Key。自定义 OSM 使用自己的 HTTPS XYZ 连接，不提供 Key 字段；规划的自定义 OSRM 同样仅填写连接地址。
3. 自定义图源需填写模板、坐标系和数据来源/版权标识。适用于标准 Web Mercator XYZ 栅格瓦片；不接受矢量 PBF、Style JSON、普通 WMS 或任意 WMTS 投影。
4. 点击「应用底图配置」。设置保存在本机，并随工作区 JSON 导入/导出；不同来源的地址分别保留。控制台、线路和编辑器预览共用配置。预览中的「在线底图」开关也会保存。
5. 加载失败会暂时显示离线 WGS84 轨迹，保留已保存的开关和图源，可点击「重试底图」。关闭在线底图后仅显示离线轨迹；空坐标预览不会创建瓦片层。
6. 「地图建线」与空坐标预览不同：打开后即按初始查看范围加载底图，以便选点。底图关闭或失败时仍保留交互坐标地图和手动坐标输入；它本身不包含道路数据。路径规划单独配置，见 [ROUTE_PLANNING.md](ROUTE_PLANNING.md)。

配置不会创建终端、连接 JT808 平台或自动运行任务。

## 网上图源比较

| 图源 | 官方接入与坐标 | 本项目处理 |
|---|---|---|
| OpenStreetMap | 公共标准 XYZ；WGS84 地理坐标配合 Web Mercator；无需 Key，但受公共瓦片政策限制 | 可选海外图源，不保证中国大陆可达；保留已有选择，不作为新工作区默认。持续显示版权链接并发送应用标识，不提供批量预取 |
| 高德地图 | 官方 API/SDK 使用 GCJ-02；服务协议限制直接使用内部图片和未经授权的第三方接入 | 提供 GCJ-02 显示适配；须由使用者提供获授权的标准 XYZ 地址，最高缩放 18 |
| 百度地图 | 官方 API/SDK 使用 BD-09，地图投影还涉及百度墨卡托；不是普通 EPSG:3857 XYZ | 提供 BD-09、百度墨卡托及原点瓦片编号适配；须提供与下文约定一致的授权地址 |
| 天地图 | 官方带 Key 的 WMTS；`_w` 为球面墨卡托，`_c` 为经纬度投影 | 国内默认选项：填写自有 Key，自动加载官方 `vec_w` 底图和 `cva_w` 中文注记。其他 `_w` 服务仍可配置为单层自定义来源，不支持 `_c` |
| MapTiler | 官方 Maps API 提供带 API Key 的 Raster XYZ，支持 256px 瓦片及多种图片格式 | 可使用自有账号的 256px 栅格地址作为自定义来源，选择 WGS84，并按其要求填写完整版权信息；受套餐、配额及许可约束 |
| 自建或其他已授权来源 | 标准 256px Web Mercator XYZ；坐标可为 WGS84 或 GCJ-02 | 使用自定义来源，避免把地图服务商名称当作授权证明 |

普通高德 Key、百度 AK 或商业基础服务许可，不应被当作任意内部瓦片接口的授权。对直接瓦片使用范围、版权/商标/审图号、缓存、商业用途有疑问时，应向供应商确认；项目中的文字归属不能替代供应商要求的全部标识。

## 地址模板

- 非空连接必须为 HTTPS，包含 `{z}`、`{x}`、`{y}`；允许可选 `{s}`、`{r}`。高德/百度模板额外允许查询参数中的 `{key}`，由对应独立 Key 安全编码替换，不能用于主机名或路径；其他图源不接受此占位符。未知占位符仍被拒绝，空连接则保存为待配置状态。`{r}` 为地图组件的可选高清后缀。
- 不接受网址内的用户名/密码、片段或空格。API Key/令牌应使用供应商支持的查询参数形式。
- `{s}` 的替换范围：高德 `1–4`，百度 `0–3`，自定义 `a/b/c`。其他范围应固定具体主机名，不使用 `{s}`。
- 默认按 256px 栅格瓦片解释。自定义图源缩放范围为 3–19，应选择覆盖该范围的服务；不自动发现 TileJSON 元数据。

标准 XYZ 示例（占位域名，不可实际访问）：`https://tiles.example.com/{z}/{x}/{y}.png?token=YOUR_TOKEN`。

MapTiler 官方 API 模板示例：`https://api.maptiler.com/maps/streets-v4/256/{z}/{x}/{y}.png?key=YOUR_MAPTILER_API_KEY`。需替换为自己有权使用的 Key 和地图样式，并核实当前套餐及归属要求。

天地图官方球面墨卡托影像示例：`https://t0.tianditu.gov.cn/img_w/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=img&STYLE=default&TILEMATRIXSET=w&FORMAT=tiles&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&tk=YOUR_KEY`。需自备 Key、选择 WGS84 显示，并按授权要求标注来源。作为自定义来源时只加载该影像层；内置天地图选项则自动加载矢量底图与中文注记两层。

### 百度模板约定

百度选项不是给标准 XYZ 服务改名。它要求：

- 输入图源地理坐标为 BD-09，经百度墨卡托多项式投影。
- 256px 瓦片，投影原点为 `(0, 0)`，像素比例为 `2^(zoom − 18)`。
- 服务端 X 从原点向东增长，Y 从原点向北增长。组件屏幕 Y 向下，因此服务端 Y 为 `−tileY − 1`。
- 负瓦片编号以 `M` 加绝对值编码，例如 `−1 → M1`。

此网格适配是实现约定，**不是百度对外开放瓦片 API 或稳定性的承诺**。实际合同图源的原点、编号或瓦片尺寸不同，需要另行适配。若服务商已将百度数据转换为标准 XYZ，应按供应商说明使用自定义来源，而不是此百度原点适配器。

## 坐标与隐私边界

- CSV 线路输入、存储、CSV/JSON 导出、回放、里程计算和 JT808 上报使用 **WGS84**。预览按图源转换显示坐标；地图建线则将所选位置反向转换为 WGS84，路径规划在 API 边界转换坐标后保存 WGS84。见 [ROUTE_PLANNING.md](ROUTE_PLANNING.md)。
- 本地转换为常见近似算法，不是供应商在线坐标转换服务，也不用于测绘或道路导航。GCJ-02 转换采用常见矩形范围判断，不是精确国界判断；边境和海外图源需实际核对对齐情况。
- 百度投影纬度限制为 ±74°；OSM/其他标准 Web Mercator 也有高纬度显示限制。原始坐标不会因此被改写。
- 在线底图开关默认开启，配置有效后才请求瓦片。天地图缺少 Key 时不请求，也不自动切换 OSM。有坐标的地图预览及地图建线会向所选图源请求瓦片，图源可获得 IP、查看区域、应用标识及 URL 中的令牌；不会将手机号、车牌或完整线路 CSV 附加到请求。
- 保存的天地图 Key、各来源地址及其中令牌会以明文写入 Hive 和工作区 JSON。分享前应移除这些内容；关闭底图不会删除已保存的地址，也不能撤销已发出的网络请求。
- OSM 公共瓦片无可用性保证，可能受网络或配额限制。批量部署前应核对政策并考虑自建或有服务协议的供应商。

## 调研来源

- [OpenStreetMap Tile Usage Policy](https://operations.osmfoundation.org/policies/tiles/)：归属、应用标识、缓存和禁止批量预取等要求。
- [高德坐标转换说明](https://lbs.amap.com/api/javascript-api/guide/transform/convertfrom)：GPS/WGS84 与高德坐标的关系。
- [高德开放平台服务协议](https://lbs.amap.com/pages/terms)：重点为 3.5、4.12 的内部数据与第三方接入限制，以及商业用途许可。
- [百度坐标说明](https://lbsyun.baidu.com/faq/api?title=androidsdk/guide/tool/coordinate)及[坐标转换 API](https://lbsyun.baidu.com/index.php?title=webapi/guide/changeposition)：BD-09 与坐标转换。
- [百度开放平台服务条款](https://lbsyun.baidu.com/index.php?title=open/law)：重点为 2.2、3.3 的内部数据限制及标识、许可要求。
- [天地图官方地图服务](https://lbs.tianditu.gov.cn/server/MapService.html)：Key、WMTS、`_w`/`_c` 投影及请求模板。
- [MapTiler 官方 Maps API](https://docs.maptiler.com/cloud/api/maps/)：Raster XYZ、256px 与 Key。
- [gcoord BD09MC](https://github.com/hujiulong/gcoord/blob/master/src/crs/BD09MC.ts)：百度墨卡托多项式常量参考，MIT 许可保留于 `lib/src/features/simulator/data/maps/GCOORD_LICENSE`。此代码参考不构成百度服务使用授权。

自动化测试覆盖本地配置、坐标数学和组件行为；高德、百度、天地图及 MapTiler 的授权图源尚未实网验收。实际可用性需使用自己的授权地址和凭证在目标平台确认。
