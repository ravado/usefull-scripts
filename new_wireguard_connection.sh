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

echo "--- MIKROTIK COMMAND ---"
echo "/interface wireguard peers add interface=wg-server public-key=\"$PUB_KEY\" allowed-address=$CLIENT_IP comment=\"Pi-Client\""
echo ""
echo "--- CLIENT CONFIG (/etc/wireguard/wg0.conf) ---"
cat <<EOF
[Interface]
PrivateKey = $PRIV_KEY
Address = ${CLIENT_IP%/*}/24

[Peer]
PublicKey = $SERVER_PUB_KEY
Endpoint = $SERVER_ENDPOINT:$SERVER_PORT
AllowedIPs = $TUNNEL_NETWORK
PersistentKeepalive = 25
EOF