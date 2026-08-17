<div align="center">
  <img src="Resources/AppIcon.png" width="128" height="128" alt="RestPilot app icon">
  <h1>RestPilot</h1>
  <p>一个完全本地运行的 macOS 菜单栏休息助手。</p>
</div>

RestPilot 通过眼睛休息和站立休息帮你建立更健康的工作节奏。它不需要账号、网络或云服务，所有设置和运行状态都保存在本机。

## 主要功能

- 眼睛休息与站立休息组合计划
- 菜单栏倒计时、暂停、重置和手动休息
- 自动休息可延后 5 分钟，并记录连续跳过情况
- 多显示器全屏休息提示与柔和淡入淡出
- 可编辑提示文字、导入图片并选择内置背景
- 锁屏、睡眠和长时间无操作时自动暂停
- 浅色与深色外观，跟随 macOS 系统强调色
- 可选开机启动和休息结束提示音

## 系统要求

- macOS 13 Ventura 或更高版本
- Swift 6.0 兼容工具链

项目仅使用 SwiftUI、AppKit、ServiceManagement 等系统框架，没有第三方运行时依赖。

## 构建与运行

```bash
swift test
zsh scripts/build-app.sh
open outputs/RestPilot.app
```

构建脚本会在 `outputs/RestPilot.app` 生成本地应用。它不会执行开发者签名、公证或自动更新配置。

## 隐私

RestPilot 不会发起网络请求，不包含分析 SDK，也不收集使用数据。你导入的背景和提示图片只保存在本机。

## 项目结构

```text
Sources/RestPilot/   应用源码
Tests/               日程、交互与视觉回归测试
Resources/           应用图标和内置背景
scripts/             本地 .app 构建脚本
```

## 许可证

源代码和仓库内自带的图像资源均在 [MIT License](LICENSE) 下发布。
