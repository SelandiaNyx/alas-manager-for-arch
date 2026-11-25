#!/usr/bin/env bash
# =================================================================
# Project: ALAS Manager for Linux (Universal Single-File TUI)
# Version: 1.5.0
# Description: 全系列 Linux 通用 Docker 版 AzurLaneAutoScript 管理工具
#              支持自动检测系统语言、包管理器、初始化系统与下载工具
#              支持终端直接运行或文件管理器双击运行
# Author: SelandiaNyx
# License: GPL-3.0
# =================================================================

set -u
set -o pipefail

# ------------------------- 基础配置 -------------------------
APP_VERSION="1.5.0"
INSTALL_DIR="$HOME/ALAS/alas-docker"
SRC_DIR="$INSTALL_DIR/src"
REPO_URL="https://github.com/LmeSzinc/AzurLaneAutoScript.git"
IMAGE_NAME="alas-conda"
CONTAINER_NAME="alas"
WEBUI_PORT="22267"
LANG_PREF_FILE="$INSTALL_DIR/.ui-lang"

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"

# ------------------------- 颜色与样式 -------------------------
if [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    C_RED=$'\033[0;31m'
    C_BRED=$'\033[1;31m'
    C_GREEN=$'\033[0;32m'
    C_BGREEN=$'\033[1;32m'
    C_YELLOW=$'\033[1;33m'
    C_BLUE=$'\033[0;34m'
    C_BBLUE=$'\033[1;34m'
    C_BCYAN=$'\033[1;36m'
    C_WHITE=$'\033[1;37m'
    C_REV=$'\033[7m'
else
    C_RESET="" C_BOLD="" C_DIM="" C_RED="" C_BRED="" C_GREEN="" C_BGREEN=""
    C_YELLOW="" C_BLUE="" C_BBLUE="" C_BCYAN="" C_WHITE="" C_REV=""
fi

# ------------------------- 全局运行时状态 -------------------------
UI_LANG=""
OS_ID="unknown"
OS_PRETTY="Linux"
CPU_ARCH="x86_64"
PKG_MANAGER="unknown"
INIT_SYSTEM="unknown"
SUDO_CMD=""
DOWNLOADER="none"
COMPOSE_CMD=()

TUI_ACTIVE=0
TUI_SELECTED=0
DASH_STATUS_TEXT=""
DASH_STATUS_COLOR=""
DASH_WEBUI_TEXT=""
DASH_SRC_TEXT=""
DASH_ADB_TEXT=""
DASH_ADB_COLOR=""

declare -A MSG=()

# =================================================================
# 1. 多语言 i18n 模块（自动检测系统语言，支持 zh / en / ja）
# =================================================================

detect_system_lang() {
    local override="${1:-${ALAS_LANG:-}}"
    local raw_locale=""

    if [ -n "$override" ]; then
        raw_locale="$override"
    elif [ -f "$LANG_PREF_FILE" ]; then
        raw_locale="$(tr -d '[:space:]' < "$LANG_PREF_FILE" 2>/dev/null || true)"
    else
        raw_locale="${LC_ALL:-${LC_MESSAGES:-${LANGUAGE:-${LANG:-en}}}}"
    fi

    # LANGUAGE 可能是冒号分隔列表，取第一个条目
    raw_locale="${raw_locale%%:*}"
    raw_locale="$(printf '%s' "$raw_locale" | tr '[:upper:]' '[:lower:]')"

    case "$raw_locale" in
        zh*|cn*)
            UI_LANG="zh"
            ;;
        ja*|jp*)
            UI_LANG="ja"
            ;;
        *)
            UI_LANG="en"
            ;;
    esac
}

