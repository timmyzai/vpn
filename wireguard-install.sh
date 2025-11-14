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

readonly WG_DIR="/etc/docker/containers/wg-easy"
readonly WG_ENV="$WG_DIR/.env"
readonly WG_COMPOSE="$WG_DIR/docker-compose.yml"
readonly ADMIN_PORT_INTERNAL=51821
readonly TIMEOUT=30

# ------------------------------------------------------------
#  AUTO-DETECT SYSTEM DNS (Cloud-agnostic + systemd-aware)
# ------------------------------------------------------------

detect_system_dns() {
    local resolvconf

    # If using systemd-resolved stub (127.0.0.53), use actual upstream file
    if grep -q "127.0.0.53" "/etc/resolv.conf"; then
        resolvconf="/run/systemd/resolve/resolv.conf"
    else
        resolvconf="/etc/resolv.conf"
    fi

    # Extract the first valid IPv4 DNS server
    local dns
    dns=$(awk '/^nameserver/ && $2 !~ /^127\./ && $2 ~ /^[0-9.]+$/ {print $2; exit}' "$resolvconf")

    if [[ -z "$dns" ]]; then
        echo "ERROR: Could not auto-detect DNS from $resolvconf" >&2
        exit 1
    fi

    echo "$dns"
}

# ------------------------------------------------------------
#  UTILITY FUNCTIONS
# ------------------------------------------------------------

header() { echo -e "\n=== $1 ===\n"; }

detect_os() {
    if [ -e /etc/debian_version ]; then
        OS="debian"
    elif [ -e /etc/redhat-release ]; then
        OS="rhel"
    elif grep -qi "amazon linux" /etc/os-release; then
        OS="amazon"
    elif grep -qi "fedora" /etc/os-release; then
        OS="fedora"
    else
        echo "Unsupported OS"
        exit 1
    fi
}

detect_arch() {
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64) ARCH="amd64" ;;
        aarch64 | arm64) ARCH="arm64" ;;
        *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
    esac
}

ensure_sysctl() {
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/wg-easy.conf
    sysctl -p /etc/sysctl.d/wg-easy.conf >/dev/null 2>&1 || true
}

find_compose() {
    if docker compose version >/dev/null 2>&1; then
        COMPOSE="docker compose"
    elif command -v docker-compose >/dev/null 2>&1; then
        COMPOSE="docker-compose"
    else
        echo "ERROR: docker compose plugin not found"
        exit 1
    fi
}

get_public_ip() {
    ip=$(timeout 5 curl -s ifconfig.me || true)
    [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && echo "$ip" || echo "$1"
}

# ------------------------------------------------------------
#  INSTALL DOCKER
# ------------------------------------------------------------

install_docker_debian() {
    apt-get update -y
    apt-get install -y ca-certificates curl gnupg lsb-release

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    . /etc/os-release
    echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/${ID} ${VERSION_CODENAME} stable" \
        > /etc/apt/sources.list.d/docker.list

    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
}

install_docker_rhel() {
    yum install -y yum-utils device-mapper-persistent-data lvm2
    yum-config-manager --add-repo \
        https://download.docker.com/linux/centos/docker-ce.repo

    yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
}

install_docker_fedora() {
    dnf -y install dnf-plugins-core
    dnf config-manager --add-repo \
        https://download.docker.com/linux/fedora/docker-ce.repo

    dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
}

install_docker_amazon2() {
    amazon-linux-extras install docker -y
    systemctl enable --now docker

    local version="v2.24.4"
    curl -SL "https://github.com/docker/compose/releases/download/${version}/docker-compose-linux-${ARCH}" \
        -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
}

install_docker_amazon2023() {
    dnf install -y dnf-plugins-core
    dnf config-manager --add-repo \
        https://download.docker.com/linux/fedora/docker-ce.repo

    dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
}

install_docker() {
    case "$OS" in
        debian) install_docker_debian ;;
        rhel)   install_docker_rhel ;;
        fedora) install_docker_fedora ;;
        amazon)
            if grep -q "Amazon Linux 2" /etc/os-release; then
                install_docker_amazon2
            else
                install_docker_amazon2023
            fi
            ;;
    esac

    systemctl enable --now docker || true
}

