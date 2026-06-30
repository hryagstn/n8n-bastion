#!/usr/bin/env bash
# =============================================================
# uptime-check.sh — HTTP Application Uptime Monitor
# =============================================================
# Checks if the application responds with a healthy HTTP status.
# Confirms twice (30-second gap) before sending an alert
# to avoid false alarms from transient network issues.
#
# Triggered by cron every 2 minutes.
# Exits silently if the application is healthy.
#
# Note: Since n8n runs on the same VPS as the application,
# this detects application-level downtime (PHP-FPM crash,
# Laravel errors, database issues) but NOT full server outages.
# For server-level monitoring, pair with an external service
# such as UptimeRobot (free tier available).
#
# Dependencies: curl, python3
# =============================================================

set -eo pipefail

CONFIG_FILE="/opt/n8n-bastion/bastion.env"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: Configuration file not found: $CONFIG_FILE"
  exit 1
fi
source "$CONFIG_FILE"

LOG="/opt/n8n-bastion/logs/uptime-check.log"
HOSTNAME=$(hostname)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"
}

if [ -z "${APP_URL:-}" ] || [ -z "${WEBHOOK_UPTIME:-}" ] || [ -z "${WEBHOOK_SECRET:-}" ]; then
  log "ERROR: Missing required configuration (APP_URL, WEBHOOK_UPTIME, WEBHOOK_SECRET)"
  exit 1
fi

check_url() {
  curl -s -o /dev/null -w "%{http_code}" \
    --max-time 10 \
    --connect-timeout 5 \
    "${APP_URL}" 2>/dev/null || echo "0"
}

is_healthy() {
  local status=$1
  [ "$status" -ge 200 ] && [ "$status" -lt 400 ] 2>/dev/null
}

STATUS=$(check_url)
log "First check: HTTP $STATUS"

if is_healthy "$STATUS"; then
  exit 0
fi

log "Unhealthy response ($STATUS). Waiting 30s for confirmation..."
sleep 30

STATUS2=$(check_url)
log "Confirmation check: HTTP $STATUS2"

if is_healthy "$STATUS2"; then
  log "Application recovered between checks. No alert sent."
  exit 0
fi

# ==============================================================================
# SELF-HEALING: Execute Application Recovery
# ==============================================================================
RESTART_CMD="${RESTART_APP_COMMAND:-sudo systemctl restart php-fpm}"
log "HEAL: Application down confirmed. Running recovery command: $RESTART_CMD"

# Run recovery command
eval "$RESTART_CMD" &>/dev/null || log "WARNING: Self-healing command executed (might require sudo/root)."

# Wait for service to bind and verify recovery
sleep 5
STATUS_POST_HEAL=$(check_url)
log "HEAL: Verification check post-healing: HTTP $STATUS_POST_HEAL"

HEAL_SUCCESS=false
if is_healthy "$STATUS_POST_HEAL"; then
  HEAL_SUCCESS=true
  log "HEAL: Self-healing auto-recovery SUCCESSFUL. Application is back online."
  STATUS2="$STATUS_POST_HEAL"
  REASON="Recovered by Self-Healing (HTTP $STATUS_POST_HEAL)"
else
  log "HEAL: Self-healing auto-recovery FAILED. Application remains DOWN."
  REASON="HTTP Status: ${STATUS2} (Self-healing restart failed)"
  [ "$STATUS2" = "0" ] && REASON="Unreachable (Self-healing restart failed)"
fi
# ==============================================================================

log "Downtime confirmed (HTTP $STATUS2). Sending webhook..."

PAYLOAD=$(python3 -c "
import json
print(json.dumps({
  'is_down': True,
  'status_code': int('${STATUS2}'),
  'reason': '${REASON}',
  'app_url': '${APP_URL}',
  'hostname': '${HOSTNAME}',
  'timestamp': '${TIMESTAMP}',
}))
")

HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "${WEBHOOK_UPTIME}" \
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
