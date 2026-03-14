#!/bin/bash
# Configuration
SERVER_PUB_KEY="PASTE_MIKROTIK_PUBLIC_KEY_HERE"
SERVER_ENDPOINT="YOUR_ROUTER_PUBLIC_IP"
SERVER_PORT="13231"
CLIENT_IP="10.0.0.2/32"
TUNNEL_NETWORK="10.0.0.0/24"

# Generate Client Keys
PRIV_KEY=$(wg genkey)
PUB_KEY=$(echo "$PRIV_KEY" | wg pubkey)

echo "----------------------------------------------------------------"
echo "1. MIKROTIK COMMAND (Run this in the WinBox Terminal)"
echo "----------------------------------------------------------------"
echo "/interface wireguard peers add interface=wireguard public-key=\"$PUB_KEY\" allowed-address=$CLIENT_IP comment=\"Pi-Client\""
echo ""
echo "----------------------------------------------------------------"
echo "2. CLIENT CONFIG (Save to /etc/wireguard/wg0.conf)"
echo "----------------------------------------------------------------"
[Interface]
PrivateKey = $PRIV_KEY
Address = ${CLIENT_IP%/*}/24

[Peer]
PublicKey = $SERVER_PUB_KEY
Endpoint = $SERVER_ENDPOINT:$SERVER_PORT
AllowedIPs = $TUNNEL_NETWORK
PersistentKeepalive = 25
EOF

echo ""
echo "----------------------------------------------------------------"
echo "3. PI OPERATIONAL COMMANDS (How to reapply and persist)"
echo "----------------------------------------------------------------"
echo "# To apply changes immediately:"
echo "sudo wg-quick down wg0 && sudo wg-quick up wg0"
echo ""
echo "# To verify the handshake is active:"
echo "sudo wg show"
echo ""
echo "# To ensure the connection starts on every reboot:"
echo "sudo systemctl enable wg-quick@wg0"
echo "----------------------------------------------------------------"