load_i18n() {
    MSG=()
    case "$UI_LANG" in
        zh)
            MSG[app_title]="ALAS Docker 管理器"
            MSG[lang_label]="简体中文"
            MSG[sec_status]="运行状态"
            MSG[sec_actions]="功能菜单"
            MSG[lbl_system]="系统环境"
            MSG[lbl_container]="容器状态"
            MSG[lbl_webui]="WebUI 地址"
            MSG[lbl_source]="ALAS 源码"
            MSG[lbl_adb]="模拟器 / ADB"
            MSG[lbl_path]="安装目录"
            MSG[st_running]="● 正在运行 (Running)"
            MSG[st_stopped]="○ 已停止 (Stopped)"
            MSG[st_not_installed]="◌ 尚未安装"
            MSG[st_perm_denied]="✖ Docker 权限不足"
            MSG[st_docker_down]="✖ Docker 服务未运行"
            MSG[st_webui_up]="可访问"
            MSG[st_webui_wait]="未监听"
            MSG[st_src_none]="未下载"
            MSG[st_adb_none]="未检测到设备"
            MSG[st_adb_no_bin]="未安装 adb"
            MSG[st_adb_unauth]="已发现但未授权 (unauthorized)"
            MSG[st_adb_connected]="已连接"
            MSG[st_waydroid_ready]="Waydroid 已连接"
            MSG[st_waydroid_unauth]="Waydroid 未授权 (请在窗口点允许)"
            MSG[st_waydroid_disc]="Waydroid 运行中 (未连接 ADB)"
            MSG[menu_1]="启动 ALAS"
            MSG[desc_1]="自动检查依赖、下载/补丁源码、连接 ADB 并启动 WebUI"
            MSG[menu_2]="停止 ALAS"
            MSG[desc_2]="停止正在运行的 ALAS 容器"
            MSG[menu_3]="查看实时日志"
            MSG[desc_3]="实时查看容器输出日志（按 Ctrl+C 返回界面）"
            MSG[menu_4]="检查并更新 ALAS"
            MSG[desc_4]="安全同步 GitHub 最新代码、自动重打 Linux 补丁并重启"
            MSG[menu_5]="连接 Waydroid / ADB 诊断"
            MSG[desc_5]="自动识别 Waydroid IP、连接 ADB 并检查可用设备"
            MSG[menu_6]="重新构建 Docker 镜像"
            MSG[desc_6]="从 Dockerfile 重新构建 alas-conda 运行环境镜像"
            MSG[menu_7]="修复 Docker 用户权限"
            MSG[desc_7]="将当前用户加入 docker 组并尝试立即刷新权限"
            MSG[menu_8]="切换界面语言 (中文/EN/日本語)"
            MSG[desc_8]="当前语言：简体中文（也会记住你的选择）"
            MSG[menu_9]="完全卸载 ALAS"
            MSG[desc_9]="确认后备份配置并删除容器、镜像与安装目录"
            MSG[menu_0]="退出管理器"
            MSG[desc_0]="退出本程序（不会停止正在运行的 ALAS 容器）"
            MSG[footer_tui]="↑/↓ 选择   Enter 执行   0-9 快捷触发   R 刷新   L 切语言   Q 退出"
            MSG[prompt_choice]="请输入选项 [0-9] (R刷新/L切语言/Q退出): "
            MSG[press_enter]="按回车键返回主界面..."
            MSG[invalid_choice]="无效选项。"
            MSG[err_no_root_tool]="需要管理员权限，但未找到 sudo / doas / pkexec，请以 root 运行或手动安装依赖。"
            MSG[info_sys_check]="[1/3] 检测系统环境与必要依赖..."
            MSG[ok_deps_ready]="系统依赖已齐全。"
            MSG[info_deps_install]="正在通过 %s 安装缺失依赖: %s"
            MSG[err_deps_install]="依赖安装失败，请检查软件源或网络后重试。"
            MSG[warn_nixos]="检测到 NixOS（声明式系统），请在 configuration.nix 中启用以下配置后 rebuild："
            MSG[warn_ostree]="检测到不可变系统 (%s)，请手动执行以下命令并重启后继续："
            MSG[warn_unknown_pm]="未识别的包管理器 (%s)，请手动安装以下工具: %s"
            MSG[warn_docker_fallback]="默认软件源未包含 Docker，正在尝试通过 %s 使用官方安装脚本 (get.docker.com)..."
            MSG[err_no_downloader]="未检测到 curl / wget，无法下载官方 Docker 安装脚本。"
            MSG[info_docker_check]="[2/3] 检查 Docker 服务与访问权限..."
            MSG[info_docker_start]="正在启动 Docker 服务 (%s)..."
            MSG[err_docker_start]="Docker 服务启动失败，请检查系统服务日志。"
            MSG[info_workdir_prep]="[3/3] 准备工作目录 (%s)..."
            MSG[ok_env_ready]="运行环境与 Compose 配置已就绪。"
            MSG[err_no_compose]="未找到可用的 docker compose 或 docker-compose 命令。"
            MSG[info_fix_perm]="正在将用户 %s 加入 docker 组..."
            MSG[ok_fix_perm]="已加入 docker 组，正在尝试通过 sg 立即生效..."
            MSG[warn_relogin]="请注销并重新登录（或执行 newgrp docker）使权限生效。"
            MSG[ok_perm_already]="当前用户已具备 Docker 访问权限，无需修复。"
            MSG[info_patch]="正在应用 Linux/Docker 兼容性补丁 (requirements.txt)..."
            MSG[ok_patch]="requirements.txt 补丁已应用。"
            MSG[err_no_req]="未找到文件: %s"
            MSG[info_deploy_init]="初始化容器版 deploy.yaml..."
            MSG[ok_deploy_init]="deploy.yaml 已初始化并适配 alas-conda 容器环境。"
            MSG[ok_deploy_fix]="已自动修正 deploy.yaml 中的 Windows 默认路径。"
            MSG[warn_no_deploy_tpl]="未找到 deploy 模板，将交由 ALAS 首次启动生成。"
            MSG[info_cloning]="正在克隆 ALAS 源码到 %s ..."
            MSG[err_clone]="克隆仓库失败，请检查网络连接。"
            MSG[info_checking_update]="正在检查 ALAS 上游源码更新..."
            MSG[err_git_perm]="Git 目录无写入权限：%s\n请先执行: sudo chown -R \"%s:%s\" \"%s\""
            MSG[err_dirty_tree]="检测到除 requirements.txt 以外的本地源码修改，为避免覆盖已中止更新："
            MSG[err_fetch]="git fetch 失败，请检查网络或代理设置。"
            MSG[info_pulling]="发现新版本 (%s -> %s)，正在安全拉取更新..."
            MSG[err_pull]="git pull 失败，请手动检查仓库状态。"
            MSG[warn_req_changed]="注意：上游更新修改了 requirements.txt；如启动报缺包，请运行「重新构建 Docker 镜像」。"
            MSG[info_restarting]="检测到 ALAS 正在运行，正在重启容器以加载最新代码..."
            MSG[ok_up_to_date]="ALAS 源码已是最新版本 (%s)。"
            MSG[ok_updated]="ALAS 已成功更新到最新版本 (%s)。"
            MSG[info_building]="正在构建 Docker 镜像 (%s，架构: %s)..."
            MSG[err_build]="Docker 镜像构建失败。"
            MSG[ok_build]="Docker 镜像 %s 构建完成。"
            MSG[info_wd_connect]="检测到运行中的 Waydroid (%s)，正在连接 ADB..."
            MSG[warn_wd_stopped]="未检测到运行中的 Waydroid（如使用其他模拟器或真机，请确保已通过 adb connect 连接）。"
            MSG[lbl_adb_list]="当前 ADB 设备列表："
            MSG[warn_adb_unauth]="提示：设备处于 unauthorized 状态，请在模拟器/Waydroid 窗口中点击「始终允许 USB 调试」。"
            MSG[info_starting]="正在启动 ALAS 容器..."
            MSG[err_start]="启动 ALAS 容器失败。"
            MSG[info_wait_webui]="等待 WebUI (http://127.0.0.1:%s) 就绪..."
            MSG[ok_started]="ALAS 启动成功！请在浏览器打开: http://127.0.0.1:%s"
            MSG[err_exited]="容器启动后异常退出，最近日志如下："
            MSG[warn_webui_timeout]="容器已启动，但 WebUI 暂未响应，可通过「查看实时日志」排查。"
            MSG[ok_stopped]="ALAS 已停止。"
            MSG[warn_not_init]="尚未初始化目录: %s"
            MSG[info_logs_hint]="正在查看实时日志，按 Ctrl+C 返回主界面..."
            MSG[warn_uninstall]="警告：此操作将删除容器 (%s)、镜像 (%s) 以及目录 (%s)。"
            MSG[prompt_uninstall]="确认彻底卸载 ALAS 吗？(y/N): "
            MSG[prompt_backup]="卸载前是否备份 ALAS 配置 (src/config)？(Y/n): "
            MSG[ok_backup]="配置已备份至: %s"
            MSG[warn_rm_sudo]="部分文件因权限未能直接删除，请手动执行: sudo rm -rf \"%s\""
            MSG[ok_uninstalled]="已清理 ALAS 相关资源。"
            MSG[msg_cancelled]="已取消操作。"
            MSG[usage_text]="用法: %s [start|stop|restart|logs|update|rebuild|adb|status|uninstall] [--lang zh|en|ja]"
            ;;
        ja)
            MSG[app_title]="ALAS Docker マネージャー"
            MSG[lang_label]="日本語"
            MSG[sec_status]="ステータス"
            MSG[sec_actions]="メニュー"
            MSG[lbl_system]="システム"
            MSG[lbl_container]="コンテナ"
            MSG[lbl_webui]="WebUI"
            MSG[lbl_source]="ALAS ソース"
            MSG[lbl_adb]="エミュレータ/ADB"
            MSG[lbl_path]="インストール先"
            MSG[st_running]="● 実行中 (Running)"
            MSG[st_stopped]="○ 停止中 (Stopped)"
            MSG[st_not_installed]="◌ 未インストール"
            MSG[st_perm_denied]="✖ Docker 権限不足"
            MSG[st_docker_down]="✖ Docker 未起動"
            MSG[st_webui_up]="接続可能"
            MSG[st_webui_wait]="待機中"
            MSG[st_src_none]="未取得"
            MSG[st_adb_none]="デバイス未検出"
            MSG[st_adb_no_bin]="adb 未導入"
            MSG[st_adb_unauth]="未承認 (unauthorized)"
            MSG[st_adb_connected]="接続済み"
            MSG[st_waydroid_ready]="Waydroid 接続済み"
            MSG[st_waydroid_unauth]="Waydroid 未承認 (画面で許可してください)"
            MSG[st_waydroid_disc]="Waydroid 稼働中 (ADB 未接続)"
            MSG[menu_1]="ALAS を起動"
            MSG[desc_1]="依存確認・ソース取得/パッチ適用・ADB 接続・WebUI 起動を一括実行"
            MSG[menu_2]="ALAS を停止"
            MSG[desc_2]="実行中の ALAS コンテナを停止します"
            MSG[menu_3]="リアルタイムログ表示"
            MSG[desc_3]="コンテナログを追跡します（Ctrl+C でメニューに戻る）"
            MSG[menu_4]="ALAS の更新確認・適用"
            MSG[desc_4]="最新ソースを安全に取得し Linux パッチ再適用＆再起動"
            MSG[menu_5]="Waydroid / ADB 接続診断"
            MSG[desc_5]="Waydroid IP を自動検出して ADB 接続・状態確認"
            MSG[menu_6]="Docker イメージ再ビルド"
            MSG[desc_6]="Dockerfile から alas-conda イメージを再構築します"
            MSG[menu_7]="Docker 権限を修復"
            MSG[desc_7]="現在ユーザーを docker グループへ追加し反映します"
            MSG[menu_8]="表示言語を切替 (中文/EN/日本語)"
            MSG[desc_8]="現在の言語: 日本語（設定は保存されます）"
            MSG[menu_9]="ALAS を完全アンインストール"
            MSG[desc_9]="設定バックアップ後にコンテナ・イメージ・ディレクトリを削除"
            MSG[menu_0]="終了"
            MSG[desc_0]="マネージャーを終了します（ALAS コンテナは維持）"
            MSG[footer_tui]="↑/↓ 移動   Enter 実行   0-9 番号選択   R 更新   L 言語切替   Q 終了"
            MSG[prompt_choice]="番号を入力 [0-9] (R更新/L言語/Q終了): "
            MSG[press_enter]="Enter キーでメニューに戻ります..."
            MSG[invalid_choice]="無効な選択です。"
            MSG[err_no_root_tool]="管理者権限が必要ですが sudo / doas / pkexec が見つかりません。"
            MSG[info_sys_check]="[1/3] システム環境と依存パッケージを確認中..."
            MSG[ok_deps_ready]="必要なシステム依存はすべて揃っています。"
            MSG[info_deps_install]="%s で不足パッケージをインストール中: %s"
            MSG[err_deps_install]="依存パッケージのインストールに失敗しました。"
            MSG[warn_nixos]="NixOS を検出しました。configuration.nix に以下を追加して rebuild してください:"
            MSG[warn_ostree]="イミュータブル OS (%s) を検出しました。以下を実行し再起動してください:"
            MSG[warn_unknown_pm]="未対応のパッケージマネージャ (%s) です。手動で次を導入してください: %s"
            MSG[warn_docker_fallback]="標準リポジトリに Docker がないため %s で公式スクリプト (get.docker.com) を実行します..."
            MSG[err_no_downloader]="curl / wget が見つからず Docker を取得できません。"
            MSG[info_docker_check]="[2/3] Docker サービスとアクセス権限を確認中..."
            MSG[info_docker_start]="Docker サービスを起動中 (%s)..."
            MSG[err_docker_start]="Docker サービスの起動に失敗しました。"
            MSG[info_workdir_prep]="[3/3] 作業ディレクトリを準備中 (%s)..."
            MSG[ok_env_ready]="環境と Compose 設定の準備が完了しました。"
            MSG[err_no_compose]="docker compose / docker-compose が見つかりません。"
            MSG[info_fix_perm]="ユーザー %s を docker グループに追加中..."
            MSG[ok_fix_perm]="docker グループへ追加しました。sg で即時反映を試みます..."
            MSG[warn_relogin]="再ログイン（または newgrp docker）して権限を反映してください。"
            MSG[ok_perm_already]="すでに Docker へのアクセス権限があります。"
            MSG[info_patch]="Linux/Docker 互換パッチを適用中 (requirements.txt)..."
            MSG[ok_patch]="requirements.txt パッチを適用しました。"
            MSG[err_no_req]="ファイルが見つかりません: %s"
            MSG[info_deploy_init]="コンテナ用 deploy.yaml を初期化中..."
            MSG[ok_deploy_init]="deploy.yaml を alas-conda 環境向けに初期化しました。"
            MSG[ok_deploy_fix]="deploy.yaml 内の Windows 既定パスを自動修正しました。"
            MSG[warn_no_deploy_tpl]="deploy テンプレートが見つかりません。初回起動時に自動生成されます。"
            MSG[info_cloning]="ALAS ソースを %s へクローン中..."
            MSG[err_clone]="リポジトリのクローンに失敗しました。"
            MSG[info_checking_update]="ALAS の更新を確認中..."
            MSG[err_git_perm]="Git ディレクトリに書込権限がありません: %s\n実行してください: sudo chown -R \"%s:%s\" \"%s\""
            MSG[err_dirty_tree]="requirements.txt 以外に未コミットの変更があるため更新を中止しました:"
            MSG[err_fetch]="git fetch に失敗しました。ネットワーク接続を確認してください。"
            MSG[info_pulling]="更新を検出 (%s -> %s)。安全に取得しています..."
            MSG[err_pull]="git pull に失敗しました。リポジトリ状態を確認してください。"
            MSG[warn_req_changed]="注意: requirements.txt が更新されました。起動時に依存エラーが出る場合はイメージを再ビルドしてください。"
            MSG[info_restarting]="稼働中の ALAS コンテナを再起動して最新コードを反映中..."
            MSG[ok_up_to_date]="ALAS ソースは最新です (%s)。"
            MSG[ok_updated]="ALAS を最新バージョン (%s) に更新しました。"
            MSG[info_building]="Docker イメージをビルド中 (%s, arch: %s)..."
            MSG[err_build]="Docker イメージのビルドに失敗しました。"
            MSG[ok_build]="Docker イメージ %s のビルドが完了しました。"
            MSG[info_wd_connect]="稼働中の Waydroid (%s) を検出。ADB 接続中..."
            MSG[warn_wd_stopped]="稼働中の Waydroid が見つかりません（他エミュレータの場合は adb connect してください）。"
            MSG[lbl_adb_list]="ADB デバイス一覧:"
            MSG[warn_adb_unauth]="ヒント: unauthorized 状態です。Waydroid 画面で「USB デバッグを常に許可」を押してください。"
            MSG[info_starting]="ALAS コンテナを起動中..."
            MSG[err_start]="ALAS コンテナの起動に失敗しました。"
            MSG[info_wait_webui]="WebUI (http://127.0.0.1:%s) の応答を待機中..."
            MSG[ok_started]="ALAS の起動に成功しました！ブラウザで開いてください: http://127.0.0.1:%s"
            MSG[err_exited]="コンテナが異常終了しました。直近のログ:"
            MSG[warn_webui_timeout]="コンテナは起動しましたが WebUI 応答待ちです。ログを確認してください。"
            MSG[ok_stopped]="ALAS を停止しました。"
            MSG[warn_not_init]="未初期化のディレクトリです: %s"
            MSG[info_logs_hint]="ログ表示中。Ctrl+C でメニューに戻ります..."
            MSG[warn_uninstall]="警告: コンテナ (%s)、イメージ (%s)、ディレクトリ (%s) を削除します。"
            MSG[prompt_uninstall]="ALAS を完全に削除しますか？(y/N): "
            MSG[prompt_backup]="削除前に設定 (src/config) をバックアップしますか？(Y/n): "
            MSG[ok_backup]="設定をバックアップしました: %s"
            MSG[warn_rm_sudo]="一部ファイルを削除できませんでした。手動で実行してください: sudo rm -rf \"%s\""
            MSG[ok_uninstalled]="ALAS 関連リソースを削除しました。"
            MSG[msg_cancelled]="キャンセルしました。"
            MSG[usage_text]="使い方: %s [start|stop|restart|logs|update|rebuild|adb|status|uninstall] [--lang zh|en|ja]"
            ;;
        *)
            MSG[app_title]="ALAS Docker Manager"
            MSG[lang_label]="English"
            MSG[sec_status]="Status"
            MSG[sec_actions]="Actions"
            MSG[lbl_system]="System"
            MSG[lbl_container]="Container"
            MSG[lbl_webui]="WebUI"
            MSG[lbl_source]="ALAS Source"
            MSG[lbl_adb]="Emulator / ADB"
            MSG[lbl_path]="Install Dir"
            MSG[st_running]="● Running"
            MSG[st_stopped]="○ Stopped"
            MSG[st_not_installed]="◌ Not Installed"
            MSG[st_perm_denied]="✖ Docker Permission Denied"
            MSG[st_docker_down]="✖ Docker Daemon Inactive"
            MSG[st_webui_up]="Reachable"
            MSG[st_webui_wait]="Not Listening"
            MSG[st_src_none]="Not Cloned"
            MSG[st_adb_none]="No Device Attached"
            MSG[st_adb_no_bin]="adb Not Installed"
            MSG[st_adb_unauth]="Unauthorized"
            MSG[st_adb_connected]="Connected"
            MSG[st_waydroid_ready]="Waydroid Connected"
            MSG[st_waydroid_unauth]="Waydroid Unauthorized (Allow in window)"
            MSG[st_waydroid_disc]="Waydroid Running (ADB disconnected)"
            MSG[menu_1]="Start ALAS"
            MSG[desc_1]="Check deps, clone/patch source, connect ADB, and launch WebUI"
            MSG[menu_2]="Stop ALAS"
            MSG[desc_2]="Stop the running ALAS container"
            MSG[menu_3]="View Live Logs"
            MSG[desc_3]="Follow container output (press Ctrl+C to return to menu)"
            MSG[menu_4]="Check & Update ALAS"
            MSG[desc_4]="Safely sync upstream code, reapply Linux patches, and restart"
            MSG[menu_5]="Connect Waydroid / ADB Diagnostics"
            MSG[desc_5]="Auto-detect Waydroid IP, connect ADB, and inspect devices"
            MSG[menu_6]="Rebuild Docker Image"
            MSG[desc_6]="Rebuild the alas-conda runtime image from Dockerfile"
            MSG[menu_7]="Fix Docker Permissions"
            MSG[desc_7]="Add current user to docker group and refresh permissions"
            MSG[menu_8]="Switch UI Language (中文/EN/日本語)"
            MSG[desc_8]="Current language: English (saved automatically)"
            MSG[menu_9]="Uninstall ALAS"
            MSG[desc_9]="Optionally back up config, then remove container, image & files"
            MSG[menu_0]="Exit"
            MSG[desc_0]="Exit manager (leaves running ALAS container untouched)"
            MSG[footer_tui]="↑/↓ Move   Enter Run   0-9 Shortcut   R Refresh   L Language   Q Quit"
            MSG[prompt_choice]="Select [0-9] (R refresh / L lang / Q quit): "
            MSG[press_enter]="Press Enter to return to menu..."
            MSG[invalid_choice]="Invalid choice."
            MSG[err_no_root_tool]="Root privileges required, but neither sudo, doas, nor pkexec was found."
            MSG[info_sys_check]="[1/3] Checking system environment and dependencies..."
            MSG[ok_deps_ready]="All required system dependencies are installed."
            MSG[info_deps_install]="Installing missing packages via %s: %s"
            MSG[err_deps_install]="Failed to install dependencies. Please check repositories/network."
            MSG[warn_nixos]="NixOS detected (declarative OS). Enable the following in configuration.nix and rebuild:"
            MSG[warn_ostree]="Immutable OS (%s) detected. Run the command below and reboot:"
            MSG[warn_unknown_pm]="Unsupported package manager (%s). Please install manually: %s"
            MSG[warn_docker_fallback]="Docker not found in default repos. Running official installer (get.docker.com) via %s..."
            MSG[err_no_downloader]="Neither curl nor wget is available to fetch the Docker installer."
            MSG[info_docker_check]="[2/3] Checking Docker daemon and access permissions..."
            MSG[info_docker_start]="Starting Docker service (%s)..."
            MSG[err_docker_start]="Failed to start Docker service. Check system logs."
            MSG[info_workdir_prep]="[3/3] Preparing working directory (%s)..."
            MSG[ok_env_ready]="Environment and Compose configuration are ready."
            MSG[err_no_compose]="Neither 'docker compose' nor 'docker-compose' is available."
            MSG[info_fix_perm]="Adding user %s to the docker group..."
            MSG[ok_fix_perm]="Added to docker group. Refreshing session via sg..."
            MSG[warn_relogin]="Please log out and back in (or run 'newgrp docker') to apply group changes."
            MSG[ok_perm_already]="Current user already has Docker access."
            MSG[info_patch]="Applying Linux/Docker compatibility patches (requirements.txt)..."
            MSG[ok_patch]="requirements.txt patches applied."
            MSG[err_no_req]="File not found: %s"
            MSG[info_deploy_init]="Initializing Docker deploy.yaml..."
            MSG[ok_deploy_init]="deploy.yaml initialized for alas-conda container."
            MSG[ok_deploy_fix]="Fixed Windows default paths in deploy.yaml."
            MSG[warn_no_deploy_tpl]="No deploy template found; ALAS will generate one on first boot."
            MSG[info_cloning]="Cloning ALAS repository into %s ..."
            MSG[err_clone]="Failed to clone repository. Check your network connection."
            MSG[info_checking_update]="Checking upstream ALAS updates..."
            MSG[err_git_perm]="No write permission in Git directory: %s\nFix with: sudo chown -R \"%s:%s\" \"%s\""
            MSG[err_dirty_tree]="Local tracked changes found outside requirements.txt; aborting update to protect your edits:"
            MSG[err_fetch]="git fetch failed. Check network or proxy settings."
            MSG[info_pulling]="Update available (%s -> %s). Pulling safely..."
            MSG[err_pull]="git pull failed. Please inspect repository status."
            MSG[warn_req_changed]="Note: upstream modified requirements.txt. If ALAS reports missing packages, run 'Rebuild Docker Image'."
            MSG[info_restarting]="ALAS is running; restarting container to load updated code..."
            MSG[ok_up_to_date]="ALAS source is already up to date (%s)."
            MSG[ok_updated]="ALAS updated successfully (%s)."
            MSG[info_building]="Building Docker image (%s, arch: %s)..."
            MSG[err_build]="Docker image build failed."
            MSG[ok_build]="Docker image %s built successfully."
            MSG[info_wd_connect]="Running Waydroid detected (%s). Connecting ADB..."
            MSG[warn_wd_stopped]="No running Waydroid detected (if using another emulator/device, connect it via adb)."
            MSG[lbl_adb_list]="Attached ADB devices:"
            MSG[warn_adb_unauth]="Tip: Device is unauthorized. Click 'Always allow USB debugging' inside Waydroid/emulator."
            MSG[info_starting]="Starting ALAS container..."
            MSG[err_start]="Failed to start ALAS container."
            MSG[info_wait_webui]="Waiting for WebUI (http://127.0.0.1:%s)..."
            MSG[ok_started]="ALAS is ready! Open in browser: http://127.0.0.1:%s"
            MSG[err_exited]="Container exited unexpectedly. Recent logs:"
            MSG[warn_webui_timeout]="Container is running, but WebUI did not respond yet. Check live logs."
            MSG[ok_stopped]="ALAS stopped."
            MSG[warn_not_init]="Directory not initialized yet: %s"
            MSG[info_logs_hint]="Streaming logs. Press Ctrl+C to return to menu..."
            MSG[warn_uninstall]="Warning: This removes container (%s), image (%s), and directory (%s)."
            MSG[prompt_uninstall]="Confirm complete ALAS removal? (y/N): "
            MSG[prompt_backup]="Back up ALAS config (src/config) before removing? (Y/n): "
            MSG[ok_backup]="Config backed up to: %s"
            MSG[warn_rm_sudo]="Some files could not be deleted due to permissions. Run: sudo rm -rf \"%s\""
            MSG[ok_uninstalled]="ALAS resources cleaned up."
            MSG[msg_cancelled]="Operation cancelled."
            MSG[usage_text]="Usage: %s [start|stop|restart|logs|update|rebuild|adb|status|uninstall] [--lang zh|en|ja]"
            ;;
    esac
}

