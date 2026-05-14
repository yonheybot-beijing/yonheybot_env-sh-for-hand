#!/bin/bash
# ============================================================
# 机械臂运行环境一键安装脚本
# 支持 Ubuntu 20.04 / 22.04 / 24.04
# 用法: bash install.sh
# ============================================================

set -e

# ---------- 颜色 ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC}  $1"; }

if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi

# ==================== 1. 检测 Ubuntu 版本 ====================
detect_os() {
    log_step "检测系统版本..."

    . /etc/os-release

    if [ "$ID" != "ubuntu" ]; then
        log_error "仅支持 Ubuntu 系统"
        exit 1
    fi

    UBUNTU_VERSION="$VERSION_ID"
    UBUNTU_CODENAME="$VERSION_CODENAME"

    case "$UBUNTU_VERSION" in
        "20.04")
            ROS_DISTRO="noetic"
            ROS_VERSION="1"
            ;;
        "22.04")
            ROS_DISTRO="humble"
            ROS_VERSION="2"
            ;;
        "24.04")
            ROS_DISTRO="jazzy"
            ROS_VERSION="2"
            ;;
        *)
            log_error "不支持 Ubuntu ${UBUNTU_VERSION}，仅支持 20.04/22.04/24.04"
            exit 1
            ;;
    esac

    PYTHON_VER=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
    PYTHON="python3"

    log_info "Ubuntu ${UBUNTU_VERSION} ${UBUNTU_CODENAME} → ROS ${ROS_DISTRO} (ROS ${ROS_VERSION}), Python ${PYTHON_VER}"
}

# ==================== 2. 选择镜像源 ====================
select_mirror() {
    echo ""
    echo -e "${CYAN}============================================${NC}"
    echo -e "${CYAN}  请选择网络环境${NC}"
    echo -e "${CYAN}============================================${NC}"
    echo ""
    echo "  1) 国内环境 (中科大/清华/阿里云 多源回退)"
    echo "  2) 国际环境 (官方源)"
    echo ""

    while true; do
        read -rp "  请输入选项 [1/2]: " mirror_choice
        case "$mirror_choice" in
            1)
                USE_MIRROR=true
                # ROS 源列表（按优先级，第一个通的会被使用）
                ROS_MIRRORS=(
                    "https://mirrors.ustc.edu.cn"
                    "https://mirrors.tuna.tsinghua.edu.cn"
                )
                # Ubuntu apt 源
                UBUNTU_MIRROR="http://mirrors.aliyun.com"
                # pip 源列表（按优先级回退）
                PIP_MIRRORS=(
                    "https://mirrors.ustc.edu.cn/pypi/simple/"
                    "https://pypi.tuna.tsinghua.edu.cn/simple/"
                    "https://mirrors.aliyun.com/pypi/simple/"
                    "https://pypi.douban.com/simple/"
                )
                log_info "使用国内镜像源（多源回退）"
                break
                ;;
            2)
                USE_MIRROR=false
                ROS_MIRRORS=("http://packages.ros.org")
                UBUNTU_MIRROR="http://archive.ubuntu.com"
                PIP_MIRRORS=("https://pypi.org/simple/")
                log_info "使用国际官方源"
                break
                ;;
            *)
                log_warn "输入无效，请输入 1 或 2"
                ;;
        esac
    done
}

# ==================== 3. 配置 apt 源 ====================
setup_apt_mirror() {
    if [ "$USE_MIRROR" = true ]; then
        log_step "切换 apt 源为阿里云镜像..."
        $SUDO sed -i "s@http://.*archive.ubuntu.com@${UBUNTU_MIRROR}@g" /etc/apt/sources.list 2>/dev/null || true
        $SUDO sed -i "s@http://.*security.ubuntu.com@${UBUNTU_MIRROR}@g" /etc/apt/sources.list 2>/dev/null || true
    fi
    log_step "更新 apt 缓存..."
    $SUDO apt update -y
}

