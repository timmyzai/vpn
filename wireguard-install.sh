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
#   - Restart Policy: Sets restart: unless-stopped for **automatic reboot** persistence.
#   - Management: Menu for **logs**, **uninstallation**, and **WG_HOST update**.
# -----------------------------------------------------------------------------------

set -euo pipefail

# --- Config ---
readonly WG_DIR="/etc/docker/containers/wg-easy"
readonly WG_ENV="$WG_DIR/.env"
readonly WG_COMPOSE="$WG_DIR/docker-compose.yml"
readonly ADMIN_PORT_INTERNAL=51821
readonly TIMEOUT=30

# --- Functions ---
check_pkg() { command -v "$1" >/dev/null 2>&1 || DEBIAN_FRONTEND=noninteractive apt-get install -y "$1" >/dev/null 2>&1; }

set_port() {
    local pattern="$1" replace="$2" file="$3"
    grep -qF "$replace" "$file" && return 0
    
    # CRITICAL FIX 1: Use literal newline for sed multiline replacement
    if grep -qF "$pattern" "$file"; then
        sed -i "/$pattern/c\\
        - \"${replace}\"" "$file"
    else
        sed -i "/ports:/a\\
        - \"${replace}\"" "$file"
    fi
}

ensure_restart() {
    grep -q "restart: unless-stopped" "$1" && return 0
    # CRITICAL FIX 2: Use literal newline for sed multiline append
    sed -i '/image:.*wg-easy/a\\
        restart: unless-stopped' "$1"
}

find_compose() {
    docker compose version >/dev/null 2>&1 && COMPOSE="docker compose" || COMPOSE="docker-compose"
    command -v ${COMPOSE%% *} >/dev/null 2>&1 || { echo "Error: Docker Compose not found"; exit 1; }
}

header() { echo -e "\n=== $1 ===\n"; }

get_ip() {
    local ip=$(timeout 5 curl -s ifconfig.me 2>/dev/null || echo "")
    [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] && echo "$ip" || echo "$1"
}

# --- Checks ---
[ "$EUID" -ne 0 ] && { echo "Run as root"; exit 1; }
[ ! -e /etc/debian_version ] && { echo "Debian/Ubuntu only"; exit 1; }

apt-get update -y >/dev/null 2>&1
check_pkg curl

PRIVATE_IP=$(hostname -I | awk '{print $1}')
PUBLIC_IP=$(get_ip "$PRIVATE_IP")

# Determine compose command only if docker is present, otherwise COMPOSE=""
command -v docker >/dev/null 2>&1 && find_compose || COMPOSE=""

# --- Existing Installation ---
WG_INSTALLED=0
# 1. Container Running/Existing
command -v docker >/dev/null 2>&1 && docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q '^wg-easy$' && WG_INSTALLED=1
# 2. Compose file exists
[ $WG_INSTALLED -eq 0 ] && [ -f "$WG_COMPOSE" ] && WG_INSTALLED=1
# 3. Directory exists (Minimal trace)
[ $WG_INSTALLED -eq 0 ] && [ -d "$WG_DIR" ] && WG_INSTALLED=1

if [ $WG_INSTALLED -eq 1 ]; then
    header "WG-EASY DETECTED"
    echo "1) Logs  2) Uninstall  3) Change IP  4) Exit"
    read -rp "Choice [1-4]: " choice
    [ -z "$choice" ] && { echo "Invalid"; exit 1; }

    case "$choice" in
        1)
            docker ps -a --format '{{.Names}}' | grep -q '^wg-easy$' || { echo "Container not found"; exit 1; }
            echo -e "\nLogs (Ctrl+C to exit):\n"
            docker logs wg-easy --tail 50 -f 2>&1 || true
            exit 0
        ;;
        2)
            echo -e "\nWARNING: Remove WireGuard + all data + Docker images"
            read -rp "Type YES: " confirm
            [ "$confirm" = "YES" ] || { echo "Cancelled"; exit 0; }
            
            echo "Removing..."
            # Shutdown compose project if possible
            [ -n "$COMPOSE" ] && [ -f "$WG_COMPOSE" ] && timeout $TIMEOUT $COMPOSE -f "$WG_COMPOSE" down 2>/dev/null || true
            # Force remove container instance
            docker rm -f wg-easy 2>/dev/null || true
            # Remove specific image(s)
            docker images --format '{{.Repository}}:{{.Tag}}' | grep 'wg-easy' | xargs -r docker rmi -f 2>/dev/null || true
            # Prune dangling layers
            docker image prune -af >/dev/null 2>&1 || true
            # Remove configuration directory
            rm -rf "$WG_DIR"
            echo "✓ Uninstalled"
            exit 0
        ;;
        3)
            [ ! -f "$WG_ENV" ] && { echo ".env missing"; exit 1; }
            [ -z "$COMPOSE" ] && { echo "Docker Compose not found"; exit 1; }
            
            current=$(grep -E '^WG_HOST=' "$WG_ENV" 2>/dev/null | cut -d= -f2)
            echo -e "\nCurrent: ${current:-<none>}"
            read -rp "New WG_HOST: " new_host
            [ -z "$new_host" ] && { echo "No change"; exit 0; }
            
            sed -i "s|^WG_HOST=.*|WG_HOST=${new_host}|" "$WG_ENV"
            timeout $TIMEOUT $COMPOSE -f "$WG_COMPOSE" down 2>/dev/null || true
            timeout $TIMEOUT $COMPOSE -f "$WG_COMPOSE" up -d || { echo "Restart failed"; exit 1; }
            echo "✓ Updated to: $new_host"
            exit 0
        ;;
        4) exit 0 ;;
        *) echo "Invalid"; exit 1 ;;
    esac
