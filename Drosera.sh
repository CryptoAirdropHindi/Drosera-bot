#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Error handling function
error_exit() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
    exit 1
}

# Clear screen and display header
clear
echo -e "\n\n\n\n"
echo -e "${RED}    ██╗  ██╗ █████╗ ███████╗ █████╗ ███╗   ██╗${NC}"
echo -e "${GREEN}    ██║  ██║██╔══██╗██╔════╝██╔══██╗████╗  ██║${NC}"
echo -e "${BLUE}    ███████║███████║███████╗███████║██╔██╗ ██║${NC}"
echo -e "${YELLOW}    ██╔══██║██╔══██║╚════██║██╔══██║██║╚██╗██║${NC}"
echo -e "${MAGENTA}    ██║  ██║██║  ██║███████║██║  ██║██║ ╚████║${NC}"
echo -e "${CYAN}    ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝${NC}"
echo -e "${BLUE}=======================================================${NC}"
echo -e "${GREEN}             🚀 Drosera Network Installer 🚀 ${NC}"
echo -e "${BLUE}=======================================================${NC}"
echo -e "${CYAN}           🌐  Telegram: @CryptoAirdropHindi${NC}"
echo -e "${CYAN}           📺  YouTube:  @CryptoAirdropHindi6${NC}"
echo -e "${CYAN}           💻  GitHub:   github.com/CryptoAirdropHindi${NC}"
echo -e "${BLUE}=======================================================${NC}\n"

# Main menu function
show_menu() {
    echo -e "${GREEN}1) Setup Full Node + Deploy Trap${NC}"
    echo -e "${GREEN}2) Run 1 address Operator${NC}"
    echo -e "${GREEN}3) Setup with docker${NC}"
    echo -e "${GREEN}4) Quit${NC}"
    echo -ne "${YELLOW}Select an option (1-4): ${NC}"
}

# Function to setup full node and deploy trap
setup_full_node() {
    echo -e "\n${GREEN}=== Setting up Full Node + Trap ===${NC}"
    
    # Install dependencies
    echo -e "${YELLOW}Installing dependencies...${NC}"
    sudo apt-get update || error_exit "Failed to update packages"
    sudo apt-get install -y \
        curl ufw iptables build-essential git wget lz4 jq make gcc \
        nano automake autoconf tmux htop nvme-cli libgbm1 pkg-config \
        libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip || error_exit "Failed to install dependencies"

    # Install Docker
    echo -e "${YELLOW}Installing Docker...${NC}"
    sudo apt-get remove -y docker.io docker-doc docker-compose podman-docker containerd runc || error_exit "Failed to remove old docker packages"
    sudo apt-get install -y ca-certificates curl gnupg || error_exit "Failed to install prerequisites"
    
    sudo install -m 0755 -d /etc/apt/keyrings || error_exit "Failed to create keyrings directory"
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg || error_exit "Failed to add Docker GPG key"
    sudo chmod a+r /etc/apt/keyrings/docker.gpg || error_exit "Failed to set permissions on Docker GPG key"
    
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null || error_exit "Failed to add Docker repository"
    
    sudo apt-get update || error_exit "Failed to update package lists"
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || error_exit "Failed to install Docker"

    # Install Drosera CLI
    echo -e "${YELLOW}Installing Drosera CLI...${NC}"
    curl -L https://app.drosera.io/install | bash || error_exit "Failed to install Drosera CLI"
    export PATH="$HOME/.drosera/bin:$PATH"
    source ~/.bashrc
    droseraup || error_exit "Drosera update failed"

    # Install Foundry
    echo -e "${YELLOW}Installing Foundry...${NC}"
    curl -L https://foundry.paradigm.xyz | bash || error_exit "Failed to install Foundry"
    source ~/.bashrc
    foundryup || error_exit "Foundry update failed"

    # Install Bun
    echo -e "${YELLOW}Installing Bun...${NC}"
    curl -fsSL https://bun.sh/install | bash || error_exit "Failed to install Bun"
    source ~/.bashrc

    # Setup Trap Project
    echo -e "${YELLOW}Setting up Trap Project...${NC}"
    mkdir -p ~/my-drosera-trap || error_exit "Failed to create directory"
    cd ~/my-drosera-trap || error_exit "Failed to change directory"

    echo -ne "${GREEN}Enter GITHUB EMAIL: ${NC}"
    read -r GITHUB_EMAIL
    echo -ne "${GREEN}Enter GITHUB USERNAME: ${NC}"
    read -r GITHUB_USERNAME
    git config --global user.email "$GITHUB_EMAIL" || error_exit "Failed to set git email"
    git config --global user.name "$GITHUB_USERNAME" || error_exit "Failed to set git username"

    forge init -t drosera-network/trap-foundry-template || error_exit "Failed to initialize trap project"
    source ~/.bashrc
    ~/.bun/bin/bun install || error_exit "Bun install failed"
    forge build || error_exit "Forge build failed"

# Deploy Trap
echo -e "${YELLOW}Deploying Trap...${NC}"

# Open drosera.toml for editing
echo -e "${CYAN}Please configure your Drosera trap in 'drosera.toml'...${NC}"
read -rp "$(echo -e "${GREEN}Press Enter to open the config file...${NC}")"
nano drosera.toml

# Prompt for private key
echo -ne "${GREEN}Enter Private Key EVM: ${NC}"
read -rs PRIVATE_KEY
echo
DROSERA_PRIVATE_KEY="$PRIVATE_KEY" drosera apply || error_exit "Failed to apply Drosera configuration"


    echo -e "${CYAN}Please login on website: https://app.drosera.io/${NC}"
    echo -e "${CYAN}Connect your wallet and configure your trap${NC}"
    read -rp "${GREEN}Press Enter to continue after setting up your trap...${NC}"

    # Setup Operator
    setup_operator
}

