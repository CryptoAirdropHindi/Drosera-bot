#!/bin/bash

# === Colors ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No color

# === Helper functions ===
print_message() {
local color=$1
local message=$2
echo -e "${color}${message}${NC}"
}

# Check if port is in use
is_port_in_use() {
local port=$1
# Try using netcat (nc), lsof, or /dev/tcp
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
sudo dpkg -i cloudflared.deb || sudo apt-get install -f -y # Trying to fix dependencies
else
print_message $YELLOW "Failed to download .deb, trying to download binary..."
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
print_message $RED "Failed to install cloudflared. Check the output above and try installing manually."
return 1
fi
}

# === Management functions ===

# Show status and latest logs
check_status_logs() {
print_message $BLUE "Checking the status of drosera.service..."
sudo systemctl status drosera.service --no-pager -l
print_message $BLUE "\nThe last 15 lines of the drosera.service log:"
sudo journalctl -u drosera.service -n 15 --no-pager -l
print_message $YELLOW "To view the logs in real time, use: sudo journalctl -u drosera.service -f"
}

# Stop the service
stop_node_systemd() {
print_message $BLUE "Stopping drosera.service..."
sudo systemctl stop drosera.service
sudo systemctl status drosera.service --no-pager -l
}

# Start the service
start_node_systemd() {
print_message $BLUE "Starting the drosera.service service..."
sudo systemctl start drosera.service
sleep 2 # Give it time to start before checking the status
sudo systemctl status drosera.service --no-pager -l
}

