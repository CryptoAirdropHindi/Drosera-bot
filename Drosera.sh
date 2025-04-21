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
    # Try using netcat (nc), lsof or /dev/tcp
    if command -v nc &> /dev/null; then
        nc -z localhost "$port" &> /dev/null
        return $?
    elif command -v lsof &> /dev/null; then
        lsof -i:"$port" &> /dev/null
        return $?
    else
        # Bash fallback
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
        sudo dpkg -i cloudflared.deb || sudo apt-get install -f -y # Try to fix dependencies
    else
        print_message $YELLOW "Failed to download .deb, trying binary download..."
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
        print_message $RED "Failed to install cloudflared. Check output above and try manual installation."
        return 1
    fi
}

# === Management Functions ===

# Show status and recent logs
check_status_logs() {
    print_message $BLUE "Checking drosera.service status..."
    sudo systemctl status drosera.service --no-pager -l
    print_message $BLUE "\nLast 15 lines of drosera.service log:"
    sudo journalctl -u drosera.service -n 15 --no-pager -l
    print_message $YELLOW "To view logs in real-time use: sudo journalctl -u drosera.service -f"
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
    sleep 2 # Give time to start before checking status
    sudo systemctl status drosera.service --no-pager -l
}

# Backup function (SystemD) - CREATES ARCHIVE ONLY
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

    # Check for key components
    if [ ! -d "$trap_dir" ]; then
        print_message $RED "Error: Trap directory ($trap_dir) not found. Backup impossible."
        return 1
    fi
    if [ ! -f "$operator_env_file" ]; then
        print_message $RED "Error: Operator env file ($operator_env_file) not found. Backup impossible."
        return 1
    fi
     if [ ! -f "$service_file" ]; then
        print_message $YELLOW "Warning: Service file ($service_file) not found. Backup will be incomplete."
    fi
    
    # Find binary path
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
        # Try to restart service if it was stopped
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
        print_message $GREEN "File $operator_env_file found."
        # Use -v for verbose output. sudo not needed as we run as root.
        if cp -v "$operator_env_file" "$backup_dir/"; then
            print_message $GREEN "Successfully copied $operator_env_file to $backup_dir"
        else
            print_message $RED "Error copying $operator_env_file (Error code: $?). Check permissions on $backup_dir."
        fi
    else
        print_message $RED "Error: File $operator_env_file NOT FOUND at specified path!"
    fi

    # Copy service file
    print_message $BLUE "Attempting to copy $service_file..."
    if [ -f "$service_file" ]; then
        print_message $GREEN "File $service_file found."
        # Use -v. sudo not needed.
        if cp -v "$service_file" "$backup_dir/"; then
           print_message $GREEN "Successfully copied $service_file to $backup_dir"
        else
           print_message $RED "Error copying $service_file (Error code: $?)."
        fi
    else
        print_message $YELLOW "Warning: Service file $service_file NOT FOUND."
    fi

    # Copy operator binary
    if [ -n "$operator_bin" ] && [ -f "$operator_bin" ]; then
        print_message $BLUE "Attempting to copy binary $operator_bin..."
        if cp -v "$operator_bin" "$backup_dir/"; then
            print_message $GREEN "Successfully copied binary $operator_bin"
            # Save binary path for restore
            echo "OPERATOR_BIN_PATH=$operator_bin" > "$backup_dir/restore_info.txt"
        else
            print_message $YELLOW "Error copying $operator_bin (Error code: $?)."
        fi
    fi

    print_message $BLUE "Creating archive $backup_archive..."
    if tar czf "$backup_archive" -C "$backup_base_dir" "drosera_backup_$backup_date"; then
        print_message $GREEN "Backup successfully created: $backup_archive"
        print_message $YELLOW "PLEASE copy this file to a safe location (not on this VPS)!"
        print_message $YELLOW "Archive contains your private key in .drosera_operator.env file!"
    else
        print_message $RED "Error creating archive."
    fi

    print_message $BLUE "Cleaning up temporary backup directory..."
    rm -rf "$backup_dir" 
    # Could remove $backup_base_dir if empty, but leaving for now
    # find "$backup_base_dir" -maxdepth 0 -empty -delete

    print_message $BLUE "Starting drosera.service..."
    sudo systemctl start drosera.service
    print_message $BLUE "--- Backup creation complete ---"
    return 0
}

