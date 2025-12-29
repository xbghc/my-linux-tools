# WSL PROXY Auto Setup Tool

## 简介

自动配置WSL环境代理的Shell函数，支持自动检测Windows主机IP。

## 安装

在 `~/.bashrc` 末尾添加：

```bash
source /path/to/wsl-proxy/main.sh
```

然后重新加载：`source ~/.bashrc`

## 使用方式

```bash
proxy on                      # 自动检测IP，端口默认7890
proxy on 192.168.1.1          # 指定IP
proxy on 192.168.1.1 10808    # 指定IP和端口
proxy off                     # 关闭代理
proxy status                  # 查看代理状态

# 自定义测试URL
proxy on --test-direct https://baidu.com   # 代理前测试URL
proxy on --test-proxy https://x.com        # 代理后测试URL
```

## 功能特点

- 自动检测Windows主机IP（通过默认网关）
- 连接测试验证（自动回滚失败配置）
- 支持HTTP/HTTPS/FTP代理
- 彩色输出提示