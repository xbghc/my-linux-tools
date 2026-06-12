#!/usr/bin/env bash
#
# proxy 用户级安装：仅当前用户。复制副本到 ~/.local/lib，无需 root，可迁移
# （加载块用 $HOME 变量，换机器 / 换用户都正确，不依赖仓库位置）。
#
# 用法:
#   ./install-user.sh             安装
#   ./install-user.sh --uninstall 卸载
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

LIB_DIR="$HOME/.local/lib/proxy"
LIB_FILE="$LIB_DIR/proxy.sh"
CONFIG_DIR="$HOME/.config/proxy"
CONFIG="$CONFIG_DIR/config"
BASHRC="$HOME/.bashrc"

MARKER_BEGIN="# >>> proxy tool >>>"
MARKER_END="# <<< proxy tool <<<"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'
info() { echo -e "${GREEN}==>${NC} $*"; }
warn() { echo -e "${YELLOW}!!${NC}  $*"; }
err()  { echo -e "${RED}错误:${NC} $*" >&2; }

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
    info "安装函数本体 -> $LIB_FILE"
    install -d -m 755 "$LIB_DIR"
    fetch_main "$LIB_FILE"

    info "在 $BASHRC 注册加载"
    if grep -qF "$MARKER_BEGIN" "$BASHRC" 2>/dev/null; then
        warn "$BASHRC 已有加载块，跳过"
    else
        cat >> "$BASHRC" <<EOF

$MARKER_BEGIN
if [ -f "\$HOME/.local/lib/proxy/proxy.sh" ]; then
    . "\$HOME/.local/lib/proxy/proxy.sh"
    # 仅首个 shell 自动开启；子 shell 继承环境变量即可
    if [ -z "\$http_proxy" ] && grep -qsiE '^[[:space:]]*auto_on[[:space:]]*=[[:space:]]*(1|true|yes)' "\$HOME/.config/proxy/config"; then
        proxy on
    fi
fi
$MARKER_END
EOF
    fi

    if [ -f "$CONFIG" ]; then
        warn "已存在 $CONFIG，保留不覆盖"
    else
        info "创建用户配置 -> $CONFIG"
        install -d -m 755 "$CONFIG_DIR"
        cat > "$CONFIG" <<'EOF'
# proxy 工具用户级配置
proxy_schema=http
proxy_host=
# proxy_port 用 'proxy detect-port' 探测写入；也可手动填
proxy_port=

# 登录时自动开启代理：1 / true / yes 开启，其它为关闭
auto_on=0
EOF
    fi

    # 装好后自动探测并配置（探测逻辑在 proxy detect-port 命令里；代理需正在运行）
    info "尝试自动探测代理端口..."
    # shellcheck disable=SC1090
    . "$LIB_FILE"
    if proxy detect-port >/dev/null 2>&1; then
        sed -i 's/^auto_on=.*/auto_on=1/' "$CONFIG" 2>/dev/null
        info "已自动写入 host+port 并设 auto_on=1（登录自动开启）"
    else
        warn "未探测到端口（代理可能未运行）。启动代理后执行 'proxy detect-port'"
    fi

    echo
    info "完成。执行 'source $BASHRC' 让命令生效，proxy status 验证。"
}

do_uninstall() {
    info "移除 $LIB_DIR"; rm -rf "$LIB_DIR"
    if grep -qF "$MARKER_BEGIN" "$BASHRC" 2>/dev/null; then
        info "清理 $BASHRC 加载块"
        sed -i "/$MARKER_BEGIN/,/$MARKER_END/d" "$BASHRC"
    fi
    [ -f "$CONFIG" ] && warn "保留 $CONFIG（如需删除手动 rm -r $CONFIG_DIR）"
    info "卸载完成（当前会话仍有 proxy 函数，重开终端即清）"
}

case "${1:-}" in
    "")          do_install ;;
    --uninstall) do_uninstall ;;
    -h|--help)   echo "用法: $0 [--uninstall]" ;;
    *) err "未知参数: $1"; echo "用法: $0 [--uninstall]"; exit 1 ;;
esac
