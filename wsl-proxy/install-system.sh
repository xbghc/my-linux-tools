#!/usr/bin/env bash
#
# proxy 系统级安装：一个系统一份配置，所有用户（含将来新建用户）可用。
#
# 用法:
#   sudo ./install-system.sh             安装
#   sudo ./install-system.sh --uninstall 卸载
#
set -euo pipefail

# 远程源（可用环境变量覆盖：镜像加速 / 自托管 / 换分支）
RAW_BASE="${PROXY_RAW_BASE:-https://raw.githubusercontent.com/xbghc/my-linux-tools/main/wsl-proxy}"

# 定位本地 main.sh（git clone 场景）；curl|bash 场景无本地文件，留空走远程
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    SCRIPT_DIR=""
fi

LIB_DIR="/usr/local/lib/proxy"
LIB_FILE="$LIB_DIR/proxy.sh"
PROFILE_D="/etc/profile.d/proxy.sh"
BASHRC_SYS="/etc/bash.bashrc"
CONFIG_DIR="/etc/proxy"
CONFIG="$CONFIG_DIR/config"

MARKER_BEGIN="# >>> proxy tool >>>"
MARKER_END="# <<< proxy tool <<<"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'
info() { echo -e "${GREEN}==>${NC} $*"; }
warn() { echo -e "${YELLOW}!!${NC}  $*"; }
err()  { echo -e "${RED}错误:${NC} $*" >&2; }

require_root() {
    [ "$(id -u)" -eq 0 ] || {
        err "系统安装需要 root："
        err "  本地: sudo ./install-system.sh"
        err "  远程: curl -fsSL $RAW_BASE/install-system.sh | sudo bash"
        exit 1
    }
}

# 取 main.sh 到目标路径：本地优先，否则从远程下载
fetch_main() {
    local dest="$1"
    if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/main.sh" ]; then
        install -m 644 "$SCRIPT_DIR/main.sh" "$dest"
    else
        command -v curl >/dev/null 2>&1 || { err "需要 curl 才能从远程获取 main.sh"; exit 1; }
        info "从远程获取 main.sh：$RAW_BASE/main.sh"
        local tmp; tmp="$(mktemp)"
        if curl -fsSL "$RAW_BASE/main.sh" -o "$tmp"; then
            install -m 644 "$tmp" "$dest"; rm -f "$tmp"
        else
            rm -f "$tmp"; err "下载失败：$RAW_BASE/main.sh"; exit 1
        fi
    fi
}

do_install() {
    require_root

    info "安装函数本体 -> $LIB_FILE"
    install -d -m 755 "$LIB_DIR"
    fetch_main "$LIB_FILE"

    info "写入登录加载器 -> $PROFILE_D"
    cat > "$PROFILE_D" <<EOF
# proxy 工具登录加载器（由 install-system.sh 生成，请勿手改）
if [ -n "\$BASH_VERSION" ] && [ -f "$LIB_FILE" ]; then
    . "$LIB_FILE"
    # 仅登录 shell 按系统配置自动开启；子 shell 继承环境变量即可
    if [ -z "\$http_proxy" ] && grep -qsiE '^[[:space:]]*auto_on[[:space:]]*=[[:space:]]*(1|true|yes)' "$CONFIG"; then
        proxy on
    fi
fi
EOF
    chmod 644 "$PROFILE_D"

    info "为交互式非登录 shell 注册加载 -> $BASHRC_SYS"
    if [ -f "$BASHRC_SYS" ] && grep -qF "$MARKER_BEGIN" "$BASHRC_SYS"; then
        warn "$BASHRC_SYS 已有加载块，跳过"
    else
        cat >> "$BASHRC_SYS" <<EOF

$MARKER_BEGIN
[ -n "\$BASH_VERSION" ] && [ -f "$LIB_FILE" ] && . "$LIB_FILE"
$MARKER_END
EOF
    fi

    if [ -f "$CONFIG" ]; then
        warn "已存在 $CONFIG，保留不覆盖"
    else
        info "创建系统配置 -> $CONFIG"
        install -d -m 755 "$CONFIG_DIR"
        cat > "$CONFIG" <<'EOF'
# proxy 工具系统级配置（一个系统一份）
# 用户可在 ~/.config/proxy/config 覆盖以下任意项
proxy_schema=http
proxy_host=
proxy_port=7890

# 登录时自动开启代理：1 / true / yes 开启，其它为关闭
auto_on=0
EOF
        chmod 644 "$CONFIG"
    fi

    echo
    info "完成。后续："
    echo "  1. 编辑 $CONFIG 填入 proxy_host / proxy_port"
    echo "  2. 需要登录自动开启时把 auto_on 设为 1"
    echo "  3. 重新登录，任意用户执行 'proxy status' 验证"
}

do_uninstall() {
    require_root
    info "移除 $LIB_DIR"; rm -rf "$LIB_DIR"
    info "移除 $PROFILE_D"; rm -f "$PROFILE_D"
    if [ -f "$BASHRC_SYS" ] && grep -qF "$MARKER_BEGIN" "$BASHRC_SYS"; then
        info "清理 $BASHRC_SYS 加载块"
        sed -i "/$MARKER_BEGIN/,/$MARKER_END/d" "$BASHRC_SYS"
    fi
    [ -f "$CONFIG" ] && warn "保留 $CONFIG（如需删除手动 rm -r $CONFIG_DIR）"
    info "卸载完成（已开启的会话需重新登录或手动 proxy off）"
}

case "${1:-}" in
    "")          do_install ;;
    --uninstall) do_uninstall ;;
    -h|--help)   echo "用法: sudo $0 [--uninstall]" ;;
    *) err "未知参数: $1"; echo "用法: sudo $0 [--uninstall]"; exit 1 ;;
esac
