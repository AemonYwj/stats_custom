# Stats

<a href="https://github.com/exelban/stats/releases"><p align="center"><img src="https://github.com/exelban/stats/raw/master/Stats/Supporting%20Files/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="120"></p></a>

[![Stats](https://serhiy.s3.eu-central-1.amazonaws.com/Github_repo/stats/menus%3Fv2.3.2.png?v1)](https://github.com/exelban/stats/releases)
[![Stats](https://serhiy.s3.eu-central-1.amazonaws.com/Github_repo/stats/popups%3Fv2.3.2.png?v3)](https://github.com/exelban/stats/releases)

macOS 菜单栏系统监控工具

> 本仓库基于 [exelban/stats](https://github.com/exelban/stats) 进行扩展，新增了 AI 用量监控模块。原始项目由 [Serhiy Mytrovtsiy](https://github.com/exelban) 开发，采用 MIT 协议开源。

## 安装

### 手动安装
从 [Releases](https://github.com/AemonYwj/stats_custom/releases) 下载最新版本的 `Stats.dmg`，打开后将应用拖入 Applications 文件夹。

### Homebrew
```bash
brew install stats
```

### 卸载
```bash
sh /Applications/Stats.app/Contents/Resources/Scripts/uninstall.sh
```

## 系统要求
Stats 支持 macOS 12 (Monterey) 及以上版本。不保证 Beta 版兼容性。

## 功能

Stats 是一款 macOS 系统监控应用，支持以下模块：

- CPU 利用率
- GPU 利用率
- 内存使用
- 磁盘使用
- 网络流量
- 电池电量
- 风扇控制（维护模式）
- 传感器信息（温度/电压/功耗）
- 蓝牙设备
- 多时区时钟
- **AI 用量** — ChatGPT/Codex、DeepSeek、Kimi Coding Plan 额度监控（本仓库新增）

## AI 用量模块
> 本仓库新增模块，上游 [exelban/stats](https://github.com/exelban/stats) 不包含此功能。

AI 用量模块读取本地 CLI 登录凭证，将 AI 服务剩余额度实时显示在 Stats 菜单栏和弹窗中。

### 支持的提供商

| 提供商 | 数据来源 | 配置方式 |
|--------|----------|----------|
| ChatGPT / Codex | `~/.codex/auth.json` → `chatgpt.com/backend-api/wham/usage` | 默认启用，需先 `codex login` |
| DeepSeek | API Key → `api.deepseek.com/user/balance` | 在设置中填写 API Key |
| Kimi Coding Plan | `~/.kimi-code/credentials/kimi-code.json` → `api.kimi.com/coding/v1/user/usage` | 自动检测，需先 `kimi login` |

### 架构设计

- 沿用 Stats 原生的 `Module` / `Popup` / `Settings` / `Reader` / `Widget` 模块架构
- 各提供商实现 `AIUsageProvider` 协议，新增提供商只需实现协议并注册
- 菜单栏显示首选提供商的剩余额度百分比（支持 Mini / BarChart / Tachometer / Text 控件）
- 弹窗展示所有已启用提供商的详细信息：套餐类型、额度窗口、余额、重置倒计时
- 设置中可独立开关各提供商、配置 API Key、调整刷新频率（1 分钟 — 1 小时）

### 弹窗示例
```
ChatGPT Pro
  每周额度: 42% · 3天12小时
  短周期额度: 68% · 1小时22分

DeepSeek
  余额: 110.00 CNY

Kimi Coding Plan
  Coding Plan · 85%
```

### 隐私说明
所有凭证均从本地读取，API 令牌仅发送至各提供商的官方接口：
- `chatgpt.com`
- `api.deepseek.com`
- `api.kimi.com`

不读取浏览器 Cookie，不向第三方发送任何数据。

## 外部 API

Stats 本身不收集任何遥测数据。AI 用量模块新增以下外部请求：

- https://api.mac-stats.com — 检查更新、获取公网 IP
- https://api.github.com — 更新检查的备用源
- https://chatgpt.com — AI 用量模块（Codex/ChatGPT 额度）
- https://api.deepseek.com — AI 用量模块（DeepSeek 余额）
- https://api.kimi.com — AI 用量模块（Kimi Coding Plan 用量）

## 常见问题

### 如何调整菜单栏图标顺序？
按住 ⌘ 键拖动图标即可。

### Stats 图标不出现在菜单栏？
macOS 26 新增了隐私控制：**系统设置 → 菜单栏**，确保 Stats 已开启。

### 如何降低 Stats 的能耗？
禁用 Sensors 和 Bluetooth 模块可减少高达 50% 的 CPU 占用和功耗。

### 风扇控制
风扇控制处于维护模式，不接收功能更新，但在旧款 Mac 上仍可使用。

### 传感器显示 CPU/GPU 核心数不准确？
CPU/GPU 传感器是芯片上的热感区域（thermal zones），与实际核心数量无关。

### 外部 API 请求说明
如果您对 Stats 的外部请求有顾虑，可以用网络过滤工具（如 Little Snitch）屏蔽相关域名，但这将导致无法收到更新通知、网络模块中看不到公网 IP，以及 AI 用量模块无法获取额度数据。

## 支持的语言
- English
- 中文 (简体)
- 中文 (繁體)
- Українська
- Русский
- Polski
- Türkçe
- 한국어
- Deutsch
- Español
- Français
- Italiano
- 日本語
- 以及其他 20+ 种语言

## 许可证
[MIT License](https://github.com/exelban/stats/blob/master/LICENSE)

## 致谢
本项目基于 [exelban/stats](https://github.com/exelban/stats) 扩展开发，感谢 [Serhiy Mytrovtsiy](https://github.com/exelban) 和所有 stats 贡献者。
