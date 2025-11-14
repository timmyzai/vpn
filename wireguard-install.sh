#!/bin/bash
# ------------------------------------------------------------
# 📜 License & Disclaimer
# ------------------------------------------------------------
# MIT License
# © Timmy Chin Did Choong
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the “Software”), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES, OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
# ⚠️ Extended Disclaimer (Additional Legal Protection)
#
# This installer script is provided strictly "as-is". No guarantees, assurances,
# or support commitments are made regarding functionality, security, stability,
# or suitability for any purpose. By using this script, you acknowledge and agree
# to the following:
#
# • You assume full responsibility for any system changes, failures, or damages.
# • The author is NOT liable for misconfiguration, service downtime, data loss,
#   security breaches, unauthorized access, privacy exposure, or any operational
#   or financial impact caused by using this script.
# • You acknowledge that VPN deployment, encryption usage, and network tunneling
#   may be subject to local laws, regulations, or compliance requirements.
#   You are fully responsible for ensuring your own legal and regulatory compliance.
# • The author provides NO warranty that the script is secure, bug-free, or
#   appropriate for production environments.
# • The author provides NO obligation for updates, patches, security fixes, or support.
# • You must independently review, validate, and test this script before deploying it
#   in any environment, including development, testing, staging, or production.
# • If you modify, redistribute, or use a modified version of this script, you assume
#   full responsibility for any consequences arising from your changes.
#
# ❗ Important Clarification
# This script is NOT affiliated with, endorsed by, or supported by:
# • WireGuard
# • wg-easy
# • OpenVPN
# • Any VPN provider, project, or organization
#
# This script is provided for educational and operational convenience only.
# Improper use of VPNs may lead to legal, security, or privacy implications for
# which the author assumes zero responsibility.
#
# USE THIS SCRIPT ENTIRELY AT YOUR OWN RISK.
# ------------------------------------------------------------
#!/bin/bash
set -euo pipefail

# ============================================================
# MENU FUNCTIONS
# ============================================================

show_menu() {
    echo
    echo "==============================="
    echo "     WireGuard / wg-easy       "
    echo "==============================="
    echo "1) Install wg-easy"
    echo "2) Uninstall wg-easy and clean up"
    echo "3) Exit"
    echo
}

uninstall_wg_easy() {
    echo "Stopping wg-easy..."
    docker rm -f wg-easy 2>/dev/null || true

    echo "Removing Docker network..."
    docker network rm wg-easy_wg 2>/dev/null || true

    echo "Removing Docker volume..."
    docker volume rm wg-easy_etc_wireguard 2>/dev/null || true

    echo "Removing wg-easy image..."
    docker rmi ghcr.io/wg-easy/wg-easy:15 2>/dev/null || true

    echo "Removing installation directory..."
    rm -rf /etc/docker/containers/wg-easy

    echo "Removing sysctl configuration..."
    rm -f /etc/sysctl.d/wg-easy.conf
    sysctl --system >/dev/null 2>&1 || true

    echo
    read -rp "Run 'docker system prune -af'? (y/N): " PRUNE
    if [[ "$PRUNE" =~ ^[Yy]$ ]]; then
        docker system prune -af
    fi

    echo "Uninstall complete."
    exit 0
}

# ============================================================
# ROOT CHECK
# ============================================================
if [ "$EUID" -ne 0 ]; then
    echo "Re-running with sudo..."
    sudo bash "$0" "$@"
    exit $?
fi

# ============================================================
# MAIN MENU
# ============================================================
show_menu
read -rp "Select an option [1-3]: " OPTION

case "$OPTION" in
    1) echo "Proceeding with installation..." ;;
    2) uninstall_wg_easy ;;
    3) exit 0 ;;
    *) echo "Invalid option"; exit 1 ;;
esac

# ============================================================
# HELPER FUNCTIONS
# ============================================================

header() { echo -e "\n=== $1 ===\n"; }

