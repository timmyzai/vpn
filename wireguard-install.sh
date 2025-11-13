#!/bin/bash
# -----------------------------------------------------------------------------------
# 🚀 WireGuard VPN Installer & Management Script (using wg-easy)
# -----------------------------------------------------------------------------------
# ⚙️ Compatibility:
#   - OS Support: **Debian/Ubuntu** (22.04+ recommended).
#   - Container Engine: **Docker** (with Compose Plugin or legacy docker-compose).
#
# 🛡️ Security & Access:
#   - VPN Protocol: **WireGuard** (modern, fast, cryptographically sound).
#   - Access Control: Generates a **unique Hex password** for Admin UI access.
#   - Admin UI Modes: Supports **Public**, **Private**, and **Nginx Reverse Proxy** (with optional SSL).
#
# 🌐 Network & Configuration:
#   - Protocol: Uses **UDP** (Standard WireGuard transport).
#   - Port Mapping: **Idempotent** and supports **custom external ports** for Admin UI.
#   - Public IP: Automatic detection with **manual override** for WG_HOST.
#   - DNS: Choice of **System**, **Cloudflare**, **Google**, or **Quad9** DNS for clients.
#
# 🛠️ Maintenance & Stability:
#   - Restart Policy: Sets `restart: unless-stopped` for **automatic reboot** persistence.
#   - Management: Menu for **logs**, **uninstallation**, and **WG_HOST update**.
# -----------------------------------------------------------------------------------

set -e

# --- Constants ---------------------------------------------------------------------

WG_DIR="/etc/docker/containers/wg-easy"
WG_ENV="$WG_DIR/.env"
WG_COMPOSE="$WG_DIR/docker-compose.yml"
ADMIN_PORT_INTERNAL=51821 # Fixed internal port for the wg-easy container

# --- Functions ---------------------------------------------------------------------

# Checks if a package is installed; installs it silently if missing.
check_package() {
  command -v "$1" >/dev/null 2>&1 || DEBIAN_FRONTEND=noninteractive apt-get install -y "$1"
}

# Safely adds or updates the container port mapping in docker-compose.yml.
set_compose_port() {
  local pattern="$1" replace="$2" file="$3"
  
  grep -qF "$replace" "$file" && { echo "   ✓ Port already set: $replace"; return; }
  
  if grep -qF "$pattern" "$file"; then
    # Use pattern (internal port) to replace the entire existing mapping line reliably
    sed -i "/$pattern/c \      - \"${replace}\"" "$file"
    echo "   ✓ Updated: $replace"
  else
    # Add new mapping after the 'ports:' keyword
    sed -i "/ports:/a \      - \"${replace}\"" "$file"
    echo "   + Added: $replace"
  fi
}

# Ensures the container has the auto-restart policy for system reboots.
ensure_restart_policy() {
  grep -q "restart: unless-stopped" "$1" && { echo "   ✓ Restart policy exists"; return; }
  sed -i '/image:.*wg-easy/a \    restart: unless-stopped' "$1"
  echo "   + Added restart policy"
}

# Detects and sets the correct 'docker compose' command (modern vs legacy).
find_docker_compose_cmd() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker compose"
  elif command -v docker-compose >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker-compose"
  else
    echo "Error: Docker Compose not found"; exit 1
  fi
}

# Standardized function for printing section headers.
print_header() {
  echo ""
  echo "==========================================="
  echo "  $1"
  echo "==========================================="
  echo ""
}

# --- Initial Checks ----------------------------------------------------------------

# Ensure script is run as root and on a Debian-based system
[ "$EUID" -ne 0 ] && { echo "Run as root"; exit 1; }
[ ! -e /etc/debian_version ] && { echo "Debian/Ubuntu only"; exit 1; }

apt-get update -y >/dev/null 2>&1 # Silent update
check_package curl

PRIVATE_IP=$(hostname -I | awk '{print $1}')
PUBLIC_IP=$(curl -s ifconfig.me || echo "$PRIVATE_IP")

command -v docker >/dev/null 2>&1 && find_docker_compose_cmd # Find compose command if docker is installed

# --- Existing Installation Detection -----------------------------------------------

if [ -d "$WG_DIR" ] && [ -f "$WG_COMPOSE" ]; then
  print_header "WG-EASY ALREADY INSTALLED"
  
  cat <<EOF
What would you like to do?

1) View logs
2) Uninstall (remove completely)
3) Change WG_HOST IP
4) Exit

