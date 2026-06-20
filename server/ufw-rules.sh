#!/bin/bash
#
# ufw-rules.sh
#
# Firewall setup for the WireGuard server VM (Ubuntu Server 24.04).
# Documents the exact UFW configuration used, including the fix for
# routed traffic being silently dropped by the default forward policy.
#
# Run with: sudo bash ufw-rules.sh
# Review each step before running on your own system — adjust the
# SSH source subnet if your WireGuard subnet differs from 10.10.10.0/24.

set -e

echo "Enabling UFW..."
ufw --force enable

echo "Allowing WireGuard (UDP 51820) from anywhere..."
ufw allow 51820/udp

# IMPORTANT: by default, Ubuntu's UFW ships with
#   DEFAULT_FORWARD_POLICY="DROP"
# in /etc/default/ufw. This silently blocks traffic being routed
# THROUGH the server (e.g. a VPN client reaching another device on
# the LAN), even though the WireGuard tunnel itself connects fine.
#
# This was the root cause of "tunnel handshakes, but I can't reach
# anything on the network" during initial testing.
echo "Fixing UFW forward policy (DROP -> ACCEPT) to allow routed VPN traffic..."
sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw

# Restrict SSH to the VPN subnet only, instead of leaving it open
# to the entire internet. Connect via WireGuard first, then SSH in
# over the 10.10.10.0/24 tunnel address.
echo "Restricting SSH (22/tcp) to the VPN subnet only..."
ufw delete allow 22/tcp 2>/dev/null || true
ufw allow from 10.10.10.0/24 to any port 22

echo "Reloading UFW..."
ufw reload

echo "Done. Current status:"
ufw status verbose
