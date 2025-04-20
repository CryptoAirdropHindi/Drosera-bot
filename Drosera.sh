#!/bin/bash

echo "CREATED JANETF.ETH"
echo "Drosera auto install"

# 1. User inputs
read -p "Enter your GitHub email: " GHEMAIL
read -p "Enter your GitHub username: " GHUSER
read -p "Enter your Drosera private key (starts with 0x): " PK
read -p "Enter your VPS public IP: " VPSIP
read -p "Do you want to use custom RPC endpoints? (y/n): " USE_CUSTOM_RPC
if [[ $USE_CUSTOM_RPC =~ ^[Yy]$ ]]; then
    read -p "Enter your primary Holesky RPC URL: " PRIMARY_RPC_URL
    read -p "Enter your backup Holesky RPC URL (press Enter to skip): " BACKUP_RPC_URL
    
    if [ -z "$PRIMARY_RPC_URL" ]; then
        print_error "Primary RPC URL cannot be empty"
        exit 1
    fi
else
    PRIMARY_RPC_URL="https://ethereum-holesky-rpc.publicnode.com"
    BACKUP_RPC_URL="https://1rpc.io/holesky"
fi

if [[ -z "$PK" || -z "$VPSIP" || -z "$GHEMAIL" || -z "$GHUSER" ]]; then
  echo "❌ Missing info. All fields are required."
  exit 1
fi

# 2. Install dependencies
echo "📦 Installing dependencies..."
sudo apt-get update && sudo apt-get upgrade -y
sudo apt install curl ufw iptables build-essential git wget lz4 jq make gcc nano automake autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip libleveldb-dev -y

# 3. Install Drosera CLI
curl -L https://app.drosera.io/install | bash
source ~/.bashrc
droseraup

# 4. Install Foundry CLI
curl -L https://foundry.paradigm.xyz | bash
source ~/.bashrc
foundryup

# 5. Install Bun
curl -fsSL https://bun.sh/install | bash
source ~/.bashrc

# 6. Set up drosera trap project
mkdir -p ~/my-drosera-trap && cd ~/my-drosera-trap
git config --global user.email "$GHEMAIL"
git config --global user.name "$GHUSER"
forge init -t drosera-network/trap-foundry-template

# 7. Build trap
bun install
forge build

# 8. Deploy Trap (1st apply)
echo "Deploying trap to Holesky, your wallet need balance of holesky eth buddy"
DROSERA_PRIVATE_KEY=$PK drosera apply <<< "ofc"

# 9. Edit drosera.toml to whitelist operator
echo "Whitelisting operator..."
cd ~/my-drosera-trap
read -p "📬 Enter the PUBLIC address linked to your used private key (starts with 0x): " OP_ADDR

if [[ -z "$OP_ADDR" ]]; then
  echo "❌ Public address is required to whitelist operator."
  exit 1
fi
echo -e '\nprivate_trap = true\nwhitelist = ["'"$OP_ADDR"'"]' >> drosera.toml

# 10. Deploy Trap again (2nd apply)
echo "Re-applying trap config with whitelist..."
DROSERA_PRIVATE_KEY=$PK drosera apply <<< "ofc"

# 11. Download operator binary
cd ~
curl -LO https://github.com/drosera-network/releases/releases/download/v1.16.2/drosera-operator-v1.16.2-x86_64-unknown-linux-gnu.tar.gz
tar -xvf drosera-operator-v1.16.2-x86_64-unknown-linux-gnu.tar.gz
sudo cp drosera-operator /usr/bin
chmod +x /usr/bin/drosera-operator

# 12. Register operator
echo "Registering operator..."
drosera-operator register --eth-rpc-url https://ethereum-holesky-rpc.publicnode.com --eth-private-key $PK

# 13. Open ports
sudo ufw disable

# 14. Create systemd service
echo "Setting up systemd service..."

# Check if the user is root or not
CURRENT_USER=$(whoami)
if [ "$CURRENT_USER" != "root" ]; then
  USER=$CURRENT_USER
else
  USER="root"
fi

# Use the username dynamically instead of hardcoding root
sudo tee /etc/systemd/system/drosera.service > /dev/null <<EOF
[Unit]
Description=drosera node service
After=network-online.target

[Service]
User=$USER
Restart=always
RestartSec=15
LimitNOFILE=65535
ExecStart=/usr/bin/drosera-operator node --db-file-path /home/$USER/.drosera.db --network-p2p-port 31313 --server-port 31314 \\
    --eth-rpc-url https://ethereum-holesky-rpc.publicnode.com \\
    --eth-backup-rpc-url https://1rpc.io/holesky \\
    --drosera-address 0xea08f7d533C2b9A62F40D5326214f39a8E3A32F8 \\
    --eth-private-key $PK \\
    --listen-address 0.0.0.0 \\
    --network-external-p2p-address $VPSIP \\
    --disable-dnr-confirmation true

[Install]
WantedBy=multi-user.target
EOF

# 15. Start systemd service
sudo systemctl daemon-reload
sudo systemctl enable drosera
sudo systemctl start drosera

# ⚠️ Trap must be deployed at this point!

# Parse deployed trap address from drosera apply log
TRAP_ADDR=$(cat ~/.drosera/deployments.json | jq -r '.[0].trapAddress')

if [[ -z "$TRAP_ADDR" || "$TRAP_ADDR" == "null" ]]; then
  echo "❌ Could not auto-detect trap address. Please check manually in the Drosera dashboard."
  exit 1
fi

BLOOM_URL="https://app.drosera.io/trap?trapId=$TRAP_ADDR"

echo ""
echo "🌱 Your trap has been deployed at: $TRAP_ADDR"
echo "💸 You MUST send Bloom Boost to it before continuing."
echo "🧭 Go to this link in your browser and click 'Send Bloom Boost':"
echo ""
echo "👉 $BLOOM_URL"
echo ""
read -p "⏳ Press Enter once you've sent the Bloom Boost..."

# 16. Run dryrun
echo "📡 Running drosera dryrun..."
drosera dryrun

# 17. Done
echo ""
echo "✅ All done. Node running via systemd."
echo "💻 Logs: journalctl -u drosera -f"
echo "🌐 Dashboard: https://app.drosera.io"
