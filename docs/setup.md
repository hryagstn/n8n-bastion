# n8n-bastion — Full Setup Guide

This guide covers the complete setup from a fresh VPS to all four watchdog
workflows running and sending Telegram alerts.

Follow each section in order.

---

## Requirements

| Component | Minimum | Notes |
|-----------|---------|-------|
| OS | Ubuntu 20.04 | Ubuntu 22.04+ recommended |
| RAM | 1 GB | 2 GB recommended (n8n uses ~150–300 MB idle) |
| Web Server | Apache 2.4+ | |
| PHP | 8.1 | |
| Laravel | 10.x | laravel-scalpel supports 10.x – 13.x |
| Node.js | 24.x LTS | Active LTS as of May 2026 |
| curl | Any | Pre-installed on most Ubuntu systems |
| python3 | 3.8+ | Pre-installed on most Ubuntu systems |

---

## Section 1 — Clone the Repository

```bash
cd ~
git clone https://github.com/hryagstn/n8n-bastion.git
cd n8n-bastion
```

---

## Section 2 — Install Node.js 24 LTS

> Node.js 24 is the Active LTS as of May 2026.
> Node.js 26 enters LTS in October 2026 — use 24.x for production stability.

```bash
curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
sudo apt-get install -y nodejs

# Verify
node --version   # v24.x.x
npm --version
```

---

## Section 3 — Install n8n

```bash
sudo npm install n8n -g
n8n --version
```

---

## Section 4 — Create Required Directories

```bash
mkdir -p ~/.n8n/logs
sudo mkdir -p /opt/n8n-bastion/{scripts,logs}
sudo chown -R $USER:$USER /opt/n8n-bastion
```

---

## Section 5 — Configure Environment

```bash
cp ~/n8n-bastion/config/bastion.env.example /opt/n8n-bastion/bastion.env
nano /opt/n8n-bastion/bastion.env
```

Fill in every value. Generate a webhook secret:

```bash
openssl rand -hex 32
```

The `WEBHOOK_*` URLs will be filled in after workflows are created (Section 10).

---

## Section 6 — Set Up systemd Service

```bash
sudo cp ~/n8n-bastion/config/n8n.service.example /etc/systemd/system/n8n.service
sudo nano /etc/systemd/system/n8n.service
```

Replace `YOUR_LINUX_USERNAME` and `YOUR_PASSWORD`, then:

```bash
sudo systemctl daemon-reload
sudo systemctl enable n8n
sudo systemctl start n8n
sudo systemctl status n8n   # should show: active (running)
```

---

## Section 7 — Access the n8n UI

n8n listens on `127.0.0.1` only. Access it from your local machine via SSH tunnel:

```bash
# Run this on your LOCAL machine, not the VPS
ssh -fNL 5678:127.0.0.1:5678 YOUR_USER@YOUR_VPS_IP
```

Open your browser: `http://localhost:5678`

---

## Section 8 — Set Up Telegram and Credentials

Follow [telegram-setup.md](telegram-setup.md) to:

1. Create a Telegram bot via @BotFather and get your API token
2. Get your Chat ID via @userinfobot
3. Register the **Telegram API** credential in n8n (name it `Telegram Bastion`)
4. Register the **Header Auth** credential in n8n (name it `Bastion Webhook Auth`)

---

## Section 9 — Install laravel-scalpel

```bash
cd /path/to/your/laravel-project
composer require hryagstn/laravel-scalpel --dev
php artisan vendor:publish --tag=scalpel-config
php artisan scalpel:baseline

# Verify
ls -la storage/app/private/scalpel/
```

> Re-run `php artisan scalpel:baseline --force` after every deployment.

---

## Section 10 — Import and Configure Workflows

### Import

```
n8n UI → Overview → Workflows → Import → select JSON file from workflows/
```

