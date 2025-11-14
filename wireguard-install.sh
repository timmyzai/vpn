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
set -euo pipefail

# ============================================================
# MENU FUNCTIONS
# ============================================================

show_menu() {
    echo
    echo "==============================="
    echo "      WireGuard / wg-easy      "
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
# CLOUD CIDR AUTO-DETECTION
# ============================================================
get_cidr_by_cloud() {
    unset WG_VPC_CIDR
    WG_VPC_CIDR=""

    case "$1" in

        aws)
            TOKEN=$(curl -s --max-time 1 -X PUT \
                "http://169.254.169.254/latest/api/token" \
                -H "X-aws-ec2-metadata-token-ttl-seconds: 300" || true)

            MAC=$(curl -s --max-time 1 -H "X-aws-ec2-metadata-token: $TOKEN" \
                http://169.254.169.254/latest/meta-data/network/interfaces/macs/ | head -n 1)

            MAC="${MAC%%/}/"  # ensure trailing slash

            if [[ -n "$MAC" ]]; then
                WG_VPC_CIDR=$(curl -s --max-time 1 \
                    -H "X-aws-ec2-metadata-token: $TOKEN" \
                    "http://169.254.169.254/latest/meta-data/network/interfaces/macs/${MAC}vpc-ipv4-cidr-block")
            fi
            ;;

        gcp)
            IP=$(curl -s --max-time 1 -H "Metadata-Flavor: Google" \
                "http://169.254.169.254/computeMetadata/v1/instance/network-interfaces/0/ip")

            MASK=$(curl -s --max-time 1 -H "Metadata-Flavor: Google" \
                "http://169.254.169.254/computeMetadata/v1/instance/network-interfaces/0/subnetmask")

            if [[ -n "$IP" && -n "$MASK" ]]; then
                # Convert dotted mask (255.255.240.0) to prefix (/20)
                IFS='.' read -r m1 m2 m3 m4 <<< "$MASK"
                BITS=$(printf "%08d%08d%08d%08d" \
                    "$(bc <<< "obase=2;$m1")" \
                    "$(bc <<< "obase=2;$m2")" \
                    "$(bc <<< "obase=2;$m3")" \
                    "$(bc <<< "obase=2;$m4")")
                PREFIX=$(grep -o "1" <<< "$BITS" | wc -l)

                # Calculate network base (bitwise AND)
                IFS='.' read -r i1 i2 i3 i4 <<< "$IP"
                nw1=$((i1 & m1))
                nw2=$((i2 & m2))
                nw3=$((i3 & m3))
                nw4=$((i4 & m4))

                WG_VPC_CIDR="${nw1}.${nw2}.${nw3}.${nw4}/${PREFIX}"
            fi
            ;;

        azure)
            NET=$(curl -s --max-time 1 -H Metadata:true \
                "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/subnet/0/address?api-version=2021-02-01&format=text")

            PREFIX=$(curl -s --max-time 1 -H Metadata:true \
                "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/subnet/0/prefix?api-version=2021-02-01&format=text")

            [[ -n "$NET" && -n "$PREFIX" ]] && WG_VPC_CIDR="$NET/$PREFIX"
            ;;

        local)
            IFACE=$(ip route show default | awk '{print $5}')
            WG_VPC_CIDR=$(ip -4 addr show "$IFACE" | awk '/inet / {print $2}')
            ;;
    esac

    [[ -z "$WG_VPC_CIDR" ]] && return 1 || return 0
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
echo "Select DNS / Network Mode:"
echo "    1) Connect to Cloud VPC / Local Network"
echo "    2) System resolvers (/etc/resolv.conf)"
echo "    3) Unbound (127.0.0.1)"
echo "    4) Cloudflare"
echo "    5) Google"
echo "    6) Quad9 Secure"
echo "    7) Quad9 Unfiltered"
echo "    8) FDN"
echo "    9) DNS.WATCH"
echo "   10) OpenDNS"
echo "   11) Yandex"
echo "   12) AdGuard"
echo "   13) NextDNS"
echo "   14) Custom"
echo

DEFAULT_DNSC=1
DNSC=""