# New function to create and serve backup via URL
backup_and_serve_systemd() {
    print_message $BLUE "--- Creating and serving backup via URL ---"

    # 1. Create temporary directory with backup files
    local backup_files_dir
    # Call original backup function, it returns path to directory
    backup_files_dir=$(backup_node_systemd) 
    local backup_exit_code=$?
    
    if [[ $backup_exit_code -ne 0 ]] || [[ -z "$backup_files_dir" ]] || [[ ! -d "$backup_files_dir" ]]; then
        print_message $RED "Failed to create backup files directory. URL serving canceled."
        # Ensure service is started if backup was interrupted after stopping
        sudo systemctl start drosera.service 2>/dev/null
        return 1
    fi
    
    print_message $BLUE "Backup files prepared in: $backup_files_dir"
    
    # 2. Create archive from this directory
    local archive_name="drosera_backup_$(basename "$backup_files_dir" | sed 's/drosera_backup_//').tar.gz"
    local archive_path="$HOME/$archive_name"
    print_message $BLUE "Creating archive $archive_name..."
    if ! tar czf "$archive_path" -C "$(dirname "$backup_files_dir")" "$(basename "$backup_files_dir")"; then
        print_message $RED "Error creating archive $archive_path."
        rm -rf "$backup_files_dir"
        return 1
    fi
    print_message $GREEN "Archive successfully created: $archive_path"
    
    # 3. Clean temporary files directory (archive remains)
    print_message $BLUE "Cleaning temporary files directory..."
    rm -rf "$backup_files_dir"

    # 4. Check and install dependencies for server
    install_python3 || return 1
    install_cloudflared || return 1
    # Check for nc/lsof for port checking
    if ! command -v nc &> /dev/null && ! command -v lsof &> /dev/null; then
        print_message $BLUE "Installing netcat/lsof for port checking..."
        sudo apt-get update && sudo apt-get install -y netcat lsof
    fi

    # 5. Start server and tunnel
    local PORT=8000
    local MAX_RETRIES=10
    local RETRY_COUNT=0
    local SERVER_STARTED=false
    local HTTP_SERVER_PID=""
    local CLOUDFLARED_PID=""
    local TUNNEL_URL=""

    # Go to home directory to serve files from there
    cd ~ || { print_message $RED "Failed to change to home directory."; return 1; }

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
        sleep 3 # Give time to start

        if ! ps -p $HTTP_SERVER_PID > /dev/null; then
            print_message $RED "Failed to start HTTP server on port $PORT."
            cat "$temp_log_http"
            rm -f "$temp_log_http"
            PORT=$((PORT + 1))
            RETRY_COUNT=$((RETRY_COUNT + 1))
            continue
        fi
        print_message $GREEN "HTTP server started on port $PORT (PID: $HTTP_SERVER_PID)."
        rm -f "$temp_log_http" # Log no longer needed

        # Start Cloudflared tunnel
        print_message $BLUE "Starting cloudflared tunnel to http://localhost:$PORT..."
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
            # Stop server and tunnel, try next port
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
            rm -f "$temp_log_cf" # Log no longer needed
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
        wait $HTTP_SERVER_PID 2>/dev/null # Wait for completion
        wait $CLOUDFLARED_PID 2>/dev/null
        print_message $GREEN "Servers stopped."
        # Exit script or return to menu?
        # For now just exit
        exit 0 # Or just return if we want to return to menu
    }

    # Print URL
    print_message $GREEN "========================================================="
    print_message $GREEN "Backup available for download at:"
    print_message $YELLOW "$TUNNEL_URL/$(basename "$archive_path")"
    print_message $GREEN "========================================================="
    print_message $YELLOW "Link is active while this script is running."
    print_message $YELLOW "Press Ctrl+C to stop server and exit."

    # Wait for Ctrl+C (wait without arguments waits for all background processes)
    wait $HTTP_SERVER_PID $CLOUDFLARED_PID
    # If we got here without Ctrl+C (unlikely), clean up anyway
    cleanup_server 
    return 0 # Return to menu after Ctrl+C (if no exit 0 in trap)
}

