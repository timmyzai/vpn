#!/bin/bash
# -----------------------------------------------------------------------------------
# 🚀 WireGuard VPN Installer & Management Script (using wg-easy)
# -----------------------------------------------------------------------------------
# ⚙️ Compatibility:
#   - OS Support: Debian/Ubuntu (22.04+ recommended)
#   - Requires Docker + Compose plugin
#
# 🛡️ Security:
#   - Admin UI routing modes (Direct IP / Public ALB / Private ALB)
#   - Private-IP binding (safe by default)
#
# 🛠️ Maintenance:
#   - View logs, uninstall cleanly, update WG_HOST
# -----------------------------------------------------------------------------------

#!/bin/bash
set -euo pipefail

WG_DIR="/etc/docker/containers/wg-easy"
WG_ENV="$WG_DIR/.env"
WG_COMPOSE="$WG_DIR/docker-compose.yml"
ADMIN_PORT_INTERNAL=51821
TIMEOUT=30

header() { echo -e "\n=== $1 ===\n"; }

require_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Please run as root"
        exit 1
    fi
}

require_ubuntu() {
    if [ ! -e /etc/debian_version ]; then
        echo "This installer supports Ubuntu/Debian only"
        exit 1
    fi
}

install_docker() {
    if command -v docker >/dev/null 2>&1; then
        return
    fi

    echo "Installing Docker..."
    apt-get update -y >/dev/null 2>&1
    apt-get install -y ca-certificates curl gnupg lsb-release >/dev/null 2>&1

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    . /etc/os-release
    echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME:-$VERSION_CODENAME} stable" \
> /etc/apt/sources.list.d/docker.list

    apt-get update -y >/dev/null 2>&1
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null 2>&1

    systemctl enable --now docker
}

ensure_docker_compose() {
    if ! docker compose version >/dev/null 2>&1; then
        echo "docker compose plugin is missing"
        exit 1
    fi
}

clean_uninstall() {
    echo "Uninstalling wg-easy..."

    docker compose -f "$WG_COMPOSE" down || true
    docker rm -f wg-easy 2>/dev/null || true

    docker images --format "{{.Repository}} {{.ID}}" \
        | awk '$1=="ghcr.io/wg-easy/wg-easy"{print $2}' \
        | xargs -r docker rmi -f >/dev/null 2>&1 || true

    rm -rf "$WG_DIR"

    echo "✓ Uninstalled cleanly"
    exit 0
}

detect_existing() {
    if docker ps -a --format '{{.Names}}' | grep -q '^wg-easy$'; then return 0; fi
    if [ -d "$WG_DIR" ]; then return 0; fi
    return 1
}

show_existing_menu() {
    header "WG-EASY DETECTED"
    echo "1) View Logs"
    echo "2) Uninstall Completely"
    echo "3) Change WG_HOST"
    echo "4) Exit"
    read -rp "Choice [1-4]: " c

    case "$c" in
        1)
            docker logs wg-easy -f --tail 50
            exit 0
            ;;
        2)
            read -rp "Confirm uninstall? (y/N): " u
            [[ "$u" =~ ^[yY]$ ]] || exit 0
            clean_uninstall
            ;;
        3)
            read -rp "New WG_HOST: " NEW
            sed -i "s|^WG_HOST=.*|WG_HOST=$NEW|" "$WG_ENV"
            docker compose -f "$WG_COMPOSE" down
            docker compose -f "$WG_COMPOSE" up -d
            echo "✓ WG_HOST updated"
            exit 0
            ;;
        *)
            exit 0
            ;;
    esac
}

safe_replace_port_line() {
    local OLD="$1"
    local NEW="$2"
    local FILE="$3"

    # remove old line entirely (safe)
    sed -i "\|$OLD|d" "$FILE"

    # insert under ports:
    awk -v newline="$NEW" '
        /ports:/ {
            print
            print "        - \"" newline "\""
            next
        }
        { print }
    ' "$FILE" > "${FILE}.tmp" && mv "${FILE}.tmp" "$FILE"
}

install_new() {
    header "WIREGUARD INSTALLER"

    PRIVATE_IP=$(hostname -I | awk '{print $1}')
    PUBLIC_IP=$(curl -s ifconfig.me || echo "$PRIVATE_IP")

    echo "Private: $PRIVATE_IP"
    echo "Public : $PUBLIC_IP"
    read -rp "WG_HOST [$PUBLIC_IP]: " WG_HOST
    WG_HOST=${WG_HOST:-$PUBLIC_IP}

    echo
    echo "Admin UI Exposure:"
    echo "1) Direct IP (HTTP)"
    echo "2) Public ALB + Route53 (HTTPS)"
    echo "3) Private ALB + Route53 (HTTPS Internal - Recommended)"
    read -rp "Mode [3]: " M
    M=${M:-3}

    BIND_IP="$PRIVATE_IP"

    read -rp "WG Port [51820]: " WG_PORT
    WG_PORT=${WG_PORT:-51820}

    read -rp "Admin EXTERNAL Port [51821]: " ADMIN_PORT
    ADMIN_PORT=${ADMIN_PORT:-51821}

    echo
    echo "--- DNS Selection ---"
    echo "1) System DNS"
    echo "2) Cloudflare"
    echo "3) Google"
    echo "4) Quad9"
    read -rp "DNS [1-4]: " D
    D=${D:-1}

    case "$D" in
        1) DNS=$(awk '/nameserver/{print $2;exit}' /etc/resolv.conf || echo "1.1.1.1") ;;
        2) DNS=1.1.1.1 ;;
        3) DNS=8.8.8.8 ;;
        4) DNS=9.9.9.9 ;;
        *) DNS=1.1.1.1 ;;
    esac

    mkdir -p "$WG_DIR"
    cd "$WG_DIR"

    curl -fsSL -o docker-compose.yml \
        https://raw.githubusercontent.com/wg-easy/wg-easy/master/docker-compose.yml

    cat > "$WG_ENV" <<EOF
WG_HOST=$WG_HOST
PASSWORD=$(openssl rand -hex 16)
WG_PORT=$WG_PORT
PORT=$ADMIN_PORT_INTERNAL
WG_DEFAULT_DNS=$DNS
WG_ALLOWED_IPS=0.0.0.0/0,::/0
EOF

    chmod 600 "$WG_ENV"

    # Fix ports safely (no YAML corruption)
    safe_replace_port_line "51820:51820/udp" "0.0.0.0:$WG_PORT:51820/udp" "$WG_COMPOSE"
    safe_replace_port_line "51821:51821/tcp" "$BIND_IP:$ADMIN_PORT:51821/tcp" "$WG_COMPOSE"

    # Ensure restart
    if ! grep -q "restart: unless-stopped" "$WG_COMPOSE"; then
        sed -i '/container_name: wg-easy/a\    restart: unless-stopped' "$WG_COMPOSE"
    fi

    echo "Starting..."
    docker compose -f "$WG_COMPOSE" up -d

    header "INSTALL COMPLETE"
    PASS=$(grep PASSWORD "$WG_ENV" | cut -d= -f2)

    echo "WG Endpoint : $WG_HOST:$WG_PORT"
    echo "Admin UI    : http://$PRIVATE_IP:$ADMIN_PORT"
    echo "Password    : $PASS"
}

# -------------------------------------------------------------------
# Main Flow
# -------------------------------------------------------------------
require_root
require_ubuntu
install_docker
ensure_docker_compose

if detect_existing; then
    show_existing_menu
else
    install_new
fi