# ==================== 4. 安装 ROS ====================
install_ros() {
    log_step "安装 ROS ${ROS_DISTRO}..."

    $SUDO apt install -y curl gnupg2 lsb-release

    # 添加 ROS GPG 密钥和源（多源尝试 + [trusted=yes] 兜底）
    # 先清理所有旧 ROS 源，避免残留配置干扰
    $SUDO rm -f /etc/apt/sources.list.d/ros*.list /etc/apt/sources.list.d/ros*.sources
    if [ -f /etc/apt/trusted.gpg ]; then
        $SUDO mv /etc/apt/trusted.gpg /etc/apt/trusted.gpg.bak 2>/dev/null || true
    fi
    $SUDO rm -f /usr/share/keyrings/ros-archive-keyring.gpg

    ARCH=$(dpkg --print-architecture)
    GPG_OK=false

    # 尝试下载 GPG 密钥（多个 key 源回退）
    log_info "下载 ROS GPG 密钥..."
    for key_url in \
        "https://mirrors.ustc.edu.cn/ros/ros.key" \
        "https://mirrors.tuna.tsinghua.edu.cn/ros/ros.key" \
        "https://raw.githubusercontent.com/ros/rosdistro/master/ros.key"; do
        log_info "尝试: ${key_url}"
        if curl -sSL --connect-timeout 3 --max-time 8 "$key_url" 2>/dev/null \
            | $SUDO gpg --dearmor --batch --yes -o /usr/share/keyrings/ros-archive-keyring.gpg 2>/dev/null; then
            GPG_OK=true
            log_info "GPG 密钥下载成功: ${key_url}"
            break
        fi
    done

    # 尝试每个 ROS 镜像源，找到能用的
    ROS_SOURCE_OK=false
    for mirror in "${ROS_MIRRORS[@]}"; do
        ROS_URL="${mirror}/ros${ROS_VERSION}/ubuntu"
        log_info "尝试 ROS 源: ${ROS_URL}"

        if [ "$GPG_OK" = true ]; then
            echo "deb [arch=${ARCH} signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] ${ROS_URL} ${UBUNTU_CODENAME} main" \
                | $SUDO tee /etc/apt/sources.list.d/ros-latest.list > /dev/null
        else
            echo "deb [arch=${ARCH} trusted=yes] ${ROS_URL} ${UBUNTU_CODENAME} main" \
                | $SUDO tee /etc/apt/sources.list.d/ros-latest.list > /dev/null
        fi

        if $SUDO apt update -y 2>/dev/null; then
            ROS_SOURCE_OK=true
            log_info "ROS 源可用: ${ROS_URL}"
            break
        fi
        log_warn "ROS 源不可达: ${ROS_URL}，尝试下一个..."
    done

    if [ "$ROS_SOURCE_OK" = false ]; then
        log_warn "所有 ROS 镜像源均不可达，使用 [trusted=yes] + 最后一个源兜底"
        # 用最后一个镜像 + trusted=yes 再试
        ROS_URL="${ROS_MIRRORS[-1]}/ros${ROS_VERSION}/ubuntu"
        echo "deb [arch=${ARCH} trusted=yes] ${ROS_URL} ${UBUNTU_CODENAME} main" \
            | $SUDO tee /etc/apt/sources.list.d/ros-latest.list > /dev/null
        $SUDO apt update -y || log_warn "apt update 失败，继续尝试安装..."
    fi

    # ROS 基础包
    if [ "$ROS_VERSION" = "1" ]; then
        ROS_BASE="ros-${ROS_DISTRO}-desktop-full"
        log_info "安装 ${ROS_BASE}..."
        $SUDO apt install -y "$ROS_BASE"
    else
        ROS_BASE="ros-${ROS_DISTRO}-desktop"
        log_info "安装 ${ROS_BASE}..."
        $SUDO apt install -y "$ROS_BASE"

        # ROS 2 额外包（从目标环境提取）
        log_info "安装 ROS 2 扩展包..."
        ROS_EXTRA=(
            "ros-${ROS_DISTRO}-ros2-control"
            "ros-${ROS_DISTRO}-ros2controlcli"
            "ros-${ROS_DISTRO}-control-toolbox"
            "ros-${ROS_DISTRO}-control-msgs"
            "ros-${ROS_DISTRO}-controller-interface"
            "ros-${ROS_DISTRO}-controller-manager"
            "ros-${ROS_DISTRO}-controller-manager-msgs"
            "ros-${ROS_DISTRO}-hardware-interface"
            "ros-${ROS_DISTRO}-forward-command-controller"
            "ros-${ROS_DISTRO}-joint-state-broadcaster"
            "ros-${ROS_DISTRO}-joint-state-publisher"
            "ros-${ROS_DISTRO}-joint-state-publisher-gui"
            "ros-${ROS_DISTRO}-joint-trajectory-controller"
            "ros-${ROS_DISTRO}-joint-limits"
            "ros-${ROS_DISTRO}-position-controllers"
            "ros-${ROS_DISTRO}-gripper-controllers"
            "ros-${ROS_DISTRO}-realtime-tools"
            "ros-${ROS_DISTRO}-generate-parameter-library"
            "ros-${ROS_DISTRO}-generate-parameter-library-py"
            "ros-${ROS_DISTRO}-moveit-msgs"
            "ros-${ROS_DISTRO}-cv-bridge"
            "ros-${ROS_DISTRO}-image-transport"
            "ros-${ROS_DISTRO}-image-geometry"
            "ros-${ROS_DISTRO}-image-tools"
            "ros-${ROS_DISTRO}-vision-opencv"
            "ros-${ROS_DISTRO}-pcl-conversions"
            "ros-${ROS_DISTRO}-pcl-msgs"
            "ros-${ROS_DISTRO}-laser-geometry"
            "ros-${ROS_DISTRO}-depthimage-to-laserscan"
            "ros-${ROS_DISTRO}-robot-state-publisher"
            "ros-${ROS_DISTRO}-tf2"
            "ros-${ROS_DISTRO}-tf2-ros"
            "ros-${ROS_DISTRO}-tf2-py"
            "ros-${ROS_DISTRO}-tf2-ros-py"
            "ros-${ROS_DISTRO}-tf2-tools"
            "ros-${ROS_DISTRO}-tf2-geometry-msgs"
            "ros-${ROS_DISTRO}-tf2-sensor-msgs"
            "ros-${ROS_DISTRO}-tf2-eigen"
            "ros-${ROS_DISTRO}-tf2-kdl"
            "ros-${ROS_DISTRO}-tf2-bullet"
            "ros-${ROS_DISTRO}-tf2-msgs"
            "ros-${ROS_DISTRO}-xacro"
            "ros-${ROS_DISTRO}-urdf"
            "ros-${ROS_DISTRO}-urdf-tutorial"
            "ros-${ROS_DISTRO}-urdfdom-headers"
            "ros-${ROS_DISTRO}-urdfdom-py"
            "ros-${ROS_DISTRO}-srdfdom"
            "ros-${ROS_DISTRO}-kdl-parser"
            "ros-${ROS_DISTRO}-rviz2"
            "ros-${ROS_DISTRO}-rqt"
            "ros-${ROS_DISTRO}-rqt-gui"
            "ros-${ROS_DISTRO}-rqt-gui-cpp"
            "ros-${ROS_DISTRO}-rqt-gui-py"
            "ros-${ROS_DISTRO}-rqt-common-plugins"
            "ros-${ROS_DISTRO}-rqt-controller-manager"
            "ros-${ROS_DISTRO}-rqt-joint-trajectory-controller"
            "ros-${ROS_DISTRO}-rqt-robot-dashboard"
            "ros-${ROS_DISTRO}-rqt-robot-monitor"
            "ros-${ROS_DISTRO}-rqt-robot-steering"
            "ros-${ROS_DISTRO}-rqt-image-view"
            "ros-${ROS_DISTRO}-rqt-graph"
            "ros-${ROS_DISTRO}-rqt-plot"
            "ros-${ROS_DISTRO}-rqt-publisher"
            "ros-${ROS_DISTRO}-rqt-service-caller"
            "ros-${ROS_DISTRO}-rqt-shell"
            "ros-${ROS_DISTRO}-rqt-srv"
            "ros-${ROS_DISTRO}-rqt-topic"
            "ros-${ROS_DISTRO}-rqt-msg"
            "ros-${ROS_DISTRO}-rqt-action"
            "ros-${ROS_DISTRO}-rqt-reconfigure"
            "ros-${ROS_DISTRO}-rqt-bag"
            "ros-${ROS_DISTRO}-rqt-bag-plugins"
            "ros-${ROS_DISTRO}-common-interfaces"
            "ros-${ROS_DISTRO}-geometry2"
            "ros-${ROS_DISTRO}-sensor-msgs"
            "ros-${ROS_DISTRO}-vision-msgs"
            "ros-${ROS_DISTRO}-nav-msgs"
            "ros-${ROS_DISTRO}-diagnostic-msgs"
            "ros-${ROS_DISTRO}-shape-msgs"
            "ros-${ROS_DISTRO}-trajectory-msgs"
            "ros-${ROS_DISTRO}-stereo-msgs"
            "ros-${ROS_DISTRO}-map-msgs"
            "ros-${ROS_DISTRO}-graph-msgs"
            "ros-${ROS_DISTRO}-lifecycle-msgs"
            "ros-${ROS_DISTRO}-statistics-msgs"
            "ros-${ROS_DISTRO}-actionlib-msgs"
            "ros-${ROS_DISTRO}-example-interfaces"
            "ros-${ROS_DISTRO}-unique-identifier-msgs"
            "ros-${ROS_DISTRO}-object-recognition-msgs"
            "ros-${ROS_DISTRO}-octomap-msgs"
            "ros-${ROS_DISTRO}-geometry-msgs"
            "ros-${ROS_DISTRO}-std-msgs"
            "ros-${ROS_DISTRO}-std-srvs"
            "ros-${ROS_DISTRO}-builtin-interfaces"
            "ros-${ROS_DISTRO}-action-msgs"
            "ros-${ROS_DISTRO}-composition-interfaces"
            "ros-${ROS_DISTRO}-pendulum-msgs"
            "ros-${ROS_DISTRO}-rosbridge-suite"
            "ros-${ROS_DISTRO}-rosbridge-server"
            "ros-${ROS_DISTRO}-rosbridge-msgs"
            "ros-${ROS_DISTRO}-rosapi"
            "ros-${ROS_DISTRO}-rosapi-msgs"
            "ros-${ROS_DISTRO}-rosbag2"
            "ros-${ROS_DISTRO}-rosbag2-cpp"
            "ros-${ROS_DISTRO}-rosbag2-py"
            "ros-${ROS_DISTRO}-rosbag2-compression"
            "ros-${ROS_DISTRO}-rosbag2-compression-zstd"
            "ros-${ROS_DISTRO}-rosbag2-storage"
            "ros-${ROS_DISTRO}-rosbag2-storage-default-plugins"
            "ros-${ROS_DISTRO}-rosbag2-transport"
            "ros-${ROS_DISTRO}-rosbag2-interfaces"
            "ros-${ROS_DISTRO}-interactive-markers"
            "ros-${ROS_DISTRO}-webots-ros2"
            "ros-${ROS_DISTRO}-joy"
            "ros-${ROS_DISTRO}-udp-driver"
            "ros-${ROS_DISTRO}-udp-msgs"
            "ros-${ROS_DISTRO}-keyboard-handler"
            "ros-${ROS_DISTRO}-filters"
            "ros-${ROS_DISTRO}-angles"
            "ros-${ROS_DISTRO}-geometric-shapes"
            "ros-${ROS_DISTRO}-random-numbers"
            "ros-${ROS_DISTRO}-eigen-stl-containers"
            "ros-${ROS_DISTRO}-message-filters"
            "ros-${ROS_DISTRO}-pluginlib"
            "ros-${ROS_DISTRO}-class-loader"
            "ros-${ROS_DISTRO}-resource-retriever"
            "ros-${ROS_DISTRO}-warehouse-ros"
            "ros-${ROS_DISTRO}-ompl"
            "ros-${ROS_DISTRO}-octomap"
            "ros-${ROS_DISTRO}-ros2bag"
            "ros-${ROS_DISTRO}-ros2cli"
            "ros-${ROS_DISTRO}-ros2cli-common-extensions"
            "ros-${ROS_DISTRO}-ros2launch"
            "ros-${ROS_DISTRO}-launch"
            "ros-${ROS_DISTRO}-launch-ros"
            "ros-${ROS_DISTRO}-launch-testing"
            "ros-${ROS_DISTRO}-launch-testing-ros"
            "ros-${ROS_DISTRO}-launch-xml"
            "ros-${ROS_DISTRO}-launch-yaml"
            "ros-${ROS_DISTRO}-sros2"
            "ros-${ROS_DISTRO}-sros2-cmake"
            "ros-${ROS_DISTRO}-tracetools"
            "ros-${ROS_DISTRO}-tracetools-launch"
            "ros-${ROS_DISTRO}-tracetools-trace"
            "ros-${ROS_DISTRO}-tracetools-read"
            "ros-${ROS_DISTRO}-tracetools-test"
            "ros-${ROS_DISTRO}-tlsf"
            "ros-${ROS_DISTRO}-tlsf-cpp"
            "ros-${ROS_DISTRO}-topic-tools"
            "ros-${ROS_DISTRO}-topic-tools-interfaces"
            "ros-${ROS_DISTRO}-dummy-robot-bringup"
            "ros-${ROS_DISTRO}-dummy-map-server"
            "ros-${ROS_DISTRO}-dummy-sensors"
            "ros-${ROS_DISTRO}-backward-ros"
            "ros-${ROS_DISTRO}-ament-clang-format"
            "ros-${ROS_DISTRO}-ament-cppcheck"
            "ros-${ROS_DISTRO}-ament-cpplint"
            "ros-${ROS_DISTRO}-ament-flake8"
            "ros-${ROS_DISTRO}-ament-pep257"
            "ros-${ROS_DISTRO}-ament-uncrustify"
            "ros-${ROS_DISTRO}-ament-xmllint"
            "ros-${ROS_DISTRO}-ament-copyright"
            "ros-${ROS_DISTRO}-ament-lint"
            "ros-${ROS_DISTRO}-ament-lint-auto"
            "ros-${ROS_DISTRO}-ament-lint-cmake"
            "ros-${ROS_DISTRO}-ament-lint-common"
            "ros-${ROS_DISTRO}-v4l2-camera"
            "ros-${ROS_DISTRO}-turtlesim"
        )
        # 先批量安装，失败再逐包排查
        if ! $SUDO apt install -y "${ROS_EXTRA[@]}" 2>/dev/null; then
            log_warn "批量安装部分失败，逐包重试..."
            FAIL_COUNT=0
            for pkg in "${ROS_EXTRA[@]}"; do
                if ! $SUDO apt install -y "$pkg" 2>/dev/null; then
                    log_warn "  不可用: ${pkg}"
                    ((FAIL_COUNT++))
                fi
            done
            log_warn "${FAIL_COUNT} 个 ROS 扩展包在当前源中不可用"
        fi
    fi

    log_info "ROS ${ROS_DISTRO} 安装完成"
}

