#!/bin/bash
# -----------------------------------------------------------------------------------
# WireGuard VPN Installer using wg-easy
# OS: Ubuntu 22.04+ (ARM64/AMD64)
# Features:
#   - Public / Private / Private+Nginx Admin UI modes
#   - Restart policy added for auto-boot (Universal Fix Applied)
#   - Safe idempotent port mapping
#   - Cloud-ready (EC2, Internal ALB, Client VPN)
# -----------------------------------------------------------------------------------
set -e

# --- Helper Functions --------------------------------------------------------------

check_package() {
  if ! command -v "$1" >/dev/null 2>&1; then
    apt-get install -y "$1"
  fi
}

set_compose_port() {
  local search="$1"
  local replace="$2"
  local file="$3"

  if grep -qF "$replace" "$file"; then
    echo "   ✓ Port already set: $replace"
    return
  fi

  if grep -qF "$search" "$file"; then
    sed -i "s|${search}|${replace}|" "$file"
    echo "   ✓ Updated: $replace"
    return
  fi

  case "$search" in
    *51820/udp*) sed -i '/- ".*:51820\/udp"/d' "$file" ;;
    *51821/tcp*) sed -i '/- ".*:51821\/tcp"/d' "$file" ;;
  esac

  sed -i "/ports:/a \      - \"${replace}\"" "$file"
  echo "   + Added: $replace"
}

ensure_restart_policy() {
  local file="$1"

  if grep -q "restart:" "$file"; then
    echo "   ✓ Restart policy already exists"
    return
  fi

  # Universal matcher for any wg-easy image (ghcr, legacy, future tags)
  sed -i '/image:.*wg-easy/a \    restart: unless-stopped' "$file"
  echo "   + Added restart policy"
}

# --- Initial Setup -----------------------------------------------------------------

if [ "$EUID" -ne 0 ]; then echo "Run as root"; exit 1; fi
if [ ! -e /etc/debian_version ]; then echo "Debian/Ubuntu only"; exit 1; fi

apt-get update -y
check_package curl

PRIVATE_IP=$(hostname -I | awk '{print $1}')
PUBLIC_IP=$(curl -s ifconfig.me || echo "$PRIVATE_IP")

echo "
===========================================
🚀 WG-EASY INSTALLER (Cloud Ready)
===========================================
Private IP : $PRIVATE_IP
Public IP  : $PUBLIC_IP
"

# --- VPN Host ----------------------------------------------------------------------

read -rp "VPN endpoint hostname/IP [default $PUBLIC_IP]: " WG_HOST
WG_HOST=${WG_HOST:-$PUBLIC_IP}

# --- Admin UI Modes ----------------------------------------------------------------

echo "
Choose Admin UI Exposure Mode:

1) Public Admin UI (0.0.0.0:PORT)
   Accessible from the internet.

2) Private Admin UI ($PRIVATE_IP:PORT)
   Private only (VPC / Client VPN / Peering).
   ⚠️ Block WireGuard subnet from Admin UI port.

3) Private Admin UI + Domain + Nginx ($PRIVATE_IP:PORT)
   Nginx reverse proxy (HTTP or HTTPS with your certs).
"

read -rp "Enter choice [1-3, default 1]: " UI_MODE
UI_MODE=${UI_MODE:-1}

case "$UI_MODE" in
  1) ADMIN_BIND_IP="0.0.0.0" ;;
  2) ADMIN_BIND_IP="$PRIVATE_IP" ;;
  3) ADMIN_BIND_IP="$PRIVATE_IP" ;;
  *) echo "Invalid option"; exit 1 ;;
esac

# --- Ports -------------------------------------------------------------------------

read -rp "WireGuard UDP port [default 51820]: " WG_PORT
WG_PORT=${WG_PORT:-51820}

read -rp "Admin UI TCP port [default 51821]: " ADMIN_PORT
ADMIN_PORT=${ADMIN_PORT:-51821}

echo "
WG_HOST     = $WG_HOST
WG_PORT     = $WG_PORT
ADMIN_BIND  = $ADMIN_BIND_IP
ADMIN_PORT  = $ADMIN_PORT
"

# --- Docker Install ----------------------------------------------------------------

if ! command -v docker >/dev/null 2>&1; then
  echo "Installing Docker..."
  apt-get install -y ca-certificates curl gnupg lsb-release
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  . /etc/os-release

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME:-$VERSION_CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list

  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
