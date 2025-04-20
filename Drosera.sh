#!/bin/bash

# Drosera Node Setup Script
# WARNING: Never expose private keys in production environments

set -e  # Exit on error

# === HELPER FUNCTIONS ===
validate_input() {
    if [[ -z $1 ]]; then
        echo "❌ Error: Required input cannot be empty!"
        exit 1
    fi
}

print_header() {
    echo -e "\n\033[1;32m==> $1\033[0m\n"
}

# === INSTALL DEPENDENCIES ===
install_dependencies() {
    print_header "Installing system dependencies..."
    sudo apt-get update -y && sudo apt-get upgrade -y
    sudo apt install -y \
        curl ufw iptables build-essential git wget lz4 jq \
        make gcc nano automake autoconf tmux htop nvme-cli \
        libgbm1 pkg-config libssl-dev libleveldb-dev tar clang \
        bsdmainutils ncdu unzip
}

# === SETUP DOCKER ===
setup_docker() {
    print_header "Installing Docker..."
    sudo apt remove -y docker.io docker-doc podman-docker containerd runc
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo docker run --rm hello-world
}

# === SETUP TRAP ===
setup_trap() {
    print_header "Setting up Drosera Trap..."
    curl -L https://app.drosera.io/install | bash
    curl -L https://foundry.paradigm.xyz | bash
    source $HOME/.bashrc
    foundryup

    curl -fsSL https://bun.sh/install | bash
    source $HOME/.bashrc

    read -p "📧 GitHub email: " GHEMAIL
    read -p "👩‍💻 GitHub username: " GHUSER
    read -p "🔐 Drosera private key (without 0x): " PK_RAW
    read -p "🌍 VPS public IP: " VPS_IP
    read -p "📬 Public address for whitelist (0x...): " OP_ADDR
    read -p "🔗 Holesky RPC URL (e.g., Alchemy): " ETH_RPC_URL

    PK=${PK_RAW#0x}

    [[ "$PK" =~ ^[a-fA-F0-9]{64}$ ]] || { echo "❌ Invalid private key format."; exit 1; }
    [[ "$OP_ADDR" =~ ^0x[a-fA-F0-9]{40}$ ]] || { echo "❌ Invalid address format."; exit 1; }

    if [[ -z "$ETH_RPC_URL" || (! "$ETH_RPC_URL" =~ ^https?:// && ! "$ETH_RPC_URL" =~ ^wss?://) ]]; then
        echo "❌ Invalid RPC URL format. Using fallback..."
        ETH_RPC_URL="https://ethereum-holesky-rpc.publicnode.com"
    fi

    for var in GHEMAIL GHUSER PK VPS_IP OP_ADDR ETH_RPC_URL; do
        validate_input "${!var}"
    done

    # Save for later steps
    export GHUSER GHEMAIL PK VPS_IP OP_ADDR ETH_RPC_URL
    export PV_KEY=$PK
}

# === INSTALL OPERATOR CLI ===
setup_operator_cli() {
    print_header "Installing Drosera Operator CLI..."
    curl -LO https://github.com/drosera-network/releases/releases/download/v1.16.2/drosera-operator-v1.16.2-x86_64-unknown-linux-gnu.tar.gz
    tar -xvf drosera-operator-v1.16.2-x86_64-unknown-linux-gnu.tar.gz
    sudo cp drosera-operator /usr/bin
    drosera-operator --version
}

# === FIREWALL ===
configure_firewall() {
    print_header "Configuring UFW Firewall..."
    sudo ufw allow ssh
    sudo ufw allow 22
    sudo ufw allow 31313/tcp
    sudo ufw allow 31314/tcp
    sudo ufw --force enable
}

# === DOCKER METHOD ===
docker_method() {
    print_header "Setting up Docker deployment..."
    git clone https://github.com/0xmoei/Drosera-Network
    cd Drosera-Network
    cp .env.example .env
    sed -i "s/your_evm_private_key/$PV_KEY/g" .env
    sed -i "s/your_vps_public_ip/$VPS_IP/g" .env
    docker compose up -d
    echo "✅ Docker started. Logs: docker compose logs -f"
    cd ..
}

# === SYSTEMD METHOD ===
systemd_method() {
    print_header "Setting up SystemD service..."
    sudo tee /etc/systemd/system/drosera.service > /dev/null <<EOF
[Unit]
Description=Drosera Node Service
After=network-online.target

[Service]
User=$USER
Restart=always
RestartSec=15
LimitNOFILE=65535
ExecStart=$(which drosera-operator) node \\
    --db-file-path \$HOME/.drosera.db \\
    --network-p2p-port 31313 \\
    --server-port 31314 \\
    --eth-rpc-url $ETH_RPC_URL \\
    --eth-backup-rpc-url https://1rpc.io/holesky \\
    --drosera-address 0xea08f7d533C2b9A62F40D5326214f39a8E3A32F8 \\
    --eth-private-key $PV_KEY \\
    --listen-address 0.0.0.0 \\
    --network-external-p2p-address $VPS_IP \\
    --disable-dnr-confirmation true

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable drosera
    sudo systemctl start drosera
    echo "✅ SystemD service started. Logs: journalctl -u drosera.service -f"
}

# === MAIN FUNCTION ===
main() {
    install_dependencies
    setup_docker
    setup_trap
    setup_operator_cli
    drosera-operator register --eth-rpc-url "$ETH_RPC_URL" --eth-private-key "$PV_KEY"
    configure_firewall

    echo "Choose deployment method:"
    select method in Docker SystemD; do
        case $method in
            Docker) docker_method; break;;
            SystemD) systemd_method; break;;
            *) echo "❌ Invalid option";;
        esac
    done

    echo -e "\n✅ Setup complete!"
    echo "🧪 Test with: drosera dryrun"
    echo "🔍 Check RPC in: my-drosera-trap/drosera.toml"
}

main