t() {
    local key="$1"
    shift || true
    local fmt="${MSG[$key]:-$key}"
    if (( $# > 0 )); then
        # shellcheck disable=SC2059
        printf "$fmt" "$@"
    else
        printf '%s' "$fmt"
    fi
}

cycle_language() {
    case "$UI_LANG" in
        zh) UI_LANG="en" ;;
        en) UI_LANG="ja" ;;
        *)  UI_LANG="zh" ;;
    esac
    load_i18n
    if [ -d "$INSTALL_DIR" ]; then
        printf '%s\n' "$UI_LANG" > "$LANG_PREF_FILE" 2>/dev/null || true
    fi
}

# =================================================================
# 2. 日志打印辅助函数
# =================================================================

log_info() { printf '%s[*]%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
log_ok()   { printf '%s[OK]%s %s\n' "$C_BGREEN" "$C_RESET" "$*"; }
log_warn() { printf '%s[!]%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
log_err()  { printf '%s[ERROR]%s %s\n' "$C_BRED" "$C_RESET" "$*" >&2; }

# =================================================================
# 3. 跨发行版 Linux 环境检测（包管理器 / Init / 提权 / 下载器）
# =================================================================

detect_system_env() {
    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        OS_ID="${ID:-unknown}"
        OS_PRETTY="${PRETTY_NAME:-${NAME:-Linux}}"
    else
        OS_PRETTY="$(uname -s 2>/dev/null || echo Linux)"
    fi

    case "$(uname -m 2>/dev/null || echo x86_64)" in
        aarch64|arm64) CPU_ARCH="aarch64" ;;
        *)             CPU_ARCH="x86_64" ;;
    esac

    # 检测包管理器（先识别特殊声明式/不可变发行版，再按可用命令判断）
    if [ "$OS_ID" = "nixos" ]; then
        PKG_MANAGER="nixos"
    elif command -v rpm-ostree >/dev/null 2>&1 && [ ! -w /usr ]; then
        PKG_MANAGER="rpm-ostree"
    elif command -v pacman >/dev/null 2>&1; then
        PKG_MANAGER="pacman"
    elif command -v apt-get >/dev/null 2>&1; then
        PKG_MANAGER="apt"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MANAGER="dnf"
    elif command -v yum >/dev/null 2>&1; then
        PKG_MANAGER="yum"
    elif command -v zypper >/dev/null 2>&1; then
        PKG_MANAGER="zypper"
    elif command -v apk >/dev/null 2>&1; then
        PKG_MANAGER="apk"
    elif command -v xbps-install >/dev/null 2>&1; then
        PKG_MANAGER="xbps"
    elif command -v emerge >/dev/null 2>&1; then
        PKG_MANAGER="emerge"
    else
        PKG_MANAGER="unknown"
    fi

    # 检测 Init 系统
    if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
        INIT_SYSTEM="systemd"
    elif command -v rc-service >/dev/null 2>&1; then
        INIT_SYSTEM="openrc"
    elif command -v sv >/dev/null 2>&1 && [ -d /etc/sv ]; then
        INIT_SYSTEM="runit"
    elif command -v service >/dev/null 2>&1; then
        INIT_SYSTEM="sysvinit"
    else
        INIT_SYSTEM="unknown"
    fi

    # 检测提权方式
    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
        SUDO_CMD=""
    elif command -v sudo >/dev/null 2>&1; then
        SUDO_CMD="sudo"
    elif command -v doas >/dev/null 2>&1; then
        SUDO_CMD="doas"
    elif command -v pkexec >/dev/null 2>&1; then
        SUDO_CMD="pkexec"
    else
        SUDO_CMD=""
    fi

    # 检测可用下载/HTTP 工具
    if command -v curl >/dev/null 2>&1; then
        DOWNLOADER="curl"
    elif command -v wget >/dev/null 2>&1; then
        DOWNLOADER="wget"
    elif command -v python3 >/dev/null 2>&1; then
        DOWNLOADER="python3"
    else
        DOWNLOADER="none"
    fi
}

