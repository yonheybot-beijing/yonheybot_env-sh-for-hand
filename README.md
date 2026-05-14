# 机械臂运行环境一键配置

支持 Ubuntu 20.04 / 22.04 / 24.04，一条命令安装完整机械臂开发环境。

## 一键安装

```bash
wget -O install.sh https://raw.githubusercontent.com/yonheybot-beijing/yonheybot_env-sh-for-hand/main/install.sh && bash install.sh
```

如果 GitHub 拉不下来，先在本机把 install.sh 拷到目标机器（U盘/内网 scp 均可），然后：

```bash
bash install.sh
```

脚本会自动检测系统版本、Python 版本、CPU 架构，多源回退选择可用镜像，无需手动配置。

## 安装内容

| 类别 | 内容 |
|------|------|
| ROS | desktop + ros2-control + MoveIt + TF2 + RViz + rqt + rosbag2 等 |
| 视觉 | OpenCV + PCL + cv_bridge + image_transport + vision_opencv |
| 数学 | Eigen + Armadillo + LAPACK + SciPy + NumPy |
| Python | NumPy + SciPy + Matplotlib + OpenCV + Flask + transforms3d 等 |
| 构建 | cmake + colcon + rosdep + git |
| 驱动 | libusb + udev + OpenNI + DC1394 + V4L2 |

## 支持版本

| Ubuntu | ROS | Python |
|--------|-----|--------|
| 20.04 | Noetic (ROS 1) | 3.8 |
| 22.04 | Humble (ROS 2) | 3.10 |
| 24.04 | Jazzy (ROS 2) | 3.12 |

## 重新安装

如需卸载旧 ROS 后重装：

```bash
sudo apt purge -y 'ros-*' && sudo rm -f /etc/apt/sources.list.d/ros*.list && sudo apt autoremove -y && bash install.sh
```

## 安装后

```bash
source ~/.bashrc
```

即可使用 `ros2`、`rviz2`、`colcon` 等命令。