fi

# --- New Install ---
header "WIREGUARD INSTALLER"
echo "Private: $PRIVATE_IP | Public: $PUBLIC_IP"

read -rp "WG_HOST [$PUBLIC_IP]: " WG_HOST
WG_HOST=${WG_HOST:-$PUBLIC_IP}

echo -e "\nAdmin UI: 1) Public  2) Private  3) Nginx+Domain"
read -rp "Mode [1]: " UI_MODE
UI_MODE=${UI_MODE:-1}

case "$UI_MODE" in
    1) BIND_IP="0.0.0.0" ;;
    2|3) BIND_IP="$PRIVATE_IP" ;;
    *) echo "Invalid"; exit 1 ;;
esac

read -rp "WG Port [51820]: " WG_PORT
WG_PORT=${WG_PORT:-51820}
[[ "$WG_PORT" =~ ^[0-9]+$ ]] && [ "$WG_PORT" -ge 1 ] && [ "$WG_PORT" -le 65535 ] || WG_PORT=51820

read -rp "Admin Port [$ADMIN_PORT_INTERNAL]: " ADMIN_PORT
ADMIN_PORT=${ADMIN_PORT:-$ADMIN_PORT_INTERNAL}
[[ "$ADMIN_PORT" =~ ^[0-9]+$ ]] && [ "$ADMIN_PORT" -ge 1 ] && [ "$ADMIN_PORT" -le 65535 ] || ADMIN_PORT=$ADMIN_PORT_INTERNAL

echo -e "\nDNS: 1) System  2) Cloudflare  3) Google  4) Quad9"
read -rp "Choice [2]: " DNS_CHOICE
DNS_CHOICE=${DNS_CHOICE:-2}

case $DNS_CHOICE in
    1) DNS=$(awk '/^nameserver/{print $2; exit}' /etc/resolv.conf 2>/dev/null || echo "1.1.1.1") ;;
    2) DNS="1.1.1.1" ;;
    3) DNS="8.8.8.8" ;;
    4) DNS="9.9.9.9" ;;
    *) DNS="1.1.1.1" ;;
esac

echo -e "\nConfig: $WG_HOST:$WG_PORT | Admin: $BIND_IP:$ADMIN_PORT | DNS: $DNS\n"

# --- Docker Install ---
if ! command -v docker >/dev/null 2>&1; then
    echo "Installing Docker..."
    apt-get install -y ca-certificates curl gnupg lsb-release >/dev/null 2>&1
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    . /etc/os-release
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME:-$VERSION_CODENAME} stable" > /etc/apt/sources.list.d/docker.list
    apt-get update -y >/dev/null 2>&1
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null 2>&1
    systemctl enable --now docker
    sleep 2 # Give Docker a moment to start
    find_compose # Find the newly installed compose command
    echo "✓ Docker installed"
fi

# --- Setup ---
mkdir -p "$WG_DIR" && cd "$WG_DIR"
[ ! -f docker-compose.yml ] && curl -fsSL -o docker-compose.yml https://raw.githubusercontent.com/wg-easy/wg-easy/master/docker-compose.yml

