#!/bin/bash

clear

center_text() {
  local text="$1"
  local width=$(tput cols)
  local padding=$(( (width - ${#text}) / 2 ))
  printf "%*s%s\n" $padding "" "$text"
}

line=$(printf '=%.0s' $(seq 1 $(tput cols)))

echo "$line"
center_text "SETUP DROSERA NODE"
echo "$line"

echo "1. Setup Full Node + Deploy Trap"
echo "2. Run 1 address Operator"
echo "3. Setup with docker"
read -p "Choose opsi (1, 2 or 3): " choose

if [ "$choose" == "1" ]; then

clear
echo "Setup full node and deploy trap..."

echo "============================================="
echo        "INSTALL DEPENDENCIES & ENV"
echo "============================================="

echo "🚀 Updating and install dependencies..."
sudo apt-get update && sudo apt-get upgrade -y
sudo apt install curl ufw iptables build-essential git wget lz4 jq make gcc nano automake autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip -y

echo "🚀 Install Docker..."
sleep 3
sudo apt update -y && sudo apt upgrade -y
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do sudo apt-get remove $pkg; done
sleep 3

sudo apt-get update
sudo apt-get install ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update -y && sudo apt upgrade -y
sleep 5
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sleep 3

echo "🚀 Install Drosera CLI..."
sleep 2
curl -L https://app.drosera.io/install | bash
export PATH="$HOME/.drosera/bin:$PATH"
sleep 5
source ~/.bashrc
droseraup

echo "🚀 Install Foundry..."
curl -L https://foundry.paradigm.xyz | bash
export PATH="$HOME/.foundry/bin:$PATH"
sleep 5
source ~/.bashrc
foundryup

echo "🚀 Install Bun..."
sleep 2
curl -fsSL https://bun.sh/install | bash
export PATH="$HOME/.bun/bin:$PATH"
source ~/.bashrc

echo "============================================="
echo                 "SETUP TRAP"
echo "============================================="

echo " Setup Trap Project..."
cd ~
mkdir -p ~/my-drosera-trap
cd ~/my-drosera-trap

{
read -p "🔑 Masukkan GITHUB EMAIL: " GITHUB_EMAIL 
read -p "🔑 Masukkan GITHUB USERNAME: " GITHUB_USERNAME 
git config --global user.email "$GITHUB_EMAIL"
git config --global user.name "$GITHUB_USERNAME"
} | tee -a drosera.log

forge init -t drosera-network/trap-foundry-template
curl -fsSL https://bun.sh/install | bash
sleep 5
bun install
sleep 3
forge build


echo " Deploying Trap..."
read -p "🔑 Private Key EVM: " PRIVATE_KEY
DROSERA_PRIVATE_KEY="$PRIVATE_KEY" drosera apply

echo -e "\e[0;37m Login on website: \e[4;35mhttps://app.drosera.io/"
sleep 10
echo "Connect wallet burner"
sleep 10
echo "Click on Traps Owned to see your deployed Traps OR search your Trap address"
sleep 10
echo "Open your Trap on Dashboard and Click on Send Bloom Boost and deposit some Holesky ETH on it"
sleep 20
drosera dryrun

echo " Setting private trap config and whitelist operator..."
cd ~/my-drosera-trap
sleep 3
nano drosera.toml
sleep 5

read -p "🔑 Private Key EVM: " PRIVATE_KEY
DROSERA_PRIVATE_KEY="$PRIVATE_KEY" drosera apply
sleep 5

echo "============================================="
echo               "INSTALL OPERATOR"
echo "============================================="

echo " Install Operator CLI..."
cd ~
sleep 3
curl -LO https://github.com/drosera-network/releases/releases/download/v1.16.2/drosera-operator-v1.16.2-x86_64-unknown-linux-gnu.tar.gz
tar -xvf drosera-operator-v1.16.2-x86_64-unknown-linux-gnu.tar.gz
sudo cp drosera-operator /usr/bin

echo " Registering Operator..."
read -p "🔑 Private Key EVM: " PRIVATE_KEY
drosera-operator register --eth-rpc-url https://ethereum-holesky-rpc.publicnode.com --eth-private-key "$PRIVATE_KEY"

echo "============================================="
echo                "SYSTEMD SERVICE"
echo "============================================="

echo "📦 Make systemd service drosera..."
read -p "🔑 VPS Public IP Address: " VPS_IP 
read -p "🔐 ETH Private Key: " PRIVATE_KEY

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

echo "============================================="
echo             "SETUP UFW & RUN"
echo "============================================="

echo "️ Setting firewall and open port..."
sudo ufw allow ssh
sudo ufw allow 22
sudo ufw enable
sudo ufw allow 31313/tcp
sudo ufw allow 31314/tcp

echo " Running node Drosera..."
sudo systemctl daemon-reload
sudo systemctl enable drosera
sudo systemctl start drosera

echo " Sign OPT in..."
read -p "🔑 Private Key EVM: " PRIVATE_KEY
read -p "🔑 Private Key EVM: " TRAP_ADDRESS
drosera-operator optin --eth-rpc-url https://ethereum-holesky-rpc.publicnode.com --trap-config-address "$TRAP_ADDRESS" --eth-private-key "$PRIVATE_KEY"

echo "✅ Setup complete!"
echo "🔍 Checking node status..."
sleep 2
journalctl -u drosera.service -f

elif [ "$choose" == "2" ]; then

clear
echo "Make sure the wallet address has been whitelisted in drosera.toml beforehand"
sleep 10

echo "============================================="
echo        "INSTALL DEPENDENCIES & ENV"
echo "============================================="

echo "🚀 Install Drosera CLI..."
sleep 2
curl -L https://app.drosera.io/install | bash
export PATH="$HOME/.drosera/bin:$PATH"
sleep 5
source ~/.bashrc
droseraup
sleep 5

echo "============================================="
echo               "INSTALL OPERATOR"
echo "============================================="

echo " Install Operator CLI..."
cd ~
sleep 3
curl -LO https://github.com/drosera-network/releases/releases/download/v1.16.2/drosera-operator-v1.16.2-x86_64-unknown-linux-gnu.tar.gz
tar -xvf drosera-operator-v1.16.2-x86_64-unknown-linux-gnu.tar.gz
sudo cp drosera-operator /usr/bin
sleep 5

echo " Registering Operator..."
read -p "🔑 Private Key EVM: " PRIVATE_KEY
drosera-operator register --eth-rpc-url https://ethereum-holesky-rpc.publicnode.com --eth-private-key "$PRIVATE_KEY"
sleep 5

echo "============================================="
echo                "SYSTEMD SERVICE"
echo "============================================="

echo "📦 Make systemd service drosera..."
read -p "🔑 VPS Public IP Address: " VPS_IP 
read -p "🔐 ETH Private Key: " PRIVATE_KEY

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

echo "============================================="
echo             "SETUP UFW & RUN"
echo "============================================="

echo "️ Setting firewall and open port..."
sudo ufw allow ssh
sudo ufw allow 22
sudo ufw enable
sudo ufw allow 31313/tcp
sudo ufw allow 31314/tcp

echo " Running node Drosera..."
sudo systemctl daemon-reload
sudo systemctl enable drosera
sudo systemctl start drosera
sleep 5

echo " Sign OPT in..."
read -p "🔑 Private Key EVM: " PRIVATE_KEY
read -p "🔑 Private Key EVM: " TRAP_ADDRESS
drosera-operator optin --eth-rpc-url https://ethereum-holesky-rpc.publicnode.com --trap-config-address "$TRAP_ADDRESS" --eth-private-key "$PRIVATE_KEY"

echo "✅ Setup complete!"
echo "🔍 Checking node status..."
sleep 2
journalctl -u drosera.service -f

if [ "$choose" == "3" ]; then

clear
echo " Setup using docker..."
  echo "🚀 Install Docker..."
sleep 3
sudo apt update -y && sudo apt upgrade -y
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do sudo apt-get remove $pkg; done
sleep 3

sudo apt-get update
sudo apt-get install ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update -y && sudo apt upgrade -y
sleep 5
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sleep 3
apt install git 
sleep 5

git clone https://github.com/0xmoei/Drosera-Network
sleep 3
cd Drosera-Network
sleep 3
cp .env.example .env
sleep 3
echo " Change PK and VPSIP"
sleep 5
nano .env
docker compose up -d
sleep 3
echo "✅ Setup complete!"
echo " Optional restart and stop docker..."
# Stop node
echo " cd Drosera-Network"
echo " docker compose down -v"

# Restart node
echo " cd Drosera-Network "
echo " docker compose up -d"
echo "🔍 Checking node status..."

cd Drosera-Network
docker compose logs -f

else
    echo "❌ Choose not valid. Running again script."
    exit 1
fi