# === Main installation function (from Kazuha script) ===
install_drosera_systemd() {
    # Keep this function as is, it performs steps 1-13
    # Add check if installation was run before
    if [ -f "/etc/systemd/system/drosera.service" ]; then
        print_message $YELLOW "It appears Drosera (SystemD) was already installed."
        read -p "Are you sure you want to reinstall? This will delete some old files and reinstall components. (y/N): " confirm_reinstall
        if [[ ! "$confirm_reinstall" =~ ^[Yy]$ ]]; then
            print_message $YELLOW "Reinstallation canceled."
            return 1
        fi
        # Stop and disable old service before reinstallation
        sudo systemctl stop drosera.service 2>/dev/null
        sudo systemctl disable drosera.service 2>/dev/null
    fi

    # === BANNER REMOVED ===
    # print_banner() { ... } # Function definition removed
    clear
    # print_banner # Function call removed
    # === BANNER REMOVED ===

    echo "🚀 Drosera Full Auto Install (SystemD Only)"

    # === 1. User Inputs ===
    read -p "📧 GitHub email: " GHEMAIL
    read -p "👩‍💻 GitHub username: " GHUSER
    read -p "🔐 Drosera private key (without 0x): " PK_RAW # Request without 0x
    read -p "🌍 VPS public IP: " VPSIP
    read -p "📬 Public address for whitelist (0x...): " OP_ADDR
    # Add RPC request
    read -p "🔗 Holesky RPC URL (e.g., Alchemy): " ETH_RPC_URL

    # Remove 0x prefix from key if entered
    PK=${PK_RAW#0x}

    # Key format check (64 hex chars)
    if ! [[ "$PK" =~ ^[a-fA-F0-9]{64}$ ]]; then
        echo "❌ Invalid private key format. Must be 64 hexadecimal characters."
        exit 1
    fi

    # Address format check (0x + 40 hex chars)
    if ! [[ "$OP_ADDR" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
        echo "❌ Invalid Whitelist address format. Must start with 0x and contain 40 hex characters."
        exit 1
    fi
    
    # RPC URL format check
    if [[ -z "$ETH_RPC_URL" || (! "$ETH_RPC_URL" =~ ^https?:// && ! "$ETH_RPC_URL" =~ ^wss?://) ]]; then
        echo "❌ Invalid RPC URL format. Must start with http://, https://, ws:// or wss://."
        # Use standard as fallback?
        echo "Attempting to use standard RPC: https://ethereum-holesky-rpc.publicnode.com"
        ETH_RPC_URL="https://ethereum-holesky-rpc.publicnode.com"
        # Or better to abort?
        # exit 1
    fi

    for var in GHEMAIL GHUSER PK VPSIP OP_ADDR ETH_RPC_URL; do
        if [[ -z "${!var}" ]]; then
            echo "❌ $var is required."
            exit 1
        fi
    done

    echo "--------------------------------------------------"
    echo "Verify entered data:"
    echo "Email: $GHEMAIL"
    echo "Username: $GHUSER"
    echo "Private Key: <hidden>"
    echo "VPS IP: $VPSIP"
    echo "Whitelist Address: $OP_ADDR"
    echo "RPC URL: $ETH_RPC_URL" # Added RPC output
    echo "--------------------------------------------------"
    read -p "Is everything correct? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Installation canceled."
        exit 1
    fi


    # === 2. Install Dependencies ===
    echo "⚙️ Installing dependencies..."
    sudo apt-get update && sudo apt-get upgrade -y
    sudo apt install -y curl ufw build-essential git wget jq make gcc nano automake autoconf tmux htop pkg-config libssl-dev tar clang bsdmainutils ca-certificates gnupg unzip lz4 nvme-cli libgbm1 libleveldb-dev || { echo "❌ Error installing dependencies."; exit 1; }


    # === 3. Install Drosera CLI ===
    echo "💧 Installing Drosera CLI..."
    curl -L https://app.drosera.io/install | bash || { echo "❌ Error installing Drosera CLI."; exit 1; }
    if ! grep -q '$HOME/.drosera/bin' ~/.bashrc; then
      echo 'export PATH="$HOME/.drosera/bin:$PATH"' >> ~/.bashrc
    fi
    export PATH="$HOME/.drosera/bin:$PATH"
    droseraup || { echo "❌ Error updating Drosera CLI."; exit 1; }


    # === 4. Install Foundry ===
    echo "🛠️ Installing Foundry..."
    curl -L https://foundry.paradigm.xyz | bash || { echo "❌ Error installing Foundry."; exit 1; }
    if ! grep -q '$HOME/.foundry/bin' ~/.bashrc; then
      echo 'export PATH="$HOME/.foundry/bin:$PATH"' >> ~/.bashrc
    fi
    export PATH="$HOME/.foundry/bin:$PATH"
    foundryup || { echo "❌ Error updating Foundry."; exit 1; }


    # === 5. Install Bun ===
    echo "📦 Installing Bun..."
    curl -fsSL https://bun.sh/install | bash || { echo "❌ Error installing Bun."; exit 1; }
    if ! grep -q '$HOME/.bun/bin' ~/.bashrc; then
      echo 'export PATH="$HOME/.bun/bin:$PATH"' >> ~/.bashrc
    fi
    export PATH="$HOME/.bun/bin:$PATH"


    # === 6. Clean Old Directories ===
    echo "🧹 Cleaning previous directories..."
    # Add -f to ignore non-existent files/folders
    rm -rf ~/drosera_operator ~/my-drosera-trap ~/.drosera/.env # Remove old operator files and env
    # Better not to delete .drosera folder itself to avoid CLI reinstallation


    # === 7. Set Up Trap ===
    echo "🔧 Setting up Trap..."
    mkdir -p ~/my-drosera-trap && cd ~/my-drosera-trap || { echo "❌ Failed to create/enter ~/my-drosera-trap."; exit 1; }

    echo "👤 Configuring Git..."
    git config --global user.email "$GHEMAIL"
    git config --global user.name "$GHUSER"

    echo "⏳ Initializing Trap project (may take time)..."
    if ! timeout 300 forge init -t drosera-network/trap-foundry-template; then
        echo "❌ Error initializing Trap via forge init (possible timeout or template issue)."
        exit 1
    fi

    echo "📦 Installing Bun dependencies..."
    if ! timeout 300 bun install; then
         echo "❌ Error installing Bun dependencies."
         echo "Attempting to clean node_modules and retry..."
         rm -rf node_modules bun.lockb
         if ! timeout 300 bun install; then
             echo "❌ Error reinstalling Bun dependencies."
             exit 1
         fi
    fi

    echo "🧱 Compiling Trap..."
    if ! forge build; then
        echo "❌ Error compiling Trap."
        exit 1
    fi


    # === 8. Deploy Trap ===
    echo "🚀 Deploying Trap to Holesky (using RPC: $ETH_RPC_URL)..."
    LOG_FILE="/tmp/drosera_deploy.log"
    TRAP_NAME="mytrap"
    echo "Using trap name: $TRAP_NAME"
    rm -f "$LOG_FILE"

    # Add --eth-rpc-url
    if ! DROSERA_PRIVATE_KEY=$PK drosera apply --eth-rpc-url "$ETH_RPC_URL" <<< "ofc" | tee "$LOG_FILE"; then
        echo "❌ Error deploying Trap."
        cat "$LOG_FILE" # Show error log
        exit 1
    fi

    # Extract Trap address from log
    TRAP_ADDR=$(grep -oP "(?<=address: )0x[a-fA-F0-9]{40}" "$LOG_FILE" | head -n 1)

    if [[ -z "$TRAP_ADDR" || "$TRAP_ADDR" == "0x" ]]; then
        echo "❌ Failed to determine deployed Trap address from log:"
        cat "$LOG_FILE"
        exit 1
    fi
    echo "🪤 Trap successfully deployed at: $TRAP_ADDR"


    # === 9. Whitelist Operator ===
    echo "🔐 Updating drosera.toml for Whitelist..."
    # Use awk for safe update/addition
    temp_toml=$(mktemp)
    awk -v addr="$OP_ADDR" \
        '/^private_trap *=/{private_found=1; print "private_trap = true"; next} \
         /^whitelist *=/{whitelist_found=1; print "whitelist = [\"" addr "\"]"; next} \
         {print} \
         END { \
             if(!private_found) print "private_trap = true"; \
             if(!whitelist_found) print "whitelist = [\"" addr "\"]" \
         }' drosera.toml > "$temp_toml" \
    && mv "$temp_toml" drosera.toml || { echo "❌ Error updating drosera.toml"; rm -f "$temp_toml"; exit 1; }

    echo "File drosera.toml updated."


    # === 10. Wait & Reapply ===
    echo "⏳ Waiting 10 minutes (600 seconds) before reapplying configuration with Whitelist..."
    sleep 600
    echo "🚀 Reapplying Trap configuration with Whitelist (using RPC: $ETH_RPC_URL)..."
    rm -f "$LOG_FILE"
    # Add --eth-rpc-url
    if ! DROSERA_PRIVATE_KEY=$PK drosera apply --eth-rpc-url "$ETH_RPC_URL" <<< "ofc" | tee "$LOG_FILE"; then
        echo "❌ Error reapplying Trap configuration."
        cat "$LOG_FILE"
        exit 1
    fi
    echo "✅ Trap configuration with Whitelist successfully applied."


    # === 11. Download Operator Binary ===
    echo "🔽 Downloading operator binary..."
    cd ~ || exit 1
    OPERATOR_CLI_URL="https://github.com/drosera-network/releases/releases/download/v1.16.2/drosera-operator-v1.16.2-x86_64-unknown-linux-gnu.tar.gz"
    OPERATOR_CLI_ARCHIVE=$(basename $OPERATOR_CLI_URL)
    OPERATOR_CLI_BIN="drosera-operator"

    # Remove old files
    rm -f "$OPERATOR_CLI_ARCHIVE" "$OPERATOR_CLI_BIN" "/usr/local/bin/$OPERATOR_CLI_BIN"

    if ! curl -fLO "$OPERATOR_CLI_URL"; then
        echo "❌ Error downloading operator archive."
        exit 1
    fi

    echo "📦 Extracting operator archive..."
    if ! tar -xvf "$OPERATOR_CLI_ARCHIVE"; then
        echo "❌ Error extracting operator archive."
        rm -f "$OPERATOR_CLI_ARCHIVE"
        exit 1
    fi

    echo "🚀 Installing operator binary to /usr/local/bin..."
    if ! sudo mv "$OPERATOR_CLI_BIN" /usr/local/bin/; then
        echo "❌ Error moving $OPERATOR_CLI_BIN to /usr/local/bin/. Check sudo permissions."
        rm -f "$OPERATOR_CLI_ARCHIVE"
        # Leave binary in ~ for manual installation
        exit 1
    fi
    sudo chmod +x /usr/local/bin/drosera-operator # Give execute permissions

    # Post-install check
    if ! command -v drosera-operator &> /dev/null; then
        echo "❌ Could not find drosera-operator in PATH after installation."
        rm -f "$OPERATOR_CLI_ARCHIVE"
        exit 1
    else
        echo "✅ Operator CLI successfully installed."
        rm -f "$OPERATOR_CLI_ARCHIVE" # Remove archive
    fi


    # === 12. Register Operator ===
    echo "✍️ Registering operator (using RPC: $ETH_RPC_URL)..."
    # Use entered RPC instead of drpc.org
    if ! drosera-operator register --eth-rpc-url "$ETH_RPC_URL" --eth-private-key $PK; then
        echo "❌ Error registering operator."
        exit 1
    fi
    echo "✅ Operator successfully registered."


    # === 13. Setup SystemD ===
    echo "⚙️ Configuring SystemD service..."
    SERVICE_FILE="/etc/systemd/system/drosera.service"
    # Define env file in /root as in working configuration
    OPERATOR_ENV_FILE="/root/.drosera_operator.env" 

    echo "Creating environment file $OPERATOR_ENV_FILE..."
    # Ensure /root directory exists (though it should)
    sudo mkdir -p /root 
    sudo bash -c "cat > $OPERATOR_ENV_FILE" << EOF
ETH_PRIVATE_KEY=$PK
VPS_IP=$VPSIP
ETH_RPC_URL=$ETH_RPC_URL
EOF
    sudo chmod 600 "$OPERATOR_ENV_FILE" # Secure permissions

    echo "Creating service file $SERVICE_FILE..."
    # Use final working version of service file
    sudo tee "$SERVICE_FILE" > /dev/null << EOF
[Unit]
Description=Drosera Operator Service
After=network.target

[Service]
# Run as root user since .env file and .db file are in /root
User=root
Group=root
WorkingDirectory=/root

# Path to environment variables file (private key, IP, RPC URL)
EnvironmentFile=$OPERATOR_ENV_FILE

# Command to start operator with all required flags
# Values \${ETH_RPC_URL}, \${ETH_PRIVATE_KEY} and \${VPS_IP} will be substituted from EnvironmentFile
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

# Restart service on failure
Restart=on-failure
RestartSec=10

# Increase open files limit
LimitNOFILE=65535

[Install]
# Start service at boot for multi-user levels
WantedBy=multi-user.target
EOF

    # Firewall (UFW) setup before starting service
    echo "🔧 Configuring Firewall (UFW) rules..."
    sudo ufw allow 22/tcp comment 'Allow SSH'
    sudo ufw allow 31313/tcp comment 'Allow Drosera P2P'
    sudo ufw allow 31314/tcp comment 'Allow Drosera Server'
    # Script doesn't activate ufw, assuming user manages it themselves,
    # but required ports will be open if ufw is active.

    echo "🔄 Reloading SystemD daemon and starting service..."
    sudo systemctl daemon-reload
    sudo systemctl enable drosera.service
    sudo systemctl restart drosera.service

    # Check service status
    echo "⏳ Waiting 5 seconds for service to stabilize..."
    sleep 5
    echo "📊 Checking drosera.service status:"
    sudo systemctl status drosera.service --no-pager -l

echo "=================================================="
print_message $GREEN "✅ Drosera (SystemD) installation completed!"
echo "The main steps have been completed by the script:"
echo "  - Dependencies installed."
echo "  - Drosera CLI, Foundry, and Bun installed."
echo "  - Trap '$TRAP_NAME' deployed at address: $TRAP_ADDR"
echo "  - Operator $OP_ADDR added to Whitelist."
echo "  - Operator CLI installed."
echo "  - Operator registered (with RPC: $ETH_RPC_URL)."
echo "  - SystemD service 'drosera.service' configured and started."
echo ""
print_message $YELLOW "ℹ️ YOUR NEXT STEPS (MANDATORY):"
echo "  1. Check service status: sudo systemctl status drosera.service"
echo "     (Should show 'active (running)'. If not, check logs.)"
echo "  2. View service logs: sudo journalctl -u drosera.service -f -n 100"
echo "     (Ensure no critical errors. Initial 'InsufficientPeers' warnings are normal.)"
echo "  3. Visit the Drosera dashboard: https://app.drosera.io/"
echo "  4. Connect your operator wallet ($OP_ADDR)."
echo "  5. Locate your deployed Trap at address: $TRAP_ADDR (check 'Traps Owned' section)."
echo "  6. On your Trap page, click [Send Bloom Boost] and fund the Trap (with Holesky ETH)."
echo "     (This is required to reward operators and activate the Trap.)"
echo "  7. On your Trap page, click [Opt In]."
echo "     (This confirms your running operator agrees to serve the Trap.)"
echo "  8. Refresh the dashboard and ensure your operator appears under 'Operators Status' for your Trap (the bar should turn green)."
echo ""
print_message $YELLOW "ℹ️ Optional but HIGHLY RECOMMENDED:"
echo "  9. Check/Edit the service file to make sure your operator uses your custom RPC:"
echo "     sudo nano /etc/systemd/system/drosera.service"
echo "     Ensure the line with 'ExecStart=' includes the flag '--eth-rpc-url \"$ETH_RPC_URL\"'"
echo "     (We included this in the script, but double-checking is a good idea.)"
echo "     If changes were made: sudo systemctl daemon-reload && sudo systemctl restart drosera.service"
echo "=================================================="

echo "Installation completed by the main function."
# SystemD status check already performed at the end
return 0
}

# === Main Menu ===
main_menu() {
    while true; do
        clear
        print_message $GREEN "========= Drosera Node Management Menu (SystemD) ========"
        local status
        status=$(systemctl is-active drosera.service 2>/dev/null)
        echo -e "drosera.service status: $( [[ "$status" == "active" ]] && echo -e "${GREEN}Active${NC}" || echo -e "${RED}Inactive (${status:-not found})${NC}" )"
        print_message $BLUE "---------------------- Installation ----------------------"
        print_message $YELLOW " 1. Start full installation/reinstallation (SystemD)"
        print_message $BLUE "-------------------- Node Management ---------------------"
        print_message $GREEN " 2. Show status and latest logs"
        print_message $GREEN " 3. Start service"
        print_message $RED   " 4. Stop service"
        print_message $BLUE "---------------------- Maintenance -----------------------"
        print_message $YELLOW " 5. Create backup (archive only)"
        print_message $YELLOW " 6. Create and share backup via link"
        print_message $NC   " 7. Restore from backup (NOT IMPLEMENTED)"
        # print_message $YELLOW " 7. Re-register operator (NOT IMPLEMENTED)"
        # print_message $RED   " 8. Uninstall node (NOT IMPLEMENTED)"
        print_message $BLUE "----------------------------------------------------------"
        print_message $NC   " 0. Exit"
        print_message $BLUE "=========================================================="
        read -p "Choose an option: " choice

        case $choice in
            1) install_drosera_systemd ;; 
            2) check_status_logs ;;  
            3) start_node_systemd ;;   
            4) stop_node_systemd ;;    
            5) backup_node_systemd ;;   
            6) backup_and_serve_systemd ;;   
            7) print_message $RED "Restore functionality is not implemented yet." ;; 
            # 7) re_register_operator_menu ;; # Placeholder
            # 8) uninstall_node ;;    # Placeholder
            0) print_message $GREEN "Exiting."; exit 0 ;;
            *) print_message $RED "Invalid option.";;
        esac
        read -p "Press Enter to continue..."
    done
}

# === Entry Point ===
# Launch main menu
main_menu

# ======================================================================
# The original installer code from Kazuha script is now part of 
# install_drosera_systemd() and no longer needed below this line.
# You can safely delete everything below if the function is complete.
# ======================================================================