while true; do
    read -rp "DNS [1-14] (default: $DEFAULT_DNSC): " DNSC
    [[ -z "$DNSC" ]] && DNSC="$DEFAULT_DNSC"
    [[ "$DNSC" =~ ^[0-9]+$ && "$DNSC" -ge 1 && "$DNSC" -le 14 ]] && break
    echo "❌ Invalid selection."
done

case "$DNSC" in
    1)
        echo
        echo "Select Cloud Provider:"
        echo "    a) AWS"
        echo "    b) Google Cloud"
        echo "    c) Azure"
        echo "    d) Local / On-Prem"
        echo

        while true; do
            read -rp "Provider [a-d]: " CLOUD
            case "$CLOUD" in
                a) PROVIDER="aws"; break ;;
                b) PROVIDER="gcp"; break ;;
                c) PROVIDER="azure"; break ;;
                d) PROVIDER="local"; break ;;
                *) echo "Invalid. Enter a–d." ;;
            esac
        done

        echo "Detecting VPC CIDR from $PROVIDER..."

        if get_cidr_by_cloud "$PROVIDER"; then
            echo "CIDR detected: $WG_VPC_CIDR"

            VPC_BASE_IP=$(echo "$WG_VPC_CIDR" | cut -d'/' -f1)
            IFS='.' read -r o1 o2 o3 o4 <<< "$VPC_BASE_IP"

            case "$PROVIDER" in
                aws)
                    DNS_PRIMARY="${o1}.${o2}.${o3}.$((o4 + 2))"
                    ;;
                gcp)
                    # GCP internal DNS (always available)
                    DNS_PRIMARY="169.254.169.254"
                    ;;
                azure)
                    DNS_PRIMARY="${o1}.${o2}.${o3}.$((o4 + 1))"
                    ;;
                local)
                    DNS_PRIMARY="${o1}.${o2}.${o3}.$((o4 + 1))"
                    ;;
            esac

            DNS="${DNS_PRIMARY}"
            echo "Using Cloud DNS: $DNS"
        else
            echo "❌ Cloud VPC CIDR detection failed ($PROVIDER)."
            echo "Metadata unavailable. Installation stopped."
            exit 1
        fi
        ;;

    2) DNS=$(awk '/^nameserver/ {print $2; exit}' /etc/resolv.conf) ;;
    3) DNS="127.0.0.1" ;;
    4) DNS="1.1.1.1" ;;
    5) DNS="8.8.8.8" ;;
    6) DNS="9.9.9.9" ;;
    7) DNS="9.9.9.10" ;;
    8) DNS="80.67.169.12" ;;
    9) DNS="84.200.69.80" ;;
    10) DNS="208.67.222.222" ;;
    11) DNS="77.88.8.8" ;;
    12) DNS="94.140.14.14" ;;
    13) DNS="8.8.8.8" ;;
    14)
        read -rp "Custom DNS: " CUSTOMDNS
        DNS="$CUSTOMDNS"
        ;;
esac

# Install docker if needed
if ! command -v docker >/dev/null; then
    install_docker
fi

find_compose
ensure_sysctl

# Install directory
mkdir -p /etc/docker/containers/wg-easy
cd /etc/docker/containers/wg-easy

# Generate admin password
WG_PASSWORD=$(openssl rand -base64 16)

# ------------------------------------------------------------
# docker-compose.yml
# ------------------------------------------------------------
cat > docker-compose.yml <<EOF
services:
  wg-easy:
    image: ghcr.io/wg-easy/wg-easy:15
    container_name: wg-easy

    environment:
      - INIT_ENABLED=true
      - INIT_USERNAME=admin
      - INIT_PASSWORD=${WG_PASSWORD}
      - INIT_HOST=${HOST}
      - INIT_PORT=${WG_PORT}
      - INIT_DNS=${DNS}

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

# ------------------------------------------------------------
# DONE
# ------------------------------------------------------------
echo
echo "=== INSTALL COMPLETE ==="
echo "WireGuard Endpoint: ${HOST}:${WG_PORT}"
echo "Admin UI: http://${PRIVATE_IP}:${ADMIN_PORT}"
echo "Admin User: admin"
echo -e "Admin Password: \033[1m${WG_PASSWORD}\033[0m"

echo
echo "ALB Health Check:"
echo "Path: /login"
echo "Port: 51821"
echo "Codes: 200"
echo

exit 0
