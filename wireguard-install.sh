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
#   security breaches, unauthorized access, privacy exposure, or any operational
#   or financial impact caused by using this script.
# • You acknowledge that VPN deployment, encryption usage, and network tunneling
#   may be subject to local laws, regulations, or compliance requirements.
#   You are fully responsible for ensuring your own legal and regulatory compliance.
# • The author provides NO warranty that the script is secure, bug-free, or
#   appropriate for production environments.
# • The author provides NO obligation for updates, patches, security fixes, or support.
# • You must independently review, validate, and test this script before deploying it
#   in any environment, including development, testing, staging, or production.
# • If you modify, redistribute, or use a modified version of this script, you assume
#   full responsibility for any consequences arising from your changes.
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
    echo "     WireGuard / wg-easy       "
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
    endif
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
echo "Public  IP: $PUBLIC_IP"
read -rp "WG_HOST [$PUBLIC_IP]: " HOST
HOST="${HOST:-$PUBLIC_IP}"

read -rp "WG Port [51820]: " WG_PORT
WG_PORT="${WG_PORT:-51820}"

read -rp "Admin EXTERNAL Port [80]: " ADMIN_PORT
ADMIN_PORT="${ADMIN_PORT:-80}"

echo
echo "What DNS resolvers do you want to use with the VPN?"
echo "   1) Current system resolvers (from /etc/resolv.conf)"
echo "   2) Self-hosted DNS Resolver (Unbound) - Needs manual setup later"
echo "   3) Cloudflare (Anycast: worldwide, 1.1.1.1)"
echo "   4) Quad9 (Anycast: worldwide, Security: 9.9.9.9)"
echo "   5) Quad9 uncensored (Anycast: worldwide, Unfiltered: 9.9.9.10)"
echo "   6) FDN (France, Privacy-focused: 80.67.169.12)"
echo "   7) DNS.WATCH (Germany, Unfiltered/No-logging: 84.200.69.80)"
echo "   8) OpenDNS (Anycast: worldwide, Security/Parental Control: 208.67.222.222)"
echo "   9) Google (Anycast: worldwide, 8.8.8.8)"
echo "   10) Yandex Basic (Russia, 77.88.8.8)"
echo "   11) AdGuard DNS (Anycast: worldwide, Ad-blocking: 94.140.14.14)"
echo "   12) NextDNS (Customizable filtering) - Not supported by single IP"
echo "   13) Custom"

# Input reading loop and validation for options 1 through 13
until [[ $DNSC =~ ^[0-9]+$ ]] && [ "$DNSC" -ge 1 ] && [ "$DNSC" -le 13 ]; do
    read -rp "DNS [1-13]: " -e -i 3 DNSC # Setting default to 3 (Cloudflare)
done

# Assign the DNS variable (which is used in the docker-compose.yml)
case "$DNSC" in
    1) DNS=$(awk '/^nameserver/ {print $2; exit}' /etc/resolv.conf) ;;
    2) DNS="127.0.0.1" ;; # Use localhost, requires Unbound setup later
    3) DNS="1.1.1.1" ;;
    4) DNS="9.9.9.9" ;;
    5) DNS="9.9.9.10" ;;
    6) DNS="80.67.169.12" ;;
    7) DNS="84.200.69.80" ;;
    8) DNS="208.67.222.222" ;;
    9) DNS="8.8.8.8" ;;
    10) DNS="77.88.8.8" ;;
    11) DNS="94.140.14.14" ;;
    12) DNS="8.8.8.8" ;; # Fallback/Default for NextDNS as it needs custom client config
    13) 
        # For simplicity in this script, Custom defaults to Google DNS. 
        # A full script would require a prompt for DNS1/DNS2 here.
        read -rp "Enter Custom Primary DNS IP: " CUSTOM_DNS
        DNS="${CUSTOM_DNS:-8.8.8.8}"
        ;;
    *) DNS="1.1.1.1" ;; # Safety fallback
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

# === NEW: Generate and store password in a variable ===
WG_PASSWORD=$(openssl rand -base64 16)
# ======================================================

# ------------------------------------------------------------
# Write our own clean, stable docker-compose.yml
# ------------------------------------------------------------
cat > docker-compose.yml <<EOF
services:
  wg-easy:
    image: ghcr.io/wg-easy/wg-easy:15
    container_name: wg-easy

    environment:
      # --- Unattended Setup (only works on FIRST START) ---
      - INIT_ENABLED=true
      - INIT_USERNAME=admin
      - INIT_PASSWORD=${WG_PASSWORD} # <-- NOW USING THE VARIABLE
      - INIT_HOST=${HOST}
      - INIT_PORT=${WG_PORT}
      - INIT_DNS=${DNS}

      # --- Normal runtime values (for UI + client config) ---
      - WG_HOST=${HOST}
      - WG_PORT=${WG_PORT}
      - PORT=51821
      - WG_ALLOWED_IPS=0.0.0.0/0,::/0

    volumes:
      - etc_wireguard:/etc/wireguard
      - /lib/modules:/lib/modules:ro

    ports:
      - "${PRIVATE_IP}:${WG_PORT}:51820/udp"
      - "0.0.0.0:${ADMIN_PORT}:51821/tcp"

    restart: unless-stopped

    cap_add:
      - NET_ADMIN
      - SYS_MODULE

    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.src_valid_mark=1
      - net.ipv6.conf.all.disable_ipv6=0
      - net.ipv6.conf.all.forwarding=1
      - net.ipv6.conf.default.forwarding=1

volumes:
  etc_wireguard:
EOF

header "Starting wg-easy"
$COMPOSE up -d

echo
echo "=== INSTALL COMPLETE ==="
echo "WireGuard Endpoint: ${HOST}:${WG_PORT}"
echo "Admin UI: http://${PRIVATE_IP}:${ADMIN_PORT}"
# === NEW: Print the password here ===
echo "Admin User: admin"
echo -e "Admin Password: \033[1m${WG_PASSWORD}\033[0m" # Bold the password for visibility
# ===================================

# ------------------------------------------------------------
# ALB Health Check Recommendation
# ------------------------------------------------------------
echo "Protocol: HTTP"
echo "Port: 51821"
echo "Path: /setup/1"
echo "Success codes: 200"
echo "Healthy threshold: 2"
echo "Unhealthy threshold: 5"
echo "Timeout: 5 seconds"
echo "Interval: 10–30 seconds"
exit 0
