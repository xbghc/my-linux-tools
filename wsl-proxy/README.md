# WSL PROXY Auto Setup Tool

## 简介

自动配置WSL环境代理的Shell函数，支持自动检测Windows主机IP。

## 使用方式

1. 将 `main.sh` 的内容复制到 `~/.bashrc` 文件末尾
2. 重新加载配置：`source ~/.bashrc`
3. 使用命令：
   ```bash
   proxy on                      # 自动检测IP，端口默认7890
   proxy on 192.168.1.1          # 指定IP，端口默认7890
   proxy on 192.168.1.1 10808    # 指定IP和端口
   proxy off                     # 关闭代理
   proxy status                  # 查看代理状态
   ```

## 功能特点

- 自动检测Windows主机IP（通过默认网关）
- 连接测试验证（自动回滚失败配置）
- 支持HTTP/HTTPS/FTP代理
- 彩色输出提示