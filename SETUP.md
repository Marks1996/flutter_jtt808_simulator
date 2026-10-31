# 平台与开发配置

## SDK

使用标准 Flutter 3.44.8。项目同时保留现代 FVM 的 `.fvmrc`；FVM 2.x 需先执行 `fvm use 3.44.8` 创建本地 SDK 链接，再运行 `fvm flutter --version` 确认。全局 OpenHarmony SDK 无需切换。

依赖按 Flutter 的 `flutter_test` 版本自然解析，已移除脚手架强制旧 `test_api` 的覆盖。首次运行 `fvm flutter pub get`；镜像源不可用时可对该条命令设置 `PUB_HOSTED_URL=https://pub.dev`。

模拟器服务器在应用中配置，不依赖 HTTP API、账号后台、地图密钥或私有 `.env`。`.env.example` 只保留脚手架可选初始化，不放真实密钥。

## macOS

已生成工程并验证 Debug 构建。调试/发布 entitlement 均有出站网络和用户选择文件读写权限；只有调试默认保留 Flutter 调试所需的服务端网络权限。包含局域网访问说明。

```bash
fvm flutter run -d macos
fvm flutter build macos --debug
```

应用构建产物：`build/macos/Build/Products/Debug/JT808Simulator.app`。首次访问局域网平台时按系统提示授权；默认测试地址为 `127.0.0.1:7100`。

## Android

主 Manifest 配置了 `android.permission.INTERNET`，因此 Release 也具备 TCP 权限。手动/模拟位置不读取手机 GPS，不需要定位或后台定位权限。

```bash
fvm flutter build apk --debug
```

APK：`build/app/outputs/flutter-apk/app-debug.apk`。Android 模拟器访问电脑测试服务一般使用 `10.0.2.2`；真实手机使用服务器的可达地址。

## iOS

已生成工程，包含 `NSLocalNetworkUsageDescription`，无需为原生 TCP 添加宽泛的 HTTP ATS 例外。选择实际设备运行需要开发团队和签名；Simulator 构建不需要给应用签名。

```bash
fvm flutter build ios --simulator --debug
```

当前 SDK 使用 Swift Package Manager。`file_picker` 需要从 GitHub 拉取 `zhangao0086/DKImagePickerController`。本次此步骤在完整网络权限下仍超时，iOS 构建未完成。请先确保 Xcode/git 能访问该仓库，再重跑；不要把网络依赖失败解释为已经通过真机验证。

## Windows

已生成 Windows 桌面工程。使用项目 FVM SDK，在安装 Visual Studio 的“使用 C++ 的桌面开发”工作负载后运行：

```bash
fvm flutter run -d windows
fvm flutter build windows --debug
```

已在 Windows 上通过 Debug 构建、静态分析及 119 项测试。CMake 显式使用 UTF-8 编译源码，避免中文系统代码页引发插件 C4819 错误。

## Linux

尚未生成或验证 Linux 工程。若需要此目标，请在对应开发环境执行 Flutter 官方 `flutter create --platforms=linux .`，再进行平台依赖及 TCP/文件操作验证。应用核心 Dart 代码不依赖 macOS 专用协议实现。

## 调试与测试

```bash
fvm flutter analyze
fvm flutter test --test-randomize-ordering-seed=20261025
fvm dart run tool/mock_jt808_server.dart 7100
```

多个 Flutter test 进程同时在同一工作区运行，可能竞争 `build/native_assets/macos` 的签名产物；请使用一个测试进程执行完整套件，不要并发启动多个同目标测试命令。

协议模型与工作区使用手写 JSON，不需要生成 Hive adapter。修改翻译后可按脚手架惯例执行：

```bash
fvm dart run easy_localization:generate -S assets/translations -O lib/src/core/i18n -o locale_keys.g.dart
```