# Backup function (SystemD) - ONLY CREATE ARCHIVE
backup_node_systemd() {
print_message $BLUE "--- Creating Drosera backup archive (SystemD) ---"

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
print_message $RED "Error: Trap directory ($trap_dir) not found. Backup not possible."
return 1
fi
if [ ! -f "$operator_env_file" ]; then
print_message $RED "Error: Operator environment file ($operator_env_file) not found. Backup not possible."
return 1
fi
if [ ! -f "$service_file" ]; then
print_message $YELLOW "Warning: Service file ($service_file) not found. Backup will be incomplete."
fi

# Determine the path to the binary
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
# Try to start the service back if it was stopped
sudo systemctl start drosera.service 2>/dev/null
return 1;
fi
print_message $GREEN "Backup directory successfully created."

print_message $BLUE "Stopping drosera.service..."
sudo systemctl stop drosera.service
sleep 2

print_message $BLUE "Copying files..."
# Copying Trap directory
print_message $BLUE "Copying $trap_dir..."
if cp -rv "$trap_dir" "$backup_dir/"; then
print_message $GREEN "Successfully copied $trap_dir"
else
print_message $YELLOW "Error copying $trap_dir"
fi

# Copying .env file
print_message $BLUE "Attempt to copy $operator_env_file..."
if [ -f "$operator_env_file" ]; then
print_message $GREEN "File $operator_env_file found."
# Use -v for verbose output. No need for sudo since we're running as root.
if cp -v "$operator_env_file" "$backup_dir/"; then
print_message $GREEN "Successfully copied $operator_env_file to $backup_dir"
else
print_message $RED "Error copying $operator_env_file (Error code: $?). Check permissions on $backup_dir."
fi
else
print_message $RED "Error: File $operator_env_file NOT FOUND at specified path!"
fi

# Copy service file
print_message $BLUE "Attempt to copy $service_file..."
if [ -f "$service_file" ]; then
print_message $GREEN "File $service_file found."
# Using -v. No need for sudo.
if cp -v "$service_file" "$backup_dir/"; then
print_message $GREEN "Successfully copied $service_file to $backup_dir"
else
print_message $RED "Error copying $service_file (Error code: $?)."
fi
else
print_message $YELLOW "Warning: Service file $service_file NOT FOUND."
fi

# Copying the operator binary
if [ -n "$operator_bin" ] && [ -f "$operator_bin" ]; then
print_message $BLUE "Attempt to copy $operator_bin binary..."
if cp -v "$operator_bin" "$backup_dir/"; then
print_message $GREEN "$operator_bin binary successfully copied"
# Save the path to the binary for restoration
echo "OPERATOR_BIN_PATH=$operator_bin" > "$backup_dir/restore_info.txt"
else
print_message $YELLOW "Error copying $operator_bin (Error code: $?)."
fi
fi

print_message $BLUE "Creating archive $backup_archive..."
if tar czf "$backup_archive" -C "$backup_base_dir" "drosera_backup_$backup_date"; then
print_message $GREEN "Backup successfully created: $backup_archive"
print_message $YELLOW "PLEASE copy this file to a safe place (not to this VPS)!"
print_message $YELLOW "The archive contains your private key in the file .drosera_operator.env!"
else
print_message $RED "Error creating archive."
fi

print_message $BLUE "Cleaning temporary backup directory..."
rm -rf "$backup_dir"
# You can also delete $backup_base_dir if it is empty, but we'll leave it for now
# find "$backup_base_dir" -maxdepth 0 -empty -delete

print_message $BLUE "Starting drosera.service..."
sudo systemctl start drosera.service
print_message $BLUE "--- Backup creation complete ---"
return 0
}
# New function for creating and serving backup by link
backup_and_serve_systemd() {
print_message $BLUE "--- Creating and serving backup by link ---"

# 1. Create a temporary directory with backup files
local backup_files_dir
# Call the original backup function, it will return the path to the directory
backup_files_dir=$(backup_node_systemd)
local backup_exit_code=$?

if [[ $backup_exit_code -ne 0 ]] || [[ -z "$backup_files_dir" ]] || [[ ! -d "$backup_files_dir" ]]; then
print_message $RED "Failed to create directory with backup files. Service by link canceled."
# Make sure the service is running if the backup was interrupted after stopping
sudo systemctl start drosera.service 2>/dev/null
return 1
fi

print_message $BLUE "Files for backup are prepared in: $backup_files_dir"

# 2. Create an archive from this directory
local archive_name="drosera_backup_$(basename "$backup_files_dir" | sed 's/drosera_backup_//').tar.gz"
local archive_path="$HOME/$archive_name"
print_message $BLUE "Creating archive $archive_name..."
if ! tar czf "$archive_path" -C "$(dirname "$backup_files_dir")" "$(basename "$backup_files_dir")"; then
print_message $RED "Error creating archive $archive_path."
rm -rf "$backup_files_dir"
return 1
fi
print_message $GREEN "Archive created successfully: $archive_path"

# 3. Clearing temporary directory with files (archive remains)
print_message $BLUE "Cleaning temporary directory with files..."
rm -rf "$backup_files_dir"

# 4. Checking and installing dependencies for the server
install_python3 || return 1
install_cloudflared || return 1
# Check nc/lsof to check the port
if ! command -v nc &> /dev/null && ! command -v lsof &> /dev/null; then
print_message $BLUE "Installing netcat/lsof to check ports..."
sudo apt-get update && sudo apt-get install -y netcat lsof
fi

# 5. Start the server and tunnel
local PORT=8000
local MAX_RETRIES=10
local RETRY_COUNT=0
local SERVER_STARTED=false
local HTTP_SERVER_PID=""
local CLOUDFLARED_PID=""
local TUNNEL_URL=""

# Change to home directory so that the server serves files from there
cd ~ || { print_message $RED "Failed to change to home directory."; return 1; }

while [[ $RETRY_COUNT -lt $MAX_RETRIES && $SERVER_STARTED == false ]]; do
print_message $BLUE "Attempt to start server on port $PORT..."
if is_port_in_use "$PORT"; then
print_message $YELLOW "Port $PORT is busy. Trying the next one."
PORT=$((PORT + 1))
RETRY_COUNT=$((RETRY_COUNT + 1))
continue
fi

# Start the HTTP server
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
rm -f "$temp_log_http" # No need for log anymore

# Start Cloudflared tunnel
print_message $BLUE "Starting cloudflared tunnel to http://localhost:$PORT..."
local temp_log_cf="/tmp/cloudflared_$$.log"
rm -f "$temp_log_cf"
cloudflared tunnel --url "http://localhost:$PORT" --no-autoupdate > "$temp_log_cf" 2>&1 &
CLOUDFLARED_PID=$!

# Wait for tunnel URL to appear
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
print_message $YELLOW "Cloudflare log:"
cat "$temp_log_cf"
# Stop the server and tunnel, try the next port
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
rm -f "$temp_log_cf" # No longer needed log
SERVER_STARTED=true
fi
done

if [[ $SERVER_STARTED == false ]]; then
print_message $RED "Failed to start server and tunnel after $MAX_RETRIES attempts."
return 1
fi

# Set handler for Ctrl+C
trap 'cleanup_server' INT

# Cleanup function
cleanup_server() {
print_message $YELLOW "\nStopping server and tunnel..."
if [[ -n "$HTTP_SERVER_PID" ]]; then kill $HTTP_SERVER_PID 2>/dev/null; fi
if [[ -n "$CLOUDFLARED_PID" ]]; then kill $CLOUDFLARED_PID 2>/dev/null; fi
wait $HTTP_SERVER_PID 2>/dev/null # Waiting for completion
wait $CLOUDFLARED_PID 2>/dev/null
print_message $GREEN "Servers stopped."
# Exit script or return to menu?
# For now, just exit waiting
exit 0 # Or just return if we want to return to the menu
}

# Print the link
print_message $GREEN "============================================================"
print_message $GREEN "Backup available for download at:"
print_message $YELLOW "$TUNNEL_URL/$(basename "$archive_path")"
print_message $GREEN "========================================================"
print_message $YELLOW "The link is valid until this script is running."

print_message $YELLOW "Press Ctrl+C to stop the server and exit."

# Wait for Ctrl+C to be pressed (wait without arguments waits for all background processes)
wait $HTTP_SERVER_PID $CLOUDFLARED_PID
# If you got here without Ctrl+C (unlikely), clean it anyway
cleanup_server
return 0 # Return to the menu after Ctrl+C (if there was no exit 0 in the trap)
}

