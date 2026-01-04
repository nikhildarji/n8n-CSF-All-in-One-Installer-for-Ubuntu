#!/bin/bash

# --- 1. Setup Logging ---
# This saves every command output to install.log for troubleshooting
LOG_FILE="install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "===================================================="
echo "    n8n & CSF Optimized Installer (v2.1)"
echo "    Log File: $(pwd)/$LOG_FILE"
echo "===================================================="

# --- 2. Interactive Prompts ---
read -p "Enter your Domain (e.g., misoltechnologysolutions.com): " DOMAIN
read -p "Enter your Email: " EMAIL

if [[ -z "$DOMAIN" || -z "$EMAIL" ]]; then
    echo "ERROR: Domain and Email are required."
    exit 1
fi

# --- 3. Clean & Update ---
echo "Cleaning old conflicts and updating system..."
sudo apt update && sudo apt upgrade -y
sudo apt remove -y certbot python3-certbot-nginx
sudo snap remove certbot || true

# --- 4. Install Nginx & Dependencies ---
echo "Installing Nginx and system tools..."
sudo apt install -y nginx perl libwww-perl liblwp-protocol-https-perl ipset wget tar curl jq docker-compose-plugin

# --- 5. Deploy n8n with Speed Variables ---
mkdir -p ~/n8n-docker && cd ~/n8n-docker
cat <<EOF > docker-compose.yaml
services:
  n8n:
    image: n8nio/n8n:latest
    restart: always
    environment:
      - N8N_HOST=${DOMAIN}
      - WEBHOOK_URL=https://${DOMAIN}/
      - N8N_PROTOCOL=https
      - N8N_PUSH_BACKEND=sse
      - NODE_OPTIONS=--max-old-space-size=1024
      - EXECUTIONS_DATA_PRUNE=true
      - EXECUTIONS_DATA_MAX_AGE=72
      - EXECUTIONS_DATA_SAVE_ON_SUCCESS=none
      - GENERIC_TIMEZONE=Asia/Kolkata
    volumes:
      - n8n_data:/home/node/.n8n
volumes:
  n8n_data:
EOF
sudo docker compose up -d

# --- 6. Fix Certbot Snap Lock & Get SSL ---
echo "Configuring Certbot..."
sudo snap install --classic certbot
sudo ln -sf /snap/bin/certbot /usr/bin/certbot
sudo snap set certbot trust-plugin-with-root=ok
sudo snap connect certbot:nginx
sudo certbot --nginx -d $DOMAIN -m $EMAIL --agree-tos --non-interactive

# --- 7. Optimize Nginx for Speed ---
echo "Applying Nginx performance tuning..."
cat <<EOF > /etc/nginx/sites-available/n8n
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name $DOMAIN;

    # SSL handled by Certbot automatically

    location / {
        proxy_pass http://localhost:5678;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # SPEED OPTIMIZATIONS
        proxy_buffering off;
        proxy_cache off;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_read_timeout 86400;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/n8n /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo systemctl restart nginx

# --- 8. Install CSF Firewall ---
echo "Hardening with CSF Firewall..."
cd /usr/src
sudo wget https://download.configserver.com/csf.tgz
sudo tar -xzf csf.tgz
cd csf
sudo sh install.sh

# CSF Speed & Docker Fixes
sudo sed -i 's/TESTING = "1"/TESTING = "0"/g' /etc/csf/csf.conf
sudo sed -i 's/TCP_IN = "/TCP_IN = "80,443,5678,22,/g' /etc/csf/csf.conf
sudo sed -i 's/DOCKER = "

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
