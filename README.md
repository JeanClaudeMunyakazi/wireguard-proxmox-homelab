# WireGuard VPN on Proxmox — Homelab Project

A self-hosted WireGuard VPN server, built to solve a real problem: Tailscale
silently failed to connect whenever a second VPN (Avast SecureLine) was
active on public WiFi, with no usable error message. This repo documents
the working configuration that replaced it.

Full write-up with the diagnosis story and screenshots:
**[munyakazi.org — Building a Self-Hosted WireGuard VPN](https://munyakazi.org)**
*(link to be updated once the portfolio page is published)*

## Architecture

```
Internet
   │
   │  UDP 51820 (port forwarded)
   ▼
Telekom Speedport router
   │
   ▼
Proxmox VE host (bare metal)
   └── VM 100 — Ubuntu Server 24.04
         ├── WireGuard (wg0) — 10.10.10.1/24
         ├── UFW firewall — routed forwarding enabled, SSH VPN-only
         └── cf-ddns.sh (cron, every 10 min)
               └── updates vpn.yourdomain.com → current public IP via Cloudflare API
```

A Windows client connects to `vpn.yourdomain.com:51820`, and — once
inside the tunnel — can reach any device on the home LAN, including
when a second VPN (e.g. a public-WiFi security client) is also active.

## What's in this repo

| Path | Purpose |
|---|---|
| `server/wg0.conf.example` | WireGuard server interface config |
| `server/ufw-rules.sh` | Firewall setup, including the forward-policy fix |
| `server/sysctl-forwarding.conf` | IP forwarding required for routing |
| `client/HomeVPN.conf.example` | Windows client config — the working split-tunnel version |
| `ddns/cf-ddns.sh` | Cloudflare Dynamic DNS update script |
| `ddns/crontab.txt` | Cron schedule for the DDNS script |

All files are sanitized templates — every key, token, and IP-specific
value is a placeholder. Replace them with your own before use.

## The core problem this solves

**Tailscale's mesh VPN worked perfectly on the home network, but failed
silently the moment a second VPN client took over the network's routing
on public WiFi.** No error, no logs pointing at the cause — just a dead
tunnel. With no split-tunneling option available to exempt Tailscale's
traffic, and security policy ruling out disabling the public-WiFi VPN,
Tailscale was no longer viable as the remote-access method.

WireGuard's advantage here: it runs on a single, predictable UDP port,
independent of whatever else is active on the network stack — so it
can run *underneath* another VPN instead of competing with it.

## The routing bug (and the actual fix)

The trickiest part of this build wasn't installing WireGuard — it was
diagnosing why the tunnel connected but local devices were still
unreachable. Two separate issues, found in order:

1. **UFW's default forward policy was `DROP`.** This silently blocks
   traffic being routed *through* the server, even though the tunnel
   itself handshakes fine. Fixed by setting
   `DEFAULT_FORWARD_POLICY="ACCEPT"` in `/etc/default/ufw`.
   See `server/ufw-rules.sh`.

2. **The client's `AllowedIPs` was set to `0.0.0.0/0` (full tunnel).**
   This routes *all* traffic — including LAN-bound traffic — into the
   tunnel, which broke local reachability entirely. Scoping it down to
   `10.10.10.0/24, 192.168.1.0/24` (VPN subnet + home LAN only) fixed
   it immediately. See the inline comments in
   `client/HomeVPN.conf.example`.

Confirmed working via `sudo wg show` (showing an active handshake with
real bidirectional data transfer) and live pings to LAN devices through
the tunnel — including with Avast SecureLine active and geo-located
outside Germany.

## Setup order

1. Install WireGuard on the server VM: `sudo apt install wireguard wireguard-tools`
2. Generate keypairs for the server and each client: `wg genkey | tee privatekey | wg pubkey > publickey`
3. Fill in `server/wg0.conf.example`, save as `/etc/wireguard/wg0.conf`
4. Apply `server/sysctl-forwarding.conf` and run `sudo sysctl -p`
5. Run `server/ufw-rules.sh` to configure the firewall
6. Forward UDP 51820 on your router to the WireGuard server's local IP
7. Fill in `client/HomeVPN.conf.example` and import into the WireGuard app
8. (Optional but recommended) Set up `ddns/cf-ddns.sh` so the client
   config can use a stable hostname instead of a raw IP
9. Start the tunnel: `sudo systemctl enable --now wg-quick@wg0`

## License

MIT — use, adapt, and reuse freely.
