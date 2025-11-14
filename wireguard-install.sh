#!/bin/bash
set -euo pipefail

readonly WG_DIR="/etc/docker/containers/wg-easy"
readonly WG_ENV="$WG_DIR/.env"
readonly WG_COMPOSE="$WG_DIR/docker-compose.yml"
readonly ADMIN_PORT_INTERNAL=51821
readonly TIMEOUT=30
readonly AWS_VPC_DNS="169.254.169.253"

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
#  INSTALL DOCKER — UNIVERSAL ACROSS DISTROS
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

    # Compose plugin (manual install)
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
    local INDENT="      "

    awk -v pat="$pattern" -v rep="${INDENT}- \"$replace\"" '
        {
            if (index($0, pat) > 0 && !done) {
                print rep
                done=1
            }
            print
        }
    ' "$file" > "${file}.tmp"

    mv "${file}.tmp" "$file"
}

ensure_restart() {
    local file="$1"
    grep -q "restart: unless-stopped" "$file" && return 0
    sed -i "\|image:.*wg-easy|a\\    restart: unless-stopped" "$file"
}

inject_healthcheck() {
    local file="$1"
    grep -q "healthcheck:" "$file" && return 0

    sed -i '
      \|image: ghcr.io/wg-easy/wg-easy|a\
        healthcheck:\n\
          test: ["CMD", "curl", "-fsS", "http://localhost:51821/health"]\n\
          interval: 30s\n\
          timeout: 5s\n\
          retries: 3
    ' "$file"
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
echo "1) AWS VPC DNS"
echo "2) Cloudflare 1.1.1.1"
echo "3) Google 8.8.8.8"
echo "4) Quad9 9.9.9.9"
read -rp "DNS [1-4]: " D
D=${D:-1}

case "$D" in
    1) DNS="${AWS_VPC_DNS}" ;;
    2) DNS="1.1.1.1" ;;
    3) DNS="8.8.8.8" ;;
    4) DNS="9.9.9.9" ;;
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

set_port "51820/udp" "${BIND_IP}:${WG_PORT}:51820/udp" "$WG_COMPOSE"
set_port "${ADMIN_PORT_INTERNAL}/tcp" "0.0.0.0:${ADMIN_PORT}:${ADMIN_PORT_INTERNAL}/tcp" "$WG_COMPOSE"

ensure_restart "$WG_COMPOSE"
inject_healthcheck "$WG_COMPOSE"

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
