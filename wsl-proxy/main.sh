# ==============================================================================
#  功能强大的代理管理函数 (Pure Shell)
#  用法:
#    proxy on [ip_address] [port]  - 开启代理。若不提供IP，则自动检测。
#    proxy off                      - 关闭代理。
#    proxy status                   - 查看当前状态。
# ==============================================================================
function proxy() {
    # 定义颜色以便输出
    local C_RED='\033[0;31m'
    local C_GREEN='\033[0;32m'
    local C_YELLOW='\033[0;33m'
    local C_BLUE='\033[0;34m'
    local C_NC='\033[0m' # No Color

    # 主逻辑：根据第一个参数选择操作
    case "$1" in
        on)
            # --- 1. 预检查：测试直接网络连接 ---
            echo -e "${C_YELLOW}正在测试直接网络连接 (bing.com)...${C_NC}"
            # -s: 静默模式; -f: HTTP错误时失败退出; -o: 输出丢弃; --connect-timeout: 连接超时
            if ! curl -s -f --connect-timeout 5 -o /dev/null https://www.bing.com; then
                echo -e "${C_RED}错误: 无法访问 bing.com。请先检查您的网络连接。${C_NC}"
                return 1
            fi
            echo -e "${C_GREEN}网络连接正常。${C_NC}"

            local proxy_ip=""
            local proxy_port="7890"  # 默认端口
            
            # --- 2. 获取代理IP：检查是否传入参数，否则自动获取 ---
            if [ -n "$2" ]; then
                proxy_ip="$2"
                echo -e "${C_BLUE}使用您提供的IP地址: ${proxy_ip}${C_NC}"
            else
                echo -e "${C_BLUE}未提供IP，正在自动检测网关IP...${C_NC}"
                # 通过 `ip route` 获取默认网关IP
                proxy_ip=$(ip route | grep default | awk '{print $3}')
                if [ -z "$proxy_ip" ]; then
                    echo -e "${C_RED}错误: 自动检测IP失败。请检查 'ip route' 命令的输出。${C_NC}"
                    return 1
                fi
                echo -e "${C_BLUE}检测到IP地址: ${proxy_ip}${C_NC}"
            fi
            
            # --- 3. 获取代理端口：检查是否传入第三个参数 ---
            if [ -n "$3" ]; then
                proxy_port="$3"
                echo -e "${C_BLUE}使用自定义端口: ${proxy_port}${C_NC}"
            else
                echo -e "${C_BLUE}使用默认端口: ${proxy_port}${C_NC}"
            fi
            local proxy_url="http://${proxy_ip}:${proxy_port}"

            # --- 4. 设置环境变量 ---
            echo "设置代理环境变量为: ${proxy_url}"
            export http_proxy="${proxy_url}"
            export https_proxy="${proxy_url}"
            export ftp_proxy="${proxy_url}"
            export no_proxy="localhost,127.0.0.1,::1"
            # 兼容全大写的变量
            export HTTP_PROXY="${http_proxy}"
            export HTTPS_PROXY="${https_proxy}"
            export FTP_PROXY="${ftp_proxy}"
            export NO_PROXY="${no_proxy}"

            # --- 5. 后检查：测试通过代理的连接 ---
            echo -e "${C_YELLOW}正在通过代理测试连接 (google.com)...${C_NC}"
            if curl -s -f --connect-timeout 5 --head -o /dev/null https://www.google.com; then
                echo -e "${C_GREEN}✅ 代理设置成功并通过连接测试！${C_NC}"
            else
                echo -e "${C_RED}❌ 错误: 代理已设置，但无法通过代理访问 google.com。${C_NC}"
                echo -e "${C_RED}   请检查您的代理服务是否在 ${proxy_ip}:${proxy_port} 上正常运行。${C_NC}"
                echo -e "${C_YELLOW}正在撤销代理设置...${C_NC}"
                proxy off > /dev/null # 调用自己来关闭代理，并抑制其输出
            fi
            ;;

        off)
            echo "正在清除代理环境变量..."
            unset http_proxy
            unset https_proxy
            unset ftp_proxy
            unset no_proxy
            unset HTTP_PROXY
            unset HTTPS_PROXY
            unset FTP_PROXY
            unset NO_PROXY
            echo -e "${C_GREEN}☑️ 代理已关闭。${C_NC}"
            ;;

        status)
            echo -e "${C_BLUE}--- 当前代理状态 ---${C_NC}"
            if [ -n "$http_proxy" ]; then
                echo -e "状态: ${C_GREEN}🟢 开启${C_NC}"
                echo "http_proxy : $http_proxy"
                echo "https_proxy: $https_proxy"
                echo "no_proxy   : $no_proxy"
            else
                echo -e "状态: ${C_RED}🔴 关闭${C_NC}"
            fi
            echo -e "${C_BLUE}--------------------${C_NC}"
            ;;

        *)
            echo "用法: proxy [on|off|status] [ip_address] [port]"
            echo "  on [ip] [port]   - 开启代理。IP和端口都可选，默认自动检测IP，端口默认7890。"
            echo "  off              - 关闭代理。"
            echo "  status           - 查看当前状态。"
            echo ""
            echo "示例:"
            echo "  proxy on                    # 自动检测IP，使用默认端口7890"
            echo "  proxy on 192.168.1.1        # 指定IP，使用默认端口7890"
            echo "  proxy on 192.168.1.1 10808  # 指定IP和端口"
            ;;
    esac
}