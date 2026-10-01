#!/usr/bin/env bash
# =================================================================
# Project: ALAS Manager for Arch Linux
# Version: 2.0.0
# Description: 一键安装、更新、管理 Docker 版 AzurLaneAutoScript
# Author: SelandiaNyx
# License: GPL-3.0
#
# 2.0 设计原则：
# - 直接复用 ALAS 上游 deploy/docker/Dockerfile 与 requirements.txt
# - 不再修改 ALAS requirements.txt
# - 不再安装 Miniconda / Conda / Mamba
# - ALAS 源码以 bind mount 方式挂载，用户配置保留在源码 config 目录
# - 支持从 1.x 目录安全迁移
# =================================================================

set -u
set -o pipefail
IFS=$'\n\t'

VERSION="2.0.0"

INSTALL_DIR="${HOME}/Downloads/alas-docker"
SRC_DIR="${INSTALL_DIR}/src"
COMPOSE_FILE="${INSTALL_DIR}/compose.yaml"
IMAGE_BUILD_COMMIT_FILE="${INSTALL_DIR}/.image-source-commit"

REPO_URL="https://github.com/LmeSzinc/AzurLaneAutoScript.git"
REPO_BRANCH="master"

IMAGE_NAME="alas"
LEGACY_IMAGE_NAME="alas-conda"
CONTAINER_NAME="alas"
SERVICE_NAME="ALAS"
WEBUI_PORT="22267"

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
NC=$'\033[0m'

DOCKER_COMPOSE=()

msg() {
    printf '%s\n' "$*"
}

info() {
    printf '%s[*]%s %s\n' "$YELLOW" "$NC" "$*"
}

ok() {
    printf '%s[OK]%s %s\n' "$GREEN" "$NC" "$*"
}

warn() {
    printf '%s[!]%s %s\n' "$YELLOW" "$NC" "$*"
}

err() {
    printf '%s[ERROR]%s %s\n' "$RED" "$NC" "$*" >&2
}

pause_menu() {
    read -r -p "按回车键继续..." _
}

print_banner() {
    clear
    printf '%s==============================================%s\n' "$BLUE" "$NC"
    printf '%s      ALAS Docker 管理器 for Arch Linux       %s\n' "$BLUE" "$NC"
    printf '%s                 v%s                    %s\n' "$BLUE" "$VERSION" "$NC"
    printf '%s==============================================%s\n' "$BLUE" "$NC"
}

require_arch_linux() {
    if [[ ! -f /etc/arch-release ]]; then
        err "未检测到 /etc/arch-release。此脚本仅面向 Arch Linux。"
        return 1
    fi
}

select_compose_command() {
    if docker compose version >/dev/null 2>&1; then
        DOCKER_COMPOSE=(docker compose)
        return 0
    fi

    if command -v docker-compose >/dev/null 2>&1 && docker-compose version >/dev/null 2>&1; then
        DOCKER_COMPOSE=(docker-compose)
        return 0
    fi

    err "未找到可用的 Docker Compose。"
    return 1
}