# Function to setup operator
setup_operator() {
    echo -e "\n${GREEN}=== Setting up Operator ===${NC}"
    
    # Install Operator CLI
    echo -e "${YELLOW}Installing Operator CLI...${NC}"
    cd ~ || error_exit "Failed to change to home directory"
    curl -LO https://github.com/drosera-network/releases/releases/download/v1.16.2/drosera-operator-v1.16.2-x86_64-unknown-linux-gnu.tar.gz || error_exit "Failed to download operator"
    tar -xvf drosera-operator-v1.16.2-x86_64-unknown-linux-gnu.tar.gz || error_exit "Failed to extract operator"
    sudo cp drosera-operator /usr/bin || error_exit "Failed to install operator"

    # Register Operator
    echo -e "${YELLOW}Registering Operator...${NC}"
    read -rp "${GREEN}Enter Private Key EVM: ${NC}" -s PRIVATE_KEY
    echo
    drosera-operator register --eth-rpc-url https://ethereum-holesky-rpc.publicnode.com --eth-private-key "$PRIVATE_KEY" || error_exit "Failed to register operator"

    # Create systemd service
    echo -e "${YELLOW}Creating systemd service...${NC}"
    read -rp "${GREEN}Enter VPS Public IP Address: ${NC}" VPS_IP
    read -rp "${GREEN}Enter ETH Private Key: ${NC}" -s PRIVATE_KEY
    echo

    sudo tee /etc/systemd/system/drosera.service > /dev/null <<EOF
[Unit]
Description=Drosera Node Service
After=network-online.target

[Service]
User=$USER
Restart=always
RestartSec=15
LimitNOFILE=65535
ExecStart=$(which drosera-operator) node --db-file-path $HOME/.drosera.db --network-p2p-port 31313 --server-port 31314 \
    --eth-rpc-url https://ethereum-holesky-rpc.publicnode.com \
    --eth-backup-rpc-url https://1rpc.io/holesky \
    --drosera-address 0xea08f7d533C2b9A62F40D5326214f39a8E3A32F8 \
    --eth-private-key ${PRIVATE_KEY} \
    --listen-address 0.0.0.0 \
    --network-external-p2p-address ${VPS_IP} \
    --disable-dnr-confirmation true

[Install]
WantedBy=multi-user.target
EOF

    # Setup firewall
    echo -e "${YELLOW}Configuring firewall...${NC}"
    sudo ufw allow ssh
    sudo ufw allow 22
    sudo ufw allow 31313/tcp
    sudo ufw allow 31314/tcp
    echo "y" | sudo ufw enable

    # Start service
    echo -e "${YELLOW}Starting service...${NC}"
    sudo systemctl daemon-reload
    sudo systemctl enable drosera
    sudo systemctl start drosera || error_exit "Failed to start drosera service"

    # Opt-in
    echo -e "${YELLOW}Opting in...${NC}"
    read -rp "${GREEN}Enter Trap Address: ${NC}" TRAP_ADDRESS
    drosera-operator optin --eth-rpc-url https://ethereum-holesky-rpc.publicnode.com --trap-config-address "$TRAP_ADDRESS" --eth-private-key "$PRIVATE_KEY" || error_exit "Failed to opt-in"

    echo -e "\n${GREEN}=== Setup Complete ===${NC}"
    echo -e "Check node status with: ${CYAN}journalctl -u drosera.service -f${NC}"
}

