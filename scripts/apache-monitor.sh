#!/usr/bin/env bash
# =============================================================
# apache-monitor.sh — Apache Health Monitor & Auto-Recovery
# =============================================================
# Checks Apache service status every minute.
# If down, attempts automatic restart and reports the outcome
# to the n8n webhook for Telegram notification.
#
# Triggered by cron every 1 minute.
# Exits silently if Apache is running normally.
#
# Dependencies: systemctl, curl, python3
# Requires: sudo systemctl restart apache2 (without password prompt)
# =============================================================

set -eo pipefail

CONFIG_FILE="/opt/n8n-bastion/bastion.env"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: Configuration file not found: $CONFIG_FILE"
  exit 1
fi
source "$CONFIG_FILE"

LOG="/opt/n8n-bastion/logs/apache-monitor.log"
HOSTNAME=$(hostname)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"
}

if [ -z "${WEBHOOK_APACHE:-}" ] || [ -z "${WEBHOOK_SECRET:-}" ]; then
  log "ERROR: Missing required configuration (WEBHOOK_APACHE, WEBHOOK_SECRET)"
  exit 1
fi

APACHE_STATUS=$(systemctl is-active apache2 2>/dev/null || echo "inactive")

if [ "$APACHE_STATUS" = "active" ]; then
  exit 0
fi

log "Apache is DOWN (status: $APACHE_STATUS). Attempting restart..."

RESTART_SUCCESS="false"

if sudo systemctl restart apache2 2>/dev/null; then
  sleep 5
  VERIFY=$(systemctl is-active apache2 2>/dev/null || echo "inactive")
  if [ "$VERIFY" = "active" ]; then
    RESTART_SUCCESS="true"
    log "Auto-restart SUCCEEDED. Apache is back online."
  else
    log "Auto-restart FAILED. Apache is still inactive after restart attempt."
  fi
else
  log "Auto-restart FAILED. systemctl restart command returned an error."
fi

PAYLOAD=$(python3 -c "
import json
print(json.dumps({
  'was_down': True,
  'restart_attempted': True,
  'restart_success': ${RESTART_SUCCESS^},
  'hostname': '${HOSTNAME}',
  'timestamp': '${TIMESTAMP}',
}))
")

log "Sending webhook (restart_success: $RESTART_SUCCESS)..."

HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "${WEBHOOK_APACHE}" \
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
