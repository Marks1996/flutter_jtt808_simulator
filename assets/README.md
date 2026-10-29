# 模拟器资源

## 应用标识

`images/logo.png` 为项目负责人选定的白底珊瑚红小马天线版，母版尺寸为 **1254 × 1254 PNG**。该文件从生成原图直接复制，保留白色背景、原始构图与配色。

生成来源：`output/ip-as-logo/2026-10-28-白底小马天线版/B1-天线版.png`。

已从同一母版按既有资源尺寸导出应用启动图标：

- macOS：`macos/Runner/Assets.xcassets/AppIcon.appiconset/`，16–1024 像素，共 7 张。
- iOS：`ios/Runner/Assets.xcassets/AppIcon.appiconset/`，20–1024 像素，共 15 张。
- Android：`android/app/src/main/res/mipmap-*/ic_launcher.png`，48–192 像素，共 5 张。

适配过程仅按原有尺寸缩放，不裁切、不重绘；保持 PNG RGB、不含透明通道。平台图标的原文件名与资源配置保持一致。替换前的图标备份位于 `output/ip-as-logo/2026-10-28-应用图标替换备份/`，按原项目目录保存。

## 界面与地图资源

导航继续使用各功能的图标资源，路线按实际坐标绘制。在线地图瓦片为可选资源，并保留 OpenStreetMap 署名。
