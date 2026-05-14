#!/bin/bash
# ============================================================
# 一键安装 ROS + Python + NumPy 环境配置脚本
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

# ---------- sudo 处理 ----------
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    SUDO="sudo"
fi

# ==================== 1. 检测 Ubuntu 版本 ====================
detect_os() {
    log_step "检测系统版本..."

    if [ ! -f /etc/os-release ]; then
        log_error "无法检测系统版本，仅支持 Ubuntu 20.04/22.04/24.04"
        exit 1
    fi

    . /etc/os-release

    if [ "$ID" != "ubuntu" ]; then
        log_error "当前系统为 ${ID}，仅支持 Ubuntu"
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
            log_error "不支持的 Ubuntu 版本: ${UBUNTU_VERSION}"
            log_error "仅支持: 20.04 (Noetic), 22.04 (Humble), 24.04 (Jazzy)"
            exit 1
            ;;
    esac

    log_info "Ubuntu ${UBUNTU_VERSION} ${UBUNTU_CODENAME} → ROS ${ROS_DISTRO} (ROS ${ROS_VERSION})"
}

# ==================== 2. 选择镜像源 ====================
select_mirror() {
    echo ""
    echo -e "${CYAN}============================================${NC}"
    echo -e "${CYAN}  请选择网络环境${NC}"
    echo -e "${CYAN}============================================${NC}"
    echo ""
    echo "  1) 国内环境 (清华镜像 + 阿里云镜像)"
    echo "  2) 国际环境 (官方源)"
    echo ""

    while true; do
        read -rp "  请输入选项 [1/2]: " mirror_choice
        case "$mirror_choice" in
            1)
                USE_MIRROR=true
                MIRROR_URL="https://mirrors.tuna.tsinghua.edu.cn"
                UBUNTU_MIRROR="http://mirrors.aliyun.com"
                PIP_INDEX="https://pypi.tuna.tsinghua.edu.cn/simple/"
                log_info "使用国内镜像源"
                break
                ;;
            2)
                USE_MIRROR=false
                MIRROR_URL="http://packages.ros.org"
                UBUNTU_MIRROR="http://archive.ubuntu.com"
                PIP_INDEX="https://pypi.org/simple/"
                log_info "使用国际官方源"
                break
                ;;
            *)
                log_warn "输入无效，请输入 1 或 2"
                ;;
        esac
    done
}

# ==================== 3. 配置 Ubuntu apt 源 ====================
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

    # 添加 ROS GPG 密钥
    if [ "$USE_MIRROR" = true ]; then
        ROS_SOURCE="deb ${MIRROR_URL}/ros${ROS_VERSION}/ubuntu ${UBUNTU_CODENAME} main"
        curl -sSL https://mirrors.tuna.tsinghua.edu.cn/ros/ros.key | $SUDO gpg --dearmor -o /usr/share/keyrings/ros-archive-keyring.gpg 2>/dev/null
    else
        ROS_SOURCE="deb http://packages.ros.org/ros${ROS_VERSION}/ubuntu ${UBUNTU_CODENAME} main"
        curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key | $SUDO gpg --dearmor -o /usr/share/keyrings/ros-archive-keyring.gpg 2>/dev/null
    fi

    # 添加 ROS apt 源
    echo "$ROS_SOURCE" | $SUDO tee /etc/apt/sources.list.d/ros-latest.list > /dev/null
    $SUDO apt update -y

    # 选择要安装的 ROS 包
    if [ "$ROS_VERSION" = "1" ]; then
        ROS_PKG="ros-${ROS_DISTRO}-desktop-full"
    else
        ROS_PKG="ros-${ROS_DISTRO}-desktop"
    fi

    log_info "安装 ${ROS_PKG}（可能需要几分钟）..."
    $SUDO apt install -y "$ROS_PKG"

    log_info "ROS ${ROS_DISTRO} 安装完成"
}

# ==================== 5. 安装 Python + NumPy ====================
install_python_numpy() {
    log_step "安装 Python 及 NumPy..."

    $SUDO apt install -y python3 python3-pip python3-dev python3-venv

    if [ "$USE_MIRROR" = true ]; then
        pip3 install --upgrade pip -i "$PIP_INDEX" 2>/dev/null || true
        pip3 install numpy -i "$PIP_INDEX"
    else
        pip3 install --upgrade pip 2>/dev/null || true
        pip3 install numpy
    fi

    PY_VER=$(python3 --version 2>&1)
    NP_VER=$(python3 -c "import numpy; print(numpy.__version__)" 2>&1)
    log_info "${PY_VER} + NumPy ${NP_VER} 安装完成"
}

