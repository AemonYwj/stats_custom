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

AI 用量模块读取本地 CLI 登录凭证，将 AI 服务额度使用量实时显示在 Stats 菜单栏和弹窗中。

### 支持的提供商

| 提供商 | 数据来源 | 配置方式 |
|--------|----------|----------|
| ChatGPT / Codex | `~/.codex/auth.json` → `chatgpt.com/backend-api/wham/usage` | 默认启用，需先 `codex login` |
| DeepSeek | API Key → `api.deepseek.com/user/balance` | 在设置中填写 API Key |
| Kimi Coding Plan | `~/.kimi-code/credentials/kimi-code.json` → `api.kimi.com/coding/v1/usages` | 自动检测，需先 `kimi login`；OAuth 过期后自动刷新 |
| OpenCode Go | `~/.local/share/opencode/auth.json` + `opencode.db` | 自动检测；本地估算 5 小时 $12、每周 $30、每月 $60 三个窗口 |

### 架构设计

- 沿用 Stats 原生的 `Module` / `Popup` / `Settings` / `Reader` / `Widget` 模块架构
- 各提供商实现 `AIUsageProvider` 协议，新增提供商只需实现协议并注册
- 菜单栏显示剩余额度；默认是 ChatGPT 周额度，并可在设置中精确选择提供商和额度窗口
- 弹窗用成对进度条比较“额度剩余”和“时间剩余”；OpenCode Go 增加 5 小时、周、月三个窗口
- 设置中可选择顶部栏指标、独立开关各提供商、配置 API Key（输入时即时保存）、调整刷新频率（1 分钟 — 1 小时）

### 弹窗示例
```
ChatGPT Pro
  每周额度: 剩余 58% · 时间剩余 43%

DeepSeek
  余额: 110.00 CNY

Kimi Coding Plan
  每周额度: 剩余 65% · 时间剩余 43%
  5 小时额度: 剩余 32% · 时间剩余 36%

OpenCode Go · 本地估算
  5 小时额度 · 每周额度 · 每月额度
```

### 隐私说明
所有凭证均从本地读取，API 令牌仅发送至各提供商的官方接口：
- `chatgpt.com`
- `api.deepseek.com`
- `api.kimi.com`

OpenCode Go 的额度由 Stats 从 OpenCode 本机 SQLite 用量历史估算，其 API Key 不会由 Stats 发送到网络。

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
