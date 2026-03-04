# ALAS Manager for Arch Linux

这是一个专为 Arch Linux 用户设计的 **AzurLaneAutoScript (ALAS)** Docker 版一键管理脚本。

本脚本旨在简化 Docker 环境下，ALAS 的安装、配置及后续更新维护流程。

## 🌟 功能特性 (Features)

* **一键环境配置**：自动安装 Docker, Docker-compose, ADB 等必要依赖。
* **自动补丁修复**：针对 Arch 编译环境，自动修复 `requirements.txt` 中的版本冲突。
* **智能更新检测**：一键同步 GitHub 源码，并自动完成补丁重应用。
* **容器化管理**：提供 启动、停止、查看日志、重新构建镜像 等常用功能。
* **彻底卸载**：一键清理容器、镜像及工作目录，不留痕迹。

## 🚀 快速开始 (Quick Start)

在终端中执行以下命令即可下载并运行管理器：

```bash
curl -sSL https://raw.githubusercontent.com/SelandiaNyx/alas-manager-for-arch/main/alas-manager-for-arch.sh -o alas-manager.sh
chmod +x alas-manager.sh
./alas-manager.sh

```

## 🛠️ 使用前准备 (Prerequisites)

如果你使用 **Waydroid** 作为模拟器，启动 ALAS 前请确保已连接 ADB：

```bash
# 查看 Waydroid IP
waydroid status

# 连接 ADB (请替换为实际 IP)
adb connect <Waydroid_IP>:5555

```

## 📂 默认路径 (Default Path)

* **脚本安装目录**: `~/Downloads/alas-docker`
* **配置文件位置**: `~/Downloads/alas-docker/config`
* **ALAS 源码**: `~/Downloads/alas-docker/src`

## 📜 免责声明 (Disclaimer)

1. 本脚本仅作为辅助安装工具，核心功能由 [AzurLaneAutoScript](https://github.com/LmeSzinc/AzurLaneAutoScript) 提供。
2. 使用脚本即表示您知晓自动化脚本可能带来的游戏账号风险，作者对此不承担任何责任。

## 🤝 致谢 (Credits)

* 核心项目: [LmeSzinc/AzurLaneAutoScript](https://github.com/LmeSzinc/AzurLaneAutoScript)