# ==================== 5. 安装系统开发库 ====================
install_system_libs() {
    log_step "安装系统开发库..."

    DEV_LIBS=(
        build-essential cmake git curl wget
        g++ gcc gfortran
        pkg-config automake autoconf libtool m4 make
        clang-format cppcheck
        net-tools can-utils
        nodejs
        libeigen3-dev
        libblas-dev liblapack-dev
        libarmadillo-dev
        libarpack2-dev
        libsuperlu-dev
        libopencv-dev
        libpcl-dev
        libjpeg-dev libjpeg8-dev libjpeg-turbo8-dev
        libpng-dev libpng-tools
        libtiff-dev
        libwebp-dev
        libopenjp2-7-dev
        libjbig-dev
        libavcodec-dev libavformat-dev libavutil-dev
        libswresample-dev libswscale-dev
        libx264-dev libx265-dev
        libtheora-dev libogg-dev
        libde265-dev libheif-dev libaom-dev
        libdav1d-dev
        libv4l-0 libv4lconvert0
        libdc1394-25 libdc1394-dev libraw1394-dev
        libhdf5-dev libhdf5-mpi-dev libhdf5-openmpi-dev
        libnetcdf-dev libnetcdf-cxx-legacy-dev
        libfcl-dev libccd-dev
        liboctomap-dev
        libflann-dev
        libqhull-dev
        libassimp-dev
        libbullet-dev
        libyaml-cpp-dev libyaml-dev
        liburdfdom-dev liburdfdom-headers-dev
        libtinyxml-dev libtinyxml2-dev
        libconsole-bridge-dev
        liborocos-kdl-dev
        libzmq5
        libcurl4-openssl-dev libssl-dev
        libsdl2-dev libsdl2-2.0-0
        libgl-dev libgl1-mesa-dev libegl1-mesa-dev libgles2
        libglu1-mesa-dev
        libglew-dev
        libglfw3-dev
        libx11-dev libxext-dev libxrender-dev libxrandr-dev
        libxi-dev libxmu-dev libxpm-dev
        libxt-dev libxaw7-dev
        libxft-dev libxss-dev
        libxv-dev libxxf86vm-dev
        libxfixes-dev libxinerama-dev libxcursor-dev
        libwayland-dev libxkbcommon-dev
        libfontconfig1-dev libfreetype-dev
        libxcb1-dev libxcb-render0-dev
        libusb-1.0-0-dev
        libudev-dev
        libpcap0.8
        libpq-dev
        default-libmysqlclient-dev
        libsqlite3-dev
        libgdal-dev libgeos-dev libproj-dev
        libgeotiff-dev
        libcfitsio-dev
        libfyba-dev
        libkml-dev
        librttopo-dev libspatialite-dev
        liburiparser-dev libxml2-dev
        libminizip-dev liblz4-dev
        libzstd-dev libpcre2-dev libpcre3-dev
        libgtest-dev google-mock googletest
        libfmt-dev libspdlog-dev
        libtbb-dev
        libdouble-conversion-dev
        libjsoncpp-dev libjson-c-dev
        libutfcpp-dev
        libxsimd-dev
        libexpected-dev
        libopenni-dev libopenni2-dev
        openni-utils
    )

    # 版本相关的包按 Ubuntu 版本添加
    case "$UBUNTU_VERSION" in
        "20.04")
            DEV_LIBS+=(
                libopencv4.2-java
                libvpx6
                libconsole-bridge0.4
                libglew2.1
                libprotobuf17
                libsuitesparseconfig5
                libinih1
                libopenni-sensor-pointclouds0
            )
            ;;
        "22.04")
            DEV_LIBS+=(
                libopencv4.5-java
                libvpx7
                libconsole-bridge1.0
                libglew2.2
                libprotobuf23
                libsuitesparseconfig5
                libinih1
                libopenni-sensor-pointclouds0
            )
            ;;
        "24.04")
            DEV_LIBS+=(
                libopencv4.10-java
                libvpx8
                libconsole-bridge1.0
                libglew2.2
                libprotobuf-lite25
                libsuitesparseconfig7
                libinih1
                libopenni-sensor-pointclouds0
            )
            ;;
    esac

    $SUDO apt install -y "${DEV_LIBS[@]}" 2>/dev/null || log_warn "部分开发库安装失败，继续..."
    log_info "系统开发库安装完成"
}