# Function to run operator only
run_operator() {
    echo -e "\n${GREEN}=== Setting up Operator Only ===${NC}"
    echo -e "${YELLOW}Make sure the wallet address has been whitelisted in drosera.toml${NC}"
    read -rp "${GREEN}Press Enter to continue...${NC}"

    # Install Drosera CLI
    echo -e "${YELLOW}Installing Drosera CLI...${NC}"
    curl -L https://app.drosera.io/install | bash || error_exit "Failed to install Drosera CLI"
    export PATH="$HOME/.drosera/bin:$PATH"
    source ~/.bashrc
    droseraup || error_exit "Drosera update failed"

    setup_operator
}

# Function to setup with docker
setup_docker() {
    echo -e "\n${GREEN}=== Setting up with Docker ===${NC}"
    
    # Install Docker
    echo -e "${YELLOW}Installing Docker...${NC}"
    sudo apt-get update || error_exit "Failed to update packages"
    sudo apt-get remove -y docker.io docker-doc docker-compose podman-docker containerd runc || error_exit "Failed to remove old docker packages"
    sudo apt-get install -y ca-certificates curl gnupg || error_exit "Failed to install prerequisites"
    
    sudo install -m 0755 -d /etc/apt/keyrings || error_exit "Failed to create keyrings directory"
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg || error_exit "Failed to add Docker GPG key"
    sudo chmod a+r /etc/apt/keyrings/docker.gpg || error_exit "Failed to set permissions on Docker GPG key"
    
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null || error_exit "Failed to add Docker repository"
    
    sudo apt-get update || error_exit "Failed to update package lists"
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || error_exit "Failed to install Docker"

    # Clone and setup
    echo -e "${YELLOW}Setting up Drosera Network...${NC}"
    git clone https://github.com/0xmoei/Drosera-Network || error_exit "Failed to clone repository"
    cd Drosera-Network || error_exit "Failed to enter directory"
    cp .env.example .env || error_exit "Failed to copy environment file"

    echo -e "${YELLOW}Please edit the .env file with your configuration${NC}"
    read -rp "${GREEN}Press Enter to open the editor...${NC}"
    nano .env

    # Start containers
    echo -e "${YELLOW}Starting containers...${NC}"
    docker compose up -d || error_exit "Failed to start containers"

    echo -e "\n${GREEN}=== Docker Setup Complete ===${NC}"
    echo -e "View logs with: ${CYAN}cd Drosera-Network && docker compose logs -f${NC}"
    echo -e "To restart: ${CYAN}docker compose down -v && docker compose up -d${NC}"
}

# Main menu loop
while true; do
    show_menu
    read -r choice
    
    case $choice in
        1) setup_full_node ;;
        2) run_operator ;;
        3) setup_docker ;;
        4) 
            echo -e "${GREEN}Exiting...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option. Please select 1-4.${NC}"
            sleep 1
            ;;
    esac
    
    # After completing an option, show menu again unless quitting
    if [[ $choice != 4 ]]; then
        echo -e "\n${BLUE}=======================================================${NC}\n"
        read -rp "$(echo -e "${GREEN}Press Enter to return to main menu...${NC}")"
    fi
done
