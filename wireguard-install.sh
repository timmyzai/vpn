#!/bin/bash
# -----------------------------------------------------------------------------------
# 🚀 WireGuard VPN Installer & Management Script (using wg-easy)
# -----------------------------------------------------------------------------------
# ⚙️ Compatibility:
#   - OS Support: **Debian/Ubuntu** (22.04+ recommended).
#   - Container Engine: **Docker** (with Compose Plugin or legacy docker-compose).
#
# 🛡️ Security & Access:
#   - Admin UI Modes: **Cloud-Optimized** (Direct HTTP, Public ALB, Private ALB for HTTPS).
#   - WireGuard Port Binding: **Dual-stack compatible** (IPv4/IPv6).
#
# 🛠️ Maintenance & Stability:
#   - Management: Menu for **logs**, **robust uninstallation**, and **WG_HOST update**.
# -----------------------------------------------------------------------------------

set -euo pipefail

# --- Config ---
readonly WG_DIR="/etc/docker/containers/wg-easy"
readonly WG_ENV="$WG_DIR/.env"
readonly WG_COMPOSE="$WG_DIR/docker-compose.yml"
readonly ADMIN_PORT_INTERNAL=51821
readonly TIMEOUT=30

# --- Functions ---
check_pkg() {
    command -v "$1" >/dev/null 2>&1 || \
    DEBIAN_FRONTEND=noninteractive apt-get install -y "$1" >/dev/null 2>&1
}

# CORRECTED sed functions using single quotes and \n for maximum robustness
set_port() {
    local pattern="$1"
    local replace="$2"
    local file="$3"

    grep -qF "$replace" "$file" && return 0

    if grep -qF "$pattern" "$file"; then
        # Change existing port line
        sed -i.bak "/$pattern/c\\
- \"$replace\"" "$file"
    else
        # Append new port line after 'ports:'
        sed -i.bak "/ports:/a\\
- \"$replace\"" "$file"
    fi
    rm -f "$file".bak # Remove temporary backup file
}

ensure_restart() {
    local file="$1"
    grep -q "restart: unless-stopped" "$file" && return 0

    # Use single quotes for robust multiline insertion
    sed -i "\|image:.*wg-easy|a\\
        restart: unless-stopped" "$file"
}

find_compose() {
    if docker compose version >/dev/null 2>&1; then
        COMPOSE="docker compose"
    else
        COMPOSE="docker-compose"
    fi
    command -v ${COMPOSE%% *} >/dev/null 2>&1 || {
        echo "Error: Docker Compose not found"; exit 1;
    }
}

header() { echo -e "\n=== $1 ===\n"; }

get_ip() {
    local ip=$(timeout 5 curl -s ifconfig.me 2>/dev/null || echo "")
    [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && echo "$ip" || echo "$1"
}

# --- Checks ---
[ "$EUID" -ne 0 ] && { echo "Run as root"; exit 1; }
[ ! -e /etc/debian_version ] && { echo "Debian/Ubuntu only"; exit 1; }

apt-get update -y >/dev/null 2>&1
check_pkg curl

PRIVATE_IP=$(hostname -I | awk '{print $1}')
PUBLIC_IP=$(get_ip "$PRIVATE_IP")

command -v docker >/dev/null 2>&1 && find_compose || COMPOSE=""

# --- Detect Existing Installation ---
WG_INSTALLED=0
command -v docker >/dev/null 2>&1 && docker ps -a --format '{{.Names}}' | grep -q '^wg-easy$' && WG_INSTALLED=1
[ $WG_INSTALLED -eq 0 ] && [ -f "$WG_COMPOSE" ] && WG_INSTALLED=1
[ $WG_INSTALLED -eq 0 ] && [ -d "$WG_DIR" ] && WG_INSTALLED=1

if [ $WG_INSTALLED -eq 1 ]; then
    header "WG-EASY DETECTED"
    echo "1) View Logs"
    echo "2) Uninstall Completely"
    echo "3) Change WG_HOST"
    echo "4) Exit"

    read -rp "Choice [1-4]: " choice

    case "$choice" in
        1)
            docker logs wg-easy --tail 50 -f || true
            exit 0
        ;;
        2)
            read -rp "Confirm uninstall? (y/N): " c
            [[ "$c" =~ ^[yY]$ ]] || exit 0

            [ -n "$COMPOSE" ] && [ -f "$WG_COMPOSE" ] && \
                timeout "$TIMEOUT" $COMPOSE -f "$WG_COMPOSE" down || true

            # The error in the output "Error response from daemon: invalid reference format: repository name (library/321MB) must be lowercase"
            # likely comes from a hung `docker images` command when cleaning up.
            # We add a check for non-empty output before xargs to be safer.
            docker rm -f wg-easy 2>/dev/null || true
            WG_IMAGE_IDS=$(docker images | grep wg-easy | awk '{print $3}' | xargs)
            [ -n "$WG_IMAGE_IDS" ] && docker rmi -f $WG_IMAGE_IDS || true
            docker image prune -af >/dev/null 2>&1 || true

            rm -rf "$WG_DIR"
            echo "✓ Uninstalled"
            exit 0
        ;;
        3)
            read -rp "New WG_HOST: " new_host
            [ -z "$new_host" ] && exit 0

            sed -i "s|^WG_HOST=.*|WG_HOST=${new_host}|" "$WG_ENV"
            timeout "$TIMEOUT" $COMPOSE -f "$WG_COMPOSE" down || true
            timeout "$TIMEOUT" $COMPOSE -f "$WG_COMPOSE" up -d
            echo "✓ WG_HOST updated"
            exit 0
        ;;
        *) exit 0 ;;
    esac
