# ==============================================================================
#  WSL 代理管理函数
#  用法:
#    proxy on [ip] [port] [--test-direct URL] [--test-proxy URL]
#    proxy off
#    proxy status
#  配置文件: ~/.config/proxy/config
#    proxy_schema=http
#    proxy_host=192.168.1.1
#    proxy_port=7890
# ==============================================================================

function proxy() {
    # ----------------------------- 配置 -----------------------------
    local CONFIG_FILE="$HOME/.config/proxy/config"
    local DEFAULT_SCHEMA="http"
    local DEFAULT_HOST=""
    local DEFAULT_PORT="7890"
    local TIMEOUT=5

    # 读取配置文件
    if [ -f "$CONFIG_FILE" ]; then
        local config_schema config_host config_port
        config_schema=$(grep -E "^proxy_schema=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d ' ')
        config_host=$(grep -E "^proxy_host=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d ' ')
        config_port=$(grep -E "^proxy_port=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d ' ')

        [ -n "$config_schema" ] && DEFAULT_SCHEMA="$config_schema"
        [ -n "$config_host" ] && DEFAULT_HOST="$config_host"
        [ -n "$config_port" ] && DEFAULT_PORT="$config_port"
    fi

    # ----------------------------- 颜色 -----------------------------
    local RED='\033[0;31m'
    local GREEN='\033[0;32m'
    local YELLOW='\033[0;33m'
    local BLUE='\033[0;34m'
    local NC='\033[0m'

    # --------------------------- 辅助函数 ---------------------------
    local _verbose=0

    _proxy_log_info()    { [[ $_verbose -eq 1 ]] && echo -e "${BLUE}$1${NC}"; return 0; }
    _proxy_log_success() { [[ $_verbose -eq 1 ]] && echo -e "${GREEN}$1${NC}"; return 0; }
    _proxy_log_warn()    { [[ $_verbose -eq 1 ]] && echo -e "${YELLOW}$1${NC}"; return 0; }
    _proxy_log_error()   { echo -e "${RED}$1${NC}"; }

    _proxy_test_url() {
        curl -s -f --connect-timeout "$TIMEOUT" --head -o /dev/null "$1" 2>/dev/null
    }

    _proxy_is_wsl() {
        grep -qi 'microsoft\|wsl' /proc/version 2>/dev/null
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
  on [ip] [port] [options]   开启代理
  off                        关闭代理
  status                     查看当前状态

选项 (on/off 命令):
  -v, --verbose        显示详细输出信息

选项 (仅 on 命令):
  --test-direct URL    代理前测试的URL（默认: baidu.com）
  --test-proxy URL     代理后测试的URL（默认: google.com）

配置文件: ~/.config/proxy/config
  proxy_schema=http    代理协议（http/socks5）
  proxy_host=1.2.3.4   代理主机地址
  proxy_port=7890      代理端口

说明:
  在WSL环境下会自动获取Windows主机IP作为代理地址
  非WSL环境需要通过参数或配置文件指定代理主机
  默认静默模式运行，使用 -v 选项可显示详细日志

示例:
  proxy on                              # WSL下自动检测，或使用配置文件
  proxy on -v                           # 显示详细输出
  proxy on 192.168.1.1                  # 指定IP
  proxy on 192.168.1.1 10808            # 指定IP和端口
  proxy on --test-proxy https://x.com   # 自定义代理测试URL
EOF
    }

    # --------------------------- 主逻辑 ---------------------------
    case "$1" in
        on)
            shift  # 移除 'on'

            if [ -n "$http_proxy" ]; then
                _proxy_log_warn "代理当前已启用: $http_proxy"
                _proxy_log_info "正在重置并重新配置..."
                _proxy_unset_env
            fi

            local proxy_schema="$DEFAULT_SCHEMA"
            local proxy_ip="$DEFAULT_HOST"
            local proxy_port=""
            local test_url_direct="https://www.baidu.com"
            local test_url_proxy="https://www.google.com"

            # 解析参数
            while [ $# -gt 0 ]; do
                case "$1" in
                    -v|--verbose)
                        _verbose=1
                        shift
                        ;;
                    --test-direct)
                        test_url_direct="$2"
                        shift 2
                        ;;
                    --test-proxy)
                        test_url_proxy="$2"
                        shift 2
                        ;;
                    *)
                        # 位置参数：第一个是IP，第二个是端口
                        if [ -z "$proxy_ip" ]; then
                            proxy_ip="$1"
                        elif [ -z "$proxy_port" ]; then
                            proxy_port="$1"
                        fi
                        shift
                        ;;
                esac
            done

            proxy_port="${proxy_port:-$DEFAULT_PORT}"

            # 获取 IP
            if [ -n "$proxy_ip" ]; then
                _proxy_log_info "使用代理主机: $proxy_ip"
            elif _proxy_is_wsl; then
                _proxy_log_info "检测到WSL环境，正在自动获取主机IP..."
                proxy_ip=$(_proxy_get_gateway_ip)
                if [ -z "$proxy_ip" ]; then
                    _proxy_log_error "错误: 无法检测网关IP"
                    return 1
                fi
                _proxy_log_info "检测到主机: $proxy_ip"
            else
                _proxy_log_error "错误: 未指定代理主机，请通过参数或配置文件设置"
                return 1
            fi

            # 测试直连
            _proxy_log_warn "正在测试网络连接 ($test_url_direct)..."
            if ! _proxy_test_url "$test_url_direct"; then
                _proxy_log_error "错误: 无法访问网络，请检查连接"
                return 1
            fi

            # 设置代理
            local proxy_url="${proxy_schema}://${proxy_ip}:${proxy_port}"
            _proxy_set_env "$proxy_url"
            _proxy_log_info "代理地址: $proxy_url"

            # 测试代理
            _proxy_log_warn "正在测试代理连接 ($test_url_proxy)..."
            if _proxy_test_url "$test_url_proxy"; then
                _proxy_log_success "代理设置成功！"
            else
                _proxy_log_error "代理连接失败，请检查代理服务"
                _proxy_unset_env
                return 1
            fi
            ;;

        off)
            shift
            [[ "$1" == "-v" || "$1" == "--verbose" ]] && _verbose=1
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
