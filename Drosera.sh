#!/bin/bash

# Drosera Node Setup Script
# WARNING: Never expose private keys in production environments

set -e # Exit on error

# Configuration Variables (prompt user)
read -p "Enter GitHub Email: " GITHUB_EMAIL
read -p "Enter GitHub Username: " GITHUB_USERNAME
read -p "Enter EVM Private Key (with 0x prefix): " PV_KEY
read -p "Enter VPS Public IP: " VPS_IP
read -p "Enter Operator Address (0x...): " OPERATOR_ADDRESS
read -p "Enter Ethereum RPC URL: " ETH_RPC_URL

validate_input() {
    if [[ -z $1 ]]; then
        echo "Error: Required input cannot be empty!"
        exit 1
    fi
}

validate_input "$GITHUB_EMAIL"
validate_input "$GITHUB_USERNAME"
validate_input "$PV_KEY"
validate_input "$VPS_IP"
validate_input "$OPERATOR_ADDRESS"
validate_input "$ETH_RPC_URL"

install_dependencies() {
    echo "Installing system dependencies..."
    sudo apt-get update -y && sudo apt-get upgrade -y
    sudo apt install -y \
        curl ufw iptables build-essential git wget lz4 jq \
        make gcc nano automake autoconf tmux htop nvme-cli \
        libgbm1 pkg-config libssl-dev libleveldb-dev tar clang \
        bsdmainutils ncdu unzip
}

setup_docker() {
    echo "Configuring Docker..."
    sudo apt remove -y docker.io docker-doc podman-docker containerd runc
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo docker run --rm hello-world
}

setup_trap() {
    echo "Setting up Drosera Trap..."
    curl -L https://app.drosera.io/install | bash
    curl -L https://foundry.paradigm.xyz | bash
    source $HOME/.bashrc
    foundryup

    # Bun installation
    curl -fsSL https://bun.sh/install | bash
    source $HOME/.bashrc

    # Project setup
    mkdir -p my-drosera-trap && cd my-drosera-trap
    git config --global user.email "$GITHUB_EMAIL"
    git config --global user.name "$GITHUB_USERNAME"
    forge init -t drosera-network/trap-foundry-template
    
    # Configure RPC URL
    sed -i "s|ethereum_rpc = \".*\"|ethereum_rpc = \"$ETH_RPC_URL\"|" drosera.toml
    
    bun install
    forge build

    # Whitelist operator
    echo -e "\n[whitelist]\noperators = [\"$OPERATOR_ADDRESS\"]" >> drosera.toml
    DROSERA_PRIVATE_KEY="$PV_KEY" drosera apply
    cd ..
}

setup_operator_cli() {
    echo "Installing Operator CLI..."
    curl -LO https://github.com/drosera-network/releases/releases/download/v1.16.2/drosera-operator-v1.16.2-x86_64-unknown-linux-gnu.tar.gz
    tar -xvf drosera-operator-v1.16.2-x86_64-unknown-linux-gnu.tar.gz
    sudo cp drosera-operator /usr/bin
    drosera-operator --version
}

configure_firewall() {
    echo "Configuring firewall..."
    sudo ufw allow ssh
    sudo ufw allow 22
    sudo ufw allow 31313/tcp
    sudo ufw allow 31314/tcp
    sudo ufw --force enable
}

docker_method() {
    echo "Setting up Docker method..."
    git clone https://github.com/0xmoei/Drosera-Network
    cd Drosera-Network
    cp .env.example .env
    sed -i "s/your_evm_private_key/$PV_KEY/g" .env
    sed -i "s/your_vps_public_ip/$VPS_IP/g" .env
    docker compose up -d
    echo "Check logs with: docker compose logs -f"
    cd ..
}

systemd_method() {
    echo "Configuring SystemD service..."
    sudo tee /etc/systemd/system/drosera.service > /dev/null <<EOF
[Unit]
Description=drosera node service
After=network-online.target

[Service]
User=$USER
Restart=always
RestartSec=15
LimitNOFILE=65535
ExecStart=$(which drosera-operator) node --db-file-path \$HOME/.drosera.db --network-p2p-port 31313 --server-port 31314 \
    --eth-rpc-url $ETH_RPC_URL \
    --eth-backup-rpc-url https://1rpc.io/holesky \
    --drosera-address 0xea08f7d533C2b9A62F40D5326214f39a8E3A32F8 \
    --eth-private-key $PV_KEY \
    --listen-address 0.0.0.0 \
    --network-external-p2p-address $VPS_IP \
    --disable-dnr-confirmation true

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable drosera
    sudo systemctl start drosera
    echo "Check logs with: journalctl -u drosera.service -f"
}

main() {
    install_dependencies
    setup_docker
    setup_trap
    setup_operator_cli
    drosera-operator register --eth-rpc-url "$ETH_RPC_URL" --eth-private-key "$PV_KEY"
    configure_firewall

    echo "Select deployment method:"
    select method in Docker SystemD; do
        case $method in
            Docker) docker_method; break;;
            SystemD) systemd_method; break;;
            *) echo "Invalid option";;
        esac
    done

    echo "Setup complete! Verify operation with 'drosera dryrun'"
    echo "Verify RPC configuration with: grep 'ethereum_rpc' my-drosera-trap/drosera.toml"
}

main