# ------------------------------------------------------------
#  FILE PATCHING FUNCTIONS
# ------------------------------------------------------------

set_port() {
    local pattern="$1"
    local replace="$2"
    local file="$3"

    # Use | as the sed delimiter so patterns with / (like 51820/udp) are safe
    sed -i "\|${pattern}|c\      - \"${replace}\"" "$file"
}

ensure_restart() {
    local file="$1"
    grep -q "restart: unless-stopped" "$file" && return 0
    sed -i '\|image:.*wg-easy|a\    restart: unless-stopped' "$file"
}

# ------------------------------------------------------------
#  MAIN LOGIC
# ------------------------------------------------------------

detect_os
detect_arch

header "WIREGUARD INSTALLER (Universal Production Version)"

PRIVATE_IP=$(hostname -I | awk '{print $1}')
PUBLIC_IP=$(get_public_ip "$PRIVATE_IP")

echo "Private: $PRIVATE_IP"
echo "Public : $PUBLIC_IP"

read -rp "WG_HOST [$PUBLIC_IP]: " WG_HOST
WG_HOST="${WG_HOST:-$PUBLIC_IP}"

echo
echo "Admin UI Exposure:"
echo "1) Direct IP (HTTP)"
echo "2) Public ALB (HTTPS → private)"
echo "3) Private ALB (Internal HTTPS)"
read -rp "Mode [3]: " UI_MODE
UI_MODE=${UI_MODE:-3}

BIND_IP="$PRIVATE_IP"

read -rp "WG Port [51820]: " WG_PORT
WG_PORT=${WG_PORT:-51820}

read -rp "Admin EXTERNAL Port [80]: " ADMIN_PORT
ADMIN_PORT=${ADMIN_PORT:-80}

echo
echo "DNS for clients:"
echo "1) Use system DNS (auto-detect from /etc/resolv.conf) — recommended"
echo "2) Cloudflare 1.1.1.1"
echo "3) Google 8.8.8.8"
echo "4) Quad9 9.9.9.9"
read -rp "DNS [1-4]: " D
D=${D:-1}

case "$D" in
    1) DNS="$(detect_system_dns)" ;;
    2) DNS="1.1.1.1" ;;
    3) DNS="8.8.8.8" ;;
    4) DNS="9.9.9.9" ;;
    *) DNS="$(detect_system_dns)" ;;
esac

ensure_sysctl

if ! command -v docker >/dev/null 2>&1; then
    header "Installing Docker"
    install_docker
fi

find_compose

mkdir -p "$WG_DIR"
cd "$WG_DIR"

curl -fsSL -o docker-compose.yml \
    https://raw.githubusercontent.com/wg-easy/wg-easy/master/docker-compose.yml

cat > .env <<EOF
WG_HOST=${WG_HOST}
WG_PORT=${WG_PORT}
PORT=${ADMIN_PORT_INTERNAL}
WG_DEFAULT_DNS=${DNS}
WG_ALLOWED_IPS=0.0.0.0/0,::/0
EOF

chmod 600 .env

# Patch docker-compose.yml
set_port "51820/udp" "${BIND_IP}:${WG_PORT}:51820/udp" "$WG_COMPOSE"
set_port "${ADMIN_PORT_INTERNAL}/tcp" "0.0.0.0:${ADMIN_PORT}:${ADMIN_PORT_INTERNAL}/tcp" "$WG_COMPOSE"

ensure_restart "$WG_COMPOSE"

header "Starting wg-easy"
timeout "$TIMEOUT" $COMPOSE -f "$WG_COMPOSE" up -d

header "INSTALL COMPLETE"
echo "Endpoint: ${WG_HOST}:${WG_PORT}/udp"
echo
echo "Admin UI:"
case "$UI_MODE" in
    1) echo "http://${PRIVATE_IP}:${ADMIN_PORT}" ;;
    2) echo "HTTPS via PUBLIC ALB → http://${PRIVATE_IP}:${ADMIN_PORT}" ;;
    3) echo "HTTPS via PRIVATE ALB → http://${PRIVATE_IP}:${ADMIN_PORT}" ;;
esac

echo
echo "Config stored in: $WG_ENV"
echo "Admin will be created on first visit."
exit 0