# ==================== 6. 安装 Python 环境 ====================
install_python() {
    log_step "安装 Python 及 apt 包..."

    PYTHON_APT=(
        python3 python3-pip python3-dev python3-venv
        python3-tk python${PYTHON_VER}-dev
        python3-numpy
        python3-scipy
        python3-matplotlib
        python3-opencv
        python3-yaml
        python3-lxml
        python3-pil python3-pil.imagetk
        python3-requests
        python3-flask
        python3-tornado
        python3-jinja2
        python3-click
        python3-paramiko
        python3-psutil
        python3-six python3-dateutil
        python3-tz
        python3-packaging
        python3-setuptools
        python3-wheel
        python3-pyparsing python3-cycler python3-kiwisolver
        python3-attr python3-decorator
        python3-sympy python3-mpmath
        python3-pytest python3-pytest-cov
        python3-coverage python3-cov-core
        python3-flake8 python3-pyflakes python3-pycodestyle python3-mccabe
        python3-pydocstyle python3-snowballstemmer
        python3-gast python3-pythran python3-beniget python3-ply
        python3-colorama
        python3-future
        python3-empy
        python3-distro
        python3-rospkg-modules python3-catkin-pkg-modules
        python3-rosdistro-modules
        python3-rosdep python3-rosdep-modules
        python3-colcon-common-extensions
        python3-vcstool
        python3-bson
        python3-pyqt5 python3-pyqt5.qtsvg python3-pyqt5.sip
        python3-pyside2.qtcore python3-pyside2.qtgui python3-pyside2.qtsvg python3-pyside2.qtwidgets
        python3-gi python3-gi-cairo
        python3-dbus
        python3-cryptography python3-bcrypt python3-nacl
        python3-jwt python3-oauthlib
        python3-pymacaroons python3-macaroonbakery
        python3-cbor2
        python3-lz4
        python3-serial
        python3-can
        python3-rpi.gpio
        python3-smbus
        python3-pygments
        python3-pydot python3-pygraphviz
        python3-protobuf
        python3-ujson
        python3-netifaces
        python3-argcomplete
        python3-fasteners
        python3-fs
        python3-monotonic
        python3-lark
        python3-typeguard
        python3-notify2 python3-xdg
        python3-olefile python3-webencodings python3-html5lib python3-bs4
        python3-fonttools python3-ufolib2
        python3-unicodedata2
        python3-distlib
        python3-keyring python3-secretstorage python3-jeepney
        python3-babel python3-babel-localedata
        python3-renderpm python3-reportlab python3-reportlab-accel
        python3-brlapi
        python3-speechd
        python3-cups python3-cupshelpers
        python3-debian
        python3-distro-info python3-distupgrade
        python3-ldb
        python3-talloc
        python3-systemd
        python3-software-properties
        python3-commandnotfound
        python3-problem-report python3-apport
        python3-launchpadlib python3-lazr.restfulclient python3-lazr.uri
        python3-apt python3-aptdaemon python3-aptdaemon.gtk3widgets
        python3-debconf
        python3-ibus-1.0
        python3-louis
        python3-pyatspi
        python3-uno
        python3-wadllib
    )

    # distutils / lib2to3 在 Python 3.12+ 被移除
    if [ "$UBUNTU_VERSION" != "24.04" ]; then
        PYTHON_APT+=(python3-distutils python3-lib2to3)
    fi

    # vtk 版本随 Ubuntu 不同
    case "$UBUNTU_VERSION" in
        "20.04") PYTHON_APT+=(python3-vtk7) ;;
        "22.04") PYTHON_APT+=(python3-vtk9) ;;
        "24.04") PYTHON_APT+=(python3-vtk9) ;;
    esac

    $SUDO apt install -y "${PYTHON_APT[@]}" 2>/dev/null || log_warn "部分 Python 包安装失败，继续..."

    log_step "安装 pip 包..."

    # 探测可用的 pip 镜像源
    PIP_WORKING=""
    for idx in "${!PIP_MIRRORS[@]}"; do
        log_info "探测 pip 源: ${PIP_MIRRORS[$idx]}"
        if pip3 install --upgrade pip -i "${PIP_MIRRORS[$idx]}" --timeout 10 --retries 1 2>/dev/null; then
            PIP_WORKING="${PIP_MIRRORS[$idx]}"
            log_info "pip 源可用: ${PIP_WORKING}"
            break
        fi
    done

    if [ -z "$PIP_WORKING" ]; then
        log_warn "所有 pip 镜像源均不可达！pip 包将跳过"
    else
        PIP_PKGS=(
            numpy scipy matplotlib sympy
            Flask Werkzeug websockets websocket-client
            tqdm sounddevice vosk transforms3d
            pyserial python-can pyrealsense2 pymodbus
            PyQt5 PyQt5-sip Pillow
        )

        for pkg in "${PIP_PKGS[@]}"; do
            pip3 install "$pkg" -i "$PIP_WORKING" --timeout 30 --retries 2 2>/dev/null \
                || pip3 install "$pkg" -i "${PIP_MIRRORS[0]}" --timeout 30 --retries 2 2>/dev/null \
                || log_warn "pip install ${pkg} 失败，apt 版本可能已满足需求"
        done
    fi

    PY_VER=$(python3 --version 2>&1)
    log_info "Python 环境安装完成: ${PY_VER}"
}

