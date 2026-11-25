# ALAS Manager for Linux

这是一个专为 Linux 用户设计的 **AzurLaneAutoScript (ALAS)** Docker 版单文件 TUI 一键管理脚本，现已从 Arch Linux 扩展支持全系列主流 Linux 发行版。

## 🌟 功能特性 (Features)

* **单文件零依赖 TUI**：纯 Bash ANSI 交互界面，支持方向键 `↑/↓`（`j/k`）、数字快捷键 `0-9`、实时状态仪表盘；支持在终端直接运行，也支持在桌面文件管理器中**双击自动拉起终端窗口运行**。
* **多语言自动适配 (i18n)**：自动检测系统语言环境并在 **简体中文 / English / 日本語** 间切换，TUI 内按 `L` 可随时切换并记住偏好，同时自动同步 ALAS WebUI 默认语言。
* **全系列 Linux 自动适配**：
  * **包管理器**：自动识别 `pacman` (Arch 系)、`apt` (Debian/Ubuntu 系)、`dnf`/`yum` (Fedora/RHEL 系，缺失 Docker 源时自动回退官方脚本)、`zypper` (openSUSE)、`apk` (Alpine)、`xbps-install` (Void)、`emerge` (Gentoo)，并对 NixOS 与 `rpm-ostree` 不可变系统提供指引。
  * **服务管理与下载器**：自动识别 `systemd` / `OpenRC` / `runit` / `sysvinit`，自动选择 `curl` / `wget` / `python3`，自动适配 `sudo` / `doas` / `pkexec` 及 `x86_64` / `aarch64` 架构。
* **Linux 补丁与安全更新**：自动对 ALAS 的 `requirements.txt` 应用 Linux/Docker 兼容补丁与容器版 `deploy.yaml` 初始化；后续更新自动处理补丁冲突、拉取上游最新源码并热重启容器。
* **Waydroid / ADB 联动**：启动时自动识别运行中的 Waydroid IP 并执行 `adb connect`，提供独立诊断入口。
* **完整生命周期管理**：启动、停止、实时日志（`Ctrl+C` 返回菜单）、更新、重建镜像、修复 Docker 权限、配置备份及彻底卸载。

## 🚀 快速开始 (Quick Start)

在终端中下载单文件脚本并运行（也可在文件管理器中直接双击 `alas-manager.sh` 运行）：

```bash
mkdir -p ~/ALAS
curl -fsSL https://raw.githubusercontent.com/SelandiaNyx/alas-manager-for-arch/main/alas-manager.sh -o ~/ALAS/alas-manager.sh
chmod +x ~/ALAS/alas-manager.sh
~/ALAS/alas-manager.sh
```

如系统只有 `wget`：

```bash
mkdir -p ~/ALAS
wget -qO ~/ALAS/alas-manager.sh https://raw.githubusercontent.com/SelandiaNyx/alas-manager-for-arch/main/alas-manager.sh
chmod +x ~/ALAS/alas-manager.sh
~/ALAS/alas-manager.sh
```

### 命令行快捷子命令 (CLI)

除交互式 TUI 外，还支持无交互子命令直达：

```bash
~/ALAS/alas-manager.sh [start|stop|restart|logs|update|rebuild|adb|status|install-desktop|uninstall] [--lang zh|en|ja]
```


> **桌面一键启动提示**：GNOME 文件管理器 (Nautilus 40+) 默认禁止双击直接运行 `.sh` 脚本（需右键选择「作为程序运行」）。运行一次 `~/ALAS/alas-manager.sh install-desktop` 即可生成桌面应用启动器，随后直接在系统应用菜单 / Fuzzel / Anyrun 中搜索 **ALAS** 一键启动！

## 🛠️ 使用前准备 (Prerequisites)

如果使用 **Waydroid** 作为模拟器，管理器在启动 ALAS 时会自动检测 Waydroid IP 并尝试 `adb connect <IP>:5555`。

首次连接若提示 `unauthorized`，请在 Waydroid 窗口中点击「**始终允许 USB 调试**」即可。启动完成后在浏览器访问：

```text
http://127.0.0.1:22267
```

## 📂 默认路径 (Default Path)

* **管理器脚本**: `~/ALAS/alas-manager.sh`
* **Docker 工作目录**: `~/ALAS/alas-docker`
* **ALAS 源码**: `~/ALAS/alas-docker/src`
* **配置文件位置**: `~/ALAS/alas-docker/config`（软链接指向 `src/config`）

## 📜 免责声明 (Disclaimer)

1. 本脚本仅作为辅助安装与管理工具，核心功能由 [AzurLaneAutoScript](https://github.com/LmeSzinc/AzurLaneAutoScript) 提供。
2. 使用脚本即表示您知晓自动化脚本可能带来的游戏账号风险，作者对此不承担任何责任。

## 🤝 致谢 (Credits)

* 核心项目: [LmeSzinc/AzurLaneAutoScript](https://github.com/LmeSzinc/AzurLaneAutoScript)
