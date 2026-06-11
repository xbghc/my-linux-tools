# proxy — Linux 代理开关工具

为整个系统（或单个用户）提供一个简单的 `proxy on/off/status` 命令，统一管理 shell 的
HTTP/HTTPS/FTP 代理环境变量。支持 WSL 自动探测 Windows 主机 IP，也支持普通 Linux 通过配置文件指定代理。

## 安装

两个独立的脚本，按需选用；每个都自带 `--uninstall`。脚本**本地优先、远程回退**：`git clone` 后执行用本地 `main.sh`（零外网），`curl | bash` 则自动从 GitHub 拉取 `main.sh`。

### 一键安装（curl）

```bash
# 系统级（所有用户，需 root）
curl -fsSL https://raw.githubusercontent.com/xbghc/my-linux-tools/main/wsl-proxy/install-system.sh | sudo bash

# 用户级（仅当前用户）
curl -fsSL https://raw.githubusercontent.com/xbghc/my-linux-tools/main/wsl-proxy/install-user.sh | bash
```

> ⚠️ 本工具用于配置代理，而一键安装却需要能访问 `raw.githubusercontent.com`——受限网络下可能正好访问不了。两种应对：
> - 走镜像：`curl -fsSL <镜像>/install-system.sh | sudo PROXY_RAW_BASE=<镜像>/wsl-proxy bash`
> - 或先 `git clone` 再本地执行下面的脚本（零外网依赖）。

### 系统安装（推荐，一个系统一份配置）

所有用户共享同一份配置，将来新建的用户也自动可用，需要 root：

```bash
sudo ./install-system.sh             # 安装
sudo ./install-system.sh --uninstall # 卸载
```

| 路径 | 作用 |
| --- | --- |
| `/usr/local/lib/proxy/proxy.sh` | `proxy` 函数本体（副本） |
| `/etc/profile.d/proxy.sh` | 登录 shell 加载，并按 `auto_on` 自动开启一次 |
| `/etc/bash.bashrc`（追加可逆块） | 交互式非登录 shell（新终端 tab 等）加载函数 |
| `/etc/proxy/config` | 系统级代理配置 |

安装后编辑 `/etc/proxy/config` 填入 `proxy_host`（端口可用 `proxy detect-port --system` 探测写入），重新登录即可在任意用户下使用 `proxy`。

### 用户安装（仅当前用户，无需 root）

复制副本到 `~/.local/lib`，加载块用 `$HOME` 变量，与仓库位置解耦、可迁移：

```bash
./install-user.sh             # 安装
./install-user.sh --uninstall # 卸载
```

| 路径 | 作用 |
| --- | --- |
| `~/.local/lib/proxy/proxy.sh` | `proxy` 函数本体（副本） |
| `~/.bashrc`（追加可逆块） | 加载函数，并按 `auto_on` 自动开启一次 |
| `~/.config/proxy/config` | 用户级代理配置 |

> 两个脚本互不依赖；改了 `main.sh` 后重新执行对应脚本即可同步副本。

## 配置

配置按优先级从低到高读取，后者覆盖前者：

1. `/etc/proxy/config` —— 系统级，一个系统一份
2. `~/.config/proxy/config` —— 用户级，覆盖系统级

字段：

```ini
proxy_schema=http     # 代理协议 http / socks5
proxy_host=127.0.0.1  # 代理主机地址
proxy_port=7890       # 代理端口；用 proxy detect-port 探测写入，也可手动设置
auto_on=0             # 登录时自动开启：1/true/yes 开启（由安装生成的加载块读取）
```

WSL 环境下 `proxy_host` 可留空，会自动探测 Windows 主机 IP。

端口探测由 `proxy detect-port` 负责：遍历候选端口（默认 `7890`、`7897`、`1080`、`20172`，可在 `main.sh` 的 `COMMON_PORTS` 增减），先测连通、再实际经该端口访问测试 URL 确认是可用代理，命中后**保存到配置**（默认用户级 `~/.config/proxy/config`，加 `--system` 写 `/etc/proxy/config`，需 root）。`proxy on` 只读配置、不在运行时探测。

> 探测需要代理**正在运行**，所以安装后由你主动运行一次 `proxy detect-port`（而非安装时自动跑）。换了代理软件/端口后重跑即可。WSL 下代理在主机、IP 运行时才定，端口仍建议手动配置。

## 用法

```bash
proxy on                      # 开启（按配置 / WSL 自动探测）
proxy on 192.168.1.1          # 指定 IP
proxy on 192.168.1.1 10808    # 指定 IP 和端口
proxy on -v                   # 显示详细日志
proxy off                     # 关闭
proxy status                  # 查看状态
proxy detect-port             # 探测可用端口并保存到配置

# 自定义连通性测试 URL
proxy on --test-direct https://bing.com    # 开启前测试直连
proxy on --test-proxy https://x.com        # 开启后测试代理
```

## 工作机制

- 代理状态通过环境变量（`http_proxy` 等）传递；登录 shell 开启后，其子 shell 自动继承，无需重复开启。
- `auto_on=1` 时仅登录 shell 在启动时自动 `proxy on` 一次，避免每开一个终端都重复跑连通性测试。
- 开启时先测直连、再测代理，失败自动回滚，不会留下半开状态。

## 功能特点

- 一条命令统一开关系统代理
- 系统级 + 用户级两层配置
- WSL 自动探测主机 IP
- 一条命令探测并保存常用代理端口（`proxy detect-port`，Clash/V2Ray 等）
- 连接测试与失败回滚
- 默认静默，`-v` 显示详细日志