# ==================== 7. rosdep 初始化 ====================
init_rosdep() {
    log_step "初始化 rosdep..."
    $SUDO apt install -y python3-rosdep 2>/dev/null || true

    if [ "$USE_MIRROR" = true ]; then
        log_info "配置 rosdep 使用国内源..."
        $SUDO mkdir -p /etc/ros/rosdep/sources.list.d

        # 多源尝试下载 rosdep sources list
        for rosdep_url in \
            "https://mirrors.ustc.edu.cn/rosdistro/rosdep/20-default.list" \
            "https://mirrors.tuna.tsinghua.edu.cn/rosdistro/rosdep/20-default.list" \
            "https://gitee.com/ohhuo/rosdistro/raw/master/rosdep/sources.list.d/20-default.list"; do
            if $SUDO curl -sSL --connect-timeout 3 --max-time 15 "$rosdep_url" \
                -o /etc/ros/rosdep/sources.list.d/20-default.list 2>/dev/null; then
                log_info "rosdep 配置下载成功: ${rosdep_url}"
                break
            fi
        done

        if [ -d /etc/ros/rosdep ]; then
            $SUDO find /etc/ros/rosdep -type f -name "*.list" -exec \
                sed -i 's@https://raw.githubusercontent.com@https://mirrors.ustc.edu.cn@g' {} \; 2>/dev/null || true
        fi
        rosdep update 2>/dev/null || log_warn "rosdep update 失败，可稍后手动执行"
    else
        $SUDO rosdep init 2>/dev/null || true
        rosdep update 2>/dev/null || true
    fi

    log_info "rosdep 初始化完成"
}

