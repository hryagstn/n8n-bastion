#!/usr/bin/env bash
# =============================================================
# sentinel.sh — Filesystem Intrusion Sentinel
# =============================================================
# Runs laravel-scalpel filesystem scan and sends findings
# to the n8n webhook for processing and Telegram notification.
#
# Triggered by cron every 5 minutes.
# Only sends a webhook request when CRITICAL or HIGH findings exist.
#
# Dependencies: php, composer (laravel-scalpel), curl, python3
# =============================================================

set -eo pipefail

CONFIG_FILE="/opt/n8n-bastion/bastion.env"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: Configuration file not found: $CONFIG_FILE"
  exit 1
fi
source "$CONFIG_FILE"

LOG="/opt/n8n-bastion/logs/sentinel.log"
HOSTNAME=$(hostname)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"
}

if [ -z "${LARAVEL_PATH:-}" ] || [ -z "${WEBHOOK_SENTINEL:-}" ] || [ -z "${WEBHOOK_SECRET:-}" ]; then
  log "ERROR: Missing required configuration (LARAVEL_PATH, WEBHOOK_SENTINEL, WEBHOOK_SECRET)"
  exit 1
fi

if [ ! -d "$LARAVEL_PATH" ]; then
  log "ERROR: Laravel path not found: $LARAVEL_PATH"
  exit 1
fi

log "Running scalpel:scan..."

OUTPUT=$(cd "$LARAVEL_PATH" && php artisan scalpel:scan --format=json 2>/dev/null) || true

if ! echo "$OUTPUT" | python3 -m json.tool > /dev/null 2>&1; then
  log "ERROR: scalpel:scan did not return valid JSON. Output: ${OUTPUT:0:300}"
  exit 1
fi

TOTAL=$(echo "$OUTPUT" | python3 -c "
import json, sys
data = json.load(sys.stdin)
findings = data.get('findings', [])
critical_high = [f for f in findings if f.get('severity') in ('CRITICAL', 'HIGH')]
print(len(critical_high))
" 2>/dev/null || echo "0")

log "Scan complete. CRITICAL/HIGH findings: $TOTAL"

# ==============================================================================
# SELF-HEALING: Quarantine CRITICAL findings only
# ==============================================================================
CRITICAL_FILES=$(echo "$OUTPUT" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    critical_files = [f.get('file') for f in data.get('findings', []) if f.get('severity') == 'CRITICAL' and f.get('file')]
    print('\n'.join(critical_files))
except Exception:
    pass
" 2>/dev/null || echo "")

if [ -n "$CRITICAL_FILES" ]; then
  QUARANTINE_DIR="${QUARANTINE_DIR:-/opt/n8n-bastion/quarantine}"
  mkdir -p "$QUARANTINE_DIR"
  echo "$CRITICAL_FILES" | while IFS= read -r filepath; do
    if [ -n "$filepath" ] && [ -f "$filepath" ]; then
      filename=$(basename "$filepath")
      timestamp=$(date '+%Y%m%d%H%M%S')
      quarantine_path="${QUARANTINE_DIR}/${timestamp}_${filename}.quarantine"
      log "QUARANTINE: Moving CRITICAL threat file $filepath to $quarantine_path..."
      mv "$filepath" "$quarantine_path"
      chmod 0000 "$quarantine_path"
      log "QUARANTINE: File successfully isolated with 0000 permissions."
    elif [ -n "$filepath" ]; then
      log "WARNING: CRITICAL file not found for quarantine: $filepath"
    fi
  done
fi
# ==============================================================================

if [ "$TOTAL" -eq 0 ]; then
  log "No actionable findings. Skipping webhook."
  exit 0
fi

PAYLOAD=$(echo "$OUTPUT" | python3 -c "
import json, sys
data = json.load(sys.stdin)
data['hostname'] = '${HOSTNAME}'
data['scanned_at'] = '${TIMESTAMP}'
print(json.dumps(data))
" 2>/dev/null)

log "Sending webhook (CRITICAL/HIGH findings: $TOTAL)..."

HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "${WEBHOOK_SENTINEL}" \
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
