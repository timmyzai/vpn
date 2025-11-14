# WireGuard VPN Installer (wg-easy) — Universal Automated Installer

A **universal, fully automated WireGuard VPN installer** using **wg-easy**, supporting:

* Ubuntu / Debian
* CentOS / RHEL / Rocky / AlmaLinux
* Fedora
* Amazon Linux 2
* Amazon Linux 2023
* ARM64 & x86_64

---

## 🚀 Features

### ✔ Fully Automated Installation

* Auto-installs Docker + Docker Compose Plugin
* Auto-downloads wg-easy
* Auto-patches docker-compose.yaml safely
* Auto-configures ports based on your input
* Auto-enables IP forwarding (sysctl persistent)
* Auto-detects OS and applies correct install logic

### ✔ Admin UI Routing Modes

* Direct IP (HTTP)
* Public ALB (HTTPS → Private IP)
* Private ALB (Internal HTTPS → Private IP)

### ✔ Zero-Password First Login

wg-easy will **ask to create an admin account** on first login.

### ✔ Healthcheck Included

A built-in `HTTP /health` endpoint ensures:

* ALB/NLB perform health checks correctly
* Docker automatically restarts on failure

### ✔ Idempotent

Re-running the script:

* Never breaks existing config
* Re-patches ports cleanly
* Ensures Docker is installed and running

### ✔ Maintenance Menu

When already installed:

```
1) View Logs
2) Uninstall Completely
3) Change WG_HOST
4) Exit
```

---

## 📦 Supported Operating Systems

| OS                | Version       | Status    |
| ----------------- | ------------- | --------- |
| Ubuntu            | 20.04, 22.04+ | Supported |
| Debian            | 10, 11, 12    | Supported |
| CentOS            | 7             | Supported |
| RHEL              | 7, 8, 9       | Supported |
| Rocky Linux       | 8, 9          | Supported |
| AlmaLinux         | 8, 9          | Supported |
| Fedora            | 34–40         | Supported |
| Amazon Linux 2    | Latest        | Supported |
| Amazon Linux 2023 | Latest        | Supported |

---

## 📥 Installation

Run as regular user or root — script auto-elevates using sudo.

```bash
curl -o wireguard-install.sh https://raw.githubusercontent.com/YOUR_GITHUB_REPO/wireguard-install.sh
chmod +x wireguard-install.sh
./wireguard-install.sh
```

The script will:

1. Detect your OS
2. Install Docker
3. Install Docker Compose Plugin
4. Configure sysctl IP forwarding
5. Download wg-easy
6. Patch compose file
7. Start wg-easy

---

## ⚙ Configuration Prompts

Example:

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

## 📄 Completion Output

```
=== INSTALL COMPLETE ===

Endpoint: WG_HOST:WG_PORT/udp

Admin UI:
http://PRIVATE_IP:PORT

Config stored in: /etc/docker/containers/wg-easy/.env

⚠️ On first login, wg-easy will prompt you to create an ADMIN user/password.
```

---

## 🔥 Security Notes

* Admin UI runs HTTP internally
* For HTTPS, place behind ALB/NLB + ACM SSL
* DNS defaults to AWS VPC DNS when inside EC2
* WG_HOST updates restart the service automatically

---

## 🔧 Uninstallation

Run the script again:

```bash
./wireguard-install.sh
```

Choose:

```
2) Uninstall Completely
```

This removes:

* docker container
* docker image
* wg-easy config folder
* patched compose files

---

## 🔍 Troubleshooting

### Client connects but no Internet

Enable NAT/masquerade:

```bash
firewall-cmd --add-masquerade --permanent
firewall-cmd --reload
```

### ALB marks target as unhealthy

```bash
curl http://localhost:51821/health
```

### Docker not running

```bash
systemctl restart docker
```

---

## 🤝 Contributing

PRs welcome:

* Cross-distro enhancements
* YAML patch optimizations
* Security improvements

---

## 📜 License

MIT License
