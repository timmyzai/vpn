# ⭐ **OpenVPN Installer & Management Script**

### Automated • Secure • ALB-Compatible • ECC PKI • Multi-OS Support

---

# 🚀 Overview

A fully automated OpenVPN installation and management script designed for modern cloud setups, ALB routing (Public/Private), ECC cryptography, safe PKI generation, NAT/firewall automation, and easy client management.

Built with safety, idempotency, and maintainability in mind.

---

# 🖥️ Tested Platform (Verified)

✔ **Ubuntu 24.04 LTS (ARM64)**
✔ **Public ALB** (HTTPS → Private IP)
✔ **Private ALB** (Internal-only routing)

⚠ **Not tested yet** (supported but unverified):
• Direct IP mode (no ALB)
• Ubuntu x86_64
• RHEL / CentOS / Alma / Rocky / Fedora
• Amazon Linux 2 / Amazon Linux 2023

You are welcome to contribute more testing results.

---

# ⚙️ Supported Platforms (The Script Auto-Detects)

This script supports the following families:

• Debian / Ubuntu
• RHEL / CentOS / Rocky / AlmaLinux
• Fedora
• Amazon Linux 2
• Amazon Linux 2023

> Note: Only Ubuntu 24.04 ARM64 is confirmed working.

---

# 🔐 Security Features

• ECC Certificates (**prime256v1**)
• AES-256-GCM Encryption
• SHA-256 Authentication
• `tls-crypt` Key Protection
• Hardened OpenVPN server configuration
• Secure, automated EasyRSA PKI
• Status logging for monitoring

---

# 🌐 Networking Features

• Automatic NAT (iptables / firewalld)
• NAT duplication prevention
• Persistent IP forwarding
• Supports UDP or TCP
• DNS options:
– System resolver
– Cloudflare (1.1.1.1)
– Google (8.8.8.8)
– Quad9 (9.9.9.9)
• SELinux auto-handling on RHEL systems

---

# 🛠️ Maintenance Mode (Auto-detected if OpenVPN Already Exists)

Maintenance mode appears automatically when OpenVPN is installed.

Options:

1. Add client
2. Revoke client
3. List valid users
4. Override public IP in all .ovpn profiles
5. Clean uninstall (firewall + sysctl + config)
6. Exit

---

# 📦 Requirements

• Root access (auto elevates via sudo)
• TUN device enabled
• Internet access
• `curl` installed

Auto-installs:
• openvpn
• easy-rsa
• iptables / firewalld
• iptables-persistent / netfilter-persistent (Debian)

---

# 📥 Installation

```
wget -O openvpn-install.sh https://your-github-repo/openvpn-install.sh
chmod +x openvpn-install.sh
sudo ./openvpn-install.sh
```

---

# 🚀 Setup Flow

1. Detect public IP
2. Confirm/override IP
3. Choose port (default 1194)
4. Choose protocol (UDP/TCP)
5. Select DNS
6. Generate ECC PKI
7. Generate `tls-crypt` key
8. Configure NAT + firewall
9. Start OpenVPN service
10. Create first client (optional)

---

# 👥 Client Management

**Add new client**
• Creates `/root/<client>.ovpn`
• Bundles CA, cert, key, tls-crypt
• ECC certificate
• Optional password protection

**Revoke client**
• Updates CRL
• Restarts service

**List users**
• Reads index.txt from EasyRSA

**Override public IP**
• Rewrites all `.ovpn` files

---

# 🔥 Firewall Behavior

### firewalld systems:

• Opens OpenVPN port
• Enables masquerading
• Reloads configuration

### iptables systems:

• Adds NAT:
`MASQUERADE 10.8.0.0/24`
• Prevents duplicate NAT rules
• Persists rules via `netfilter-persistent` if available

---

# 🗑️ Uninstall (Clean Removal)

Maintenance Menu → Option 5
Removes:

• OpenVPN service & configs
• ECC keys + PKI
• sysctl forwarding rule
• NAT rules
• firewall-cmd or iptables cleanup (port + masquerade)

Uninstall leaves the server clean and safe.

---

# 🔍 Troubleshooting

**Client connects but no Internet**
• NAT missing
• Reinstall or reapply firewall rules

**ALB health check fails**
• Ensure port is open
• Check `openvpn-status.log`

**Service doesn’t start**
• Check SELinux (RHEL)
• Ensure ECC curve support

---

# 🤝 Contributing

You are welcome to:

• Fork this project
• Submit fixes or enhancements
• Test on more OSes
• Report issues
• Improve documentation

Especially helpful:

✔ Direct IP mode testing
✔ OS compatibility testing
✔ Firewall improvements
✔ Security hardening suggestions

---

# 📜 License & Disclaimer

**MIT License — © Timmy Chin Did Choong**

This software is provided **as-is**, without warranty or guarantee of any kind.
You accept full responsibility for any outcome of using this script.
The author is not liable for system issues, misconfiguration, security breaches, downtime, or legal/regulatory consequences from VPN usage.

This script is **not affiliated with OpenVPN, WireGuard, wg-easy, or any VPN provider.**

Use at your own risk.

---

# 🎨 Canva Layout Ideas (Optional)

### 🟦 **Layout 1: Feature Blocks**

• Large title banner
• Four feature boxes (Security, Networking, Maintenance, Requirements)
• Footer with installation command + QR code

### 🟩 **Layout 2: Technical Flowchart**

• Diagram: User → ALB → OpenVPN → Clients
• Steps aligned vertically
• Icons for encryption, firewall, DNS

### 🟥 **Layout 3: Minimal A4 Documentation**

• Clean headings
• Grey separators
• Ideal for printing or exporting to PDF

### 🟪 **Layout 4: Developer Card**

• Tested platform badges
• “Supported but untested” section
• GitHub fork instructions

---