Import all four files. After importing each:
1. Click the **Webhook** node → assign `Bastion Webhook Auth` credential
2. Click the **Telegram** node → assign `Telegram Bastion` credential → set your Chat ID
3. Click **Publish**
4. Copy the **Production URL** from the Webhook node

Update `bastion.env` with the Production URLs:

```bash
nano /opt/n8n-bastion/bastion.env
# Fill in WEBHOOK_SENTINEL, WEBHOOK_APACHE, WEBHOOK_RESOURCE, WEBHOOK_UPTIME
```

---

### Workflow Node Logic Reference

All four workflows share the same pattern:

```
Webhook → Parse Payload (Code) → IF → Formatting Message (Code) → Telegram
                                   └──→ No Operation (if no alert needed)
```

#### IF Node Configuration

n8n 2.0+ requires explicit type handling in IF conditions. All workflows use:

```
Condition type: Boolean
Operation:      is true
Value 1:        {{ $json.<field> }}
```

Where `<field>` is `hasFindings` (Sentinel), `wasDown` (Apache), `shouldAlert` (Resource), `isDown` (Uptime).

If you encounter type errors, ensure the Parse Payload Code node returns proper boolean values using strict comparison (`=== true`).

---

## Section 11 — Install Bash Scripts

```bash
cp ~/n8n-bastion/scripts/*.sh /opt/n8n-bastion/scripts/
chmod +x /opt/n8n-bastion/scripts/*.sh
```

---

## Section 12 — Configure Cron

```bash
crontab -e
```

Add:

```cron
# n8n-bastion Watchdog
*/5  * * * * /opt/n8n-bastion/scripts/sentinel.sh
*    * * * * /opt/n8n-bastion/scripts/apache-monitor.sh
*/15 * * * * /opt/n8n-bastion/scripts/resource-monitor.sh
*/2  * * * * /opt/n8n-bastion/scripts/uptime-check.sh
```

---

## Section 13 — Test Each Script Manually

### Test Sentinel

```bash
echo '<?php eval(base64_decode("dGVzdA==")); ?>' > /path/to/laravel/test_backdoor.php
/opt/n8n-bastion/scripts/sentinel.sh
tail -5 /opt/n8n-bastion/logs/sentinel.log
rm /path/to/laravel/test_backdoor.php
```

### Test Apache Monitor

```bash
sudo systemctl stop apache2
/opt/n8n-bastion/scripts/apache-monitor.sh
tail -5 /opt/n8n-bastion/logs/apache-monitor.log
sudo systemctl status apache2
```

### Test Resource Monitor

```bash
# Temporarily lower thresholds
sed -i 's/DISK_THRESHOLD=.*/DISK_THRESHOLD=1/' /opt/n8n-bastion/bastion.env
sed -i 's/RAM_THRESHOLD=.*/RAM_THRESHOLD=1/'   /opt/n8n-bastion/bastion.env

/opt/n8n-bastion/scripts/resource-monitor.sh

# Restore
sed -i 's/DISK_THRESHOLD=.*/DISK_THRESHOLD=85/' /opt/n8n-bastion/bastion.env
sed -i 's/RAM_THRESHOLD=.*/RAM_THRESHOLD=90/'   /opt/n8n-bastion/bastion.env
```

### Test Uptime Check

```bash
sudo systemctl stop php8.2-fpm   # adjust PHP version as needed
/opt/n8n-bastion/scripts/uptime-check.sh   # waits 30s for confirmation
sudo systemctl start php8.2-fpm
```

---

## Section 14 — Monitor Logs

```bash
tail -f /opt/n8n-bastion/logs/sentinel.log
tail -f /opt/n8n-bastion/logs/apache-monitor.log
tail -f /opt/n8n-bastion/logs/resource-monitor.log
tail -f /opt/n8n-bastion/logs/uptime-check.log
tail -f ~/.n8n/logs/n8n.log
```

---

## Section 15 — Update Baseline After Deployment

```bash
cd /path/to/your/laravel-project
php artisan optimize
php artisan scalpel:baseline --force
```