run_as_root() {
    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
        "$@"
    elif [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" "$@"
    else
        log_err "$(t err_no_root_tool)"
        return 1
    fi
}

http_probe_url() {
    local url="$1"
    case "$DOWNLOADER" in
        curl)
            curl -fsS --max-time 2 -o /dev/null "$url" 2>/dev/null
            ;;
        wget)
            wget -q --timeout=2 -O /dev/null "$url" 2>/dev/null
            ;;
        python3)
            python3 -c "import sys, urllib.request; urllib.request.urlopen(sys.argv[1], timeout=2)" "$url" >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

http_download_to_file() {
    local url="$1"
    local dest="$2"
    case "$DOWNLOADER" in
        curl)
            curl -fsSL "$url" -o "$dest"
            ;;
        wget)
            wget -qO "$dest" "$url"
            ;;
        python3)
            python3 -c "import sys, urllib.request; urllib.request.urlretrieve(sys.argv[1], sys.argv[2])" "$url" "$dest"
            ;;
        *)
            return 1
            ;;
    esac
}

# =================================================================
# 4. 单文件双击启动支持（非 TTY 桌面环境自动拉起终端窗口）
# =================================================================

maybe_relaunch_in_terminal() {
    # 仅在交互模式、非 TTY、非管道输入、且存在桌面环境时拉起新终端
    if [ "${ALAS_IN_TERMINAL:-0}" = "1" ] || [ "${ALAS_NO_TERM:-0}" = "1" ]; then
        return 0
    fi
    if [ -t 0 ] || [ -t 1 ] || [ -p /dev/stdin ]; then
        return 0
    fi
    if [ -z "${WAYLAND_DISPLAY:-}" ] && [ -z "${DISPLAY:-}" ]; then
        return 0
    fi

    local title="ALAS Docker Manager"
    local term_bin=""

    # 优先尊重用户设置的 $TERMINAL
    if [ -n "${TERMINAL:-}" ] && command -v "$TERMINAL" >/dev/null 2>&1; then
        term_bin="$(basename "$TERMINAL")"
        case "$term_bin" in
            alacritty) exec env ALAS_IN_TERMINAL=1 "$TERMINAL" -T "$title" -e "$SCRIPT_PATH" "$@" ;;
            kitty)     exec env ALAS_IN_TERMINAL=1 "$TERMINAL" --title "$title" "$SCRIPT_PATH" "$@" ;;
            foot)      exec env ALAS_IN_TERMINAL=1 "$TERMINAL" -T "$title" "$SCRIPT_PATH" "$@" ;;
            wezterm)   exec env ALAS_IN_TERMINAL=1 "$TERMINAL" start -- "$SCRIPT_PATH" "$@" ;;
            gnome-terminal) exec env ALAS_IN_TERMINAL=1 "$TERMINAL" --title="$title" -- "$SCRIPT_PATH" "$@" ;;
            xfce4-terminal|mate-terminal|terminator)
                exec env ALAS_IN_TERMINAL=1 "$TERMINAL" -x "$SCRIPT_PATH" "$@" ;;
            *)         exec env ALAS_IN_TERMINAL=1 "$TERMINAL" -e "$SCRIPT_PATH" "$@" ;;
        esac
    fi

    if command -v alacritty >/dev/null 2>&1; then
        exec env ALAS_IN_TERMINAL=1 alacritty -T "$title" -e "$SCRIPT_PATH" "$@"
    elif command -v kitty >/dev/null 2>&1; then
        exec env ALAS_IN_TERMINAL=1 kitty --title "$title" "$SCRIPT_PATH" "$@"
    elif command -v foot >/dev/null 2>&1; then
        exec env ALAS_IN_TERMINAL=1 foot -T "$title" "$SCRIPT_PATH" "$@"
    elif command -v wezterm >/dev/null 2>&1; then
        exec env ALAS_IN_TERMINAL=1 wezterm start -- "$SCRIPT_PATH" "$@"
    elif command -v ghostty >/dev/null 2>&1; then
        exec env ALAS_IN_TERMINAL=1 ghostty -e "$SCRIPT_PATH" "$@"
    elif command -v konsole >/dev/null 2>&1; then
        exec env ALAS_IN_TERMINAL=1 konsole -e "$SCRIPT_PATH" "$@"
    elif command -v gnome-terminal >/dev/null 2>&1; then
        exec env ALAS_IN_TERMINAL=1 gnome-terminal --title="$title" -- "$SCRIPT_PATH" "$@"
    elif command -v xfce4-terminal >/dev/null 2>&1; then
        exec env ALAS_IN_TERMINAL=1 xfce4-terminal --title="$title" -x "$SCRIPT_PATH" "$@"
    elif command -v mate-terminal >/dev/null 2>&1; then
        exec env ALAS_IN_TERMINAL=1 mate-terminal --title="$title" -x "$SCRIPT_PATH" "$@"
    elif command -v tilix >/dev/null 2>&1; then
        exec env ALAS_IN_TERMINAL=1 tilix -e "$SCRIPT_PATH"
    elif command -v terminator >/dev/null 2>&1; then
        exec env ALAS_IN_TERMINAL=1 terminator -x "$SCRIPT_PATH" "$@"
    elif command -v lxterminal >/dev/null 2>&1; then
        exec env ALAS_IN_TERMINAL=1 lxterminal -e "$SCRIPT_PATH"
    elif command -v urxvt >/dev/null 2>&1; then
        exec env ALAS_IN_TERMINAL=1 urxvt -title "$title" -e "$SCRIPT_PATH" "$@"
    elif command -v x-terminal-emulator >/dev/null 2>&1; then
        exec env ALAS_IN_TERMINAL=1 x-terminal-emulator -e "$SCRIPT_PATH"
    elif command -v xterm >/dev/null 2>&1; then
        exec env ALAS_IN_TERMINAL=1 xterm -T "$title" -e "$SCRIPT_PATH" "$@"
    fi
}

