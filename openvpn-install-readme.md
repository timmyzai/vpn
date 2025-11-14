# 🚀 OpenVPN Installer & Management Script

A fully automated **OpenVPN installation & client management script** designed for **Debian/Ubuntu**. Supports **ECC keys**, **AES‑256‑GCM**, **TLS‑Crypt**, user management, IP override, firewall rules, and embedded `.ovpn` profiles.

---

## ✨ Features

### 🔐 Security & Cryptography

* AES‑256‑GCM encryption
* SHA‑256 authentication
* ECC (prime256v1) certificates
* `tls-crypt` key for TLS channel protection
* Strong default OpenVPN configuration

### 🌐 Network Features

* UDP (default) and TCP support
* Auto‑detects server public IP (manual override available)
* DNS options: System / Cloudflare / Google / Quad9
* Enables NAT forwarding with iptables

### 🛠️ Management Mode

When OpenVPN is already installed, the script switches to maintenance mode:

| Option | Action                                  |
| ------ | --------------------------------------- |
| 1      | Add new client                          |
| 2      | Revoke existing client                  |
| 3      | List all active users                   |
| 4      | Override public IP in all `.ovpn` files |
| 5      | Remove OpenVPN completely               |
| 6      | Exit                                    |

---

## 📦 Requirements

* Root privileges
* Debian/Ubuntu
* TUN device enabled
* Packages auto‑installed if missing:

  * openvpn
  * easy‑rsa
  * iptables
  * curl

---

## 📥 Installation

```bash
wget -O openvpn-install.sh https://your-github-link/openvpn-install.sh
chmod +x openvpn-install.sh
sudo ./openvpn-install.sh
```

---

## 🚀 First‑Time Setup Flow

### 1️⃣ Public IP

Auto‑detected from ifconfig.me (override allowed).

### 2️⃣ Port

Default: **1194**

### 3️⃣ Protocol

* UDP (recommended)
* TCP (for restrictive networks)

### 4️⃣ DNS Resolver

System / Cloudflare / Google / Quad9

### 5️⃣ Create First Client (Optional)

Profile stored in `/root/<name>.ovpn`.

---

## 👤 Client Management

### ➕ Add Client

Run script → choose option **1**.

### ➖ Revoke Client

Run script → choose option **2**.

### 📃 List Users

Run script → choose option **3**.

### 🌐 Override Public IP in All Profiles

Run script → choose option **4**.

---

## 📁 Output Location

Generated `.ovpn` files are stored in:

```
/root/<client-name>.ovpn
```

Each profile contains embedded:

* CA certificate
* Client certificate
* Client private key
* tls‑crypt key

---

## 🔥 Uninstallation

```bash
sudo ./openvpn-install.sh
# Choose option 5
```

Removes everything under `/etc/openvpn`.

---

## 🧱 Firewall Notes

Script configures NAT:

```bash
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -j MASQUERADE
echo 1 > /proc/sys/net/ipv4/ip_forward
```

If using UFW:

```bash
sudo ufw allow 1194/udp
sudo ufw allow OpenSSH
sudo ufw disable && sudo ufw enable
```

---

## ☑️ Verified On

| OS           | Status              |
| ------------ | ------------------- |
| Ubuntu 22.04 | ✅ Fully tested      |
| Ubuntu 20.04 | ✅                   |
| Debian 11    | ⚠️ Expected to work |
| CentOS/RHEL  | ❌ Not supported     |
| Amazon Linux | ❌ Not supported     |

---

## 📜 Notes

* Script automatically loads server PROTO & PORT for consistent `.ovpn` generation.
* ECC certificates improve performance and security.
* Client configs are fully self‑contained.

---

## 📄 License

MIT License

---
