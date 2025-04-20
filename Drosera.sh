#!/bin/bash

# === Colors ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# === Helper Functions ===
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Check if port is in use
is_port_in_use() {
    local port=$1
    if command -v nc &> /dev/null; then
        nc -z localhost "$port" &> /dev/null
        return $?
    elif command -v lsof &> /dev/null; then
        lsof -i:"$port" &> /dev/null
        return $?
    else
        (echo > /dev/tcp/127.0.0.1/"$port") &> /dev/null
        return $?
    fi
}

# Install Python3 if not installed
install_python3() {
    if command -v python3 &> /dev/null; then
        print_message $GREEN "Python3 is already installed."
        return 0
    fi
    print_message $BLUE "Installing python3..."
    sudo apt-get update
    sudo apt-get install -y python3 python3-pip || {
        print_message $RED "Failed to install python3. Please install manually."
        return 1
    }
    print_message $GREEN "Python3 installed successfully."
}

# Install Cloudflared if not installed
install_cloudflared() {
    if command -v cloudflared &> /dev/null; then
        print_message $GREEN "Cloudflared is already installed."
        return 0
    fi
    print_message $BLUE "Installing cloudflared..."
    local ARCH=$(uname -m)
    local CLOUDFLARED_ARCH=""
    case $ARCH in
        x86_64) CLOUDFLARED_ARCH="amd64" ;;
        aarch64|arm64) CLOUDFLARED_ARCH="arm64" ;;
        *) print_message $RED "Unsupported architecture: $ARCH"; return 1 ;;
    esac

    local temp_dir=$(mktemp -d)
    cd "$temp_dir" || return 1

    print_message $BLUE "Downloading cloudflared for $ARCH..."
    if curl -fL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CLOUDFLARED_ARCH}.deb" -o cloudflared.deb; then
        print_message $BLUE "Installing via dpkg..."
        sudo dpkg -i cloudflared.deb || sudo apt-get install -f -y
    else
        print_message $YELLOW "Failed to download .deb, trying binary..."
        if curl -fL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CLOUDFLARED_ARCH}" -o cloudflared; then
            chmod +x cloudflared
            print_message $BLUE "Moving to /usr/local/bin..."
            sudo mv cloudflared /usr/local/bin/
        else
            print_message $RED "Failed to download cloudflared."
            cd ~; rm -rf "$temp_dir"
            return 1
        fi
    fi

    cd ~; rm -rf "$temp_dir"

    if command -v cloudflared &> /dev/null; then
        print_message $GREEN "Cloudflared installed successfully."
        return 0
    else
        print_message $RED "Failed to install cloudflared. Check output and try manual installation."
        return 1
    fi
}

# === Management Functions ===

# Show status and recent logs
check_status_logs() {
    print_message $BLUE "Checking drosera.service status..."
    sudo systemctl status drosera.service --no-pager -l
    print_message $BLUE "\nLast 15 lines of drosera.service logs:"
    sudo journalctl -u drosera.service -n 15 --no-pager -l
    print_message $YELLOW "For real-time log viewing use: sudo journalctl -u drosera.service -f"
}

# Stop service
stop_node_systemd() {
    print_message $BLUE "Stopping drosera.service..."
    sudo systemctl stop drosera.service
    sudo systemctl status drosera.service --no-pager -l
}

# Start service
start_node_systemd() {
    print_message $BLUE "Starting drosera.service..."
    sudo systemctl start drosera.service
    sleep 2
    sudo systemctl status drosera.service --no-pager -l
}

