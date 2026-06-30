#!/usr/bin/env bash
# =============================================================
# resource-monitor.sh — Disk & RAM Threshold Monitor
# =============================================================
# Monitors disk usage and RAM consumption.
# Sends an alert to the n8n webhook when either exceeds
# the configured threshold.
#
# Triggered by cron every 15 minutes.
# Exits silently if all metrics are within acceptable range.
#
# Dependencies: df, free, curl, python3
# =============================================================

set -eo pipefail

CONFIG_FILE="/opt/n8n-bastion/bastion.env"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: Configuration file not found: $CONFIG_FILE"
  exit 1
fi
source "$CONFIG_FILE"

LOG="/opt/n8n-bastion/logs/resource-monitor.log"
HOSTNAME=$(hostname)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"
}

if [ -z "${WEBHOOK_RESOURCE:-}" ] || [ -z "${WEBHOOK_SECRET:-}" ]; then
  log "ERROR: Missing required configuration (WEBHOOK_RESOURCE, WEBHOOK_SECRET)"
  exit 1
fi

DISK_THRESHOLD="${DISK_THRESHOLD:-85}"
RAM_THRESHOLD="${RAM_THRESHOLD:-90}"

DISK=$(df / --output=pcent | tail -1 | tr -d ' %')
RAM=$(free -m | awk 'NR==2{printf "%.0f", $3*100/$2}')

log "Metrics — Disk: ${DISK}% (threshold: ${DISK_THRESHOLD}%) | RAM: ${RAM}% (threshold: ${RAM_THRESHOLD}%)"

DISK_ALERT=false
RAM_ALERT=false

[ "$DISK" -ge "$DISK_THRESHOLD" ] && DISK_ALERT=true
[ "$RAM" -ge "$RAM_THRESHOLD" ]   && RAM_ALERT=true

if [ "$DISK_ALERT" = "false" ] && [ "$RAM_ALERT" = "false" ]; then
  exit 0
fi

# ==============================================================================
# SELF-HEALING: Auto-Clean Disk & Optimize RAM Caches
# ==============================================================================
INITIAL_DISK="$DISK"
INITIAL_RAM="$RAM"

if [ "$DISK_ALERT" = "true" ]; then
  log "HEAL: Disk usage ${INITIAL_DISK}% exceeded threshold ${DISK_THRESHOLD}%. Running auto-clean..."
  # Clean old monitor logs
  if [ -d "/opt/n8n-bastion/logs" ]; then
    find /opt/n8n-bastion/logs -type f -name "*.log" -mtime +7 -delete 2>/dev/null || true
  fi
  # Clean standard temp files older than 3 days
  find /tmp -type f -mtime +3 -delete 2>/dev/null || true
  # Clean Laravel caches if configured
  if [ -n "${LARAVEL_PATH:-}" ] && [ -d "$LARAVEL_PATH" ]; then
    (cd "$LARAVEL_PATH" && php artisan cache:clear && php artisan view:clear && php artisan config:clear) &>/dev/null || true
  fi
  # Recalculate Disk usage
  DISK=$(df / --output=pcent | tail -1 | tr -d ' %')
  log "HEAL: Disk cleaning complete. New disk usage: ${DISK}%"
fi

if [ "$RAM_ALERT" = "true" ]; then
  log "HEAL: RAM usage ${INITIAL_RAM}% exceeded threshold ${RAM_THRESHOLD}%. Running memory optimization..."
  # Purge OS filesystem caches
  if [ -f "/proc/sys/vm/drop_caches" ]; then
    sync && echo 3 | sudo tee /proc/sys/vm/drop_caches &>/dev/null || true
  fi
  # Restart memory-intensive processes if possible
  if command -v systemctl &>/dev/null; then
    sudo systemctl restart php-fpm &>/dev/null || true
  fi
  # Recalculate RAM usage
  RAM=$(free -m | awk 'NR==2{printf "%.0f", $3*100/$2}')
  log "HEAL: RAM optimization complete. New RAM usage: ${RAM}%"
fi
# ==============================================================================

log "Threshold exceeded. Sending webhook..."

PAYLOAD=$(python3 -c "
import json
print(json.dumps({
  'disk': int('${DISK}'),
  'ram': int('${RAM}'),
  'disk_threshold': int('${DISK_THRESHOLD}'),
  'ram_threshold': int('${RAM_THRESHOLD}'),
  'disk_alert': ${DISK_ALERT^},
  'ram_alert': ${RAM_ALERT^},
  'hostname': '${HOSTNAME}',
  'timestamp': '${TIMESTAMP}',
}))
")

HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "${WEBHOOK_RESOURCE}" \
  -H "Content-Type: application/json" \
  -H "X-Bastion-Secret: ${WEBHOOK_SECRET}" \
  -d "$PAYLOAD" \
  --max-time 30 \
  --retry 2 \
  --retry-delay 5)

if [ "$HTTP_STATUS" = "200" ]; then
  log "Webhook delivered successfully. HTTP $HTTP_STATUS"
else
  log "WARNING: Webhook returned HTTP $HTTP_STATUS"
fi
