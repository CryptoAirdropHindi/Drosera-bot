#!/bin/bash

# === Colors ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# [Previous helper functions remain the same...]

# === Main Installation Function ===
install_drosera_systemd() {
    if [ -f "/etc/systemd/system/drosera.service" ]; then
        print_message $YELLOW "Drosera (SystemD) installation appears to exist."
        read -p "Are you sure you want to reinstall? This will remove old files and reinstall components. (y/N): " confirm_reinstall
        if [[ ! "$confirm_reinstall" =~ ^[Yy]$ ]]; then
            print_message $YELLOW "Reinstallation canceled."
            return 1
        fi
        sudo systemctl stop drosera.service 2>/dev/null
        sudo systemctl disable drosera.service 2>/dev/null
    fi

    clear
    echo "🚀 Drosera Full Auto Install (SystemD Only)"

    # User inputs
    read -p "📧 GitHub email: " GHEMAIL
    read -p "👩‍💻 GitHub username: " GHUSER
    read -p "🔐 Drosera private key (without 0x): " PK_RAW
    read -p "🌍 VPS public IP: " VPSIP
    read -p "📬 Public address for whitelist (0x...): " OP_ADDR
    read -p "🔗 Holesky RPC URL (e.g. Alchemy): " ETH_RPC_URL

    PK=${PK_RAW#0x}

    if ! [[ "$PK" =~ ^[a-fA-F0-9]{64}$ ]]; then
        echo "❌ Invalid private key format. Must be 64 hex characters."
        exit 1
    fi

    if ! [[ "$OP_ADDR" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
        echo "❌ Invalid whitelist address format. Must start with 0x and 40 hex chars."
        exit 1
    fi
    
    if [[ -z "$ETH_RPC_URL" || (! "$ETH_RPC_URL" =~ ^https?:// && ! "$ETH_RPC_URL" =~ ^wss?://) ]]; then
        echo "❌ Invalid RPC URL format. Using default: https://ethereum-holesky-rpc.publicnode.com"
        ETH_RPC_URL="https://ethereum-holesky-rpc.publicnode.com"
    fi

    for var in GHEMAIL GHUSER PK VPSIP OP_ADDR ETH_RPC_URL; do
        if [[ -z "${!var}" ]]; then
            echo "❌ $var is required."
            exit 1
        fi
    done

    echo "--------------------------------------------------"
    echo "Verify inputs:"
    echo "Email: $GHEMAIL"
    echo "Username: $GHUSER"
    echo "Private Key: <hidden>"
    echo "VPS IP: $VPSIP"
    echo "Whitelist Address: $OP_ADDR"
    echo "RPC URL: $ETH_RPC_URL"
    echo "--------------------------------------------------"
    read -p "Is this correct? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Installation canceled."
        exit 1
    fi

    # Installation steps
    echo "⚙️ Installing dependencies..."
    sudo apt-get update && sudo apt-get upgrade -y
    sudo apt install -y curl ufw build-essential git wget jq make gcc nano automake autoconf tmux htop pkg-config libssl-dev tar clang bsdmainutils ca-certificates gnupg unzip lz4 nvme-cli libgbm1 libleveldb-dev || { echo "❌ Dependency installation failed."; exit 1; }

    echo "💧 Installing Drosera CLI..."
    curl -L https://app.drosera.io/install | bash || { echo "❌ Drosera CLI install failed."; exit 1; }
    if ! grep -q '$HOME/.drosera/bin' ~/.bashrc; then
      echo 'export PATH="$HOME/.drosera/bin:$PATH"' >> ~/.bashrc
    fi
    export PATH="$HOME/.drosera/bin:$PATH"
    droseraup || { echo "❌ Drosera CLI update failed."; exit 1; }

    echo "🛠️ Installing Foundry..."
    curl -L https://foundry.paradigm.xyz | bash || { echo "❌ Foundry install failed."; exit 1; }
    if ! grep -q '$HOME/.foundry/bin' ~/.bashrc; then
      echo 'export PATH="$HOME/.foundry/bin:$PATH"' >> ~/.bashrc
    fi
    export PATH="$HOME/.foundry/bin:$PATH"
    foundryup || { echo "❌ Foundry update failed."; exit 1; }

    echo "📦 Installing Bun..."
    curl -fsSL https://bun.sh/install | bash || { echo "❌ Bun install failed."; exit 1; }
    if ! grep -q '$HOME/.bun/bin' ~/.bashrc; then
      echo 'export PATH="$HOME/.bun/bin:$PATH"' >> ~/.bashrc
    fi
    export PATH="$HOME/.bun/bin:$PATH"

    echo "🧹 Cleaning old directories..."
    rm -rf ~/drosera_operator ~/my-drosera-trap ~/.drosera/.env

    echo "🔧 Setting up Trap..."
    mkdir -p ~/my-drosera-trap && cd ~/my-drosera-trap || { echo "❌ Failed to create trap directory."; exit 1; }

    echo "👤 Configuring Git..."
    git config --global user.email "$GHEMAIL"
    git config --global user.name "$GHUSER"

    echo "⏳ Initializing Trap project..."
    if ! timeout 300 forge init -t drosera-network/trap-foundry-template; then
        echo "❌ Trap initialization failed."
        exit 1
    fi

    echo "📦 Installing Bun dependencies..."
    if ! timeout 300 bun install; then
         echo "❌ Bun dependency installation failed."
         rm -rf node_modules bun.lockb
         if ! timeout 300 bun install; then
             echo "❌ Retry failed."
             exit 1
         fi
    fi

    echo "🧱 Building Trap..."
    if ! forge build; then
        echo "❌ Trap build failed."
        exit 1
    fi

    echo "🚀 Deploying Trap to Holesky..."
    LOG_FILE="/tmp/drosera_deploy.log"
    TRAP_NAME="mytrap"
    rm -f "$LOG_FILE"

    if ! DROSERA_PRIVATE_KEY=$PK drosera apply --eth-rpc-url "$ETH_RPC_URL" <<< "ofc" | tee "$LOG_FILE"; then
        echo "❌ Trap deployment failed."
        cat "$LOG_FILE"
        exit 1
    fi

    TRAP_ADDR=$(grep -oP "(?<=address: )0x[a-fA-F0-9]{40}" "$LOG_FILE" | head -n 1)

    if [[ -z "$TRAP_ADDR" || "$TRAP_ADDR" == "0x" ]]; then
        echo "❌ Failed to get Trap address from logs:"
        cat "$LOG_FILE"
        exit 1
    fi
    echo "🪤 Trap deployed at: $TRAP_ADDR"

    echo "🔐 Updating whitelist in drosera.toml..."
    temp_toml=$(mktemp)
    awk -v addr="$OP_ADDR" \
        '/^private_trap *=/{private_found=1; print "private_trap = true"; next} \
         /^whitelist *=/{whitelist_found=1; print "whitelist = [\"" addr "\"]"; next} \
         {print} \
         END { \
             if(!private_found) print "private_trap = true"; \
             if(!whitelist_found) print "whitelist = [\"" addr "\"]" \
         }' drosera.toml > "$temp_toml" \
    && mv "$temp_toml" drosera.toml || { echo "❌ Failed to update drosera.toml"; rm -f "$temp_toml"; exit 1; }

    echo "⏳ Waiting 10 minutes before reapplying config..."
    sleep 600
    echo "🚀 Reapplying Trap config with whitelist..."
    rm -f "$LOG_FILE"
    if ! DROSERA_PRIVATE_KEY=$PK drosera apply --eth-rpc-url "$ETH_RPC_URL" <<< "ofc" | tee "$LOG_FILE"; then
        echo "❌ Config reapply failed."
        cat "$LOG_FILE"
        exit 1
    fi
    echo "✅ Whitelist config applied successfully."

    echo "🔽 Downloading operator binary..."
    cd ~ || exit 1
    OPERATOR_CLI_URL="https://github.com/drosera-network/releases/releases/download/v1.16.2/drosera-operator-v1.16.2-x86_64-unknown-linux-gnu.tar.gz"
    OPERATOR_CLI_ARCHIVE=$(basename $OPERATOR_CLI_URL)
    OPERATOR_CLI_BIN="drosera-operator"

    rm -f "$OPERATOR_CLI_ARCHIVE" "$OPERATOR_CLI_BIN" "/usr/local/bin/$OPERATOR_CLI_BIN"

    if ! curl -fLO "$OPERATOR_CLI_URL"; then
        echo "❌ Failed to download operator."
        exit 1
    fi

    echo "📦 Extracting operator archive..."
    if ! tar -xvf "$OPERATOR_CLI_ARCHIVE"; then
        echo "❌ Extraction failed."
        rm -f "$OPERATOR_CLI_ARCHIVE"
        exit 1
    fi

    echo "🚀 Installing operator to /usr/local/bin..."
    if ! sudo mv "$OPERATOR_CLI_BIN" /usr/local/bin/; then
        echo "❌ Installation failed. Check permissions."
        rm -f "$OPERATOR_CLI_ARCHIVE"
        exit 1
    fi
    sudo chmod +x /usr/local/bin/drosera-operator

    if ! command -v drosera-operator &> /dev/null; then
        echo "❌ Operator not found in PATH."
        rm -f "$OPERATOR_CLI_ARCHIVE"
        exit 1
    else
        echo "✅ Operator installed successfully."
        rm -f "$OPERATOR_CLI_ARCHIVE"
    fi

    echo "✍️ Registering operator..."
    if ! drosera-operator register --eth-rpc-url "$ETH_RPC_URL" --eth-private-key $PK; then
        echo "❌ Registration failed."
        exit 1
    fi
    echo "✅ Operator registered successfully."

    # Clone and configure Drosera-Network repository
    echo -e "\n${BLUE}Cloning repository...${NC}"
    if [ -d "Drosera-Network" ]; then
        echo -e "${YELLOW}Existing repository found, updating...${NC}"
        cd Drosera-Network
        git pull origin main
        cd ..
    else
        git clone https://github.com/0xmoei/Drosera-Network
    fi

    # Configure environment
    echo -e "${BLUE}Configuring environment...${NC}"
    cp Drosera-Network/.env.example Drosera-Network/.env
    
    # Secure file permissions
    chmod 600 Drosera-Network/.env
    
    # Replace values using safe delimiter (|)
    sed -i "s|your_evm_private_key|$PK|g" Drosera-Network/.env
    sed -i "s|your_vps_public_ip|$VPSIP|g" Drosera-Network/.env

    # Start Docker services if docker is available
    if command -v docker &> /dev/null; then
        echo -e "${BLUE}Starting Docker containers...${NC}"
        cd Drosera-Network
        docker compose down -v  # Cleanup any previous instances
        docker compose up -d --build

        echo -e "\n${GREEN}=== Verification ===${NC}"
        echo -e "Container status:"
        docker compose ps
        
        echo -e "\n${GREEN}Docker services started!${NC}"
        echo -e "Check logs with: ${YELLOW}docker compose logs -f${NC}"
        cd ..
    else
        echo -e "${YELLOW}Docker not found, skipping Docker container setup${NC}"
    fi

    echo "⚙️ Configuring SystemD service..."
    SERVICE_FILE="/etc/systemd/system/drosera.service"
    OPERATOR_ENV_FILE="/root/.drosera_operator.env" 

    sudo mkdir -p /root 
    sudo bash -c "cat > $OPERATOR_ENV_FILE" << EOF
ETH_PRIVATE_KEY=$PK
VPS_IP=$VPSIP
ETH_RPC_URL=$ETH_RPC_URL
EOF
    sudo chmod 600 "$OPERATOR_ENV_FILE"

    sudo tee "$SERVICE_FILE" > /dev/null << EOF
[Unit]
Description=Drosera Operator Service
After=network.target

[Service]
User=root
Group=root
WorkingDirectory=/root
EnvironmentFile=$OPERATOR_ENV_FILE
ExecStart=/usr/local/bin/drosera-operator node \\
    --db-file-path /root/.drosera.db \\
    --network-p2p-port 31313 \\
    --server-port 31314 \\
    --eth-rpc-url \${ETH_RPC_URL} \\
    --eth-private-key \${ETH_PRIVATE_KEY} \\
    --drosera-address 0xea08f7d533C2b9A62F40D5326214f39a8E3A32F8 \\
    --listen-address 0.0.0.0 \\
    --network-external-p2p-address \${VPS_IP} \\
    --disable-dnr-confirmation true
Restart=on-failure
RestartSec=10
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    echo "🔧 Configuring firewall..."
    sudo ufw allow 22/tcp comment 'Allow SSH'
    sudo ufw allow 31313/tcp comment 'Allow Drosera P2P'
    sudo ufw allow 31314/tcp comment 'Allow Drosera Server'

    echo "🔄 Reloading SystemD and starting service..."
    sudo systemctl daemon-reload
    sudo systemctl enable drosera.service
    sudo systemctl restart drosera.service

    echo "⏳ Waiting for service stabilization..."
    sleep 5
    echo "📊 Service status:"
    sudo systemctl status drosera.service --no-pager -l

    echo "=================================================="
    print_message $GREEN "✅ Drosera (SystemD) installation complete!"
    echo "Next steps:"
    echo "1. Check service status: sudo systemctl status drosera.service"
    echo "2. View logs: sudo journalctl -u drosera.service -f -n 100"
    echo "3. Access dashboard: https://app.drosera.io/"
    echo "4. Connect operator wallet: $OP_ADDR"
    echo "5. Find your Trap: $TRAP_ADDR"
    echo "6. Fund Trap with Holesky ETH via [Send Bloom Boost]"
    echo "7. [Opt In] for your Trap"
    echo "8. Verify operator status on dashboard"
    echo ""
    print_message $YELLOW "Recommended: Verify RPC URL in service file"
    echo "sudo nano /etc/systemd/system/drosera.service"
    echo "Reload after changes: sudo systemctl daemon-reload && sudo systemctl restart drosera.service"
    echo "=================================================="
    return 0
}

# [Rest of the script remains the same...]