# ==================== 8. 配置环境变量 ====================
setup_env() {
    log_step "配置环境变量到 ~/.bashrc..."

    ROS_SETUP="/opt/ros/${ROS_DISTRO}/setup.bash"
    BASHRC="$HOME/.bashrc"
    MARKER_START="# >>> ROS ${ROS_DISTRO} auto-setup >>>"
    MARKER_END="# <<< ROS ${ROS_DISTRO} auto-setup <<<"

    sed -i "/^# >>> ROS .* auto-setup >>>/,/^# <<< ROS .* auto-setup <<</d" "$BASHRC" 2>/dev/null || true

    {
        echo "$MARKER_START"
        echo "source ${ROS_SETUP}"
        echo "export ROS_DOMAIN_ID=0"
        echo "$MARKER_END"
    } >> "$BASHRC"

    log_info "环境变量已写入 ~/.bashrc"
}

# ==================== 9. 验证安装 ====================
verify_installation() {
    echo ""
    echo -e "${CYAN}============================================${NC}"
    echo -e "${CYAN}           安装验证${NC}"
    echo -e "${CYAN}============================================${NC}"
    echo ""

    # ROS
    if [ -f "/opt/ros/${ROS_DISTRO}/setup.bash" ]; then
        echo -e "  ROS ${ROS_DISTRO}    ${GREEN}✓ 已安装${NC}"
    else
        echo -e "  ROS ${ROS_DISTRO}    ${RED}✗ 未找到${NC}"
    fi

    # Python
    echo -e "  Python      ${GREEN}✓ $(python3 --version 2>&1)${NC}"

    # NumPy
    python3 -c "import numpy; print(f'  NumPy       \033[0;32m✓ {numpy.__version__}\033[0m')" 2>/dev/null || \
        echo -e "  NumPy       ${RED}✗ 未安装${NC}"

    # OpenCV
    python3 -c "import cv2; print(f'  OpenCV      \033[0;32m✓ {cv2.__version__}\033[0m')" 2>/dev/null || \
        echo -e "  OpenCV      ${YELLOW}△ 未安装${NC}"

    # SciPy
    python3 -c "import scipy; print(f'  SciPy       \033[0;32m✓ {scipy.__version__}\033[0m')" 2>/dev/null || \
        echo -e "  SciPy       ${YELLOW}△ 未安装${NC}"

    echo ""
    echo -e "${CYAN}============================================${NC}"
}