fi

# --- New Install ---
header "WIREGUARD INSTALLER"
echo "Private: $PRIVATE_IP"
echo "Public : $PUBLIC_IP"

read -rp "WG_HOST [$PUBLIC_IP]: " WG_HOST
WG_HOST="${WG_HOST:-$PUBLIC_IP}"

echo
echo "Admin UI Exposure:"
echo "1) Direct IP (HTTP) - Binds to Private IP" 
echo "2) Public ALB + Route53 (HTTPS) - Binds to Private IP" 
echo "3) Private ALB + Route53 (HTTPS Internal - Recommended) - Binds to Private IP"
read -rp "Mode [3]: " UI_MODE
UI_MODE=${UI_MODE:-3} # Default changed to 3 (Private ALB)

# *** CORRECTED BINDING LOGIC: All modes bind to Private IP ***
case "$UI_MODE" in
    1|2|3) BIND_IP="$PRIVATE_IP" ;; 
    *) echo "Invalid UI Mode"; exit 1 ;;
esac
# *** END CORRECTED BINDING LOGIC ***

read -rp "WG Port [51820]: " WG_PORT
WG_PORT=${WG_PORT:-51820}

read -rp "Admin EXTERNAL Port [51821]: " ADMIN_PORT
ADMIN_PORT=${ADMIN_PORT:-$ADMIN_PORT_INTERNAL}

echo -e "\n------ DNS RESOLVER ------"
echo "Choose DNS for VPN clients:"
echo "1) System DNS  (from /etc/resolv.conf)"
echo "2) Cloudflare 1.1.1.1"
echo "3) Google     8.8.8.8"
echo "4) Quad9      9.9.9.9"
read -rp "DNS [1-4]: " D
D=${D:-1}

case $D in
    1) DNS=$(awk '/nameserver/{print $2;exit}' /etc/resolv.conf || echo "1.1.1.1") ;;
    2) DNS=1.1.1.1 ;;
    3) DNS=8.8.8.8 ;;
    4) DNS=9.9.9.9 ;;
    *) DNS=1.1.1.1 ;;
esac

# --- Docker Install ---
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
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null 2>&1

    systemctl enable --now docker

    # Retry until compose is ready
    for i in {1..5}; do
        if find_compose 2>/dev/null; then break; fi
        sleep 1
    done

    echo "✓ Docker installed"
fi

# --- Setup ---
mkdir -p "$WG_DIR"
cd "$WG_DIR"

if [ ! -f docker-compose.yml ]; then
    curl -fsSL -o docker-compose.yml \
        https://raw.githubusercontent.com/wg-easy/wg-easy/master/docker-compose.yml
fi

if [ ! -s docker-compose.yml ]; then
    echo "Error: Failed to download docker-compose.yml"
    exit 1
fi

cat > .env <<EOF
WG_HOST=${WG_HOST}
PASSWORD=$(openssl rand -hex 16)
WG_PORT=${WG_PORT}
PORT=${ADMIN_PORT_INTERNAL}
WG_DEFAULT_DNS=${DNS}
WG_ALLOWED_IPS=0.0.0.0/0,::/0
EOF

chmod 600 .env

WG_BIND_IP="0.0.0.0"

set_port "51820/udp" "$WG_BIND_IP:$WG_PORT:51820/udp" "$WG_COMPOSE"
set_port "${ADMIN_PORT_INTERNAL}/tcp" "$BIND_IP:$ADMIN_PORT:$ADMIN_PORT_INTERNAL/tcp" "$WG_COMPOSE"
ensure_restart "$WG_COMPOSE"

echo "Starting..."
timeout "$TIMEOUT" $COMPOSE up -d

# --- Output ---
header "INSTALL COMPLETE"
PASSWORD=$(grep -E '^PASSWORD=' "$WG_ENV" | cut -d= -f2)

echo "Endpoint: ${WG_HOST}:${WG_PORT}/udp"
echo "Password: $PASSWORD"
echo
echo "Admin UI:"
case "$UI_MODE" in
    1) echo "http://${PRIVATE_IP}:${ADMIN_PORT} (Direct Access)" ;;
    2) echo "Via PUBLIC ALB (HTTPS). Target: http://${PRIVATE_IP}:${ADMIN_PORT}" ;;
    3) echo "Via PRIVATE ALB (HTTPS internal) - Recommended. Target: http://${PRIVATE_IP}:${ADMIN_PORT}" ;;
esac

echo
echo "Config: $WG_DIR/.env"
exit 0