EOF
  read -rp "Select [1-4]: " choice

  case "$choice" in
    1) docker logs wg-easy -f; exit 0 ;;
    2)
      echo ""
      echo "WARNING: This will remove wg-easy, all configs, peers, and keys."
      read -rp "Type YES to confirm: " confirm
      [ "$confirm" = "YES" ] && {
        $DOCKER_COMPOSE_CMD -f "$WG_COMPOSE" down
        rm -rf "$WG_DIR"
        echo "✓ Uninstalled completely"
      } || echo "Cancelled"
      exit 0
      ;;
    3)
      [ ! -f "$WG_ENV" ] && { echo "Error: .env file missing"; exit 1; }
      current=$(grep -E '^WG_HOST=' "$WG_ENV" | cut -d= -f2)
      echo ""
      echo "Current WG_HOST: $current"
      read -rp "Enter new WG_HOST: " new_host
      [ -n "$new_host" ] && {
        sed -i "s|^WG_HOST=.*|WG_HOST=${new_host}|" "$WG_ENV"
        echo "✓ Updated to: $new_host"
        $DOCKER_COMPOSE_CMD -f "$WG_COMPOSE" down
        $DOCKER_COMPOSE_CMD -f "$WG_COMPOSE" up -d
        echo "✓ Restarted"
      } || echo "No changes"
      exit 0
      ;;
    4) exit 0 ;;
    *) echo "Invalid option"; exit 1 ;;
  esac
fi

# --- New Installation --------------------------------------------------------------

print_header "WIREGUARD VPN INSTALLER"

cat <<EOF
Private IP : $PRIVATE_IP
Public IP  : $PUBLIC_IP

EOF

read -rp "VPN endpoint hostname/IP (default: $PUBLIC_IP): " WG_HOST
WG_HOST=${WG_HOST:-$PUBLIC_IP}

echo ""
echo "Admin UI Exposure Mode:"
echo ""
cat <<EOF
1) Public  (0.0.0.0:PORT) - accessible from anywhere
2) Private ($PRIVATE_IP:PORT) - local network only
3) Private + Nginx + Domain - with reverse proxy (recommended for security)

EOF
read -rp "Select [1-3] (default: 1): " UI_MODE
UI_MODE=${UI_MODE:-1}

case "$UI_MODE" in
  1) ADMIN_BIND_IP="0.0.0.0" ;;
  2|3) ADMIN_BIND_IP="$PRIVATE_IP" ;;
  *) echo "Invalid option"; exit 1 ;;
esac

echo ""
read -rp "WireGuard UDP port (default: 51820): " WG_PORT
WG_PORT=${WG_PORT:-51820}

read -rp "Admin UI external port (default: $ADMIN_PORT_INTERNAL): " ADMIN_PORT_EXTERNAL
ADMIN_PORT_EXTERNAL=${ADMIN_PORT_EXTERNAL:-$ADMIN_PORT_INTERNAL}

echo ""
echo "DNS Resolver for VPN Clients:"
echo ""
cat <<EOF
1) System DNS  (from /etc/resolv.conf)
2) Cloudflare  (1.1.1.1)
3) Google      (8.8.8.8)
4) Quad9       (9.9.9.9)

EOF
read -rp "Select [1-4] (default: 2): " DNS_CHOICE
DNS_CHOICE=${DNS_CHOICE:-2}

case $DNS_CHOICE in
  1) WG_DEFAULT_DNS=$(awk '/nameserver/{print $2; exit}' /etc/resolv.conf) ;;
  2) WG_DEFAULT_DNS="1.1.1.1" ;;
  3) WG_DEFAULT_DNS="8.8.8.8" ;;
  4) WG_DEFAULT_DNS="9.9.9.9" ;;
  *) WG_DEFAULT_DNS="1.1.1.1"; echo "Invalid choice, using Cloudflare" ;;
esac

echo ""
echo "Configuration Summary:"
echo ""
cat <<EOF
WG_HOST             : $WG_HOST
WG_PORT             : $WG_PORT
ADMIN_BIND          : $ADMIN_BIND_IP
ADMIN_PORT_EXTERNAL : $ADMIN_PORT_EXTERNAL -> Container :$ADMIN_PORT_INTERNAL
DNS                 : $WG_DEFAULT_DNS

EOF

# --- Docker Installation -----------------------------------------------------------

if ! command -v docker >/dev/null 2>&1; then
  echo "Installing Docker..."
  apt-get install -y ca-certificates curl gnupg lsb-release >/dev/null 2>&1
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  . /etc/os-release
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME:-$VERSION_CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list
  apt-get update -y >/dev/null 2>&1
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1
  systemctl enable --now docker
  find_docker_compose_cmd
  echo "✓ Docker installed"
fi

# --- wg-easy Setup -----------------------------------------------------------------