# ==================== 主流程 ====================

clear
echo -e "${CYAN}"
echo "  ╔═══════════════════════════════════════════╗"
echo "  ║     机械臂运行环境 一键安装脚本           ║"
echo "  ║   ROS + PCL + OpenCV + Python + NumPy     ║"
echo "  ║   支持 Ubuntu 20.04 / 22.04 / 24.04       ║"
echo "  ╚═══════════════════════════════════════════╝"
echo -e "${NC}"

detect_os
select_mirror

echo ""
echo -e "${YELLOW}即将安装以下内容:${NC}"
echo "  • ROS ${ROS_DISTRO} (ROS ${ROS_VERSION}) + 扩展包"
echo "  • PCL / OpenCV / Boost / Eigen 等系统开发库"
echo "  • Python3 + NumPy + SciPy + Matplotlib + OpenCV"
echo "  • ros2-control / MoveIt / TF2 / RViz 等机械臂相关"
echo "  • 镜像源: $([ "$USE_MIRROR" = true ] && echo '国内' || echo '国际')"
echo ""

read -rp "  确认继续? [Y/n] " confirm
if [[ "$confirm" =~ ^[Nn] ]]; then
    echo "已取消。"
    exit 0
fi

echo ""
log_info "开始安装...（可能需要几分钟到几十分钟，取决于网速）"
echo ""

setup_apt_mirror
install_ros
install_system_libs
install_python
init_rosdep
setup_env
verify_installation

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}           全部安装完成!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "  请执行 ${YELLOW}source ~/.bashrc${NC} 使 ROS 环境生效。"
echo ""
echo -e "  如果后续需要安装你自己的工作空间依赖，执行:"
echo -e "  ${YELLOW}cd ~/ros2_ws && rosdep install --from-paths src -y${NC}"
echo ""
