#!/bin/bash

# --- INTERACTIVE INPUT ---
echo "------------------------------------------------"
echo "   n8n & CSF All-in-One Installer for Ubuntu"
echo "------------------------------------------------"

# Prompt for Domain
read -p "Enter your Domain (e.g., genzloot.com): " DOMAIN
if [[ -z "$DOMAIN" ]]; then
    echo "ERROR: Domain cannot be empty."
    exit 1
fi

# Prompt for Email
read -p "Enter your Email (for SSL/CSF): " EMAIL
if [[ -z "$EMAIL" ]]; then
    echo "ERROR: Email cannot be empty."
    exit 1
fi

TIMEZONE="Asia/Kolkata"

# --- INSTALLATION START ---

# 1. Update System & Install Dependencies
sudo apt update && sudo apt upgrade -y
sudo apt install -y perl libwww-perl liblwp-protocol-https-perl ipset wget tar curl jq

# 2. Install Docker & Docker Compose
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo apt install -y docker-compose-plugin

# 3. Create n8n Directory and Docker Compose
mkdir -p ~/n8n-docker && cd ~/n8n-docker

cat <<EOF > docker-compose.yaml
services:
  n8n:
    image: n8nio/n8n:latest
    restart: always
    ports:
      - "5678:5678"
    environment:
      - N8N_HOST=${DOMAIN}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - WEBHOOK_URL=https://${DOMAIN}/
      - N8N_SECURE_COOKIE=true
      - NODE_ENV=production
      - N8N_PUSH_BACKEND=sse
      - GENERIC_TIMEZONE=${TIMEZONE}
      - TZ=${TIMEZONE}
      - NODE_OPTIONS=--max-old-space-size=1024
      - N8N_DIAGNOSTICS_ENABLED=false
    volumes:
      - n8n_data:/home/node/.n8n

volumes:
  n8n_data:
EOF

# 4. Start n8n
sudo docker compose up -d

# 5. Install CSF (ConfigServer Security & Firewall)
cd /usr/src
sudo wget https://github.com/sentinelfirewall/sentinel/raw/refs/heads/main/csf.tgz
sudo tar -xzf csf.tgz
cd csf
sudo sh install.sh

# 6. Configure CSF for Docker and n8n
sudo sed -i "s/LF_ALERT_TO = \".*\"/LF_ALERT_TO = \"$EMAIL\"/" /etc/csf/csf.conf
sudo sed -i 's/TCP_IN = "/TCP_IN = "80,443,5678,/g' /etc/csf/csf.conf
sudo sed -i 's/TCP_OUT = "/TCP_OUT = "53,80,443,/' /etc/csf/csf.conf
sudo sed -i 's/UDP_OUT = "/UDP_OUT = "53,/' /etc/csf/csf.conf
sudo sed -i 's/TESTING = "1"/TESTING = "0"/g' /etc/csf/csf.conf
sudo sed -i 's/DOCKER = "0"/DOCKER = "1"/g' /etc/csf/csf.conf
sudo sed -i 's/ETH_DEVICE_SKIP = "/ETH_DEVICE_SKIP = "docker+,br-+,veth+,/' /etc/csf/csf.conf

# Silence Alerts
sudo sed -i 's/LF_EMAIL_ALERT = "1"/LF_EMAIL_ALERT = "0"/g' /etc/csf/csf.conf
sudo sed -i 's/PT_USERMEM = ".*"/PT_USERMEM = "0"/g' /etc/csf/csf.conf

# Allow Docker Bridge Networks
echo "172.17.0.0/16" >> /etc/csf/csf.allow
echo "172.18.0.0/16" >> /etc/csf/csf.allow
echo "iface:docker0" >> /etc/csf/csf.allow

# 7. Apply IP Forwarding for Docker
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf

# 8. Final Restart
sudo csf -r
sudo systemctl restart lfd
sudo systemctl restart docker
cd ~/n8n-docker && sudo docker compose up -d

echo "------------------------------------------------"
echo "✅ Setup Complete!"
echo "n8n Domain: https://${DOMAIN}"
echo "Admin Email: ${EMAIL}"
echo "------------------------------------------------"