mkdir -p "$WG_DIR" && cd "$WG_DIR"

[ ! -f docker-compose.yml ] && \
  curl -fsSL -o docker-compose.yml https://raw.githubusercontent.com/wg-easy/wg-easy/master/docker-compose.yml

WG_PASSWORD=$(openssl rand -hex 16)

# Create .env file with all necessary configuration variables
cat > .env <<EOF
WG_HOST=${WG_HOST}
PASSWORD=${WG_PASSWORD}
WG_PORT=${WG_PORT}
WG_DEFAULT_DNS=${WG_DEFAULT_DNS}
WG_ALLOWED_IPS=0.0.0.0/0,::/0
EOF

chmod 600 .env # Secure the sensitive password/config file

# Apply port mappings: WG_PORT:51820/udp and ADMIN_PORT_EXTERNAL:51821/tcp
set_compose_port "51820/udp" "0.0.0.0:${WG_PORT}:51820/udp" "$WG_COMPOSE"
set_compose_port "${ADMIN_PORT_INTERNAL}/tcp" "${ADMIN_BIND_IP}:${ADMIN_PORT_EXTERNAL}:${ADMIN_PORT_INTERNAL}/tcp" "$WG_COMPOSE"

ensure_restart_policy "$WG_COMPOSE"

echo "Starting wg-easy container..."
$DOCKER_COMPOSE_CMD up -d

# --- Nginx Setup (Mode 3) ----------------------------------------------------------

if [ "$UI_MODE" -eq 3 ]; then
  check_package nginx
  
  echo ""
  echo "Nginx Configuration:"
  echo ""
  read -rp "Domain (e.g., vpn.example.com): " DOMAIN_NAME
  DOMAIN_NAME=$(echo "$DOMAIN_NAME" | xargs)
  
  read -rp "SSL certificates available? [y/N] (default: N): " HAS_SSL
  HAS_SSL=${HAS_SSL,,}
  
  NCONF="/etc/nginx/sites-available/wg-easy"
  PROXY_TARGET="http://127.0.0.1:${ADMIN_PORT_INTERNAL}" # Proxy directly to host's loopback port 51821
  
  if [ "$HAS_SSL" = "y" ]; then
    read -rp "SSL cert path: " SSL_CERT
    read -rp "SSL key path : " SSL_KEY
    
    [ ! -f "$SSL_CERT" ] || [ ! -f "$SSL_KEY" ] && {
      echo "SSL files not found - using HTTP"
      HAS_SSL="n"
    }
  fi
  
  # Define standard proxy headers using a read block for DRYness
  read -r -d '' PROXY_CONFIG <<'PROXY' || true
        proxy_pass TARGET_PLACEHOLDER;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400;
PROXY
  
  # Replace placeholder with the actual proxy target
  PROXY_CONFIG="${PROXY_CONFIG//TARGET_PLACEHOLDER/$PROXY_TARGET}"
  
  if [ "$HAS_SSL" = "y" ]; then
    # Nginx SSL configuration with HTTP to HTTPS redirect
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
${PROXY_CONFIG}
    }
}
EOF
  else
    # Nginx plain HTTP configuration
    cat > "$NCONF" <<EOF
server {
    listen 80;
    server_name ${DOMAIN_NAME};
    location / {
${PROXY_CONFIG}
    }
}
EOF
  fi
  
  ln -sf "$NCONF" /etc/nginx/sites-enabled/wg-easy # Enable the site config
  rm -f /etc/nginx/sites-enabled/default 2>/dev/null # Remove default Nginx site
  
  nginx -t && systemctl restart nginx && echo "✓ Nginx configured" || {
    echo "✗ Nginx config failed"
    exit 1
  }
fi

# --- Summary -----------------------------------------------------------------------

print_header "INSTALLATION COMPLETE"

cat <<EOF
WireGuard Endpoint : ${WG_HOST}:${WG_PORT}/udp
Admin Password     : ${WG_PASSWORD}

EOF

case "$UI_MODE" in
  1) echo "Admin UI: http://${PUBLIC_IP}:${ADMIN_PORT_EXTERNAL}" ;;
  2) echo "Admin UI: http://${PRIVATE_IP}:${ADMIN_PORT_EXTERNAL}" ;;
  3) echo "Admin UI: $([ "$HAS_SSL" = "y" ] && echo "https" || echo "http")://${DOMAIN_NAME}" ;;
esac

cat <<EOF

Config Location : $WG_DIR/.env
Auto-start      : enabled
Port Mapping    : ${ADMIN_PORT_EXTERNAL} -> $ADMIN_PORT_INTERNAL

EOF
exit 0
