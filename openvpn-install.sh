#!/bin/bash
# ------------------------------------------------------------
# 📜 License & Disclaimer (Enhanced Protection)
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

# Root enforcement
if [ "$EUID" -ne 0 ]; then
    echo "⚠️ Re-running with sudo..."
    sudo bash "$0" "$@"
    exit $?
fi

# --- Config ---
readonly EASY_RSA_DIR="/etc/openvpn/easy-rsa"
readonly OPEN_VPN_SERVER_CONF="/etc/openvpn/server/server.conf"

# --- Helpers ---
header() { echo -e "\n===== $1 =====\n"; }

detect_os() {
    if [ -e /etc/debian_version ]; then echo debian
    elif [ -e /etc/redhat-release ]; then echo rhel
    elif [ -e /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            ubuntu|debian) echo debian ;;
            centos|rhel|rocky|almalinux|fedora|amzn) echo rhel ;;
            *) echo unsupported ;;
        esac
    else echo unsupported; fi
}

check_pkg() {
    for pkg in "$@"; do
        if command -v "$pkg" >/dev/null 2>&1 || ( [ "$pkg" = "easy-rsa" ] && [ -d /usr/share/easy-rsa ] ); then
            continue
        fi
        if command -v apt-get >/dev/null 2>&1; then
            apt-get install -y "$pkg" >/dev/null 2>&1 || true
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y "$pkg" >/dev/null 2>&1 || true
        elif command -v yum >/dev/null 2>&1; then
            yum install -y "$pkg" >/dev/null 2>&1 || true
        fi
    done
}

# --- Safe easyrsa binary auto-locator ---
find_easyrsa_bin() {
    local base="$1"
    local bin
    bin=$(find "$base" -type f -name easyrsa | head -n1 || true)
    if [ -z "$bin" ]; then
        echo "❌ ERROR: easyrsa binary not found inside: $base"
        exit 1
    fi
    echo "$bin"
}

# ---------------- CLIENT CREATOR ----------------
new_client() {
    N="$1"
    cd "$EASY_RSA_DIR"

    read -rp "Password protect client? [y/N]: " PW
    PASSOPT=$([[ ${PW,,} == y ]] && echo --pass || echo nopass)

    EASYRSA_BATCH=1 "$EASYRSA_BIN" gen-req "$N" $PASSOPT
    echo "yes" | EASYRSA_BATCH=1 "$EASYRSA_BIN" sign-req client "$N"

    OUT="/root/$N.ovpn"
    PROTO=$(awk '/^proto/ {print $2}' "$OPEN_VPN_SERVER_CONF")
    PORT=$(awk '/^port/ {print $2}' "$OPEN_VPN_SERVER_CONF")

cat > "$OUT" <<EOF
client
dev tun
proto $PROTO
remote $PUBLIC_IP $PORT
cipher AES-256-GCM
auth SHA256
resolv-retry infinite
nobind
persist-key
persist-tun
redirect-gateway def1
remote-cert-tls server
<ca>
$(cat pki/ca.crt)
</ca>
<cert>
$(awk '/BEGIN/,/END/' pki/issued/$N.crt)
</cert>
<key>
$(cat pki/private/$N.key)
</key>
<tls-crypt>
$(cat /etc/openvpn/ta.key)
</tls-crypt>
EOF

    [[ "$PROTO" == udp ]] && echo "explicit-exit-notify 1" >> "$OUT"

    echo "✅ Client created: $OUT"
}

# ---------------- INITIAL CHECKS ----------------
OS_TYPE=$(detect_os)
[[ "$OS_TYPE" = unsupported ]] && { echo "Unsupported OS"; exit 1; }
[[ ! -e /dev/net/tun ]] && { echo "TUN not enabled"; exit 1; }

LOCAL_IP=$(hostname -I | awk '{print $1}')
PUBLIC_IP=$(curl -4 -s ifconfig.me || echo "$LOCAL_IP")

export PUBLIC_IP LOCAL_IP

# ---------------- EXISTING INSTALL ----------------
if [ -f "$OPEN_VPN_SERVER_CONF" ]; then
    header "OPENVPN DETECTED"

    export PROTO=$(awk '/^proto/ {print $2}' "$OPEN_VPN_SERVER_CONF")
    export PORT=$(awk '/^port/ {print $2}' "$OPEN_VPN_SERVER_CONF")

    echo "1) Add user"
    echo "2) Revoke user"
    echo "3) List users"
    echo "4) Override public IP"
    echo "5) Uninstall OpenVPN"
    echo "6) Exit"
    read -rp "Choice: " CH

    case $CH in
        1)
            read -rp "Client name: " N
            new_client "$N"
            exit;;
        2)
            USERS=($(awk '/V/ {print $NF}' "$EASY_RSA_DIR/pki/index.txt"))
            [[ ${#USERS[@]} -eq 0 ]] && { echo "No users"; exit; }
            for i in "${!USERS[@]}"; do echo "$((i+1))) ${USERS[$i]}"; done
            read -rp "Select: " IDX
            SEL=${USERS[$((IDX-1))]}
            cd "$EASY_RSA_DIR"
            echo yes | EASYRSA_BATCH=1 "$EASYRSA_BIN" revoke "$SEL"
            EASYRSA_BATCH=1 "$EASYRSA_BIN" gen-crl
            cp pki/crl.pem /etc/openvpn/server/crl.pem
            systemctl restart openvpn-server@server
            echo "Revoked: $SEL"
            exit;;
        3)
            awk '/V/ {print $NF}' "$EASY_RSA_DIR/pki/index.txt"
            exit;;
        4)
            read -rp "New Public IP: " NEWIP
            for f in /root/*.ovpn; do sed -i "s/^remote .*/remote $NEWIP $PORT/" "$f"; done
            echo "Updated profiles"
            exit;;
        5)
            systemctl disable --now openvpn-server@server || true
            rm -rf /etc/openvpn /etc/sysctl.d/99-openvpn.conf
            echo "OpenVPN removed"
            exit;;
        *) exit;;
    esac