# =================================================================
# 5. Docker / Compose / 系统依赖自动适配安装
# =================================================================

has_compose() {
    docker compose version >/dev/null 2>&1 || (command -v docker-compose >/dev/null 2>&1 && docker-compose version >/dev/null 2>&1)
}

select_compose_cmd() {
    if docker compose version >/dev/null 2>&1; then
        COMPOSE_CMD=(docker compose)
        return 0
    elif command -v docker-compose >/dev/null 2>&1 && docker-compose version >/dev/null 2>&1; then
        COMPOSE_CMD=(docker-compose)
        return 0
    fi
    log_err "$(t err_no_compose)"
    return 1
}

run_compose() {
    if (( ${#COMPOSE_CMD[@]} == 0 )); then
        select_compose_cmd || return 1
    fi
    "${COMPOSE_CMD[@]}" -f "$INSTALL_DIR/docker-compose.yml" "$@"
}

install_docker_official_fallback() {
    if [ "$DOWNLOADER" = "none" ]; then
        log_err "$(t err_no_downloader)"
        return 1
    fi
    log_warn "$(t warn_docker_fallback "$DOWNLOADER")"
    local tmp_script
    tmp_script="$(mktemp)"
    if ! http_download_to_file "https://get.docker.com" "$tmp_script"; then
        rm -f "$tmp_script"
        return 1
    fi
    run_as_root sh "$tmp_script"
    local rc=$?
    rm -f "$tmp_script"
    return $rc
}

install_system_dependencies() {
    log_info "$(t info_sys_check)"

    local need_docker=0 need_compose=0 need_adb=0 need_git=0 need_http=0
    command -v docker >/dev/null 2>&1 || need_docker=1
    has_compose || need_compose=1
    command -v adb >/dev/null 2>&1 || need_adb=1
    command -v git >/dev/null 2>&1 || need_git=1
    [ "$DOWNLOADER" != "none" ] || need_http=1

    if (( need_docker == 0 && need_compose == 0 && need_adb == 0 && need_git == 0 && need_http == 0 )); then
        log_ok "$(t ok_deps_ready)"
        return 0
    fi

    local pkgs=()
    local need_official_docker=0

    case "$PKG_MANAGER" in
        pacman)
            (( need_docker ))  && pkgs+=(docker)
            (( need_compose )) && pkgs+=(docker-compose)
            (( need_adb ))     && pkgs+=(android-tools)
            (( need_git ))     && pkgs+=(git)
            (( need_http ))    && pkgs+=(curl)
            log_info "$(t info_deps_install "pacman" "${pkgs[*]}")"
            run_as_root pacman -S --needed --noconfirm "${pkgs[@]}" || {
                log_err "$(t err_deps_install)"
                return 1
            }
            ;;
        apt)
            (( need_docker )) && pkgs+=(docker.io)
            if (( need_compose )); then
                if apt-cache show docker-compose-v2 >/dev/null 2>&1; then
                    pkgs+=(docker-compose-v2)
                elif apt-cache show docker-compose-plugin >/dev/null 2>&1; then
                    pkgs+=(docker-compose-plugin)
                else
                    pkgs+=(docker-compose)
                fi
            fi
            if (( need_adb )); then
                if apt-cache show adb >/dev/null 2>&1; then
                    pkgs+=(adb)
                else
                    pkgs+=(android-tools-adb)
                fi
            fi
            (( need_git ))  && pkgs+=(git)
            (( need_http )) && pkgs+=(curl)
            log_info "$(t info_deps_install "apt" "${pkgs[*]}")"
            run_as_root apt-get update && run_as_root apt-get install -y "${pkgs[@]}" || {
                log_err "$(t err_deps_install)"
                return 1
            }
            ;;
        dnf|yum)
            local pm_bin="$PKG_MANAGER"
            if (( need_docker )); then
                if "$pm_bin" info moby-engine >/dev/null 2>&1; then
                    pkgs+=(moby-engine)
                elif "$pm_bin" info docker >/dev/null 2>&1; then
                    pkgs+=(docker)
                elif "$pm_bin" info docker-ce >/dev/null 2>&1; then
                    pkgs+=(docker-ce docker-ce-cli containerd.io)
                else
                    need_official_docker=1
                fi
            fi
            if (( need_compose && need_official_docker == 0 )); then
                if "$pm_bin" info docker-compose-plugin >/dev/null 2>&1; then
                    pkgs+=(docker-compose-plugin)
                elif "$pm_bin" info docker-compose >/dev/null 2>&1; then
                    pkgs+=(docker-compose)
                fi
            fi
            (( need_adb ))  && pkgs+=(android-tools)
            (( need_git ))  && pkgs+=(git)
            (( need_http )) && pkgs+=(curl)
            if (( ${#pkgs[@]} > 0 )); then
                log_info "$(t info_deps_install "$pm_bin" "${pkgs[*]}")"
                run_as_root "$pm_bin" install -y "${pkgs[@]}" || {
                    log_err "$(t err_deps_install)"
                    return 1
                }
            fi
            if (( need_official_docker )); then
                detect_system_env
                install_docker_official_fallback || {
                    log_err "$(t err_deps_install)"
                    return 1
                }
            fi
            ;;
        zypper)
            (( need_docker ))  && pkgs+=(docker)
            (( need_compose )) && pkgs+=(docker-compose)
            (( need_adb ))     && pkgs+=(android-tools)
            (( need_git ))     && pkgs+=(git)
            (( need_http ))    && pkgs+=(curl)
            log_info "$(t info_deps_install "zypper" "${pkgs[*]}")"
            run_as_root zypper --non-interactive install --no-recommends "${pkgs[@]}" || {
                log_err "$(t err_deps_install)"
                return 1
            }
            ;;
        apk)
            (( need_docker )) && pkgs+=(docker)
            if (( need_compose )); then
                if apk search -e docker-cli-compose 2>/dev/null | grep -q docker-cli-compose; then
                    pkgs+=(docker-cli-compose)
                else
                    pkgs+=(docker-compose)
                fi
            fi
            (( need_adb ))  && pkgs+=(android-tools)
            (( need_git ))  && pkgs+=(git)
            (( need_http )) && pkgs+=(curl)
            log_info "$(t info_deps_install "apk" "${pkgs[*]}")"
            run_as_root apk add --no-cache "${pkgs[@]}" || {
                log_err "$(t err_deps_install)"
                return 1
            }
            ;;
        xbps)
            (( need_docker ))  && pkgs+=(docker)
            (( need_compose )) && pkgs+=(docker-compose)
            (( need_adb ))     && pkgs+=(android-tools)
            (( need_git ))     && pkgs+=(git)
            (( need_http ))    && pkgs+=(curl)
            log_info "$(t info_deps_install "xbps-install" "${pkgs[*]}")"
            run_as_root xbps-install -Sy "${pkgs[@]}" || {
                log_err "$(t err_deps_install)"
                return 1
            }
            ;;
        emerge)
            (( need_docker ))  && pkgs+=(app-containers/docker app-containers/docker-cli)
            (( need_compose )) && pkgs+=(app-containers/docker-compose)
            (( need_adb ))     && pkgs+=(dev-util/android-tools)
            (( need_git ))     && pkgs+=(dev-vcs/git)
            (( need_http ))    && pkgs+=(net-misc/curl)
            log_info "$(t info_deps_install "emerge" "${pkgs[*]}")"
            run_as_root emerge --noreplace "${pkgs[@]}" || {
                log_err "$(t err_deps_install)"
                return 1
            }
            ;;
        nixos)
            log_warn "$(t warn_nixos)"
            cat <<'EOF'
  virtualisation.docker.enable = true;
  programs.adb.enable = true;
  users.users.<your-user>.extraGroups = [ "docker" "adbusers" ];
  environment.systemPackages = with pkgs; [ docker-compose git curl ];
EOF
            return 1
            ;;
        rpm-ostree)
            (( need_docker ))  && pkgs+=(moby-engine)
            (( need_compose )) && pkgs+=(docker-compose)
            (( need_adb ))     && pkgs+=(android-tools)
            (( need_git ))     && pkgs+=(git)
            (( need_http ))    && pkgs+=(curl)
            log_warn "$(t warn_ostree "$OS_PRETTY")"
            printf '  rpm-ostree install %s && systemctl reboot\n' "${pkgs[*]}"
            return 1
            ;;
        *)
            local missing_cmds=()
            (( need_docker ))  && missing_cmds+=(docker)
            (( need_compose )) && missing_cmds+=(docker-compose)
            (( need_adb ))     && missing_cmds+=(adb)
            (( need_git ))     && missing_cmds+=(git)
            (( need_http ))    && missing_cmds+=(curl)
            log_warn "$(t warn_unknown_pm "$OS_PRETTY" "${missing_cmds[*]}")"
            return 1
            ;;
    esac

    # 重新刷新检测结果（例如刚装好 curl / compose）
    detect_system_env
    select_compose_cmd || return 1
}

start_docker_service() {
    # 如果 daemon 已经可通（含 rootless / WSL2 / 自定义 daemon），直接放行
    if docker info >/dev/null 2>&1; then
        return 0
    fi
    if [ -n "$SUDO_CMD" ] && "$SUDO_CMD" -n docker info >/dev/null 2>&1; then
        return 0
    fi

    case "$INIT_SYSTEM" in
        systemd)
            if ! systemctl is-active --quiet docker 2>/dev/null; then
                log_info "$(t info_docker_start "systemd")"
                run_as_root systemctl enable --now docker || {
                    log_err "$(t err_docker_start)"
                    return 1
                }
            fi
            ;;
        openrc)
            if ! rc-service docker status >/dev/null 2>&1; then
                log_info "$(t info_docker_start "OpenRC")"
                run_as_root rc-service docker start && run_as_root rc-update add docker default || {
                    log_err "$(t err_docker_start)"
                    return 1
                }
            fi
            ;;
        runit)
            if ! sv status docker >/dev/null 2>&1; then
                log_info "$(t info_docker_start "runit")"
                run_as_root ln -sf /etc/sv/docker /var/service/ && run_as_root sv up docker || {
                    log_err "$(t err_docker_start)"
                    return 1
                }
            fi
            ;;
        sysvinit)
            if ! service docker status >/dev/null 2>&1; then
                log_info "$(t info_docker_start "sysvinit")"
                run_as_root service docker start || {
                    log_err "$(t err_docker_start)"
                    return 1
                }
            fi
            ;;
    esac
}

