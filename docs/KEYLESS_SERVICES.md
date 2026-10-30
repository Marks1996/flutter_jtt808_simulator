# 免 Key 公开地图与 OSRM 地址

调研及单次连通检查：2026-10-30。本页收集的是不需在 URL 填写 Key 的公开服务；免 Key 不等于不限流、生产服务承诺或永久可用。应用不会为测试批量抓取瓦片，也不会自动在不同服务间重试。

## 当前可用的替换预设（2026-10-30 补测）

用户反馈 OSM 快捷预设不可用后，已将该快捷入口替换为 **Esri World Imagery 卫星影像**，不再推荐点击不可达的 OSM 标准地址。进入「设置 → 地图底图」，点击「填入影像底图 · 免 Key」，然后点击应用。程序自动选中自定义 XYZ、填入 WGS84 和服务元数据中的来源标识；不会覆盖其他图商 Key 或 OSRM 配置。已经保存的旧 OSM 配置不被静默改写，需要点击新预设并应用。

模板：`https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}`。

- 使用应用 User-Agent、跳过代理，分别直连北京 `12/1552/3372`、`14/6208/13489`、`16/24833/53959`、`19/198666/431674`，均为 HTTP 200、`image/jpeg`。已逐张打开确认有真实建筑/道路影像，不是权限或无数据提示图。
- ArcGIS 模板顺序是 `zoom/row/column`，即 `{z}/{y}/{x}`，不能误写成 `{z}/{x}/{y}`。官方元数据为 256×256、Web Mercator（102100/3857），按 WGS84 经纬度显示，不做 GCJ-02 偏移。
- 来源：`Esri, Vantor, Earthstar Geographics, and the GIS User Community`。公开接口本次无需 Key，但受 Esri 服务使用条款约束，不等于无限量或商用许可；`exportTilesAllowed=false`，不提供批量离线下载。
- 这是卫星影像，不带中文道路注记，也不保证拍摄时间或道路实时性。单次本机直连成功不能保证目标大陆网络始终可达。
- 同时检查的 Esri `World_Street_Map`：北京 12 级虽正常，14 级返回 `Map data not yet available` 图片，因此**没有加入道路预设**。GeoQ 和 OSM 标准接口本次连接超时，也不作为已验证可用地址推荐。
- [官方服务元数据](https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer?f=pjson)与[官方图层及条款](https://www.arcgis.com/home/item.html?id=10df2279f9684e4a9f6a7f08febac2a9)。

下面保留此前调研的免 Key 规划服务及其他地址信息；公共 OSRM/FOSSGIS 规划入口仍可使用，不受本次瓦片替换影响。

## 公开服务调研与规划预设

「设置 → 地图底图」当前使用上述实测影像预设；OSM 连接地址仍可手动编辑。在「设置 → 路径规划」点击「公共 OSRM · 免 Key」或「FOSSGIS OSRM · 免 Key」，再应用配置。按钮填入地址并选中对应服务，不会立即保存或联网；填入后仍可编辑自定义地址，原有国内服务 Key 保留。

| 类型 | 免 Key 地址 | 本次单次直连结果 | 使用边界 |
|---|---|---|---|
| OSM 标准栅格底图 | `https://tile.openstreetmap.org/{z}/{x}/{y}.png` | `0/0/0.png` 连接超时，未取得图片 | 官方模板；仅当前视口交互浏览，显示 OSM 归属，应用标识与缓存；禁止批量预取，无 SLA |
| OSRM 官方演示入口 | `https://router.project-osrm.org` | HTTP 200；北京与柏林示例均 `code=Ok` | 公开驾车规划；不需 Key，轻量人工调用，禁大量请求；无 SLA |
| FOSSGIS OSRM 驾车入口 | `https://routing.openstreetmap.de/routed-car` | HTTP 200；北京与柏林示例均 `code=Ok` | 全球驾车路网；最多每秒一次、连接限制、来源和报告地图错误链接；禁重度使用，无 SLA |

两个规划入口可能使用相同或相关基础设施，不能把它们当作相互独立的高可用备份。应用使用共享规划服务实例，对两个公共入口合并限制为至少一秒的请求间隔、同时最多一个在途公共请求；不自动排队重试。修改地址或取消不会发送第二次请求。自建端点保留自己的调用策略。

**OSM 底图和 OSRM 路径规划是两项不同服务**：瓦片不可达不代表 OSRM 不可用；配置公共 OSRM 也不会改变当前天地图或其他底图。国内默认值保持天地图＋高德，免 Key 预设由使用者主动选择，不在缺 Key、失败或启动时自动替换配置。

### 完整请求示例

填写在 OSRM 设置中的应为表格里的基础地址，不包含 `/route/v1/driving` 和坐标。程序会自动拼接：

- `https://router.project-osrm.org/route/v1/driving/116.407400,39.904200;116.420000,39.910000?overview=full&geometries=geojson&steps=false&alternatives=false`
- `https://routing.openstreetmap.de/routed-car/route/v1/driving/116.407400,39.904200;116.420000,39.910000?overview=full&geometries=geojson&steps=false&alternatives=false`

本次使用项目应用 User-Agent、明确跳过代理的命令行直连检查，两个北京请求均返回首路线距离 `3319.1 m`、`LineString` 完整几何和中文道路名称。结果说明检查当时的本机网络可以访问接口并获得中国区域路网数据，**不证明目标大陆运营商网络、原生应用或所有地区始终可达**。道路数据可能陈旧、吸附位置可能与选点有距离，不用于真实道路导航或限行保证。路线保存、CSV 和 JT808 上报仍为 WGS84。

## 另外收集但未设为默认预设的地址

| 服务 | 地址 / 状态 | 未直接纳入免 Key 预设的原因 |
|---|---|---|
| OSM France HOT | `https://{s}.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png`，`s=a/b/c` | 单次 `a` 子域名低缩放 PNG 返回 HTTP 200，但官方要求公开可访问、非营利、中等流量，移动应用也需免费/非营利及有效应用标识；禁止内网用途，不适合作为本地联调工具的通用预设。符合条件并自行确认许可后，可在自定义 XYZ 配置并填写完整归属 |
| CARTO Positron / Dark Matter 栅格 | 网上常见 `https://basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png`、`dark_all/...` | 官方 FAQ 已说明 **2026-09-25 起栅格瓦片必须使用 Key**；无 Key 可能仍返回 HTTP 200 PNG，但内容是要求 Key 的提示，不是可用底图。本次两个低缩放地址虽返回 PNG，也不据此认定免 Key 可用 |
| FOSSGIS 德国瓦片 | `tile.openstreetmap.de` | 官方限制独立下载瓦片的应用须事先获准；不将公共可下载地址当作本应用的授权预设 |

未收录网上流传的高德/百度内部图片接口或别人项目中暴露的 Token。需要中国大陆长期稳定使用时，可用自己的天地图/高德 Key 或在大陆部署自有 OSM/OSRM 服务，见 [CHINA_ACCESS.md](CHINA_ACCESS.md)。

## 归属、隐私和服务政策

- OSM 标准图使用官方精确 HTTPS 地址，应用保留可见版权链接、独立应用 User-Agent 和地图组件原生缓存；没有瓦片离线区域下载功能。
- OSRM 结果显示来源、OpenStreetMap/ODbL 和「报告地图错误」链接，独立于当前底图。用户明确点击规划时才发送选点；公共服务可记录访问日志。不要发送敏感的真实线路。
- FOSSGIS 要求使用方适用时在应用网站/商店条目公开可联系的邮箱；发布和商用前需核对其完整政策，不能用本地限流代替全部使用条件。
- 一次成功响应不能推导稳定性，HTTP 200 也不能证明图片内是正常地图。需要在目标网络检查实际道路图、中文地名、完整线路和账号/许可边界。

## 官方来源

- [OSM Tile Usage Policy](https://operations.osmfoundation.org/policies/tiles/)：精确地址、应用标识、可见归属、缓存及禁止批量下载。
- [OSRM 公共服务政策入口](https://github.com/Project-OSRM/osrm-backend/wiki/Api-usage-policy)：当前演示服务政策和地址说明。
- [FOSSGIS OSRM 服务说明](https://routing.openstreetmap.de/about.html)：驾车全球路网、请求隐私、OSRM 版本及限制。
- [FOSSGIS 完整使用条件](https://www.fossgis.de/arbeitsgruppen/osm-server/nutzungsbedingungen/)：请求频率、连接、归属、地图错误链接、商用/重度使用限制。
- [OSM France 图源说明](https://www.openstreetmap.fr/fonds-de-carte/)与[使用条件](https://www.openstreetmap.fr/usage/)：HOT、公开/非营利/流量约束。
- [CARTO Basemaps FAQ](https://docs.carto.com/faqs/carto-basemaps)：2026 年栅格 Key 政策变化，免费额度不等于免 Key。
