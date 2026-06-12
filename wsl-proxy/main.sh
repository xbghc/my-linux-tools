# ==============================================================================
#  代理管理函数（支持系统级 / 用户级配置，WSL 下自动探测主机 IP）
#  用法:
#    proxy on [ip] [port] [--test-direct URL] [--test-proxy URL]
#    proxy off
#    proxy status
#    proxy detect-port [host] [--system]   # 探测可用端口并保存到配置
#  配置文件（优先级低→高，后者覆盖前者）:
#    /etc/proxy/config        系统级（一个系统一份）
#    ~/.config/proxy/config   用户级（覆盖系统级）
#      proxy_schema=http
#      proxy_host=192.168.1.1
#      proxy_port=7890
# ==============================================================================

function proxy() {
    # ----------------------------- 配置 -----------------------------
    local SYSTEM_CONFIG="/etc/proxy/config"
    local USER_CONFIG="$HOME/.config/proxy/config"
    local DEFAULT_SCHEMA="http"
    local DEFAULT_HOST=""
    local DEFAULT_PORT=""          # 留空则在 proxy on 时自动探测常用代理端口
    local TIMEOUT=5
    # 探测时尝试的代理端口候选（按顺序，命中即止；可按需增减）
    local COMMON_PORTS="7890 7897 1080 20172"

    # 读取配置文件：先系统级，再用户级；用户级覆盖系统级
    # （实现"一个系统一份默认配置 + 个别用户可覆盖"）
    local _cfg_file config_schema config_host config_port
    for _cfg_file in "$SYSTEM_CONFIG" "$USER_CONFIG"; do
        [ -f "$_cfg_file" ] || continue
        config_schema=$(grep -E "^proxy_schema=" "$_cfg_file" 2>/dev/null | cut -d'=' -f2 | tr -d ' ')
        config_host=$(grep -E "^proxy_host=" "$_cfg_file" 2>/dev/null | cut -d'=' -f2 | tr -d ' ')
        config_port=$(grep -E "^proxy_port=" "$_cfg_file" 2>/dev/null | cut -d'=' -f2 | tr -d ' ')

        [ -n "$config_schema" ] && DEFAULT_SCHEMA="$config_schema"
        [ -n "$config_host" ] && DEFAULT_HOST="$config_host"
        [ -n "$config_port" ] && DEFAULT_PORT="$config_port"
    done

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

    # TCP 连通性测试（不依赖 nc，用 bash 内建 /dev/tcp）
    _proxy_port_open() {
        local host="$1" port="$2"
        timeout 1 bash -c 'exec 3<>/dev/tcp/$1/$2' _ "$host" "$port" 2>/dev/null
    }

    # 在 host 上探测可用代理端口：遍历常用端口，先测连通，再验证是否真为可用代理
    # 命中则 echo 端口号并返回 0，否则返回 1
    _proxy_detect_port() {
        local host="$1" schema="$2" test_url="$3" port
        for port in $COMMON_PORTS; do
            _proxy_port_open "$host" "$port" || continue
            if curl -s -f --connect-timeout 2 --head \
                    -x "${schema}://${host}:${port}" -o /dev/null "$test_url" 2>/dev/null; then
                echo "$port"
                return 0
            fi
        done
        return 1
    }

    # 把 key=value 写入配置文件（替换或追加该 key 行，纯 bash 读写）
    _proxy_save_kv() {
        local file="$1" key="$2" val="$3" line content="" found=0
        [ -d "${file%/*}" ] || mkdir -p "${file%/*}" 2>/dev/null || return 1
        if [ -f "$file" ]; then
            while IFS= read -r line || [ -n "$line" ]; do
                case "$line" in
                    "$key="*) content+="$key=$val"$'\n'; found=1 ;;
                    *)         content+="$line"$'\n' ;;
                esac
            done < "$file"
        fi
        [ "$found" -eq 0 ] && content+="$key=$val"$'\n'
        printf '%s' "$content" > "$file" 2>/dev/null || return 1
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
  on [ip] [port] [options]   开启代理（端口取自参数/配置）
  off                        关闭代理
  status                     查看当前状态
  detect-port [host]         探测可用端口并保存到配置（加 --system 写系统级）

