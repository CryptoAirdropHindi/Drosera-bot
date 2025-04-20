#!/bin/bash

# ========== Colors ==========
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# ========== Utilities ==========
error_exit() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
    exit 1
}

info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

prompt_hidden_input() {
    echo -ne "$1"
    stty -echo
    read -r INPUT
    stty echo
    echo
    echo "$INPUT"
}

# ========== Banner ==========
clear
echo -e "${CYAN}"
echo "██████╗ ██████╗  ██████╗ ███████╗███████╗██████╗  █████╗"
echo "██╔══██╗██╔══██╗██╔════╝ ██╔════╝██╔════╝██╔══██╗██╔══██╗"
echo "██║  ██║██████╔╝██║  ███╗█████╗  █████╗  ██████╔╝███████║"
echo "██║  ██║██╔═══╝ ██║   ██║██╔══╝  ██╔══╝  ██╔═══╝ ██╔══██║"
echo "██████╔╝██║     ╚██████╔╝███████╗███████╗██║     ██║  ██║"
echo "╚═════╝ ╚═╝      ╚═════╝ ╚══════╝╚══════╝╚═╝     ╚═╝  ╚═╝"
echo -e "${NC}\n"

echo -e "${YELLOW}Welcome to the Drosera Network Installer${NC}"
echo -e "Telegram: ${CYAN}@CryptoAirdropHindi${NC}"
echo -e "GitHub:   ${CYAN}github.com/CryptoAirdropHindi${NC}\n"

# ========== Menu ==========
show_menu() {
    echo -e "${GREEN}1) Full Node + Deploy Trap"
    echo "2) Run Operator Only"
    echo "3) Setup with Docker"
    echo -e "4) Quit${NC}"
    echo -ne "${YELLOW}Select an option (1-4): ${NC}"
}

# ========== Setup Full Node + Trap ==========
setup_full_node_trap() {
    info "Installing dependencies..."
    sudo apt update && sudo apt upgrade -y
    sudo apt install curl git build-essential ufw jq nano unzip lz4 wget gcc make tmux -y || error_exit "Dependency installation failed"

    info "Installing Docker..."
    curl -fsSL https://get.docker.com | bash || error_exit "Docker installation failed"

    info "Installing Drosera CLI..."
    curl -sL https://app.drosera.io/install | bash || error_exit "Drosera CLI installation failed"
    source ~/.bashrc
    export PATH="$HOME/.drosera/bin:$PATH"
    command -v drosera || error_exit "Drosera not found"

    info "Installing Foundry CLI..."
    curl -L https://foundry.paradigm.xyz | bash || error_exit "Foundry install failed"
    source ~/.bashrc
    export PATH="$HOME/.foundry/bin:$PATH"
    foundryup || error_exit "Foundry update failed"

    info "Installing Bun..."
    curl -fsSL https://bun.sh/install | bash || error_exit "Bun install failed"
    source ~/.bashrc
    export BUN_INSTALL="$HOME/.bun"
    export PATH="$BUN_INSTALL/bin:$PATH"

    info "Cloning and setting up Trap..."
    mkdir -p ~/my-drosera-trap && cd ~/my-drosera-trap
    read -rp "${CYAN}GitHub Email: ${NC}" GITHUB_EMAIL
    read -rp "${CYAN}GitHub Username: ${NC}" GITHUB_USERNAME
    git config --global user.email "$GITHUB_EMAIL"
    git config --global user.name "$GITHUB_USERNAME"

    forge init -t drosera-network/trap-foundry-template || error_exit "Trap init failed"
    bun install || error_exit "Bun packages failed"
    forge build || error_exit "Trap build failed"

    info "Edit trap config"
    read -rp "${GREEN}Press Enter to open 'drosera.toml'...${NC}"
    nano drosera.toml

    PRIVATE_KEY=$(prompt_hidden_input "${GREEN}Enter Private Key (EVM): ${NC}")
    [[ -z "$PRIVATE_KEY" ]] && error_exit "Private key cannot be empty"

    info "Deploying Trap..."
    DROSERA_PRIVATE_KEY="$PRIVATE_KEY" drosera apply || error_exit "Drosera apply failed"

    info "Setup complete. Please deposit Holesky ETH to the trap and Opt-in later."
}

# ========== Run Operator ==========
run_operator_only() {
    PRIVATE_KEY=$(prompt_hidden_input "${GREEN}Enter Private Key (EVM): ${NC}")
    VPS_IP=$(read -p "Enter VPS Public IP: " && echo "$REPLY")
    [[ -z "$PRIVATE_KEY" || -z "$VPS_IP" ]] && error_exit "Missing key or IP"

    info "Installing Operator CLI..."
    cd ~
    curl -LO https://github.com/drosera-network/releases/releases/download/v1.16.2/drosera-operator-v1.16.2-x86_64-unknown-linux-gnu.tar.gz
    tar -xvf drosera-operator-v1.16.2-x86_64-unknown-linux-gnu.tar.gz
    sudo mv drosera-operator /usr/bin/
    chmod +x /usr/bin/drosera-operator

    info "Registering Operator..."
    drosera-operator register --eth-rpc-url https://ethereum-holesky-rpc.publicnode.com --eth-private-key "$PRIVATE_KEY" || error_exit "Registration failed"

    info "Setting up systemd service..."
    sudo tee /etc/systemd/system/drosera.service > /dev/null <<EOF
[Unit]
Description=Drosera Operator
After=network.target

[Service]
User=$USER
ExecStart=/usr/bin/drosera-operator node --db-file-path=$HOME/.drosera.db \
  --network-p2p-port=31313 --server-port=31314 \
  --eth-rpc-url=https://ethereum-holesky-rpc.publicnode.com \
  --eth-backup-rpc-url=https://1rpc.io/holesky \
  --drosera-address=0xea08f7d533C2b9A62F40D5326214f39a8E3A32F8 \
  --eth-private-key=$PRIVATE_KEY \
  --listen-address=0.0.0.0 \
  --network-external-p2p-address=$VPS_IP \
  --disable-dnr-confirmation=true
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable drosera
    sudo systemctl start drosera || error_exit "Failed to start operator"

    info "Operator setup complete"
    echo -e "${CYAN}Use 'journalctl -u drosera.service -f' to monitor logs.${NC}"
}

# ========== Docker Setup ==========
docker_setup() {
    info "Installing Docker..."
    curl -fsSL https://get.docker.com | bash || error_exit "Docker install failed"
    
    info "Cloning Docker repo..."
    git clone https://github.com/0xmoei/Drosera-Network || error_exit "Clone failed"
    cd Drosera-Network || error_exit "Missing directory"

    cp .env.example .env
    nano .env

    info "Starting containers..."
    docker compose up -d || error_exit "Docker start failed"

    info "Docker setup complete"
    echo -e "${CYAN}Logs: docker compose logs -f${NC}"
}

# ========== Main Loop ==========
while true; do
    show_menu
    read -r OPTION
    case $OPTION in
        1) setup_full_node_trap ;;
        2) run_operator_only ;;
        3) docker_setup ;;
        4) echo -e "${MAGENTA}Goodbye!${NC}"; exit 0 ;;
        *) echo -e "${RED}Invalid option!${NC}";;
    esac
    echo
    read -rp "${GREEN}Press Enter to return to menu...${NC}"
done