detect_os() {
    if [ -e /etc/debian_version ]; then
        OS="debian"
    elif grep -qi "amazon linux" /etc/os-release; then
        OS="amazon"
    elif [ -e /etc/redhat-release ]; then
        OS="rhel"
    else
        OS="unknown"
    fi
}

detect_arch() {
    case "$(uname -m)" in
        x86_64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        *) echo "Unsupported architecture"; exit 1 ;;
    esac
}

ensure_sysctl() {
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/wg-easy.conf
    sysctl -p /etc/sysctl.d/wg-easy.conf >/dev/null || true
}

find_compose() {
    if docker compose version >/dev/null 2>&1; then
        COMPOSE="docker compose"
    elif command -v docker-compose >/dev/null; then
        COMPOSE="docker-compose"
    else
        echo "docker compose not installed."
        exit 1
    fi
}

install_docker() {
    case "$OS" in
        debian)
            apt-get update -y
            apt-get install -y docker.io docker-compose-plugin
            ;;
        amazon)
            amazon-linux-extras install docker -y
            systemctl enable --now docker
            ;;
        rhel)
            yum install -y docker docker-compose-plugin || true
            systemctl enable --now docker
            ;;
        *)
            echo "Unsupported OS"
            exit 1
            ;;
    esac
}

# ============================================================
# INSTALLATION PROCESS
# ============================================================

detect_os
detect_arch

header "WIREGUARD INSTALLER"

PRIVATE_IP=$(hostname -I | awk '{print $1}')
PUBLIC_IP=$(curl -s ifconfig.me || echo "$PRIVATE_IP")

echo "Private IP: $PRIVATE_IP"
echo "Public  IP: $PUBLIC_IP"
read -rp "WG_HOST [$PUBLIC_IP]: " HOST
HOST="${HOST:-$PUBLIC_IP}"

read -rp "WG Port [51820]: " WG_PORT
WG_PORT="${WG_PORT:-51820}"

read -rp "Admin EXTERNAL Port [80]: " ADMIN_PORT
ADMIN_PORT="${ADMIN_PORT:-80}"

echo
echo "DNS for clients:"
echo "1) Auto-detect"
echo "2) Cloudflare"
echo "3) Google"
echo "4) Quad9"
read -rp "DNS [1]: " DNSC

case "${DNSC:-1}" in
    1) DNS=$(awk '/^nameserver/ {print $2; exit}' /etc/resolv.conf) ;;
    2) DNS="1.1.1.1" ;;
    3) DNS="8.8.8.8" ;;
    4) DNS="9.9.9.9" ;;
esac

# Docker installation
if ! command -v docker >/dev/null; then
    install_docker
fi

find_compose
ensure_sysctl

# Installation directory
mkdir -p /etc/docker/containers/wg-easy
cd /etc/docker/containers/wg-easy

# Download compose
curl -fsSL -o docker-compose.yml \
    https://raw.githubusercontent.com/wg-easy/wg-easy/master/docker-compose.yml

# Write env
cat > .env <<EOF
WG_HOST=${HOST}
WG_PORT=${WG_PORT}
PORT=51821
WG_DEFAULT_DNS=${DNS}
WG_ALLOWED_IPS=0.0.0.0/0,::/0
EOF
chmod 600 .env

# Patch ports
sed -i "\|51820/udp|c\      - \"${PRIVATE_IP}:${WG_PORT}:51820/udp\"" docker-compose.yml
sed -i "\|51821/tcp|c\      - \"0.0.0.0:${ADMIN_PORT}:51821/tcp\"" docker-compose.yml

header "Starting wg-easy"
$COMPOSE up -d

echo
echo "=== INSTALL COMPLETE ==="
echo "WireGuard Endpoint: ${HOST}:${WG_PORT}"
echo "Admin UI: http://${PRIVATE_IP}:${ADMIN_PORT}"
echo "Config stored at: /etc/docker/containers/wg-easy/.env"

exit 0