选项 (on/off 命令):
  -v, --verbose        显示详细输出信息

选项 (仅 on 命令):
  --test-direct URL    代理前测试的URL（默认: baidu.com）
  --test-proxy URL     代理后测试的URL（默认: google.com）

配置文件（优先级低→高，后者覆盖前者）:
  /etc/proxy/config        系统级（一个系统一份）
  ~/.config/proxy/config   用户级（覆盖系统级）
    proxy_schema=http    代理协议（http/socks5）
    proxy_host=1.2.3.4   代理主机地址
    proxy_port=7890      代理端口（用 proxy detect-port 探测保存，或手动设置）

说明:
  在WSL环境下会自动获取Windows主机IP作为代理地址
  非WSL环境需要通过参数或配置文件指定代理主机
  端口用 'proxy detect-port' 探测并保存到配置；proxy on 只读配置端口
  默认静默模式运行，使用 -v 选项可显示详细日志

示例:
  proxy on                              # WSL下自动检测，或使用配置文件
  proxy on -v                           # 显示详细输出
  proxy on 192.168.1.1                  # 指定IP
  proxy on 192.168.1.1 10808            # 指定IP和端口
  proxy detect-port                     # 探测端口并保存到配置
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
            local _pos=0
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
                        # 位置参数：第一个是IP，第二个是端口（按位置计数，不受配置默认值影响）
                        _pos=$((_pos + 1))
                        if   [ "$_pos" -eq 1 ]; then proxy_ip="$1"
                        elif [ "$_pos" -eq 2 ]; then proxy_port="$1"
                        fi
                        shift
                        ;;
                esac
            done

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

            # 确定端口：来自参数或配置；都没有则提示先探测或配置
            proxy_port="${proxy_port:-$DEFAULT_PORT}"
            if [ -z "$proxy_port" ]; then
                _proxy_log_error "错误: 未配置端口。请运行 'proxy detect-port' 探测，或在配置中设置 proxy_port"
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

        detect-port)
            shift
            local detect_host="$DEFAULT_HOST"
            local save_target="$USER_CONFIG"
            while [ $# -gt 0 ]; do
                case "$1" in
                    -v|--verbose) _verbose=1; shift ;;
                    --system) save_target="$SYSTEM_CONFIG"; shift ;;
                    *) [ -z "$detect_host" ] && detect_host="$1"; shift ;;
                esac
            done
            # 未指定主机时：WSL 取网关，否则探测本机
            if [ -z "$detect_host" ]; then
                if _proxy_is_wsl; then
                    detect_host=$(_proxy_get_gateway_ip)
                else
                    detect_host="localhost"
                fi
            fi
            if [ -z "$detect_host" ]; then
                _proxy_log_error "错误: 无法确定要探测的主机"
                return 1
            fi
            echo -e "${YELLOW}正在探测代理端口 ($detect_host)...${NC}"
            local _p
            _p=$(_proxy_detect_port "$detect_host" "$DEFAULT_SCHEMA" "https://www.google.com")
            if [ -z "$_p" ]; then
                _proxy_log_error "未探测到可用代理端口，请确认代理正在运行"
                return 1
            fi
            if _proxy_save_kv "$save_target" proxy_host "$detect_host" \
               && _proxy_save_kv "$save_target" proxy_port "$_p"; then
                echo -e "${GREEN}已探测并保存 ${detect_host}:${_p} 到 $save_target${NC}"
            else
                _proxy_log_error "探测到 ${detect_host}:${_p}，但无法写入 $save_target（写系统配置需 root）"
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