# ==================== 6. rosdep 初始化 ====================
init_rosdep() {
    log_step "初始化 rosdep..."
    $SUDO apt install -y python3-rosdep 2>/dev/null || true

    if [ "$USE_MIRROR" = true ]; then
        # 国内环境: 手动创建 rosdep 源列表，绕过 raw.githubusercontent.com
        log_info "配置 rosdep 使用国内源..."
        $SUDO mkdir -p /etc/ros/rosdep/sources.list.d
        $SUDO curl -sSL https://mirrors.tuna.tsinghua.edu.cn/rosdistro/rosdep/20-default.list \
            -o /etc/ros/rosdep/sources.list.d/20-default.list 2>/dev/null || \
        $SUDO curl -sSL https://gitee.com/ohhuo/rosdistro/raw/master/rosdep/sources.list.d/20-default.list \
            -o /etc/ros/rosdep/sources.list.d/20-default.list 2>/dev/null || true

        # 替换 rosdep 源中的 GitHub 地址为清华镜像
        if [ -d /etc/ros/rosdep ]; then
            $SUDO find /etc/ros/rosdep -type f -name "*.list" -exec \
                sed -i 's@https://raw.githubusercontent.com@https://mirrors.tuna.tsinghua.edu.cn@g' {} \; 2>/dev/null || true
            $SUDO find /etc/ros/rosdep -type f -name "*.list" -exec \
                sed -i 's@https://raw.githubusercontent.com@https://gitee.com/ohhuo@g' {} \; 2>/dev/null || true
        fi

        rosdep update 2>/dev/null || log_warn "rosdep update 失败，可稍后手动执行"
    else
        $SUDO rosdep init 2>/dev/null || true
        rosdep update 2>/dev/null || true
    fi

    log_info "rosdep 初始化完成"
}

# ==================== 7. 配置 ROS 环境变量 ====================
setup_ros_env() {
    log_step "配置 ROS 环境变量到 ~/.bashrc..."

    ROS_SETUP="/opt/ros/${ROS_DISTRO}/setup.bash"
    BASHRC="$HOME/.bashrc"
    MARKER_START="# >>> ROS ${ROS_DISTRO} auto-setup >>>"
    MARKER_END="# <<< ROS ${ROS_DISTRO} auto-setup <<<"

    # 删除旧的 ROS 配置
    sed -i "/^# >>> ROS .* auto-setup >>>/,/^# <<< ROS .* auto-setup <<</d" "$BASHRC" 2>/dev/null || true

    {
        echo "$MARKER_START"
        echo "source ${ROS_SETUP}"
        echo "$MARKER_END"
    } >> "$BASHRC"

    log_info "ROS 环境变量已写入 ~/.bashrc"
}

# ==================== 8. 验证安装 ====================
verify_installation() {
    echo ""
    echo -e "${CYAN}============================================${NC}"
    echo -e "${CYAN}           安装验证${NC}"
    echo -e "${CYAN}============================================${NC}"

    if [ -f "/opt/ros/${ROS_DISTRO}/setup.bash" ]; then
        echo -e "  ROS ${ROS_DISTRO}  ${GREEN}✓ 已安装${NC}"
    else
        echo -e "  ROS ${ROS_DISTRO}  ${RED}✗ 未找到${NC}"
    fi

    echo -e "  Python      ${GREEN}✓ $(python3 --version 2>&1)${NC}"
    echo -e "  NumPy       ${GREEN}✓ $(python3 -c 'import numpy; print(numpy.__version__)' 2>&1)${NC}"
    echo -e "${CYAN}============================================${NC}"
    echo ""
}

# ==================== 主流程 ====================

clear
echo -e "${CYAN}"
echo "  ╔═══════════════════════════════════════════╗"
echo "  ║   ROS + Python + NumPy  一键安装脚本      ║"
echo "  ║   支持 Ubuntu 20.04 / 22.04 / 24.04       ║"
echo "  ╚═══════════════════════════════════════════╝"
echo -e "${NC}"

detect_os
select_mirror

# 确认信息
echo ""
echo -e "${YELLOW}即将安装以下内容:${NC}"
echo "  • ROS ${ROS_DISTRO} (ROS ${ROS_VERSION})"
echo "  • Python3 (系统匹配版本)"
echo "  • NumPy (pip 安装)"
echo "  • 镜像源: $([ "$USE_MIRROR" = true ] && echo '国内' || echo '国际')"
echo ""

read -rp "  确认继续? [Y/n] " confirm
if [[ "$confirm" =~ ^[Nn] ]]; then
    echo "已取消。"
    exit 0
fi

echo ""
log_info "开始安装... （可能需要 sudo 密码）"
echo ""

setup_apt_mirror
install_ros
install_python_numpy
init_rosdep
setup_ros_env
verify_installation

echo -e "${GREEN}全部安装完成!${NC}"
echo -e "请执行 ${YELLOW}source ~/.bashrc${NC} 或重新打开终端使 ROS 环境生效。"