fi

# ---------------- INSTALL DEPENDENCIES ----------------
header "INSTALLING DEPENDENCIES"

if [ "$OS_TYPE" = debian ]; then
    check_pkg openvpn easy-rsa iptables curl iptables-persistent netfilter-persistent
else
    check_pkg openvpn iptables curl
    if [ ! -d /usr/share/easy-rsa ]; then
        echo "Installing EasyRSA source..."
        VER=3.1.7
        URL="https://github.com/OpenVPN/easy-rsa/releases/download/v${VER}/EasyRSA-${VER}.tgz"
        TMP=$(mktemp -d)
        curl -L "$URL" -o "$TMP/e.tgz"
        tar -xf "$TMP/e.tgz" -C "$TMP"
        mkdir -p /usr/share/easy-rsa
        mv "$TMP/EasyRSA-${VER}/"* /usr/share/easy-rsa/
        rm -rf "$TMP"
    fi
    check_pkg iptables-services
fi

# ---------------- INTERACTIVE SETUP ----------------
header "INTERACTIVE SETUP"

echo "Detected Public IP: $PUBLIC_IP"
read -rp "Override? [y/N]: " O
[[ ${O,,} == y ]] && read -rp "Enter new IP: " PUBLIC_IP

read -rp "OpenVPN Port (default 1194): " PORT
PORT=${PORT:-1194}

read -rp "Protocol 1)UDP 2)TCP [1]: " P
[[ ${P:-1} == 2 ]] && PROTO=tcp || PROTO=udp

echo "DNS: 1)System 2)Cloudflare 3)Google 4)Quad9"
read -rp "DNS [1]: " D
case ${D:-1} in
    1) DNS=$(awk '/nameserver/ {print $2;exit}' /etc/resolv.conf);;
    2) DNS=1.1.1.1;;
    3) DNS=8.8.8.8;;
    4) DNS=9.9.9.9;;
esac

# ---------------- EASYRSA SETUP ----------------
header "SETTING UP EASYRSA PKI"

rm -rf "$EASY_RSA_DIR"
cp -r /usr/share/easy-rsa "$EASY_RSA_DIR"

EASYRSA_BIN=$(find_easyrsa_bin "$EASY_RSA_DIR")
chmod +x "$EASYRSA_BIN"

cd "$EASY_RSA_DIR"
cat > vars <<EOF
set_var EASYRSA_ALGO ec
set_var EASYRSA_CURVE prime256v1
EOF

"$EASYRSA_BIN" init-pki
EASYRSA_BATCH=1 "$EASYRSA_BIN" build-ca nopass
EASYRSA_BATCH=1 "$EASYRSA_BIN" gen-req server nopass
echo yes | EASYRSA_BATCH=1 "$EASYRSA_BIN" sign-req server server

openvpn --genkey --secret /etc/openvpn/ta.key

mkdir -p /etc/openvpn/server

cat > "$OPEN_VPN_SERVER_CONF" <<EOF
port $PORT
proto $PROTO
dev tun
dh none
ecdh-curve prime256v1
cipher AES-256-GCM
auth SHA256
tls-crypt /etc/openvpn/ta.key
server 10.8.0.0 255.255.255.0
push "redirect-gateway def1"
push "dhcp-option DNS $DNS"
ca /etc/openvpn/easy-rsa/pki/ca.crt
cert /etc/openvpn/easy-rsa/pki/issued/server.crt
key /etc/openvpn/easy-rsa/pki/private/server.key
crl-verify /etc/openvpn/server/crl.pem
verb 3
EOF

touch /etc/openvpn/server/crl.pem

# ---------------- FIREWALL ----------------
header "CONFIGURING FIREWALL"

echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-openvpn.conf
sysctl --system >/dev/null

if command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --add-port="$PORT/$PROTO" --permanent
    firewall-cmd --add-masquerade --permanent
    firewall-cmd --reload
else
    iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -j MASQUERADE
    if command -v netfilter-persistent >/dev/null; then
        netfilter-persistent save
    elif command -v service >/dev/null && service iptables save; then
        :
    else
        echo "⚠ iptables rule may not persist reboot"
    fi
fi

# ---------------- START OPENVPN ----------------
header "STARTING OPENVPN"

systemctl enable openvpn-server@server
systemctl restart openvpn-server@server

echo "✅ OpenVPN installed at: $PUBLIC_IP:$PORT ($PROTO)"

read -rp "Create first client? [Y/n]: " C
if [[ ${C,,} != n ]]; then
    read -rp "Client name: " NN
    new_client "$NN"
fi

exit 0
