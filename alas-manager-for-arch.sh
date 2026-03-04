#!/bin/bash
# =================================================================
# Project: ALAS Manager for Arch Linux
# Description: 一键安装、更新、管理 Docker 版 AzurLaneAutoScript
# Author: [SelandiaNyx]
# Credits: 基于 selandia.top 的 Arch Linux 指南编写
# License: GPL-3.0
# =================================================================

# 设置安装路径、源码地址和镜像名称
INSTALL_DIR="$HOME/Downloads/alas-docker"
REPO_URL="https://github.com/LmeSzinc/AzurLaneAutoScript.git"
IMAGE_NAME="alas-conda"

# 定义终端输出颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 显示菜单标题
print_banner() {
    clear
    echo -e "${BLUE}==========================================${NC}"
    echo -e "${BLUE}       ALAS Docker 管理器 (Arch Linux)    ${NC}"
    echo -e "${BLUE}==========================================${NC}"
}

# 安装必要系统依赖并配置 Docker 环境
setup_environment() {
    echo -e "${YELLOW}[!] 检查系统依赖...${NC}"
    sudo pacman -S --needed --noconfirm docker docker-compose android-tools git
    
    if ! systemctl is-active --quiet docker; then
        sudo systemctl enable --now docker
    fi

    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"

    # 写入 Dockerfile 配置文件
    cat <<EOF > Dockerfile
FROM python:3.7-slim
RUN apt-get update && apt-get install -y --no-install-recommends \\
    wget git adb libgomp1 openssh-client ca-certificates \\
    libgl1-mesa-glx libglib2.0-0 libsm6 libxext6 libxrender1 \\
    && apt-get clean && rm -rf /var/lib/apt/lists/*
RUN wget -q https://repo.anaconda.com/miniconda/Miniconda3-py313_25.9.1-3-Linux-x86_64.sh \\
    -O /tmp/miniconda.sh \\
    && bash /tmp/miniconda.sh -b -p /opt/conda \\
    && rm /tmp/miniconda.sh
ENV PATH="/opt/conda/bin:\${PATH}"
RUN conda config --system --remove channels defaults \\
    && conda config --system --add channels conda-forge \\
    && conda config --system --set channel_priority strict \\
    && conda install -y mamba
WORKDIR /app/AzurLaneAutoScript
COPY src/requirements.txt /tmp/requirements.txt
RUN AV_VERSION=\$(grep '^av==' /tmp/requirements.txt | cut -d '=' -f 3) \\
    && mamba install -y "python=3.7" "av==\$AV_VERSION" \\
    && conda clean --all --yes
RUN grep -v '^av==' /tmp/requirements.txt > /tmp/req.txt \\
    && pip install --no-cache-dir -r /tmp/req.txt \\
    && rm /tmp/requirements.txt /tmp/req.txt
CMD ["python", "gui.py"]
EOF

    # 写入 docker-compose.yml 配置文件
    cat <<EOF > docker-compose.yml
services:
  alas:
    image: $IMAGE_NAME
    container_name: alas
    network_mode: host
    restart: unless-stopped
    volumes:
      - ~/.android:/root/.android
      - ./config:/app/AzurLaneAutoScript/config
      - ./src:/app/AzurLaneAutoScript
    working_dir: /app/AzurLaneAutoScript
    command: python gui.py
EOF
}

# 检查远程仓库源码是否有更新
check_update() {
    if [ ! -d "$INSTALL_DIR/src" ]; then
        echo -e "${YELLOW}[!] 克隆远程仓库...${NC}"
        git clone "$REPO_URL" "$INSTALL_DIR/src"
        apply_patches
        return
    fi

    echo -e "${YELLOW}[*] 正在检查源码更新...${NC}"
    cd "$INSTALL_DIR/src"
    git fetch
    LOCAL=$(git rev-parse HEAD)
    REMOTE=$(git rev-parse @{u})

    if [ $LOCAL != $REMOTE ]; then
        echo -e "${GREEN}[+] 发现更新，正在拉取代码...${NC}"
        git pull
        apply_patches
    else
        echo -e "${GREEN}[OK] 源码已是最新。${NC}"
    fi
    cd "$INSTALL_DIR"
}

# 修改 requirements.txt 以适配 Docker 编译环境
apply_patches() {
    echo -e "${YELLOW}[*] 应用环境兼容性补丁...${NC}"
    sed -i 's/^av==/# av==/' "$INSTALL_DIR/src/requirements.txt"
    sed -i 's/^pywin32==/# pywin32==/' "$INSTALL_DIR/src/requirements.txt"
    sed -i 's/requests==2.18.4/requests>=2.20.0,<3/' "$INSTALL_DIR/src/requirements.txt"
}

# 运行 Docker 镜像构建流程
build_image() {
    echo -e "${YELLOW}[*] 正在构建镜像...${NC}"
    cd "$INSTALL_DIR"
    docker build -t "$IMAGE_NAME" .
}

# 停止容器并删除相关所有文件和镜像
uninstall_alas() {
    read -p "确定要彻底删除 ALAS 吗？(y/N): " confirm
    if [[ $confirm == [yY] ]]; then
        cd "$INSTALL_DIR" && docker-compose down
        docker rmi "$IMAGE_NAME"
        rm -rf "$INSTALL_DIR"
        echo -e "${GREEN}[OK] 已清理所有相关资源。${NC}"
        exit 0
    fi
}

# 主程序循环
while true; do
    print_banner
    echo -e "1. ${GREEN}启动 ALAS${NC}"
    echo -e "2. ${YELLOW}停止 ALAS${NC}"
    echo -e "3. ${BLUE}查看 运行日志${NC}"
    echo -e "4. 检查/下载 源码更新"
    echo -e "5. 重新构建 镜像"
    echo -e "6. ${RED}完全卸载 ALAS${NC}"
    echo -e "7. 退出"
    echo -e "------------------------------------------"
    
    # 状态检测逻辑
    if [ -d "$INSTALL_DIR" ]; then
        STATUS=$(docker ps -q -f name=alas 2>/dev/null)
        EXIT_CODE=$?
        if [ $EXIT_CODE -ne 0 ]; then
            echo -e "当前状态: ${RED}权限不足 (Docker Permission Denied)${NC}"
        elif [ ! -z "$STATUS" ]; then
            echo -e "当前状态: ${GREEN}正在运行 (Running)${NC}"
        else
            echo -e "当前状态: ${RED}已停止 (Stopped)${NC}"
        fi
    else
        echo -e "当前状态: ${YELLOW}尚未安装${NC}"
    fi
    echo -e "------------------------------------------"
    
    read -p "请输入选项 [1-7]: " choice

    case $choice in
        1)
            if [ ! -f "$INSTALL_DIR/docker-compose.yml" ]; then setup_environment; fi
            if [ ! -d "$INSTALL_DIR/src" ]; then check_update; fi
            if [[ "$(docker images -q $IMAGE_NAME 2> /dev/null)" == "" ]]; then build_image; fi
            cd "$INSTALL_DIR" && docker-compose up -d
            sleep 2
            ;;
        2)
            if [ -d "$INSTALL_DIR" ]; then
                cd "$INSTALL_DIR" && docker-compose stop
            fi
            sleep 2
            ;;
        3)
            if [ -d "$INSTALL_DIR" ]; then
                cd "$INSTALL_DIR" && docker-compose logs -f
            fi
            ;;
        4)
            check_update
            read -p "按回车键继续..."
            ;;
        5)
            build_image
            read -p "按回车键继续..."
            ;;
        6)
            uninstall_alas
            ;;
        7)
            exit 0
            ;;
        *)
            echo -e "${RED}无效选项。${NC}"
            sleep 1
            ;;
    esac
done