# Backup function (SystemD) - Creates archive only
backup_node_systemd() {
    print_message $BLUE "--- Creating Drosera Backup Archive (SystemD) ---"
    
    local backup_date=$(date +%Y%m%d_%H%M%S)
    local backup_base_dir="$HOME/drosera_backup"
    local backup_dir="$backup_base_dir/drosera_backup_$backup_date"
    local backup_archive="$HOME/drosera_backup_$backup_date.tar.gz"
    local operator_env_file="/root/.drosera_operator.env"
    local trap_dir="$HOME/my-drosera-trap"
    local service_file="/etc/systemd/system/drosera.service"
    local operator_bin=""

    # Verify key components
    if [ ! -d "$trap_dir" ]; then
        print_message $RED "Error: Trap directory ($trap_dir) not found. Backup aborted."
        return 1
    fi
    if [ ! -f "$operator_env_file" ]; then
        print_message $RED "Error: Operator environment file ($operator_env_file) not found. Backup aborted."
        return 1
    fi
     if [ ! -f "$service_file" ]; then
        print_message $YELLOW "Warning: Service file ($service_file) not found. Backup will be incomplete."
    fi
    
    # Find operator binary
    if command -v drosera-operator &> /dev/null; then
        operator_bin=$(command -v drosera-operator)
        print_message $BLUE "Found operator binary: $operator_bin"
    else
        print_message $YELLOW "Warning: drosera-operator binary not found in PATH. Backup will be incomplete."
    fi

    # Create backup directory
    print_message $BLUE "Creating backup directory: $backup_dir"
    if ! mkdir -p "$backup_dir"; then 
        print_message $RED "Failed to create backup directory $backup_dir. Exiting."; 
        sudo systemctl start drosera.service 2>/dev/null 
        return 1;
    fi
    print_message $GREEN "Backup directory created successfully."

    print_message $BLUE "Stopping drosera.service..."
    sudo systemctl stop drosera.service
    sleep 2

    print_message $BLUE "Copying files..."
    # Copy Trap directory
    print_message $BLUE "Copying $trap_dir..."
    if cp -rv "$trap_dir" "$backup_dir/"; then
       print_message $GREEN "Successfully copied $trap_dir"
    else
       print_message $YELLOW "Error copying $trap_dir"
    fi
    
    # Copy .env file
    print_message $BLUE "Attempting to copy $operator_env_file..."
    if [ -f "$operator_env_file" ]; then
        print_message $GREEN "Found $operator_env_file"
        if cp -v "$operator_env_file" "$backup_dir/"; then
            print_message $GREEN "Successfully copied $operator_env_file to $backup_dir"
        else
            print_message $RED "Error copying $operator_env_file (Error code: $?). Check permissions."
        fi
    else
        print_message $RED "Error: $operator_env_file not found at specified path!"
    fi

    # Copy service file
    print_message $BLUE "Attempting to copy $service_file..."
    if [ -f "$service_file" ]; then
        print_message $GREEN "Found $service_file"
        if cp -v "$service_file" "$backup_dir/"; then
           print_message $GREEN "Successfully copied $service_file to $backup_dir"
        else
           print_message $RED "Error copying $service_file (Error code: $?)."
        fi
    else
        print_message $YELLOW "Warning: Service file $service_file not found."
    fi

    # Copy operator binary
    if [ -n "$operator_bin" ] && [ -f "$operator_bin" ]; then
        print_message $BLUE "Attempting to copy binary $operator_bin..."
        if cp -av "$operator_bin" "$backup_dir/"; then
            print_message $GREEN "Successfully copied binary $operator_bin"
            echo "OPERATOR_BIN_PATH=$operator_bin" > "$backup_dir/restore_info.txt"
        else
            print_message $YELLOW "Error copying $operator_bin (Error code: $?)."
        fi
    fi

    print_message $BLUE "Creating archive $backup_archive..."
    if tar czf "$backup_archive" -C "$backup_base_dir" "drosera_backup_$backup_date"; then
        print_message $GREEN "Backup created successfully: $backup_archive"
        print_message $YELLOW "PLEASE copy this file to a secure location (not on this VPS)!"
        print_message $YELLOW "Archive contains your private key in .drosera_operator.env file!"
    else
        print_message $RED "Error creating archive."
    fi

    print_message $BLUE "Cleaning temporary backup directory..."
    rm -rf "$backup_dir" 

    print_message $BLUE "Starting drosera.service..."
    sudo systemctl start drosera.service
    print_message $BLUE "--- Backup creation completed ---"
    echo "$backup_archive"  # Output the archive path
    return 0
}

