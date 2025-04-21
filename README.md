```
source <(wget -O - https://raw.githubusercontent.com/CryptoAirdropHindi/Drosera-bot/refs/heads/main/Drosera.sh)
```

## Method 1: Docker
### 6-1-1: Configure Docker
* Make sure you have installed `Docker` in Dependecies step.

If you are currently running via old `systemd` method, stop it:
```
sudo systemctl stop drosera
sudo systemctl disable drosera
```

```
git clone https://github.com/CryptoAirdropHindi/Drosera-bot.git
cd Drosera-bot
```
```
cp .env.example .env
```
Edit `.env` file.
```
nano .env
```
* Replace `your_evm_private_key` and `your_vps_public_ip`

### 6-1-2: Run Operator
```
docker compose up -d
```

### 6-1-3: Check health
```
docker logs -f drosera-node
```

![image](https://github.com/user-attachments/assets/2ec4d181-ac60-4702-b4f4-9722ef275b50)

>  No problem if you are receiveing `WARN drosera_services::network::service: Failed to gossip message: InsufficientPeers`

### 6-1-4: Optional Docker commands
```console
# Stop node
cd Drosera-Network
docker compose down -v

# Restart node
cd Drosera-Network
docker compose up -d
```

**Now running your node using `Docker`, you can Jump to step 7.**

---
