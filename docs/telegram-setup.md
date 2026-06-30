# Telegram Bot Setup

This guide walks you through creating a Telegram bot and obtaining the credentials
needed by the n8n-bastion workflows.

---

## Step 1 — Create a Bot via BotFather

1. Open Telegram and search for **@BotFather** (verified with a blue checkmark)
2. Start a conversation and send `/newbot`
3. Enter a **display name** for your bot — e.g. `n8n Bastion Watchdog`
4. Enter a **username** — must end in `bot`, e.g. `bastion_watchdog_bot`
5. BotFather will reply with your **HTTP API Token**:

```
1234567890:ABCdefGhIJKlmNoPQRsTUVwxyZ
```

> **Keep this token private.** Anyone with this token can send messages as your bot.

---

## Step 2 — Get Your Chat ID

1. Search for **@userinfobot** in Telegram
2. Start the conversation — it will reply with your user info
3. Copy the number next to **Id** — this is your Chat ID

---

## Step 3 — Activate Your Bot

1. Search for your bot by its username in Telegram
2. Click **Start**

The bot can now send you messages.

---

## Step 4 — Set Up Telegram Credential in n8n

1. Open n8n UI (`http://localhost:5678` via SSH tunnel)
2. Go to **Credentials → Add Credential**
3. Search for **Telegram API**
4. Paste your **HTTP API Token**
5. Name it: `Telegram Bastion`
6. Click **Save**

---

## Step 5 — Set Up Header Auth Credential in n8n

This secures your webhook endpoints so only your bash scripts can trigger them.

1. Go to **Credentials → Add Credential**
2. Search for **Header Auth**
3. Configure:
   - **Name** (header name): `X-Bastion-Secret`
   - **Value**: paste the value of `WEBHOOK_SECRET` from your `bastion.env`
4. Name it: `Bastion Webhook Auth`
5. Click **Save**

Generate a strong secret if you haven't already:

```bash
openssl rand -hex 32
```

---

## Verification

Test your Telegram integration after workflow setup:

```bash
source /opt/n8n-bastion/bastion.env

curl -X POST "${WEBHOOK_SENTINEL}" \
  -H "Content-Type: application/json" \
  -H "X-Bastion-Secret: ${WEBHOOK_SECRET}" \
  -d '{
    "total": 1,
    "findings": [{
      "severity": "CRITICAL",
      "file": "public/test.php",
      "line": 1,
      "description": "Test alert from n8n-bastion"
    }],
    "hostname": "test-vps",
    "scanned_at": "2026-01-01T00:00:00Z"
  }'
```

You should receive a Telegram message within a few seconds.

---

## Optional — Send Alerts to a Group

1. Add your bot to the group
2. Send any message in the group
3. Visit: `https://api.telegram.org/bot<YOUR_TOKEN>/getUpdates`
4. Find the `chat.id` value — group Chat IDs are negative numbers (e.g. `-1001234567890`)
5. Use this negative number as the Chat ID in your n8n Telegram nodes