# New function to create and serve backup via URL
backup_and_serve_systemd() {
    print_message $BLUE "--- Creating and serving backup via URL ---"

    # Create backup archive and get path
    local backup_archive
    backup_archive=$(backup_node_systemd)
    local backup_exit_code=$?
    
    if [[ $backup_exit_code -ne 0 ]] || [[ -z "$backup_archive" ]] || [[ ! -f "$backup_archive" ]]; then
        print_message $RED "Failed to create backup archive. URL serving aborted."
        return 1
    fi

    # Install dependencies
    install_python3 || return 1
    install_cloudflared || return 1
    if ! command -v nc &> /dev/null && ! command -v lsof &> /dev/null; then
        print_message $BLUE "Installing netcat/lsof for port checking..."
        sudo apt-get update && sudo apt-get install -y netcat lsof
    fi

    # Start server and tunnel
    local PORT=8000
    local MAX_RETRIES=10
    local RETRY_COUNT=0
    local SERVER_STARTED=false
    local HTTP_SERVER_PID=""
    local CLOUDFLARED_PID=""
    local TUNNEL_URL=""

    cd ~ || { print_message $RED "Failed to switch to home directory."; return 1; }

    while [[ $RETRY_COUNT -lt $MAX_RETRIES && $SERVER_STARTED == false ]]; do
        print_message $BLUE "Attempting to start server on port $PORT..."
        if is_port_in_use "$PORT"; then
            print_message $YELLOW "Port $PORT busy. Trying next."
            PORT=$((PORT + 1))
            RETRY_COUNT=$((RETRY_COUNT + 1))
            continue
        fi

        # Start HTTP server
        local temp_log_http="/tmp/http_server_$$.log"
        rm -f "$temp_log_http"
        python3 -m http.server "$PORT" > "$temp_log_http" 2>&1 &
        HTTP_SERVER_PID=$!
        sleep 3

        if ! ps -p $HTTP_SERVER_PID > /dev/null; then
            print_message $RED "Failed to start HTTP server on port $PORT."
            cat "$temp_log_http"
            rm -f "$temp_log_http"
            PORT=$((PORT + 1))
            RETRY_COUNT=$((RETRY_COUNT + 1))
            continue
        fi
        print_message $GREEN "HTTP server running on port $PORT (PID: $HTTP_SERVER_PID)."
        rm -f "$temp_log_http"

        # Start Cloudflared tunnel
        print_message $BLUE "Starting Cloudflared tunnel to http://localhost:$PORT..."
        local temp_log_cf="/tmp/cloudflared_$$.log"
        rm -f "$temp_log_cf"
        cloudflared tunnel --url "http://localhost:$PORT" --no-autoupdate > "$temp_log_cf" 2>&1 &
        CLOUDFLARED_PID=$!
        
        # Wait for tunnel URL
        print_message $YELLOW "Waiting for Cloudflare tunnel URL (up to 20 seconds)..."
        for i in {1..10}; do
            TUNNEL_URL=$(grep -o 'https://[^ ]*\.trycloudflare\.com' "$temp_log_cf" | head -n 1)
            if [[ -n "$TUNNEL_URL" ]]; then
                break
            fi
            sleep 2
        done

        if [[ -z "$TUNNEL_URL" ]]; then
            print_message $RED "Failed to get Cloudflare tunnel URL."
            print_message $YELLOW "Cloudflared log:"
            cat "$temp_log_cf"
            kill $HTTP_SERVER_PID 2>/dev/null
            kill $CLOUDFLARED_PID 2>/dev/null
            wait $HTTP_SERVER_PID 2>/dev/null
            wait $CLOUDFLARED_PID 2>/dev/null
            rm -f "$temp_log_cf"
            HTTP_SERVER_PID=""
            CLOUDFLARED_PID=""
            PORT=$((PORT + 1))
            RETRY_COUNT=$((RETRY_COUNT + 1))
        else
            print_message $GREEN "Cloudflare tunnel created: $TUNNEL_URL"
            rm -f "$temp_log_cf"
            SERVER_STARTED=true
        fi
    done

    if [[ $SERVER_STARTED == false ]]; then
        print_message $RED "Failed to start server and tunnel after $MAX_RETRIES attempts."
        return 1
    fi

    # Set up Ctrl+C handler
    trap 'cleanup_server' INT

    # Cleanup function
    cleanup_server() {
        print_message $YELLOW "\nStopping server and tunnel..."
        if [[ -n "$HTTP_SERVER_PID" ]]; then kill $HTTP_SERVER_PID 2>/dev/null; fi
        if [[ -n "$CLOUDFLARED_PID" ]]; then kill $CLOUDFLARED_PID 2>/dev/null; fi
        wait $HTTP_SERVER_PID 2>/dev/null
        wait $CLOUDFLARED_PID 2>/dev/null
        print_message $GREEN "Servers stopped."
        exit 0
    }

    # Show download URL
    print_message $GREEN "========================================================="
    print_message $GREEN "Backup download available at:"
    print_message $YELLOW "$TUNNEL_URL/$(basename "$backup_archive")"
    print_message $GREEN "========================================================="
    print_message $YELLOW "Link will remain active while this script is running."
    print_message $YELLOW "Press Ctrl+C to stop server and exit."

    wait $HTTP_SERVER_PID $CLOUDFLARED_PID
    cleanup_server 
    return 0
}

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

# === Main Menu ===
main_menu() {
    while true; do
        clear
        print_message $GREEN "========= Drosera Node Management Menu (SystemD) ========="
        local status
        status=$(systemctl is-active drosera.service 2>/dev/null)
        echo -e "Service status: $( [[ "$status" == "active" ]] && echo -e "${GREEN}Active${NC}" || echo -e "${RED}Inactive (${status:-not found})${NC}" )"
        print_message $BLUE "---------------------- Installation -----------------------"
        print_message $YELLOW " 1. Run full installation/reinstallation (SystemD)"
        print_message $BLUE "-------------------- Node Management --------------------"
        print_message $GREEN " 2. Show status and recent logs"
        print_message $GREEN " 3. Start service"
        print_message $RED   " 4. Stop service"
        print_message $BLUE "--------------------- Maintenance ---------------------"
        print_message $YELLOW " 5. Create backup (Archive only)"
        print_message $YELLOW " 6. Create and serve backup via URL"
        print_message $NC   " 7. Restore from backup (NOT IMPLEMENTED)"
        print_message $BLUE "---------------------------------------------------------"
        print_message $NC   " 0. Exit"
        print_message $BLUE "========================================================="
        read -p "Select option: " choice

        case $choice in
            1) install_drosera_systemd ;; 
            2) check_status_logs ;;  
            3) start_node_systemd ;;   
            4) stop_node_systemd ;;    
            5) backup_node_systemd ;;   
            6) backup_and_serve_systemd ;;   
            7) print_message $RED "Restore functionality not implemented." ;; 
            0) print_message $GREEN "Exiting."; exit 0 ;;
            *) print_message $RED "Invalid option.";;
        esac
        read -p "Press Enter to continue..."
    done
}

# === Entry Point ===
main_menu