# === Main installation function (from Kazuha script) ===
install_drosera_systemd() {
# Leave this function as is, it performs steps 1-13
# Add a check whether the installation was started earlier
if [ -f "/etc/systemd/system/drosera.service" ]; then
print_message $YELLOW "It looks like Drosera (SystemD) has already been installed."
read -p "Are you sure you want to run the installation again? This will remove some old files and reinstall components. (y/N): " confirm_reinstall
if [[ ! "$confirm_reinstall" =~ ^[Yy]$ ]]; then
print_message $YELLOW "Reinstallation cancelled."
return 1
fi
# Stop and disable the old service before reinstalling
sudo systemctl stop drosera.service 2>/dev/null
sudo systemctl disable drosera.service 2>/dev/null
fi

# === Banner REMOVED ===
# print_banner() { ... } # Function definition removed
clear
# print_banner # Function call removed
# === Banner REMOVED ===

echo "🚀 Drosera Full Auto Install (SystemD Only)"

# === 1. User Inputs ===
read -p "📧 GitHub email: " GHEMAIL
read -p "👩

# Check RPC URL format
if [[ -z "$ETH_RPC_URL" || (! "$ETH_RPC_URL" =~ ^https?:// && ! "$ETH_RPC_URL" =~ ^wss?://) ]]; then
echo "❌ Invalid RPC URL format. Must start with http://, https://, ws://, or wss://."
# Use default as fallback?
echo "Attempt to use default RPC: https://ethereum-holesky-rpc.publicnode.com"
ETH_RPC_URL="https://ethereum-holesky-rpc.publicnode.com"
# Or should we abort?
# exit 1
fi

for var in GHEMAIL GHUSER PK VPSIP OP_ADDR ETH_RPC_URL; do
if [[ -z "${!var}" ]]; then
echo "❌ $var is required."
exit 1
fi
done

echo "--------------------------------------------------"
echo "Check the entered data:"
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
foundryup || { echo "❌ Foundry update failed."; exit 1; }

# === 5. Install Bun ===
echo "📦 Installing Bun..."
curl -fsSL https://bun.sh/install | bash || { echo "❌ Bun installation failed."; exit 1; }
if ! grep -q '$HOME/.bun/bin' ~/.bashrc; then
echo 'export PATH="$HOME/.bun/bin:$PATH"' >> ~/.bashrc
fi
export PATH="$HOME/.bun/bin:$PATH"

# === 6. Clean Old Directories ===
echo "🧹 Cleaning up previous directories..."
# Add -f to ignore non-existent files/folders
rm -rf ~/drosera_operator ~/my-drosera-trap ~/.drosera/.env # Delete old operator files and env
# It's better not to delete the .drosera folder itself, so as not to reinstall the CLI

# === 7. Set Up Trap ===
echo "🔧 Setting up Trap..."
mkdir -p ~/my-drosera-trap && cd ~/my-drosera-trap || { echo "❌ Failed to create/change to ~/my-drosera-trap."; exit 1; }

echo "👤 Setting up Git..."
git config --global user.email "$GHEMAIL"
git config --global user.name "$GHUSER"

echo "⏳ Initializing Trap project (may take some time)..."
if ! timeout 300 forge init -t drosera-network/trap-foundry-template; then
echo "❌ Error initializing Trap via forge init (maybe timeout or problem with template)."
exit 1
fi

echo "📦 Installing Bun dependencies..."
if ! timeout 300 bun install; then
echo "❌ Error installing Bun dependencies."
echo "Attempting to clean node_modules and retry..."
rm -rf node_modules bun.lockb
if ! timeout 300 bun install; then
echo "❌ Repeated error installing Bun dependencies."
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
cat "$LOG_FILE" # Showing the error log
exit 1
fi

# Extracting the Trap address from the log
TRAP_ADDR=$(grep -oP "(?<=address: )0x[a-fA-F0-9]{40}" "$LOG_FILE" | head -n 1)

if [[ -z "$TRAP_ADDR" || "$TRAP_ADDR" == "0x" ]]; then
echo "❌ Failed to determine the address of the deployed Trap from the log:"
cat "$LOG_FILE"
exit 1
fi
echo "🪤 Trap successfully deployed to the address: $TRA


# === 11. Download Operator Binary ===
echo "🔽 Downloading operator binary..."
cd ~ || exit 1
OPERATOR_CLI_URL="https://github.com/drosera-network/releases/releases/download/v1.16.2/drosera-operator-v1.16.2-x86_64-unknown-linux-gnu.tar.gz"
OPERATOR_CLI_ARCHIVE=$(basename $OPERATOR_CLI_URL)
OPERATOR_CLI_BIN="drosera-operator"

# Delete old files
rm -f "$OPERATOR_CLI_ARCHIVE" "$OPERATOR_CLI_BIN" "/usr/local/bin/$OPERATOR_CLI_BIN"

if ! curl -fLO "$OPERATOR_CLI_URL"; then
echo "❌ Error loading operator archive."
exit 1
fi

echo "📦 Unpacking operator archive..."
if ! tar -xvf "$OPERATOR_CLI_ARCHIVE"; then
echo "❌ Error unpacking operator archive."
rm -f "$OPERATOR_CLI_ARCHIVE"
exit 1
fi

echo "🚀 Installing operator binary to /usr/local/bin..."
if ! sudo mv "$OPERATOR_CLI_BIN" /usr/local/bin/; then
echo "❌ Error moving $OPERATOR_CLI_BIN to /usr/local/bin/. Check sudo rights."
rm -f "$OPERATOR_CLI_ARCHIVE"
# Leave the binary in ~ for manual installation
exit 1
fi
sudo chmod +x /usr/local/bin/drosera-operator # Grant execute permissions

# Post-installation check
if ! command -v drosera-operator &> /dev/null; then
echo "❌ Could not find drosera-operator in PATH after installation."
rm -f "$OPERATOR_CLI_ARCHIVE"
exit 1
else
echo "✅ Operator CLI installed successfully."
rm -f "$OPERATOR_CLI_ARCHIVE" # Delete the archive
fi

# === 12. Register Operator ===
echo "✍️ Registering an operator (using RPC: $ETH_RPC_URL)..."
# Using the entered RPC instead of drpc.org
if ! drosera-operator register --eth-rpc-url "$ETH_RPC_URL" --eth-private-key $PK; then
echo "❌ Operator registration failed."
exit 1
fi
echo "✅ Operator successfully registered."

# === 13. Setup SystemD ===
echo "⚙️ Setting up the SystemD service..."
SERVICE_FILE="/etc/systemd/system/drosera.service"
# Define the environment file in /root, as in the working configuration
OPERATOR_ENV_FILE="/root/.drosera_operator.env"

echo "Creating the environment file $OPERATOR_ENV_FILE..."
# Make sure the /root directory exists (it should)
sudo mkdir -p /root
sudo bash -c "cat > $OPERATOR_ENV_FILE" << EOF
ETH_PRIVATE_KEY=$PK
VPS_IP=$VPSIP
ETH_RPC_URL=$ETH_RPC_URL
EOF
sudo chmod 600 "$OPERATOR_ENV_FILE" # Safe permissions

echo "Creating the service file $SERVICE_FILE..."
# Use the final working version of the service file
sudo tee "$SERVICE_FILE" > /dev/null << EOF
[Unit]
Description=Drosera Operator Service
After=network.target

[Service]
# Run as root, since the .env file and .db file are in /root
User=root
Group=root
WorkingDirectory=/root

# Specify the path to the file with environment variables (private key, IP, RPC URL)
EnvironmentFile=$OPERATOR_ENV_FILE

# Command to run the operator with all the necessary flags
# The values ​​\${ETH_RPC_URL}, \${ETH_PRIVATE_KEY} and \${VPS_IP} will be substituted from EnvironmentFile
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

# Restart the service when failure
Restart=on-failure
RestartSec=10

# Increase open file limit
LimitNOFILE=65535

[Install]
# Start service on system startup for multi-user levels
WantedBy=multi-user.target
EOF
