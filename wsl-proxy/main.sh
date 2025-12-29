# ==============================================================================
#  WSL 代理管理函数
#  用法:
#    proxy on [ip] [port]  - 开启代理（IP可选，自动检测；端口默认7890）
#    proxy off             - 关闭代理
#    proxy status          - 查看当前状态
# ==============================================================================

function proxy() {
    # ----------------------------- 配置 -----------------------------
    local DEFAULT_PORT="7890"
    local TIMEOUT=5
    local TEST_URL_DIRECT="https://www.bing.com"
    local TEST_URL_PROXY="https://www.google.com"

    # ----------------------------- 颜色 -----------------------------
    local RED='\033[0;31m'
    local GREEN='\033[0;32m'
    local YELLOW='\033[0;33m'
    local BLUE='\033[0;34m'
    local NC='\033[0m'

    # --------------------------- 辅助函数 ---------------------------
    _proxy_log_info()    { echo -e "${BLUE}$1${NC}"; }
    _proxy_log_success() { echo -e "${GREEN}$1${NC}"; }
    _proxy_log_warn()    { echo -e "${YELLOW}$1${NC}"; }
    _proxy_log_error()   { echo -e "${RED}$1${NC}"; }

    _proxy_test_url() {
        curl -s -f --connect-timeout "$TIMEOUT" --head -o /dev/null "$1" 2>/dev/null
    }

    _proxy_get_gateway_ip() {
        ip route | awk '/default/ {print $3; exit}'
    }

    _proxy_set_env() {
        local url="$1"
        export http_proxy="$url"
        export https_proxy="$url"
        export ftp_proxy="$url"
        export no_proxy="localhost,127.0.0.1,::1"
        export HTTP_PROXY="$url"
        export HTTPS_PROXY="$url"
        export FTP_PROXY="$url"
        export NO_PROXY="$no_proxy"
    }

    _proxy_unset_env() {
        unset http_proxy https_proxy ftp_proxy no_proxy
        unset HTTP_PROXY HTTPS_PROXY FTP_PROXY NO_PROXY
    }

    _proxy_show_usage() {
        cat << 'EOF'
用法: proxy <command> [options]

命令:
  on [ip] [port]   开启代理（IP自动检测，端口默认7890）
  off              关闭代理
  status           查看当前状态

示例:
  proxy on                    # 自动检测IP，默认端口
  proxy on 192.168.1.1        # 指定IP
  proxy on 192.168.1.1 10808  # 指定IP和端口
EOF
    }

    # --------------------------- 主逻辑 ---------------------------
    case "$1" in
        on)
            local proxy_ip=""
            local proxy_port="${3:-$DEFAULT_PORT}"

            # 获取 IP
            if [ -n "$2" ]; then
                proxy_ip="$2"
                _proxy_log_info "使用指定IP: $proxy_ip"
            else
                _proxy_log_info "正在自动检测网关IP..."
                proxy_ip=$(_proxy_get_gateway_ip)
                if [ -z "$proxy_ip" ]; then
                    _proxy_log_error "错误: 无法检测网关IP"
                    return 1
                fi
                _proxy_log_info "检测到网关: $proxy_ip"
            fi

            # 测试直连
            _proxy_log_warn "正在测试网络连接..."
            if ! _proxy_test_url "$TEST_URL_DIRECT"; then
                _proxy_log_error "错误: 无法访问网络，请检查连接"
                return 1
            fi

            # 设置代理
            local proxy_url="http://${proxy_ip}:${proxy_port}"
            _proxy_set_env "$proxy_url"
            _proxy_log_info "代理地址: $proxy_url"

            # 测试代理
            _proxy_log_warn "正在测试代理连接..."
            if _proxy_test_url "$TEST_URL_PROXY"; then
                _proxy_log_success "代理设置成功！"
            else
                _proxy_log_error "代理连接失败，请检查代理服务"
                _proxy_unset_env
                return 1
            fi
            ;;

        off)
            _proxy_unset_env
            _proxy_log_success "代理已关闭"
            ;;

        status)
            echo -e "${BLUE}--- 代理状态 ---${NC}"
            if [ -n "$http_proxy" ]; then
                echo -e "状态: ${GREEN}已开启${NC}"
                echo "地址: $http_proxy"
            else
                echo -e "状态: ${RED}已关闭${NC}"
            fi
            ;;

        *)
            _proxy_show_usage
            ;;
    esac
}
