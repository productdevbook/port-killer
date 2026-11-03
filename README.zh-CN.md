# PortKiller

<p align="center">
  <img src="https://raw.githubusercontent.com/productdevbook/port-killer/refs/heads/main/platforms/macos/Resources/AppIcon.svg" alt="PortKiller Icon" width="128" height="128">
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
  <a href="https://www.apple.com/macos/"><img src="https://img.shields.io/badge/macOS-15.0%2B-brightgreen" alt="macOS"></a>
  <a href="https://www.microsoft.com/windows"><img src="https://img.shields.io/badge/Windows-10%2B-0078D6" alt="Windows"></a>
  <a href="https://github.com/productdevbook/port-killer/releases"><img src="https://img.shields.io/github/v/release/productdevbook/port-killer" alt="GitHub Release"></a>
</p>

<p align="center">
专为开发者打造的跨平台端口管理工具。<br>
监控监听端口、管理 Kubernetes 端口转发、集成 Cloudflare 隧道，并支持一键结束占用进程。
</p>

<p align="center">
  <a href="README.md">English</a> | 简体中文
</p>

### macOS

<p align="center">
  <img src=".github/assets/macos.png" alt="PortKiller macOS" width="800">
</p>

### Windows

<p align="center">
  <img src=".github/assets/windows.jpeg" alt="PortKiller Windows" width="800">
</p>

## 安装

### macOS

**Homebrew：**
```bash
brew install --cask productdevbook/tap/portkiller
```

**手动安装：** 从 [GitHub Releases](https://github.com/productdevbook/port-killer/releases) 下载 `.dmg` 安装包。

### Windows

从 [GitHub Releases](https://github.com/productdevbook/port-killer/releases) 下载 `.zip` 压缩包并解压运行。

## 功能特性

### 端口管理
- 🔍 自动发现所有正在监听的 TCP 端口
- ⚡ 一键结束进程（支持优雅退出与强制结束）
- 🔄 支持自定义间隔的自动刷新
- 🔎 按端口号或进程名称搜索与筛选
- ⭐ 收藏常用端口以便快速访问
- 👁️ 监控指定端口并在状态变化时发送通知
- 📂 智能进程分类（Web 服务器、数据库、开发工具、系统进程）

### Kubernetes 端口转发
- 🔗 创建与管理 `kubectl port-forward` 会话
- 🔌 连接断开时自动重连
- 📝 实时连接日志与状态监控
- 🔔 连接与断开状态通知

### Cloudflare 隧道
- ☁️ 查看与管理活动的 Cloudflare Tunnel 连接
- 🌐 快速查看隧道状态与公网访问地址

### 跨平台原生体验
- 📍 菜单栏常驻集成（macOS）
- 🖥️ 系统托盘应用（Windows / Linux）
- 🎨 各平台原生 UI 设计

## 参与贡献

开发环境配置与构建说明请参阅 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 赞助商

<p align="center">
  <a href="https://cdn.jsdelivr.net/gh/productdevbook/static/sponsors.svg">
    <img src='https://cdn.jsdelivr.net/gh/productdevbook/static/sponsors.svg'/>
  </a>
</p>

## 开源协议

MIT 协议 - 详见 [LICENSE](LICENSE)。
