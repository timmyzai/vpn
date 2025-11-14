# ⭐ **OpenVPN Installer & Management Script**

---

# 🚀 Overview

A fully automated OpenVPN installer with easy setup, ECC security, NAT configuration, and complete client management.
Designed for clean deployment, ALB integration, and simple maintenance.

---

# 🖥️ Tested Platform

✔️ **Ubuntu 24.04 (ARM64)**
✔️ Works with **Public ALB**
✔️ Works with **Private ALB**

⚠️ **Not tested yet:**
• Direct IP installation (without ALB)
• Other Linux distributions

---

# ⚙️ Compatibility (Supported but *NOT* tested)

• Debian / Ubuntu family
• RHEL / CentOS / Rocky / AlmaLinux
• Fedora
• Amazon Linux 2 / 2023

---

# 🔐 Security Features

• ECC certificates (prime256v1)
• AES-256-GCM encryption
• SHA-256 authentication
• tls-crypt tunnel protection
• Hardened server configuration

---

# 🌐 Networking Features

• Auto NAT (iptables / firewalld)
• Persistent IP forwarding
• UDP or TCP
• DNS options: Cloudflare, Google, Quad9, System
• Auto-detect server IP (can override)

---

# 🛠️ Maintenance Mode (If OpenVPN Exists)

1. Add VPN user
2. Revoke VPN user
3. List valid users
4. Update public IP in all .ovpn files
5. Uninstall OpenVPN
6. Exit menu

---

# 📦 Requirements

• Root access
• TUN device enabled
• Internet connection
• curl installed

Auto-installs:
• openvpn
• easy-rsa
• iptables/firewalld
• netfilter-persistent or iptables-persistent

---

# 📥 Installation

wget -O openvpn-install.sh [https://your-github-link/openvpn-install.sh](https://your-github-link/openvpn-install.sh)
chmod +x openvpn-install.sh
sudo ./openvpn-install.sh

---

# 🚀 Setup Flow

1️⃣ Detect server IP
2️⃣ Choose port (default 1194)
3️⃣ Choose protocol (UDP/TCP)
4️⃣ Select DNS resolver
5️⃣ Generate ECC PKI
6️⃣ Configure firewall + NAT
7️⃣ Enable & start OpenVPN

---

# 👥 Client Management

➕ Add new client (.ovpn auto-generated)
➖ Revoke client
📄 List active users
🌐 Overwrite public IP (regenerate all profiles)

Output directory:
`/root/<client-name>.ovpn`

---

# 🔥 Firewall Behavior

firewalld systems:
• Open VPN port
• Enable masquerade

iptables systems:
• MASQUERADE 10.8.0.0/24
• Enable IPv4 forwarding

---

# 🗑️ Uninstall

Run script → Choose option **5**
Removes:
• OpenVPN config
• Certificates
• CRL
• NAT rules (where possible)
• Systemd service

---

# 🤝 For Developers

• Fork the repository
• Test on more OS versions
• Test **Direct IP** mode
• Submit issues & PRs
• Share “working / not working” environments

Your feedback improves cross-platform support.

---

# 🎨 Canva Layout Ideas (As You Requested)

Here are **ready-to-design** Canva layout ideas:

### 🟦 Layout 1: Clean Tech Poster

• Title banner at top
• 4 wide columns: Security / Networking / Tested / Requirements
• Bottom strip: Installation command + QR code to GitHub

### 🟥 Layout 2: Step-by-Step Infographic

• Vertical timeline: Install → Setup → Manage → Uninstall
• Icons: Shield, Server, Network, User
• Use blue + grey theme for a “DevOps look”

### 🟩 Layout 3: Developer Contribution Card

• “Tested on Ubuntu 24.04 ARM64” badge
• “Not tested: Direct IP” section
• GitHub fork/share icons
• Big QR to repository

### 🟪 Layout 4: Documentation Slide (Presentation)

• Left: Server diagram (ALB → OpenVPN → Clients)
• Right: Feature list
• Footer: Compatibility + Tested platform

### 🟧 Layout 5: Minimal A4

• All sections in blocks
• Light grey background
• Big headings
• Professional, printable

---

📜 License & Disclaimer
MIT License

© Timmy Chin Did Choong

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES, OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

⚠️ Additional Disclaimer

This installer script is provided as-is, with no guarantees, no warranty, and no responsibility from the author.

By using, running, modifying, or deploying this script, you agree that:

• You assume full responsibility for any system changes or consequences
• The author is not liable for misconfiguration, downtime, data loss, security vulnerabilities, service disruption, or any unintended side effects
• You must review and validate the script before using it in any environment
• All use is strictly at your own risk
• This tool is intended for users familiar with Linux, networking, and VPN configuration

---