fi

# --- wg-easy Setup -----------------------------------------------------------------

WG_DIR="/etc/docker/containers/wg-easy"
mkdir -p "$WG_DIR"
cd "$WG_DIR"

if [ ! -f docker-compose.yml ]; then
  curl -fsSL -o docker-compose.yml https://raw.githubusercontent.com/wg-easy/wg-easy/master/docker-compose.yml
fi

WG_PASSWORD=$(openssl rand -hex 16)

cat > .env <<EOF
WG_HOST=${WG_HOST}
PASSWORD=${WG_PASSWORD}
WG_PORT=${WG_PORT}
WG_DEFAULT_DNS=1.1.1.1
WG_ALLOWED_IPS=0.0.0.0/0,::/0
EOF

# Security: Restrict .env file permissions to root only
chmod 600 .env

compose="docker-compose.yml"

set_compose_port '"51820:51820/udp"' "0.0.0.0:${WG_PORT}:51820/udp" "$compose"
set_compose_port '"51821:51821/tcp"' "${ADMIN_BIND_IP}:${ADMIN_PORT}:51821/tcp" "$compose"

ensure_restart_policy "$compose"

docker compose up -d

# --- Nginx (Mode 3) ----------------------------------------------------------------

HAS_SSL="n"
DOMAIN_NAME=""

if [ "$UI_MODE" -eq 3 ]; then
  check_package nginx

  read -rp "Domain (example: vpn.example.com): " DOMAIN_NAME
  DOMAIN_NAME=$(echo "$DOMAIN_NAME" | xargs)

  read -rp "Do you have SSL certs? [y/N]: " HAS_SSL
  HAS_SSL=${HAS_SSL,,}

  NCONF="/etc/nginx/sites-available/wg-easy"
  rm -f "$NCONF"

  if [ "$HAS_SSL" == "y" ]; then
    read -rp "SSL cert path: " SSL_CERT
    read -rp "SSL key path : " SSL_KEY

    if [ ! -f "$SSL_CERT" ] || [ ! -f "$SSL_KEY" ]; then
      echo "SSL files missing → fallback to HTTP"
      HAS_SSL="n"
    fi
  fi

  if [ "$HAS_SSL" == "y" ]; then
    # HTTPS configuration with full proxy headers for WebSocket and IP forwarding
    cat > "$NCONF" <<EOF
server {
    listen 80;
    server_name ${DOMAIN_NAME};
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl;
    server_name ${DOMAIN_NAME};
    ssl_certificate ${SSL_CERT};
    ssl_certificate_key ${SSL_KEY};
    location / {
        proxy_pass http://${PRIVATE_IP}:${ADMIN_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400;
    }
}
EOF
  else
    # HTTP configuration with full proxy headers
    cat > "$NCONF" <<EOF
server {
    listen 80;
    server_name ${DOMAIN_NAME};
    location / {
        proxy_pass http://${PRIVATE_IP}:${ADMIN_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400;
    }
}
EOF
  fi

  ln -sf "$NCONF" /etc/nginx/sites-enabled/wg-easy
  rm -f /etc/nginx/sites-enabled/default || true

  if nginx -t; then
    systemctl restart nginx
    echo "   ✓ Nginx restarted successfully"
  else
    echo "   ✗ Nginx config test failed. Please check /etc/nginx/sites-available/wg-easy"
    exit 1
  fi
fi

# --- Summary -----------------------------------------------------------------------

echo "
===========================================
🎉 INSTALL COMPLETE
===========================================
WireGuard Endpoint: ${WG_HOST}:${WG_PORT}/udp
Admin UI Password : ${WG_PASSWORD}
"

case "$UI_MODE" in
  1)
    echo "Admin UI: http://${PUBLIC_IP}:${ADMIN_PORT}"
    ;;
  2)
    echo "Admin UI (Private): http://${PRIVATE_IP}:${ADMIN_PORT}"
    echo "⚠️ SG Reminder: Block WireGuard VPN subnet from Admin UI port (${ADMIN_PORT})"
    ;;
  3)
    if [ "$HAS_SSL" == "y" ]; then
      echo "Admin UI: https://${DOMAIN_NAME}"
    else
      echo "Admin UI: http://${DOMAIN_NAME}"
    fi
    ;;
esac

echo "
.env stored at: $WG_DIR/.env
Auto-start on reboot enabled (restart: unless-stopped)
"
exit 0
