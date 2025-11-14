Universal WireGuard VPN Installer (wg-easy)
# WireGuard VPN Installer (wg-easy)
A **universal, fully automated WireGuard VPN installer** using **wg-easy**, supporting:

✅ Ubuntu / Debian
✅ CentOS / RHEL / Rocky / AlmaLinux
✅ Fedora
✅ Amazon Linux 2
✅ Amazon Linux 2023
✅ ARM64 & x86_64
----------------

## 🚀 Features

### ✔ **Fully Automated Installation**

* Auto-installs Docker + Docker Compose Plugin
* Auto-downloads wg-easy
* Auto-patches docker-compose.yaml safely
* Auto-configures ports based on your input
* Auto-enables IP forwarding (sysctl persistent)
* Auto-detects OS and applies correct install logic

### ✔ **Admin UI Routing Modes**

* Direct IP (Private IP HTTP)
* Public ALB (HTTPS → Private IP)
* Private ALB (Internal HTTPS → Private IP)

### ✔ **Zero-Password First Login**

wg-easy will **ask to create an admin account** on first login (more secure).

### ✔ **Healthcheck Included**

A built-in `HTTP /health` endpoint ensures:

* ALB/NLB can perform health checks
* Docker keeps restarting if unhealthy

### ✔ **Safe & Idempotent**

Re-running the script:

* Does NOT break configuration
* Re-applies patches cleanly
* Ensures Docker is healthy
* Ensures ports are correct

### ✔ **Maintenance Menu**

If wg-easy is already installed, you will see:

```
1) View Logs
2) Uninstall Completely
3) Change WG_HOST
4) Exit
```

---

# 📦 Supported Operating Systems

| OS                | Version       | Status         |
| ----------------- | ------------- | -------------- |
| Ubuntu            | 20.04, 22.04+ | ✅ Full Support |
| Debian            | 10, 11, 12    | ✅ Full Support |
| CentOS            | 7             | ✅ Full Support |
| RHEL              | 7, 8, 9       | ✅ Full Support |
| Rocky Linux       | 8, 9          | ✅ Full Support |
| AlmaLinux         | 8, 9          | ✅ Full Support |
| Fedora            | 34–40         | ✅ Full Support |
| Amazon Linux 2    | Latest        | ✅ Full Support |
| Amazon Linux 2023 | Latest        | ✅ Full Support |

---

# 📥 Installation

Run as **standard user or root** — the script automatically elevates privileges.

```bash
curl -o wireguard-install.sh https://raw.githubusercontent.com/YOUR_GITHUB_REPO/wireguard-install.sh
chmod +x wireguard-install.sh
./wireguard-install.sh
```

The script will:

1. Detect your OS
2. Install Docker (correct method for your OS)
3. Install Docker Compose Plugin
4. Configure IP forwarding
5. Download wg-easy
6. Patch compose file
7. Start wg-easy

---

# ⚙️ Configuration Prompts

Example prompts:

```
Private: 172.31.24.10
Public : 18.144.19.120

WG_HOST [18.144.19.120]:

Admin UI Exposure:
1) Direct IP (HTTP)
2) Public ALB + Route53 (HTTPS)
3) Private ALB + Route53 (Internal)
Mode [3]:

WG Port [51820]:
Admin EXTERNAL Port [80]:

------ DNS RESOLVER ------
1) AWS VPC DNS
2) Cloudflare 1.1.1.1
3) Google 8.8.8.8
4) Quad9 9.9.9.9
DNS [1-4]:
```

---

# 📄 Output After Installation

```
=== INSTALL COMPLETE ===

Endpoint: WG_HOST:WG_PORT/udp

Admin UI:
http://PRIVATE_IP:PORT
(Or via ALB depending on your routing mode)

Config stored in: /etc/docker/containers/wg-easy/.env
⚠️ On first login, wg-easy will prompt you to create an ADMIN user/password.
```

---

# 🔥 Security Notes

* Admin UI **runs HTTP internally**
* Use ALB/NLB + ACM Certificate for **HTTPS**
* WG_HOST updates automatically trigger container restart
* DNS defaults to AWS VPC DNS when installed inside EC2

---

# 🔧 Uninstallation

To completely remove wg-easy:

```bash
./wireguard-install.sh
```

Choose:

```
2) Uninstall Completely
```

This removes:

* Docker container
* Docker image
* All wg-easy configuration
* All patched compose files
* Directories under `/etc/docker/containers/wg-easy`

---

# 🔍 Maintenance Commands

### View Logs

```
docker logs -f wg-easy
```

### Restart Service

```
docker restart wg-easy
```

### Update WG_HOST manually

```
nano /etc/docker/containers/wg-easy/.env
docker compose -f /etc/docker/containers/wg-easy/docker-compose.yml down
docker compose -f /etc/docker/containers/wg-easy/docker-compose.yml up -d
```

---

# 🛠️ Troubleshooting

### Client connects but no Internet

Enable NAT on RHEL/Fedora:

```
firewall-cmd --add-masquerade --permanent
firewall-cmd --reload
```

### ALB shows unhealthy

Confirm wg-easy healthcheck:

```
curl http://localhost:51821/health
```

### Docker not running

```
systemctl restart docker
```

---

# 🤝 Contributing

Pull requests welcome!

* Improve cross-distro support
* YAML patching enhancements
* Installer optimizations

---

# 📜 License

MIT License

---
