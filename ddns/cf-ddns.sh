#!/bin/bash
#
# cf-ddns.sh
#
# Keeps a Cloudflare DNS A record pointed at the current public IP
# of a dynamic home connection. Run on a schedule (see crontab.txt)
# so a WireGuard client config can use a stable hostname instead of
# a raw IP that changes whenever the ISP reassigns it.
#
# Requires a Cloudflare API token scoped to "Zone:DNS:Edit" for the
# specific zone only — not an account-wide token.
#
# Setup:
#   1. Create the API token in the Cloudflare dashboard
#      (My Profile -> API Tokens -> Create Token -> Edit zone DNS)
#   2. Find your Zone ID on the domain's Overview page sidebar
#   3. Fill in the three variables below
#   4. Create the target DNS record manually once in Cloudflare first
#      (this script updates an existing record, it does not create one)
#   5. chmod +x cf-ddns.sh and test with: sudo ./cf-ddns.sh
#
# IMPORTANT: the DNS record must be "DNS only" (grey cloud), not
# "Proxied" (orange cloud). Cloudflare's proxy does not support
# arbitrary UDP, and WireGuard needs raw UDP on its listen port.

ZONE_ID="YOUR_ZONE_ID_HERE"
RECORD_NAME="vpn.yourdomain.com"
CF_API_TOKEN="YOUR_CLOUDFLARE_API_TOKEN_HERE"

LOG_FILE="/var/log/cf-ddns.log"

CURRENT_IP=$(curl -s https://api.ipify.org)

if [ -z "$CURRENT_IP" ]; then
    echo "$(date): Failed to get current IP" >> "$LOG_FILE"
    exit 1
fi

RECORD_INFO=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?type=A&name=$RECORD_NAME" \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json")

RECORD_ID=$(echo "$RECORD_INFO" | grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4)
RECORD_IP=$(echo "$RECORD_INFO" | grep -o '"content":"[^"]*' | head -1 | cut -d'"' -f4)

if [ -z "$RECORD_ID" ]; then
    echo "$(date): Could not find DNS record for $RECORD_NAME" >> "$LOG_FILE"
    exit 1
fi

if [ "$CURRENT_IP" == "$RECORD_IP" ]; then
    echo "$(date): IP unchanged ($CURRENT_IP), no update needed" >> "$LOG_FILE"
    exit 0
fi

UPDATE_RESULT=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json" \
    --data "{\"type\":\"A\",\"name\":\"$RECORD_NAME\",\"content\":\"$CURRENT_IP\",\"ttl\":120,\"proxied\":false}")

echo "$(date): Updated $RECORD_NAME to $CURRENT_IP — Response: $UPDATE_RESULT" >> "$LOG_FILE"
