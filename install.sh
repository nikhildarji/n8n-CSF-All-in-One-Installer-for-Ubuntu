#!/bin/bash

# --- 1. Force Non-Interactive Mode ---
# This tells Ubuntu to NEVER ask questions and keep your current files
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
DPKG_OPTS='-o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"'

# --- 2. Setup Logging ---
LOG_FILE="install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "===================================================="
echo "    n8n & CSF Optimized Installer (v2.2 - SILENT)"
echo "===================================================="

# --- 3. Interactive Prompts (Still needed for your config) ---
read -p "Enter your Domain: " DOMAIN
read -p "Enter your Email: " EMAIL

if [[ -z "$DOMAIN" || -z "$EMAIL" ]]; then
    echo "ERROR: Domain and Email are required."
    exit 1
fi

# --- 4. System Update (Silent & Automatic) ---
echo "Updating system in Silent Mode..."
sudo apt-get update
sudo apt-get $DPKG_OPTS upgrade -y

# --- 5. Install Dependencies & Nginx ---
# We use the -y flag and DPKG_OPTS to bypass GRUB/SSH screens
sudo apt-get $DPKG_OPTS install -y nginx perl libwww-perl liblwp-protocol-https-perl ipset wget tar curl jq docker-compose-plugin

# --- 6. Deploy n8n (Optimized) ---
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

# --- 7. Certbot SSL (The "Snap Lock" Fix) ---
echo "Configuring Certbot..."
sudo snap install --classic certbot
sudo ln -sf /snap/bin/certbot /usr/bin/certbot
sudo snap set certbot trust-plugin-with-root=ok
sudo snap connect certbot:nginx
sudo certbot --nginx -d $DOMAIN -m $EMAIL --agree-tos --non-interactive

# --- 8. Optimize Nginx for n8n ---
cat <<EOF > /etc/nginx/sites-available/n8n
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name $DOMAIN;
    location / {
        proxy_pass http://localhost:5678;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_buffering off;
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

# --- 9. Install CSF Firewall ---
cd /usr/src
sudo wget https://download.configserver.com/csf.tgz
sudo tar -xzf csf.tgz
cd csf
sudo sh install.sh

# Configure CSF
sudo sed -i 's/TESTING = "1"/TESTING = "0"/g' /etc/csf/csf.conf
sudo sed -i 's/TCP_IN = "/TCP_IN = "80,443,5678,22,/g' /etc/csf/csf.conf
sudo sed -i 's/DOCKER = "0"/DOCKER = "1"/g' /etc/csf/csf.conf
echo "172.17.0.0/16" >> /etc/csf/csf.allow
echo "iface:docker0" >> /etc/csf/csf.allow

sudo csf -ra
echo "✅ Installation Complete! n8n is fast and secure at https://${DOMAIN}"