fix_docker_permission() {
    if docker info >/dev/null 2>&1; then
        log_ok "$(t ok_perm_already)"
        return 0
    fi

    start_docker_service || return 1
    if docker info >/dev/null 2>&1; then
        log_ok "$(t ok_perm_already)"
        return 0
    fi

    local cur_user="${USER:-$(id -un)}"
    log_info "$(t info_fix_perm "$cur_user")"
    run_as_root usermod -aG docker "$cur_user" || return 1
    log_ok "$(t ok_fix_perm)"

    if command -v sg >/dev/null 2>&1; then
        cleanup_tty
        local quoted_self
        printf -v quoted_self '%q' "$SCRIPT_PATH"
        exec sg docker -c "$quoted_self"
    fi

    log_warn "$(t warn_relogin)"
    return 1
}

# =================================================================
# 6. Docker 文件、源码补丁与 ALAS 配置管理
# =================================================================

write_docker_files() {
    mkdir -p "$INSTALL_DIR" "$HOME/.android"

    local miniconda_url
    if [ "$CPU_ARCH" = "aarch64" ]; then
        miniconda_url="https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-aarch64.sh"
    else
        miniconda_url="https://repo.anaconda.com/miniconda/Miniconda3-py313_25.9.1-3-Linux-x86_64.sh"
    fi

    cat <<EOF > "$INSTALL_DIR/Dockerfile"
FROM python:3.7-slim-bookworm
RUN apt-get update && apt-get install -y --no-install-recommends \\
    wget git adb libgomp1 openssh-client ca-certificates \\
    libgl1 libglib2.0-0 libsm6 libxext6 libxrender1 \\
    && apt-get clean && rm -rf /var/lib/apt/lists/*
RUN git config --global --add safe.directory '*'
RUN wget -q ${miniconda_url} \\
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
RUN AV_VERSION=\$(grep -E '^#?[[:space:]]*av==' /tmp/requirements.txt | head -n 1 | sed -E 's/^#?[[:space:]]*av==([^[:space:]#]+).*/\\1/') \\
    && AV_VERSION=\${AV_VERSION:-10.0.0} \\
    && mamba install -y "python=3.7" "av==\${AV_VERSION}" \\
    && conda clean --all --yes
RUN grep -Ev '^[[:space:]]*(#|[[:space:]]*\$)' /tmp/requirements.txt \\
    | grep -Ev '^(av|pywin32)==' \\
    | sed 's/^requests==2\\.18\\.4/requests>=2.20.0,<3/' > /tmp/req.txt \\
    && pip install --no-cache-dir -r /tmp/req.txt \\
    && rm -f /tmp/requirements.txt /tmp/req.txt
CMD ["python", "gui.py"]
EOF

    cat <<EOF > "$INSTALL_DIR/docker-compose.yml"
services:
  alas:
    image: $IMAGE_NAME
    container_name: $CONTAINER_NAME
    network_mode: host
    restart: unless-stopped
    volumes:
      - \${HOME}/.android:/root/.android
      - ./src:/app/AzurLaneAutoScript
      - /etc/localtime:/etc/localtime:ro
    working_dir: /app/AzurLaneAutoScript
    command: sh -c "git config --global --add safe.directory '*' && exec python gui.py"
EOF
}

setup_environment() {
    install_system_dependencies || return 1

    log_info "$(t info_docker_check)"
    start_docker_service || return 1
    if ! docker info >/dev/null 2>&1; then
        fix_docker_permission || return 1
    fi

    log_info "$(t info_workdir_prep "$INSTALL_DIR")"
    write_docker_files
    log_ok "$(t ok_env_ready)"
}

apply_patches() {
    local req_file="$SRC_DIR/requirements.txt"
    if [ ! -f "$req_file" ]; then
        log_err "$(t err_no_req "$req_file")"
        return 1
    fi
    log_info "$(t info_patch)"
    sed -i 's/^av==/# av==/' "$req_file"
    sed -i 's/^pywin32==/# pywin32==/' "$req_file"
    sed -i 's/^requests==2\.18\.4/requests>=2.20.0,<3/' "$req_file"
    log_ok "$(t ok_patch)"
}

alas_lang_code() {
    case "$UI_LANG" in
        zh) printf 'zh-CN' ;;
        ja) printf 'ja-JP' ;;
        *)  printf 'en-US' ;;
    esac
}

ensure_deploy_config() {
    local config_dir="$SRC_DIR/config"
    local deploy_file="$config_dir/deploy.yaml"

    [ -d "$config_dir" ] || return 0

    if [ ! -e "$INSTALL_DIR/config" ] && [ ! -L "$INSTALL_DIR/config" ]; then
        ln -s "src/config" "$INSTALL_DIR/config"
    fi

    if [ ! -f "$deploy_file" ]; then
        log_info "$(t info_deploy_init)"
        if [ -f "$config_dir/deploy.template-docker.yaml" ]; then
            cp "$config_dir/deploy.template-docker.yaml" "$deploy_file"
        elif [ -f "$config_dir/deploy.template.yaml" ]; then
            cp "$config_dir/deploy.template.yaml" "$deploy_file"
        else
            log_warn "$(t warn_no_deploy_tpl)"
            return 0
        fi

        local deploy_lang
        deploy_lang="$(alas_lang_code)"

        sed -i -E \
            -e 's|^([[:space:]]*GitExecutable:).*|\1 /usr/bin/git|' \
            -e 's|^([[:space:]]*PythonExecutable:).*|\1 /opt/conda/bin/python|' \
            -e 's|^([[:space:]]*AdbExecutable:).*|\1 /usr/bin/adb|' \
            -e 's|^([[:space:]]*RequirementsFile:).*|\1 requirements.txt|' \
            -e 's|^([[:space:]]*AutoUpdate:).*|\1 false|' \
            -e 's|^([[:space:]]*InstallDependencies:).*|\1 false|' \
            -e 's|^([[:space:]]*CheckUpdateInterval:).*|\1 0|' \
            -e 's|^([[:space:]]*AutoRestartTime:).*|\1 null|' \
            -e 's|^([[:space:]]*ReplaceAdb:).*|\1 false|' \
            -e "s|^([[:space:]]*Language:).*|\1 ${deploy_lang}|" \
            "$deploy_file"
        log_ok "$(t ok_deploy_init)"
    elif grep -Eq '^[[:space:]]*(Git|Python|Adb)Executable:[[:space:]]*\./toolkit/' "$deploy_file" 2>/dev/null; then
        sed -i -E \
            -e 's|^([[:space:]]*GitExecutable:).*|\1 /usr/bin/git|' \
            -e 's|^([[:space:]]*PythonExecutable:).*|\1 /opt/conda/bin/python|' \
            -e 's|^([[:space:]]*AdbExecutable:).*|\1 /usr/bin/adb|' \
            -e 's|^([[:space:]]*ReplaceAdb:).*|\1 false|' \
            "$deploy_file"
        log_ok "$(t ok_deploy_fix)"
    fi
}

container_running() {
    [ -n "$(docker ps -q -f "name=^/${CONTAINER_NAME}$" 2>/dev/null)" ]
}

check_update() {
    mkdir -p "$INSTALL_DIR"

    if [ ! -d "$SRC_DIR/.git" ]; then
        log_info "$(t info_cloning "$SRC_DIR")"
        git clone "$REPO_URL" "$SRC_DIR" || {
            log_err "$(t err_clone)"
            return 1
        }
        apply_patches || return 1
        ensure_deploy_config
        return 0
    fi

    if [ ! -w "$SRC_DIR/.git" ] || [ ! -w "$SRC_DIR/.git/objects" ]; then
        log_err "$(t err_git_perm "$SRC_DIR/.git" "${USER:-$(id -un)}" "$(id -gn)" "$INSTALL_DIR")"
        return 1
    fi

    # 检查除 requirements.txt 之外是否存在其他受跟踪文件的未提交改动
    local dirty_other
    dirty_other="$(git -C "$SRC_DIR" status --porcelain --untracked-files=no 2>/dev/null | awk '$2 != "requirements.txt"')"
    if [ -n "$dirty_other" ]; then
        log_err "$(t err_dirty_tree)"
        printf '%s\n' "$dirty_other"
        return 1
    fi

    log_info "$(t info_checking_update)"
    git -C "$SRC_DIR" fetch --prune origin || {
        log_err "$(t err_fetch)"
        return 1
    }

    local upstream local_rev remote_rev req_changed=0
    upstream="$(git -C "$SRC_DIR" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || echo 'origin/master')"
    local_rev="$(git -C "$SRC_DIR" rev-parse HEAD)"
    remote_rev="$(git -C "$SRC_DIR" rev-parse "$upstream")"

    if [ "$local_rev" != "$remote_rev" ]; then
        if ! git -C "$SRC_DIR" diff --quiet "$local_rev" "$remote_rev" -- requirements.txt 2>/dev/null; then
            req_changed=1
        fi

        log_info "$(t info_pulling "${local_rev:0:8}" "${remote_rev:0:8}")"
        git -C "$SRC_DIR" checkout -- requirements.txt 2>/dev/null || true

        if ! git -C "$SRC_DIR" pull --ff-only; then
            log_err "$(t err_pull)"
            apply_patches || true
            return 1
        fi

        apply_patches || return 1
        ensure_deploy_config

        if (( req_changed )); then
            log_warn "$(t warn_req_changed)"
        fi

        if container_running; then
            log_info "$(t info_restarting)"
            run_compose restart alas || true
            wait_for_webui || true
        fi

        log_ok "$(t ok_updated "${remote_rev:0:8}")"
    else
        log_ok "$(t ok_up_to_date "${local_rev:0:8}")"
        apply_patches || return 1
        ensure_deploy_config
    fi
}

