# Webhook Payload Reference

Each watchdog sends JSON to its own n8n webhook only when it has an actionable
event. Requests use `Content-Type: application/json` and the shared secret from
`bastion.env`:

```http
X-Bastion-Secret: <WEBHOOK_SECRET>
```

The examples below match the field names consumed by the bundled workflows.
Replace the URL and secret before using the `curl` commands. A successful n8n
webhook invocation should return HTTP 200 and send a Telegram notification.

Do not use real hostnames, application URLs, findings, or secrets in public bug
reports.

## Filesystem Sentinel

Endpoint configuration: `WEBHOOK_SENTINEL`

The script forwards the Laravel Scalpel JSON result, adds `hostname` and
`scanned_at`, and sends it only when at least one CRITICAL or HIGH finding is
present. Additional fields produced by Laravel Scalpel are forwarded unchanged.

```json
{
  "total": 1,
  "findings": [
    {
      "severity": "CRITICAL",
      "file": "/var/www/example/public/icons/index.php",
      "description": "Obfuscated executable PHP detected"
    }
  ],
  "hostname": "app-01",
  "scanned_at": "2026-09-14T03:00:00Z"
}
```

```bash
curl -X POST "$WEBHOOK_SENTINEL" \
  -H "Content-Type: application/json" \
  -H "X-Bastion-Secret: $WEBHOOK_SECRET" \
  -d '{
    "total": 1,
    "findings": [{
      "severity": "CRITICAL",
      "file": "/var/www/example/public/icons/index.php",
      "description": "Test finding"
    }],
    "hostname": "app-01",
    "scanned_at": "2026-09-14T03:00:00Z"
  }'
```

## Apache Health Monitor

Endpoint configuration: `WEBHOOK_APACHE`

The script sends this event only after Apache is found inactive and a restart
has been attempted.

```json
{
  "was_down": true,
  "restart_attempted": true,
  "restart_success": true,
  "hostname": "app-01",
  "timestamp": "2026-09-14T03:01:00Z"
}
```

```bash
curl -X POST "$WEBHOOK_APACHE" \
  -H "Content-Type: application/json" \
  -H "X-Bastion-Secret: $WEBHOOK_SECRET" \
  -d '{
    "was_down": true,
    "restart_attempted": true,
    "restart_success": true,
    "hostname": "app-01",
    "timestamp": "2026-09-14T03:01:00Z"
  }'
```

## Resource Monitor

Endpoint configuration: `WEBHOOK_RESOURCE`

The script sends this event when disk or RAM usage reaches its configured
threshold. `disk_alert` and `ram_alert` describe the pre-remediation condition;
`disk` and `ram` contain the measurements taken after any remediation attempt.
The workflow independently recalculates whether an alert should be sent from
the reported measurements and thresholds.

```json
{
  "disk": 87,
  "ram": 62,
  "disk_threshold": 85,
  "ram_threshold": 90,
  "disk_alert": true,
  "ram_alert": false,
  "hostname": "app-01",
  "timestamp": "2026-09-14T03:15:00Z"
}
```

```bash
curl -X POST "$WEBHOOK_RESOURCE" \
  -H "Content-Type: application/json" \
  -H "X-Bastion-Secret: $WEBHOOK_SECRET" \
  -d '{
    "disk": 87,
    "ram": 62,
    "disk_threshold": 85,
    "ram_threshold": 90,
    "disk_alert": true,
    "ram_alert": false,
    "hostname": "app-01",
    "timestamp": "2026-09-14T03:15:00Z"
  }'
```

## HTTP Uptime Check

Endpoint configuration: `WEBHOOK_UPTIME`

The script sends this event after two failed health checks and an automatic
recovery attempt. `status_code` is `0` when the application is unreachable.
The workflow also accepts an optional `response_time_ms` field, although the
bundled script does not currently emit it.

```json
{
  "is_down": true,
  "status_code": 503,
  "reason": "HTTP Status: 503 (Self-healing restart failed)",
  "app_url": "https://example.com/health",
  "hostname": "app-01",
  "timestamp": "2026-09-14T03:20:00Z"
}
```

```bash
curl -X POST "$WEBHOOK_UPTIME" \
  -H "Content-Type: application/json" \
  -H "X-Bastion-Secret: $WEBHOOK_SECRET" \
  -d '{
    "is_down": true,
    "status_code": 503,
    "reason": "HTTP Status: 503 (Self-healing restart failed)",
    "app_url": "https://example.com/health",
    "hostname": "app-01",
    "timestamp": "2026-09-14T03:20:00Z"
  }'
```

## Response and Retry Behavior

The Bash scripts treat HTTP 200 as successful delivery. They retry failed or
timed-out requests twice with a five-second delay, but do not persist events or
attach an idempotency key. If delivery guarantees matter, put a durable queue or
event store between the scripts and the notification workflow.
