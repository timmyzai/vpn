# ⭐ **WireGuard Installer & Management Script**

---

# 🚀 **Overview**

A **universal, production-safe WireGuard VPN installer** powered by **wg-easy**, supporting all major Linux distributions and both x86_64 and ARM64.
Includes automated Docker setup, YAML patching, persistent config, healthcheck insertion, and ALB-friendly routing modes.

Designed for reliability, safety, and consistent behavior across environments.

---

# 🧪 **Tested Environment**

✔ **Ubuntu 24.04 ARM64**
✔ Works with **Public ALB (HTTPS → Private IP)**
✔ Works with **Private ALB (Internal HTTPS)**

⚠ Direct IP mode is *supported* but **not officially tested yet**.

---

# ⚙️ **Universal OS Compatibility**

**Supported Linux families:**

• Ubuntu 20.04 / 22.04 / 24.04
• Debian 10 / 11 / 12
• CentOS 7
• RHEL 7 / 8 / 9
• Rocky Linux 8 / 9
• AlmaLinux 8 / 9
• Fedora 34–40
• Amazon Linux 2
• Amazon Linux 2023

**Architectures:**
• x86_64
• ARM64

---

# 🔧 **Key Features**

### ✔ Fully Automated Installation

• Detects OS & architecture automatically
• Auto-installs Docker & Docker Compose
• Enables persistent IP forwarding
• Downloads and configures wg-easy
• Safe, idempotent re-run behavior

### ✔ Admin UI Routing Modes

• Direct IP (HTTP)
• Public ALB → Private Node (HTTPS)
• Private ALB → Private Node (Internal HTTPS)

### ✔ Production-Safe Defaults

• restart: unless-stopped
• Auto-injected healthcheck
• No hard-coded credentials
• Secure .env handling (600 permissions)

### ✔ YAML Auto-Patching

• WireGuard UDP port changes
• Admin UI port changes
• Automatic healthcheck block
• Automatic restart policy

### ✔ Zero-Password First Login

Admin credentials created on first visit.

### ✔ Maintenance Menu

• View logs
• Uninstall completely
• Change WG_HOST
• Exit

---

# 📥 **Installation Flow**

The installer performs the following automatically:

1. Detect OS + architecture
2. Install Docker + Compose plugin
3. Enable sysctl IP forwarding
4. Create persistent wg-easy folder
5. Download latest docker-compose.yml
6. Create .env config file
7. Patch ports and healthcheck
8. Start WireGuard service
9. Display WG endpoint + Admin URL

---

# ⚙️ **Configuration Prompts**

You will be asked for:

• WG_HOST
• Admin UI routing mode (Direct, Public ALB, Private ALB)
• WireGuard UDP port
• Admin UI port
• DNS resolver for VPN clients

DNS Options:

1. AWS VPC DNS
2. Cloudflare
3. Google
4. Quad9

---

# 📄 **Completion Summary**

Example final output:

Endpoint: `WG_HOST:WG_PORT/udp`
Admin UI:
• Direct IP → http://PRIVATE_IP:PORT
• Public ALB → HTTPS → http://PRIVATE_IP:PORT
• Private ALB → Internal HTTPS → http://PRIVATE_IP:PORT

Config directory:
`/etc/docker/containers/wg-easy/.env`

First login: system will ask you to create the admin account.

---

# 🔥 **Security Notes**

• Admin UI is HTTP internally (use ALB/NLB + ACM for HTTPS)
• DNS defaults to AWS VPC DNS for EC2 deployments
• WG_HOST updates safely restart wg-easy
• No passwords stored in script or .env

---

# 🗑️ **Uninstallation**

Re-run installer and select:
**Uninstall Completely**

Removes:
• Docker container
• Docker image
• wg-easy compose/YAML
• Persistent config folder

---

# 🧰 **Troubleshooting Guide**

**ALB Unhealthy:**
Check: [http://localhost:51821/health](http://localhost:51821/health)

**Client has no internet:**
Check NAT/firewalld rules (not configured in Option A)

**Docker failed to start:**
systemctl restart docker

---

# 🤝 **Contributing**

Pull requests welcome for:

• Additional OS refinements
• Docker repo improvements
• YAML patch optimizations
• Architecture-specific enhancements
• NAT/firewall add-on modules

---

# 📜 **License**

MIT License
© Timmy Chin Did Choong

---