build_image() {
    if ! docker info >/dev/null 2>&1; then
        setup_environment || return 1
    fi
    write_docker_files
    if [ ! -d "$SRC_DIR/.git" ]; then
        check_update || return 1
    fi

    log_info "$(t info_building "$IMAGE_NAME" "$CPU_ARCH")"
    docker build -t "$IMAGE_NAME" "$INSTALL_DIR" || {
        log_err "$(t err_build)"
        return 1
    }
    log_ok "$(t ok_build "$IMAGE_NAME")"

    if container_running; then
        log_info "$(t info_restarting)"
        run_compose up -d --force-recreate || true
        wait_for_webui || true
    fi
}

connect_waydroid_adb() {
    if ! command -v adb >/dev/null 2>&1; then
        log_warn "$(t st_adb_no_bin)"
        return 0
    fi

    if command -v waydroid >/dev/null 2>&1; then
        local wd_ip
        wd_ip="$(waydroid status 2>/dev/null | awk '/IP address:/ {print $3; exit}')"
        if [ -n "$wd_ip" ]; then
            log_info "$(t info_wd_connect "$wd_ip")"
            adb connect "${wd_ip}:5555" || true
        else
            log_warn "$(t warn_wd_stopped)"
        fi
    fi

    printf '%s%s%s\n' "$C_BCYAN" "$(t lbl_adb_list)" "$C_RESET"
    local devices_out
    devices_out="$(adb devices -l 2>&1 || true)"
    printf '%s\n' "$devices_out"

    if printf '%s\n' "$devices_out" | grep -q 'unauthorized'; then
        log_warn "$(t warn_adb_unauth)"
    fi
}

wait_for_webui() {
    log_info "$(t info_wait_webui "$WEBUI_PORT")"
    local i
    for i in $(seq 1 20); do
        if http_probe_url "http://127.0.0.1:${WEBUI_PORT}"; then
            log_ok "$(t ok_started "$WEBUI_PORT")"
            return 0
        fi
        if ! container_running; then
            log_err "$(t err_exited)"
            run_compose logs --tail=40 alas || true
            return 1
        fi
        sleep 1
    done
    log_warn "$(t warn_webui_timeout)"
    printf '  http://127.0.0.1:%s\n' "$WEBUI_PORT"
    return 0
}

start_alas() {
    if [ ! -f "$INSTALL_DIR/docker-compose.yml" ]; then
        setup_environment || return 1
    else
        select_compose_cmd || return 1
        start_docker_service || return 1
        if ! docker info >/dev/null 2>&1; then
            fix_docker_permission || return 1
        fi
    fi

    if [ ! -d "$SRC_DIR/.git" ]; then
        check_update || return 1
    else
        apply_patches || return 1
        ensure_deploy_config
    fi

    if [ -z "$(docker images -q "$IMAGE_NAME" 2>/dev/null)" ]; then
        build_image || return 1
    fi

    connect_waydroid_adb

    log_info "$(t info_starting)"
    run_compose up -d || {
        log_err "$(t err_start)"
        return 1
    }

    wait_for_webui
}

stop_alas() {
    if [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
        run_compose stop
        log_ok "$(t ok_stopped)"
    else
        log_warn "$(t warn_not_init "$INSTALL_DIR")"
    fi
}

restart_alas() {
    stop_alas || true
    start_alas
}

show_logs() {
    if [ ! -f "$INSTALL_DIR/docker-compose.yml" ]; then
        log_warn "$(t warn_not_init "$INSTALL_DIR")"
        return 0
    fi
    printf '%s[*] %s%s\n' "$C_BCYAN" "$(t info_logs_hint)" "$C_RESET"
    trap ':' INT
    run_compose logs -f --tail=100
    trap - INT
}

uninstall_alas() {
    log_warn "$(t warn_uninstall "$CONTAINER_NAME" "$IMAGE_NAME" "$INSTALL_DIR")"
    local confirm backup_ans
    read -r -p "$(t prompt_uninstall)" confirm
    if [[ ! "$confirm" =~ ^[yY]$ ]]; then
        printf '%s\n' "$(t msg_cancelled)"
        return 0
    fi

    if [ -d "$SRC_DIR/config" ]; then
        read -r -p "$(t prompt_backup)" backup_ans
        if [[ ! "$backup_ans" =~ ^[nN]$ ]]; then
            local ts backup_file
            ts="$(date +%Y%m%d-%H%M%S)"
            backup_file="$HOME/ALAS/alas-config-backup-${ts}.tar.gz"
            mkdir -p "$HOME/ALAS"
            if tar -C "$SRC_DIR" -czf "$backup_file" config 2>/dev/null; then
                log_ok "$(t ok_backup "$backup_file")"
            fi
        fi
    fi

    if [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
        run_compose down --remove-orphans || true
    else
        docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
    fi
    docker rmi "$IMAGE_NAME" 2>/dev/null || true

    if [ -d "$INSTALL_DIR" ]; then
        if ! rm -rf "$INSTALL_DIR" 2>/dev/null; then
            log_warn "$(t warn_rm_sudo "$INSTALL_DIR")"
        fi
    fi
    log_ok "$(t ok_uninstalled)"
}

# =================================================================
# 7. 状态仪表盘采集（缓存至内存，保证 TUI 方向键 0 延迟）
# =================================================================

refresh_dashboard() {
    # 容器状态
    if [ ! -d "$INSTALL_DIR" ]; then
        DASH_STATUS_COLOR="$C_YELLOW"
        DASH_STATUS_TEXT="$(t st_not_installed)"
    elif ! command -v docker >/dev/null 2>&1; then
        DASH_STATUS_COLOR="$C_BRED"
        DASH_STATUS_TEXT="$(t st_docker_down)"
    else
        local cid rc
        cid="$(docker ps -q -f "name=^/${CONTAINER_NAME}$" 2>/dev/null)"
        rc=$?
        if [ $rc -ne 0 ]; then
            DASH_STATUS_COLOR="$C_BRED"
            DASH_STATUS_TEXT="$(t st_perm_denied)"
        elif [ -n "$cid" ]; then
            DASH_STATUS_COLOR="$C_BGREEN"
            DASH_STATUS_TEXT="$(t st_running)"
        else
            DASH_STATUS_COLOR="$C_YELLOW"
            DASH_STATUS_TEXT="$(t st_stopped)"
        fi
    fi

    # WebUI 状态
    if http_probe_url "http://127.0.0.1:${WEBUI_PORT}"; then
        DASH_WEBUI_TEXT="${C_BCYAN}http://127.0.0.1:${WEBUI_PORT}${C_RESET} ${C_BGREEN}[$(t st_webui_up)]${C_RESET}"
    else
        DASH_WEBUI_TEXT="${C_DIM}http://127.0.0.1:${WEBUI_PORT} [$(t st_webui_wait)]${C_RESET}"
    fi

    # 源码版本
    if [ -d "$SRC_DIR/.git" ]; then
        local rev branch
        rev="$(git -C "$SRC_DIR" rev-parse --short HEAD 2>/dev/null || echo '?')"
        branch="$(git -C "$SRC_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'master')"
        DASH_SRC_TEXT="${C_WHITE}${rev}${C_RESET} ${C_DIM}(${branch})${C_RESET}"
    else
        DASH_SRC_TEXT="${C_DIM}$(t st_src_none)${C_RESET}"
    fi

    # Waydroid / ADB 状态
    local wd_ip=""
    if command -v waydroid >/dev/null 2>&1; then
        wd_ip="$(waydroid status 2>/dev/null | awk '/IP address:/ {print $3; exit}')"
    fi

    if ! command -v adb >/dev/null 2>&1; then
        DASH_ADB_COLOR="$C_DIM"
        DASH_ADB_TEXT="$(t st_adb_no_bin)"
    else
        local adb_out
        adb_out="$(adb devices 2>/dev/null | tail -n +2 | grep -v '^[[:space:]]*$' || true)"
        if [ -n "$wd_ip" ]; then
            if printf '%s\n' "$adb_out" | grep -q "${wd_ip}:5555[[:space:]]\+device"; then
                DASH_ADB_COLOR="$C_BGREEN"
                DASH_ADB_TEXT="$(t st_waydroid_ready) (${wd_ip}:5555)"
            elif printf '%s\n' "$adb_out" | grep -q "${wd_ip}:5555[[:space:]]\+unauthorized"; then
                DASH_ADB_COLOR="$C_YELLOW"
                DASH_ADB_TEXT="$(t st_waydroid_unauth)"
            else
                DASH_ADB_COLOR="$C_YELLOW"
                DASH_ADB_TEXT="$(t st_waydroid_disc) (${wd_ip})"
            fi
        elif [ -n "$adb_out" ]; then
            if printf '%s\n' "$adb_out" | grep -q 'unauthorized'; then
                DASH_ADB_COLOR="$C_YELLOW"
                DASH_ADB_TEXT="$(t st_adb_unauth)"
            else
                local first_dev
                first_dev="$(printf '%s\n' "$adb_out" | awk '$2=="device"{print $1; exit}')"
                DASH_ADB_COLOR="$C_BGREEN"
                DASH_ADB_TEXT="$(t st_adb_connected) (${first_dev:-device})"
            fi
        else
            DASH_ADB_COLOR="$C_DIM"
            DASH_ADB_TEXT="$(t st_adb_none)"
        fi
    fi
}

print_status_cli() {
    refresh_dashboard
    printf '%s%s%s v%s  [%s | %s | %s]\n' "$C_BBLUE" "$(t app_title)" "$C_RESET" "$APP_VERSION" "$OS_PRETTY" "$PKG_MANAGER" "$(t lang_label)"
    printf '  %-14s %s%s%s\n' "$(t lbl_container):" "$DASH_STATUS_COLOR" "$DASH_STATUS_TEXT" "$C_RESET"
    printf '  %-14s %s\n'     "$(t lbl_webui):" "$DASH_WEBUI_TEXT"
    printf '  %-14s %s\n'     "$(t lbl_source):" "$DASH_SRC_TEXT"
    printf '  %-14s %s%s%s\n' "$(t lbl_adb):" "$DASH_ADB_COLOR" "$DASH_ADB_TEXT" "$C_RESET"
    printf '  %-14s %s\n'     "$(t lbl_path):" "$INSTALL_DIR"
}

# =================================================================
# 8. 现代化兼容 TUI（零外部依赖，方向键 + 快捷键 + 降级兼容）
# =================================================================

MENU_KEYS=(1 2 3 4 5 6 7 8 9 0)

enter_tui_screen() {
    if (( TUI_ACTIVE == 0 )); then
        printf '\033[?1049h\033[?25l'
        TUI_ACTIVE=1
    fi
}

leave_tui_screen() {
    if (( TUI_ACTIVE == 1 )); then
        printf '\033[?25h\033[?1049l'
        TUI_ACTIVE=0
    fi
}

cleanup_tty() {
    leave_tui_screen
    printf '%s' "$C_RESET"
}

draw_tui() {
    local hr="${C_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    local sub_hr="${C_DIM}──────────────────────────────────────────────────────────────${C_RESET}"

    # 回到左上角并清屏，减少闪烁
    printf '\033[H\033[J'

    printf '%s\n' "$hr"
    printf '  %s%s%s  %sv%s%s   %s[%s]%s\n' \
        "$C_BCYAN" "$(t app_title)" "$C_RESET" \
        "$C_DIM" "$APP_VERSION" "$C_RESET" \
        "$C_GREEN" "$(t lang_label)" "$C_RESET"
    printf '%s\n' "$hr"

    # 状态仪表盘
    printf '  %s%s%s\n' "$C_BOLD" "$(t sec_status)" "$C_RESET"
    printf '  %s  %s%s (%s / %s)%s\n' "${C_DIM}$(t lbl_system):${C_RESET}" "$C_WHITE" "$OS_PRETTY" "$PKG_MANAGER" "$DOWNLOADER" "$C_RESET"
    printf '  %s  %s%s%s\n'            "${C_DIM}$(t lbl_container):${C_RESET}" "$DASH_STATUS_COLOR" "$DASH_STATUS_TEXT" "$C_RESET"
    printf '  %s  %s\n'                "${C_DIM}$(t lbl_webui):${C_RESET}" "$DASH_WEBUI_TEXT"
    printf '  %s  %s\n'                "${C_DIM}$(t lbl_source):${C_RESET}" "$DASH_SRC_TEXT"
    printf '  %s  %s%s%s\n'            "${C_DIM}$(t lbl_adb):${C_RESET}" "$DASH_ADB_COLOR" "$DASH_ADB_TEXT" "$C_RESET"
    printf '  %s  %s%s%s\n'            "${C_DIM}$(t lbl_path):${C_RESET}" "$C_DIM" "$INSTALL_DIR" "$C_RESET"
    printf '%s\n' "$sub_hr"

    # 操作菜单
    printf '  %s%s%s\n' "$C_BOLD" "$(t sec_actions)" "$C_RESET"
    local idx key label
    for idx in "${!MENU_KEYS[@]}"; do
        key="${MENU_KEYS[$idx]}"
        label="$(t "menu_${key}")"
        if (( idx == TUI_SELECTED )); then
            if [ "$key" = "9" ]; then
                printf '  %s%s ❯ [%s] %s %s\n' "$C_REV" "$C_BRED" "$key" "$label" "$C_RESET"
            else
                printf '  %s%s ❯ [%s] %s %s\n' "$C_REV" "$C_BCYAN" "$key" "$label" "$C_RESET"
            fi
        else
            if [ "$key" = "9" ]; then
                printf '     %s[%s]%s %s%s%s\n' "$C_DIM" "$key" "$C_RESET" "$C_RED" "$label" "$C_RESET"
            elif [ "$key" = "1" ]; then
                printf '     %s[%s]%s %s%s%s\n' "$C_DIM" "$key" "$C_RESET" "$C_BGREEN" "$label" "$C_RESET"
            else
                printf '     %s[%s]%s %s\n' "$C_DIM" "$key" "$C_RESET" "$label"
            fi
        fi
    done

    # 当前高亮项的简明说明
    local cur_key="${MENU_KEYS[$TUI_SELECTED]}"
    printf '%s\n' "$sub_hr"
    printf '  %s▸ %s%s\n' "$C_YELLOW" "$(t "desc_${cur_key}")" "$C_RESET"
    printf '%s\n' "$hr"
    printf '  %s%s%s\n' "$C_DIM" "$(t footer_tui)" "$C_RESET"
}

run_menu_action() {
    local key="$1"
    local pause_after=1

    case "$key" in
        8)
            cycle_language
            refresh_dashboard
            return 0
            ;;
        0)
            cleanup_tty
            exit 0
            ;;
    esac

    # 执行实际命令时退出备用屏幕，保留完整可滚屏输出
    leave_tui_screen
    printf '\033[H\033[J'
    printf '%s━━━ %s ━━━%s\n\n' "$C_BCYAN" "$(t "menu_${key}")" "$C_RESET"

    case "$key" in
        1) start_alas || true ;;
        2) stop_alas || true ;;
        3) show_logs; pause_after=0 ;;
        4) check_update || true ;;
        5) connect_waydroid_adb || true ;;
        6) build_image || true ;;
        7) fix_docker_permission || true ;;
        9) uninstall_alas || true ;;
    esac

    if (( pause_after == 1 )); then
        printf '\n'
        read -r -p "$(t press_enter)" _ || true
    fi

    refresh_dashboard
}

