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
git clone https://github.com/0xmoei/Drosera-Network
```
```
cd Drosera-Network
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

### 6-2-3: Check Node Health
```console
journalctl -u drosera.service -f
```

![image](https://github.com/user-attachments/assets/a4ad6e66-4749-4780-9347-c878399d4067)

> !! No problem if you are receiveing `WARN drosera_services::network::service: Failed to gossip message: InsufficientPeers`

### 6-2-4: Optional commands
```console
# Stop node
sudo systemctl stop drosera

# Restart node
sudo systemctl restart drosera
```
**Now running your node using `SystemD`, you can Jump to step 7.**
---

## 7. Opt-in Trap
In the dashboard., Click on `Opti in` to connect your operator to the Trap

![image](https://github.com/user-attachments/assets/5189b5cb-cb46-4d10-938a-33f71951dfc2)

---

## 8. Check Node Liveness
Your node will start producing greeen blocks in the dashboard
