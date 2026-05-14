# 机械臂运行环境一键配置

支持 Ubuntu 20.04 / 22.04 / 24.04 系统，一键安装 ROS + Python + NumPy 环境，自动适配系统版本和网络环境。

## 一键安装

```bash
bash <(curl -sSL https://raw.githubusercontent.com/<用户名>/<仓库>/main/install.sh)
```

国内环境推荐从 Gitee 下载：

```bash
bash <(curl -sSL https://gitee.com/<用户名>/<仓库>/raw/main/install.sh)
```

执行后脚本会自动检测 Ubuntu 版本并开始安装，中间需选择：
- **1** — 国内环境（清华/阿里云镜像，速度快）
- **2** — 国际环境（官方源）

其余全程自动完成。

## 安装内容

| 软件 | 说明 |
|------|------|
| ROS | 根据 Ubuntu 版本自动匹配对应发行版 |
| Python3 | 安装系统匹配版本 |
| NumPy | 通过 pip 安装 |
| rosdep | 自动初始化（国内环境替换镜像源） |

## 版本对应关系

| Ubuntu 版本 | ROS 发行版 | Python |
|-------------|-----------|--------|
| 20.04 | ROS Noetic (ROS 1) | 3.8 |
| 22.04 | ROS 2 Humble | 3.10 |
| 24.04 | ROS 2 Jazzy | 3.12 |

## 安装后

```bash
source ~/.bashrc
```

环境变量立即生效，即可使用 `roscore`、`ros2` 等命令。