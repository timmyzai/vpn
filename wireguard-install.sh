#!/bin/bash
# -----------------------------------------------------------------------------------
# 🚀 WireGuard VPN Installer & Management Script (using wg-easy)
# -----------------------------------------------------------------------------------
# ⚙️ Compatibility:
#   - OS Support: **Debian/Ubuntu** (22.04+ recommended).
#   - Container Engine: **Docker** (with Compose Plugin or legacy docker-compose).
#
# 🛡️ Security & Access:
#   - Admin UI Modes: **Cloud-Optimized** (Direct HTTP, Public ALB, Private ALB for HTTPS).
#   - WireGuard Port Binding: **Dual-stack compatible** (IPv4/IPv6).
#
# 🛠️ Maintenance & Stability:
#   - Management: Menu for **logs**, **robust uninstallation**, and **WG_HOST update**.
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
            # Change: Make Uninstall check easier (y/n)
            read -rp "Are you SURE you want to uninstall? (y/N): " confirm_uninstall
            [[ "$confirm_uninstall" =~ ^[yY]$ ]] || { echo "Cancelled"; exit 0; }
            
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

# ----------------------------------------
# --- New Install (Cloud Optimized) ---
# ----------------------------------------
header "WIREGUARD INSTALLER"
echo "Private: $PRIVATE_IP | Public: $PUBLIC_IP"

read -rp "WG_HOST [$PUBLIC_IP]: " WG_HOST
WG_HOST=${WG_HOST:-$PUBLIC_IP}

echo -e "\nAdmin UI Exposure Method (HTTPS Recommended):"
echo "1) Direct IP (HTTP Admin UI - Less Secure)"
echo "2) ALB + Route 53 Public Zone (Recommended for Production HTTPS)"
echo "3) Private ALB + Route 53 Private Zone (Recommended for Internal HTTPS)"
read -rp "Mode [2]: " UI_MODE
UI_MODE=${UI_MODE:-2}

case "$UI_MODE" in
    1) BIND_IP="$PRIVATE_IP" ;; # Bind to private IP for direct access
    2|3) BIND_IP="127.0.0.1" ;; # Bind to localhost, requiring an ALB/Proxy
    *) echo "Invalid"; exit 1 ;;
esac

read -rp "WG Port [51820]: " WG_PORT
WG_PORT=${WG_PORT:-51820}
[[ "$WG_PORT" =~ ^[0-9]+$ ]] && [ "$WG_PORT" -ge 1 ] && [ "$WG_PORT" -le 65535 ] || WG_PORT=51820

# FIX: ALWAYS prompt for the external ADMIN_PORT for port mapping, regardless of mode.
read -rp "Admin EXTERNAL Port (Used for ALB/Browser access) [$ADMIN_PORT_INTERNAL]: " ADMIN_PORT
ADMIN_PORT=${ADMIN_PORT:-$ADMIN_PORT_INTERNAL}
[[ "$ADMIN_PORT" =~ ^[0-9]+$ ]] && [ "$ADMIN_PORT" -ge 1 ] && [ "$ADMIN_PORT" -le 65535 ] || ADMIN_PORT=$ADMIN_PORT_INTERNAL


# --- Updated DNS Resolver Block ---
echo -e "\n------ DNS RESOLVER ------"
echo "Choose DNS for VPN clients:"
echo "1) System DNS  (from /etc/resolv.conf)"
echo "2) Cloudflare 1.1.1.1"
echo "3) Google     8.8.8.8"
echo "4) Quad9      9.9.9.9"

read -rp "DNS [1-4] (Default: 1): " D
D=${D:-1}
case $D in
    # FIX: Use head -n 1 to ensure only a single IP is captured, preventing sed issues.
    1) DNS=$(awk '/nameserver/{print $2; exit}' /etc/resolv.conf 2>/dev/null | head -n 1 || echo "1.1.1.1");;
    2) DNS=1.1.1.1;;
    3) DNS=8.8.8.8;;
    4) DNS=9.9.9.9;;
    *) DNS=1.1.1.1;; # Fallback
esac
# --- End Updated DNS Resolver Block ---

echo -e "\nConfig: $WG_HOST:$WG_PORT | Admin Bind: $BIND_IP:$ADMIN_PORT | DNS: $DNS\n"

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

# FIX: HIGH #1 - Dual-stack WireGuard port binding
WG_BIND_IP="0.0.0.0"

# WireGuard UDP Port mapping
set_port "51820/udp" "${WG_BIND_IP}:${WG_PORT}:51820/udp" "$WG_COMPOSE"

# Admin UI TCP Port mapping
# FIX: Port mapping now uses the user-defined ADMIN_PORT (External) -> ADMIN_PORT_INTERNAL (Container 51821)
set_port "${ADMIN_PORT_INTERNAL}/tcp" "${BIND_IP}:${ADMIN_PORT}:${ADMIN_PORT_INTERNAL}/tcp" "$WG_COMPOSE"
ensure_restart "$WG_COMPOSE"

echo "Starting..."
timeout $TIMEOUT $COMPOSE up -d || { echo "Start failed"; exit 1; }

# --- Done ---
header "INSTALLATION COMPLETE"
PASSWORD=$(grep -E '^PASSWORD=' "$WG_ENV" | cut -d= -f2)
echo "Endpoint: ${WG_HOST}:${WG_PORT}/udp"
echo "Password: ${PASSWORD}"

echo -e "\n\n⚠️ **IMPORTANT: Cloud Configuration Required**"
echo "--------------------------------------------------------"
echo "VPN Traffic Port: UDP ${WG_PORT}"
echo "Admin UI Internal Port: HTTP ${ADMIN_PORT_INTERNAL}"

case "$UI_MODE" in
    1)
        echo -e "\nMODE 1: Direct Access (HTTP Admin UI)"
        echo "Admin UI Access: http://${PRIVATE_IP}:${ADMIN_PORT}"
        echo "NOTE: This mode does **NOT** provide HTTPS. Use it for testing or behind a local proxy."
        echo "Security Group: Open TCP ${ADMIN_PORT} from source IP."
    ;;
    2)
        echo -e "\nMODE 2: ALB + Route 53 (Recommended for HTTPS)"
        echo "The Admin UI is bound to 127.0.0.1:${ADMIN_PORT} (localhost)."
        echo "NEXT STEPS (Manual AWS Configuration):"
        echo "1. Create an ALB/Target Group (Target Port: **${ADMIN_PORT}**) and register EC2 **PRIVATE IP** (${PRIVATE_IP})."
        echo "2. Configure Route 53 **Public Hosted Zone** A-Record pointing to the ALB."
        echo "Security Group: Open TCP 443 (from Internet to ALB) and TCP ${ADMIN_PORT} (from ALB to EC2)."
    ;;
    3)
        echo -e "\nMODE 3: Private ALB + Route 53 (Internal HTTPS Admin UI)"
        echo "The Admin UI is bound to 127.0.0.1:${ADMIN_PORT} (localhost)."
        echo "NEXT STEPS (Manual AWS Configuration):"
        echo "1. Create a **Private ALB** and Target Group (Target Port: **${ADMIN_PORT}**) and register EC2 **PRIVATE IP** (${PRIVATE_IP})."
        echo "2. Configure Route 53 **Private Hosted Zone** A-Record pointing to the Private ALB."
        echo "Security Group: Open TCP ${ADMIN_PORT} (from Private ALB to EC2)."
    ;;
esac

echo -e "\nConfig: $WG_DIR/.env\n"
exit 0