# CRITICAL FIX 3: Add PORT=${ADMIN_PORT_INTERNAL}
cat > .env <<EOF
WG_HOST=${WG_HOST}
PASSWORD=$(openssl rand -hex 16)
WG_PORT=${WG_PORT}
PORT=${ADMIN_PORT_INTERNAL}
WG_DEFAULT_DNS=${DNS}
WG_ALLOWED_IPS=0.0.0.0/0,::/0
EOF
chmod 600 .env

# FIX: HIGH #1 - Use ::/0 (or 0.0.0.0) for dual-stack support in compose.
# The Docker standard for dual-stack is to use 0.0.0.0, which binds to all interfaces (IPv4 and IPv6)
WG_BIND_IP="0.0.0.0"

# WireGuard UDP Port mapping
set_port "51820/udp" "${WG_BIND_IP}:${WG_PORT}:51820/udp" "$WG_COMPOSE"

# Admin UI TCP Port mapping
set_port "${ADMIN_PORT_INTERNAL}/tcp" "${BIND_IP}:${ADMIN_PORT}:${ADMIN_PORT_INTERNAL}/tcp" "$WG_COMPOSE"
ensure_restart "$WG_COMPOSE"

echo "Starting..."
timeout $TIMEOUT $COMPOSE up -d || { echo "Start failed"; exit 1; }


# --- Nginx (Mode 3) ---
if [ "$UI_MODE" -eq 3 ]; then
    check_pkg nginx
    
    read -rp "Domain: " DOMAIN
    DOMAIN=$(echo "$DOMAIN" | xargs)
    [ -z "$DOMAIN" ] && { echo "Domain required"; exit 1; }
    
    read -rp "SSL cert path (leave empty for HTTP): " SSL_CERT
    
    NCONF="/etc/nginx/sites-available/wg-easy"
    
    if [ -n "$SSL_CERT" ]; then
        read -rp "SSL key path: " SSL_KEY
        [ ! -f "$SSL_CERT" ] || [ ! -f "$SSL_KEY" ] && { echo "SSL files not found, using HTTP"; SSL_CERT=""; }
    fi
    
    PROXY_PASS="http://127.0.0.1:${ADMIN_PORT_INTERNAL}"

    PROXY_HEADERS='
        proxy_pass PROXY_PASS_PLACEHOLDER;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400;
        proxy_http_version 1.1;'
    
    # CRITICAL FIX 4: Use printf/sed for safe $host replacement
    PROXY_HEADERS=$(printf "%s" "$PROXY_HEADERS" | sed "s|PROXY_PASS_PLACEHOLDER|$PROXY_PASS|g")

    if [ -n "$SSL_CERT" ]; then
        cat > "$NCONF" <<EOF
server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl http2;
    server_name ${DOMAIN};
    ssl_certificate ${SSL_CERT};
    ssl_certificate_key ${SSL_KEY};
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_cache shared:SSL:10m;
    location / {
${PROXY_HEADERS}
    }
}
EOF
    else
        cat > "$NCONF" <<EOF
server {
    listen 80;
    server_name ${DOMAIN};
    location / {
${PROXY_HEADERS}
    }
}
EOF
    fi
    
    ln -sf "$NCONF" /etc/nginx/sites-enabled/wg-easy
    rm -f /etc/nginx/sites-enabled/default 2>/dev/null
    nginx -t && systemctl restart nginx && echo "✓ Nginx configured" || { echo "Nginx failed"; exit 1; }
fi

# --- Done ---
header "INSTALLATION COMPLETE"
PASSWORD=$(grep -E '^PASSWORD=' "$WG_ENV" | cut -d= -f2)
echo "Endpoint: ${WG_HOST}:${WG_PORT}/udp"
echo "Password: ${PASSWORD}"

case "$UI_MODE" in
    1) echo "Admin UI: http://${PUBLIC_IP}:${ADMIN_PORT}" ;;
    2) echo "Admin UI: http://${PRIVATE_IP}:${ADMIN_PORT}" ;;
    3) echo "Admin UI: $([ -n "$SSL_CERT" ] && echo "https" || echo "http")://${DOMAIN}" ;;
esac

echo -e "\nConfig: $WG_DIR/.env | Port: $ADMIN_PORT -> $ADMIN_PORT_INTERNAL"
echo -e "\n\n⚠️ **IMPORTANT: Cloud Firewall / Security Group**"
echo "You MUST open the following ports in your AWS/Cloud Security Group:"
echo "  - **UDP ${WG_PORT}** (WireGuard VPN Traffic)"
echo "  - **TCP ${ADMIN_PORT}** (Admin Web UI)"

exit 0
