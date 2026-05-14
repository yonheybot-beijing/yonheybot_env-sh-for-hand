# 机械臂运行环境一键配置

支持 Ubuntu 20.04 / 22.04 / 24.04 系统，一键安装完整的机械臂开发环境，自动适配系统版本和网络环境。

## 一键安装

```bash
bash <(curl -sSL https://raw.githubusercontent.com/<用户名>/<仓库>/main/install.sh)
```

国内环境推荐从 Gitee 下载：

```bash
bash <(curl -sSL https://gitee.com/<用户名>/<仓库>/raw/main/install.sh)
```

执行后选择网络环境（国内 1 / 国际 2），其余全程自动完成。

## 安装内容

| 类别 | 具体内容 |
|------|----------|
| ROS | desktop + ros2-control + MoveIt + TF2 + RViz + rosbag 等扩展包 |
| 视觉库 | OpenCV + PCL + cv_bridge + image_transport |
| 数学库 | Eigen + Boost + Armadillo + LAPACK + SciPy |
| Python | NumPy + SciPy + Matplotlib + OpenCV + Transform3D |
| 构建工具 | cmake + colcon + rosdep + git |
| 硬件驱动 | libusb + udev + OpenNI + DC1394 |

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

即可使用 `ros2`、`rviz2`、`colcon` 等命令。

## 查询目标环境依赖

在已配好环境的机器上运行：

```bash
dpkg -l | awk '/^ii/{print $2}' > env_info.txt
pip3 freeze >> env_info.txt 2>/dev/null
lsb_release -a >> env_info.txt 2>/dev/null
```

将 `env_info.txt` 提供给脚本维护者即可同步依赖。