compose() {
    if (( ${#DOCKER_COMPOSE[@]} == 0 )); then
        select_compose_command || return 1
    fi
    "${DOCKER_COMPOSE[@]}" -f "$COMPOSE_FILE" "$@"
}

install_system_dependencies() {
    local packages=(
        docker
        docker-compose
        docker-buildx
        git
    )
    local missing=()
    local pkg

    info "检查 Arch Linux 系统依赖..."

    for pkg in "${packages[@]}"; do
        if ! pacman -Q "$pkg" >/dev/null 2>&1; then
            missing+=("$pkg")
        fi
    done

    if (( ${#missing[@]} > 0 )); then
        info "安装缺失软件包: ${missing[*]}"
        sudo pacman -S --needed --noconfirm "${missing[@]}" || {
            err "pacman 安装失败。"
            return 1
        }
    else
        ok "系统依赖已安装。"
    fi

    if ! systemctl is-active --quiet docker; then
        info "启动并启用 Docker 服务..."
        sudo systemctl enable --now docker || {
            err "Docker 服务启动失败。"
            return 1
        }
    fi

    select_compose_command || return 1
}

ensure_docker_access() {
    if docker info >/dev/null 2>&1; then
        return 0
    fi

    if ! sudo docker info >/dev/null 2>&1; then
        err "Docker daemon 当前不可用。请先检查：systemctl status docker"
        return 1
    fi

    warn "当前 shell 没有访问 Docker daemon 的权限。"
    info "将用户 ${USER} 加入 docker 组。"
    sudo usermod -aG docker "$USER" || {
        err "无法将当前用户加入 docker 组。"
        return 1
    }

    if command -v sg >/dev/null 2>&1; then
        info "使用新的 docker 组权限重新启动本管理器..."
        local quoted_script
        printf -v quoted_script '%q' "$SCRIPT_PATH"
        exec sg docker -c "$quoted_script"
    fi

    warn "系统没有 sg 命令。请注销并重新登录后再次运行本脚本。"
    return 1
}

write_compose_file() {
    mkdir -p "$INSTALL_DIR" "$HOME/.android"

    cat > "$COMPOSE_FILE" <<'EOF'
services:
  ALAS:
    container_name: "alas"
    image: "alas"
    network_mode: "host"
    restart: "unless-stopped"
    build:
      context: "./src/deploy/docker"
      dockerfile: "./Dockerfile"
    volumes:
      - "./src:/app/AzurLaneAutoScript:rw"
      - "${HOME}/.android:/root/.android:rw"
      - "/etc/localtime:/etc/localtime:ro"
EOF

    ok "Compose 配置已写入: $COMPOSE_FILE"
}

ensure_source() {
    mkdir -p "$INSTALL_DIR"

    if [[ -d "$SRC_DIR/.git" ]]; then
        return 0
    fi

    if [[ -e "$SRC_DIR" ]]; then
        if [[ -d "$SRC_DIR" ]] && [[ -z "$(find "$SRC_DIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
            rmdir "$SRC_DIR" || return 1
        else
            err "$SRC_DIR 已存在，但不是可识别的 Git 仓库。"
            err "为避免覆盖未知数据，脚本不会继续。"
            return 1
        fi
    fi

    info "克隆 ALAS 上游仓库 (${REPO_BRANCH})..."
    git clone --branch "$REPO_BRANCH" --single-branch "$REPO_URL" "$SRC_DIR" || {
        err "ALAS 源码克隆失败。"
        return 1
    }

    ok "ALAS 源码克隆完成。"
}

validate_upstream_layout() {
    local required=(
        "$SRC_DIR/gui.py"
        "$SRC_DIR/deploy/docker/Dockerfile"
        "$SRC_DIR/deploy/docker/requirements.txt"
    )
    local path

    for path in "${required[@]}"; do
        if [[ ! -f "$path" ]]; then
            err "ALAS 上游目录结构与本管理器预期不一致，缺少：$path"
            err "脚本不会猜测新的路径，请先更新本管理器。"
            return 1
        fi
    done
}

repair_v1_requirements_patch() {
    local target="$SRC_DIR/requirements.txt"
    local original
    local expected_v1

    [[ -d "$SRC_DIR/.git" && -f "$target" ]] || return 0

    if git -C "$SRC_DIR" diff --quiet -- requirements.txt; then
        return 0
    fi

    original="$(mktemp)"
    expected_v1="$(mktemp)"

    if ! git -C "$SRC_DIR" show HEAD:requirements.txt > "$original"; then
        rm -f "$original" "$expected_v1"
        return 0
    fi

    cp "$original" "$expected_v1"
    sed -i 's/^av==/# av==/' "$expected_v1"
    sed -i 's/^pywin32==/# pywin32==/' "$expected_v1"
    sed -i 's/requests==2.18.4/requests>=2.20.0,<3/' "$expected_v1"

    if cmp -s "$target" "$expected_v1"; then
        info "检测到 1.x 管理器留下的 requirements.txt 补丁，正在恢复上游原文件..."
        git -C "$SRC_DIR" restore -- requirements.txt
        ok "已恢复 requirements.txt；2.0 不再修改上游依赖文件。"
    fi

    rm -f "$original" "$expected_v1"
}

migrate_v1_config() {
    local legacy_config="$INSTALL_DIR/config"
    local backup_dir

    [[ -d "$legacy_config" ]] || return 0

    if [[ -z "$(find "$legacy_config" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
        rmdir "$legacy_config" 2>/dev/null || true
        return 0
    fi

    mkdir -p "$SRC_DIR/config"

    info "检测到 1.x 的独立配置目录，正在迁移到 ALAS 源码 config 目录..."
    cp -a --no-clobber "$legacy_config"/. "$SRC_DIR/config"/ || {
        err "旧配置复制失败，原目录保持不变。"
        return 1
    }

    backup_dir="${INSTALL_DIR}/config.v1-backup-$(date +%Y%m%d-%H%M%S)"
    mv "$legacy_config" "$backup_dir" || {
        err "无法重命名旧配置目录。"
        return 1
    }

    ok "旧配置已迁移。原目录保留为备份：$backup_dir"
}

container_exists() {
    docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1
}

container_running() {
    [[ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null || true)" == "true" ]]
}

handle_existing_container() {
    local config_files
    local workdir

    container_exists || return 0

    config_files="$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.project.config_files" }}' "$CONTAINER_NAME" 2>/dev/null || true)"
    workdir="$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}' "$CONTAINER_NAME" 2>/dev/null || true)"

    if [[ "$config_files" == *"$COMPOSE_FILE"* ]]; then
        return 0
    fi

    if [[ "$workdir" == "$INSTALL_DIR" ]]; then
        info "检测到同一安装目录下由旧版 Compose 创建的 ALAS 容器，正在迁移..."
        docker rm -f "$CONTAINER_NAME" >/dev/null || {
            err "旧 ALAS 容器移除失败。"
            return 1
        }
        ok "旧容器已移除；配置和源码数据未删除。"
        return 0
    fi

    err "检测到名为 '$CONTAINER_NAME' 的现有容器，但无法确认它属于本安装目录。"
    err "为避免误删其他容器，本管理器不会继续。"
    err "请手动执行以下命令确认来源："
    msg "  docker inspect $CONTAINER_NAME"
    return 1
}

current_source_commit() {
    git -C "$SRC_DIR" rev-parse HEAD 2>/dev/null
}

image_exists() {
    docker image inspect "$IMAGE_NAME" >/dev/null 2>&1
}

build_image() {
    validate_upstream_layout || return 1

    info "使用 ALAS 上游 deploy/docker/Dockerfile 构建镜像..."
    compose build --pull "$SERVICE_NAME" || {
        err "Docker 镜像构建失败。"
        return 1
    }

    current_source_commit > "$IMAGE_BUILD_COMMIT_FILE" || true
    ok "镜像构建完成。"
}

docker_inputs_changed_between() {
    local old_commit="$1"
    local new_commit="$2"

    git -C "$SRC_DIR" cat-file -e "${old_commit}^{commit}" 2>/dev/null || return 0
    git -C "$SRC_DIR" cat-file -e "${new_commit}^{commit}" 2>/dev/null || return 0

    ! git -C "$SRC_DIR" diff --quiet "$old_commit" "$new_commit" -- \
        deploy/docker/Dockerfile \
        deploy/docker/requirements.txt
}

ensure_image_current() {
    local current
    local built=""

    current="$(current_source_commit)" || {
        err "无法读取 ALAS 当前 Git commit。"
        return 1
    }

    if ! image_exists; then
        info "尚未检测到 $IMAGE_NAME 镜像。"
        build_image
        return $?
    fi

    if [[ ! -f "$IMAGE_BUILD_COMMIT_FILE" ]]; then
        warn "现有镜像没有 2.0 构建记录，将重建一次以建立可靠基线。"
        build_image
        return $?
    fi

    built="$(tr -d '[:space:]' < "$IMAGE_BUILD_COMMIT_FILE")"

    if [[ "$built" == "$current" ]]; then
        return 0
    fi

    if docker_inputs_changed_between "$built" "$current"; then
        info "ALAS 的 Dockerfile/容器依赖自上次构建后发生变化，需要重建镜像。"
        build_image
        return $?
    fi

    # 镜像只包含运行环境，ALAS 源码通过 bind mount 提供。
    # Docker 构建输入未改变时，镜像仍然有效。
    printf '%s\n' "$current" > "$IMAGE_BUILD_COMMIT_FILE"
}

prepare_runtime() {
    require_arch_linux || return 1
    install_system_dependencies || return 1
    ensure_docker_access || return 1
    ensure_source || return 1
    repair_v1_requirements_patch
    handle_existing_container || return 1
    migrate_v1_config || return 1
    validate_upstream_layout || return 1
    write_compose_file || return 1
    select_compose_command || return 1
    compose config -q || {
        err "生成的 Compose 配置未通过 docker compose config 校验。"
        return 1
    }
}

start_alas() {
    prepare_runtime || return 1
    ensure_image_current || return 1

    info "启动 ALAS..."
    compose up -d "$SERVICE_NAME" || {
        err "ALAS 启动失败。"
        return 1
    }

    ok "ALAS 已启动。"
    msg "WebUI: http://127.0.0.1:${WEBUI_PORT}"
    warn "ALAS 默认 WebUIHost 为 0.0.0.0。不要把 ${WEBUI_PORT} 直接映射/转发到公网。"
}

stop_alas() {
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        warn "未找到 $COMPOSE_FILE。"
        return 0
    fi

    select_compose_command || return 1

    info "停止 ALAS..."
    compose stop "$SERVICE_NAME"
}

show_logs() {
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        warn "ALAS 2.0 尚未初始化。"
        return 0
    fi

    select_compose_command || return 1
    compose logs -f --tail=200 "$SERVICE_NAME"
}

working_tree_clean() {
    [[ -z "$(git -C "$SRC_DIR" status --porcelain --untracked-files=no)" ]]
}

show_tracked_changes() {
    git -C "$SRC_DIR" status --short --untracked-files=no
}

update_alas() {
    local local_commit
    local remote_commit
    local new_commit
    local upstream
    local was_running="false"
    local built=""

    prepare_runtime || return 1

    if ! working_tree_clean; then
        err "ALAS 仓库存在未提交的 tracked 文件修改，管理器不会覆盖它们："
        show_tracked_changes
        return 1
    fi

    if container_running; then
        was_running="true"
    fi

    info "获取 ALAS 上游更新..."
    git -C "$SRC_DIR" fetch --prune origin || {
        err "git fetch 失败。"
        return 1
    }

    upstream="$(git -C "$SRC_DIR" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
    if [[ -z "$upstream" ]]; then
        err "当前 Git 分支没有 upstream tracking 配置。"
        err "脚本不会猜测需要跟踪的远程分支。"
        return 1
    fi

    local_commit="$(git -C "$SRC_DIR" rev-parse HEAD)" || return 1
    remote_commit="$(git -C "$SRC_DIR" rev-parse "$upstream")" || return 1

    if [[ "$local_commit" != "$remote_commit" ]]; then
        if ! git -C "$SRC_DIR" merge-base --is-ancestor "$local_commit" "$remote_commit"; then
            err "本地分支不是 $upstream 的简单 fast-forward 状态。"
            err "为避免覆盖本地提交或处理分叉，管理器停止自动更新。"
            return 1
        fi

        info "发现 ALAS 更新：${local_commit:0:8} -> ${remote_commit:0:8}"
        git -C "$SRC_DIR" pull --ff-only || {
            err "git pull --ff-only 失败。"
            return 1
        }
    else
        ok "ALAS 源码已经是 $upstream 最新版本。"
    fi

    new_commit="$(git -C "$SRC_DIR" rev-parse HEAD)" || return 1

    if [[ -f "$IMAGE_BUILD_COMMIT_FILE" ]]; then
        built="$(tr -d '[:space:]' < "$IMAGE_BUILD_COMMIT_FILE")"
    fi

    if [[ -z "$built" ]] || ! image_exists; then
        build_image || return 1
    elif [[ "$built" != "$new_commit" ]] && docker_inputs_changed_between "$built" "$new_commit"; then
        info "本次更新包含 Docker 构建依赖变化，自动重建镜像。"
        build_image || return 1
    else
        printf '%s\n' "$new_commit" > "$IMAGE_BUILD_COMMIT_FILE"
    fi

    if [[ "$was_running" == "true" ]]; then
        info "重启 ALAS 以载入最新源码..."
        compose up -d --force-recreate "$SERVICE_NAME" || return 1
    fi

    ok "ALAS 更新检查完成。"
}

force_rebuild() {
    prepare_runtime || return 1
    build_image || return 1

    if container_running; then
        info "使用新镜像重新创建 ALAS 容器..."
        compose up -d --force-recreate "$SERVICE_NAME" || return 1
    fi
}

show_diagnostics() {
    local status
    local image_id
    local commit

    msg ""
    msg "===== ALAS 诊断信息 ====="
    msg "管理器版本: $VERSION"
    msg "安装目录:   $INSTALL_DIR"

    if ! docker info >/dev/null 2>&1; then
        msg "Docker:     无法访问"
        return 1
    fi

    msg "Docker:     可访问"

    if select_compose_command; then
        msg "Compose:    ${DOCKER_COMPOSE[*]}"
    else
        msg "Compose:    未检测到"
    fi

    if [[ -d "$SRC_DIR/.git" ]]; then
        commit="$(git -C "$SRC_DIR" rev-parse --short HEAD 2>/dev/null || true)"
        msg "ALAS commit: ${commit:-读取失败}"
    else
        msg "ALAS commit: 未安装"
    fi

    status="$(docker inspect -f '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || true)"
    msg "容器状态:   ${status:-不存在}"

    image_id="$(docker image inspect -f '{{.Id}}' "$IMAGE_NAME" 2>/dev/null || true)"
    msg "镜像:       ${image_id:-不存在}"

    if container_running; then
        msg ""
        msg "----- 容器内 ADB -----"
        docker exec "$CONTAINER_NAME" adb version 2>&1 || true
        docker exec "$CONTAINER_NAME" adb devices -l 2>&1 || true
        msg ""
        msg "WebUI: http://127.0.0.1:${WEBUI_PORT}"
    fi
}

fix_docker_permission() {
    require_arch_linux || return 1

    if docker info >/dev/null 2>&1; then
        ok "当前用户已经可以访问 Docker daemon。"
        return 0
    fi

    ensure_docker_access
}

cleanup_legacy_image() {
    if ! docker image inspect "$LEGACY_IMAGE_NAME" >/dev/null 2>&1; then
        ok "未检测到 1.x 旧镜像 $LEGACY_IMAGE_NAME。"
        return 0
    fi

    read -r -p "确认删除旧镜像 '$LEGACY_IMAGE_NAME'？(y/N): " confirm
    if [[ "$confirm" =~ ^[yY]$ ]]; then
        docker image rm "$LEGACY_IMAGE_NAME"
    fi
}

backup_config() {
    local backup_file

    [[ -d "$SRC_DIR/config" ]] || return 0

    backup_file="${HOME}/Downloads/alas-config-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    tar -C "$SRC_DIR" -czf "$backup_file" config || {
        err "config 备份失败。"
        return 1
    }

    ok "ALAS config 已备份到：$backup_file"
}

uninstall_alas() {
    local confirm
    local backup_answer

    warn "此操作会删除：容器、2.0 的 alas 镜像以及 $INSTALL_DIR。"
    read -r -p "请输入 DELETE 以确认完全卸载: " confirm

    if [[ "$confirm" != "DELETE" ]]; then
        msg "已取消。"
        return 0
    fi

    read -r -p "卸载前备份 ALAS config 到 ~/Downloads？(Y/n): " backup_answer
    if [[ ! "$backup_answer" =~ ^[nN]$ ]]; then
        backup_config || return 1
    fi

    if [[ -f "$COMPOSE_FILE" ]]; then
        select_compose_command || return 1
        compose down --remove-orphans || true
    elif container_exists; then
        local workdir
        workdir="$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}' "$CONTAINER_NAME" 2>/dev/null || true)"
        if [[ "$workdir" == "$INSTALL_DIR" ]]; then
            docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
        fi
    fi

    docker image rm "$IMAGE_NAME" >/dev/null 2>&1 || true
    rm -rf "$INSTALL_DIR"

    ok "ALAS Manager 相关安装目录和 2.0 镜像已删除。"
    warn "Docker、Docker Compose、Git 等系统软件包不会被卸载。"
}

status_line() {
    local status

    if ! docker info >/dev/null 2>&1; then
        printf '当前状态: %sDocker 不可访问%s\n' "$RED" "$NC"
        return
    fi

    status="$(docker inspect -f '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || true)"

    case "$status" in
        running)
            printf '当前状态: %s正在运行%s  |  WebUI: http://127.0.0.1:%s\n' "$GREEN" "$NC" "$WEBUI_PORT"
            ;;
        "")
            if [[ -d "$SRC_DIR/.git" ]]; then
                printf '当前状态: %s已安装，容器不存在%s\n' "$YELLOW" "$NC"
            else
                printf '当前状态: %s尚未安装%s\n' "$YELLOW" "$NC"
            fi
            ;;
        *)
            printf '当前状态: %s%s%s\n' "$YELLOW" "$status" "$NC"
            ;;
    esac
}

main_menu() {
    while true; do
        print_banner

        msg "1. ${GREEN}首次安装 / 启动 ALAS${NC}"
        msg "2. ${YELLOW}停止 ALAS${NC}"
        msg "3. ${CYAN}查看运行日志${NC}"
        msg "4. 检查并更新 ALAS"
        msg "5. 强制重新构建 Docker 镜像"
        msg "6. 查看容器 / ADB 诊断"
        msg "7. 修复 Docker 用户权限"
        msg "8. 清理 1.x 旧镜像 (${LEGACY_IMAGE_NAME})"
        msg "9. ${RED}完全卸载 ALAS${NC}"
        msg "0. 退出"
        msg "----------------------------------------------"
        status_line
        msg "----------------------------------------------"

        read -r -p "请输入选项 [0-9]: " choice

        case "$choice" in
            1)
                start_alas
                pause_menu
                ;;
            2)
                stop_alas
                pause_menu
                ;;
            3)
                show_logs
                ;;
            4)
                update_alas
                pause_menu
                ;;
            5)
                force_rebuild
                pause_menu
                ;;
            6)
                show_diagnostics
                pause_menu
                ;;
            7)
                fix_docker_permission
                pause_menu
                ;;
            8)
                cleanup_legacy_image
                pause_menu
                ;;
            9)
                uninstall_alas
                pause_menu
                ;;
            0)
                exit 0
                ;;
            *)
                err "无效选项。"
                sleep 1
                ;;
        esac
    done
}

main_menu