run_interactive_tui() {
    trap cleanup_tty EXIT INT TERM

    refresh_dashboard
    enter_tui_screen

    local key rest total="${#MENU_KEYS[@]}"

    while true; do
        enter_tui_screen
        draw_tui

        IFS= read -rsn1 key || break

        case "$key" in
            $'\x1b')
                # 读取方向键/功能键转义序列；若超时则是单独按下 Esc
                if LC_NUMERIC=C IFS= read -rsn1 -t 0.05 rest; then
                    if [ "$rest" = "[" ] || [ "$rest" = "O" ]; then
                        LC_NUMERIC=C IFS= read -rsn1 -t 0.05 rest || rest=""
                        case "$rest" in
                            A) TUI_SELECTED=$(( (TUI_SELECTED - 1 + total) % total )) ;;
                            B) TUI_SELECTED=$(( (TUI_SELECTED + 1) % total )) ;;
                            H|1) TUI_SELECTED=0 ;;
                            F|4) TUI_SELECTED=$(( total - 1 )) ;;
                        esac
                    fi
                else
                    break
                fi
                ;;
            k|K|w|W)
                TUI_SELECTED=$(( (TUI_SELECTED - 1 + total) % total ))
                ;;
            j|J|s|S)
                TUI_SELECTED=$(( (TUI_SELECTED + 1) % total ))
                ;;
            ""|" ")
                run_menu_action "${MENU_KEYS[$TUI_SELECTED]}"
                ;;
            [0-9])
                local i
                for i in "${!MENU_KEYS[@]}"; do
                    if [ "${MENU_KEYS[$i]}" = "$key" ]; then
                        TUI_SELECTED=$i
                        break
                    fi
                done
                run_menu_action "$key"
                ;;
            r|R)
                refresh_dashboard
                ;;
            l|L)
                cycle_language
                refresh_dashboard
                ;;
            q|Q)
                break
                ;;
        esac
    done

    cleanup_tty
}

run_fallback_menu() {
    local choice
    while true; do
        printf '\n'
        print_status_cli
        printf '%s\n' "------------------------------------------"
        local key
        for key in "${MENU_KEYS[@]}"; do
            printf '  %s. %s\n' "$key" "$(t "menu_${key}")"
        done
        printf '%s\n' "------------------------------------------"

        if ! read -r -p "$(t prompt_choice)" choice; then
            break
        fi

        case "$choice" in
            [1-9])
                run_menu_action "$choice"
                ;;
            0|q|Q)
                break
                ;;
            r|R)
                refresh_dashboard
                ;;
            l|L)
                cycle_language
                ;;
            *)
                printf '%s\n' "$(t invalid_choice)"
                ;;
        esac
    done
}

# =================================================================
# 9. 主入口与命令行参数解析
# =================================================================

main() {
    local cmd=""
    local cli_lang=""
    local orig_args=("$@")

    while (( $# > 0 )); do
        case "$1" in
            --lang|-l)
                shift
                cli_lang="${1:-}"
                ;;
            --lang=*)
                cli_lang="${1#*=}"
                ;;
            --no-relaunch)
                ALAS_NO_TERM=1
                ;;
            -h|--help)
                cmd="help"
                ;;
            start|stop|restart|logs|update|rebuild|adb|status|uninstall)
                cmd="$1"
                ;;
            *)
                detect_system_lang "$cli_lang"
                load_i18n
                printf '%s\n' "$(t usage_text "$0")" >&2
                exit 1
                ;;
        esac
        shift || true
    done

    detect_system_env
    detect_system_lang "$cli_lang"
    load_i18n

    case "$cmd" in
        help)
            printf '%s\n' "$(t usage_text "$0")"
            exit 0
            ;;
        start)     start_alas; exit $? ;;
        stop)      stop_alas; exit $? ;;
        restart)   restart_alas; exit $? ;;
        logs)      show_logs; exit $? ;;
        update)    check_update; exit $? ;;
        rebuild)   build_image; exit $? ;;
        adb)       connect_waydroid_adb; exit $? ;;
        status)    print_status_cli; exit 0 ;;
        uninstall) uninstall_alas; exit $? ;;
    esac

    # 无子命令：如果是文件管理器双击启动（无 TTY），自动拉起终端窗口
    maybe_relaunch_in_terminal ${orig_args[@]+"${orig_args[@]}"}

    if [ -t 0 ] && [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ]; then
        run_interactive_tui
    else
        run_fallback_menu
    fi
}

main "$@"
