#!/bin/bash
# ============================================================
# start-router.sh - Iniciar RPi WiFi Router + Pi-hole
# ============================================================
set -e

WIFI_IFACE="wlan0"
ETH_IFACE="eth0"
LAN_SUBNET="192.168.2.1/24"
PIHOLE_FTL="/opt/pihole/pihole-FTL"
DNSMASQ_CONF="/etc/dnsmasq.conf"
PIHOLE_CONF="/etc/dnsmasq.d/02-pihole.conf"
NFT_CONF="/tmp/nft_rules.nft"
HOSTAPD_CONF="/etc/hostapd/hostapd.conf"

echo "[*] === RPi WiFi Router + Pi-hole ==="

# 1. Enable IP forwarding
echo "[1/7] IP forwarding..."
sudo sysctl -w net.ipv4.ip_forward=1

# 2. Flush existing IP config on wlan0
echo "[2/7] Configuring wlan0..."
sudo ip link set wlan0 down 2>/dev/null || true
sudo iw dev wlan0 set type __ap 2>/dev/null || true
sudo ip link set wlan0 up
sudo ip addr flush dev wlan0
sudo ip addr add $LAN_SUBNET dev wlan0

# 3. Setup NAT with nftables
echo "[3/7] NAT rules..."
sudo /usr/sbin/nft flush ruleset 2>/dev/null || true
cat << 'EOFNFT' | sudo /usr/sbin/nft -f -
table ip nat {
  chain postrouting {
    type nat hook postrouting priority srcnat; policy accept;
    oifname "eth0" masquerade
  }
}
table ip filter {
  chain forward {
    type filter hook forward priority filter; policy accept;
    ct state related,established accept
    iifname "wlan0" accept
    oifname "wlan0" accept
  }
}
EOFNFT

# 4. Configure dnsmasq for DHCP only (DNS served by Pi-hole FTL)
echo "[4/7] Configuring dnsmasq (DHCP only)..."
# Blank main config - all settings in /etc/dnsmasq.d/
sudo tee "$DNSMASQ_CONF" > /dev/null << 'EOF'
# Empty - see /etc/dnsmasq.d/
EOF

# Pi-hole DHCP config (no DNS, DHCP only)
sudo tee "$PIHOLE_CONF" > /dev/null << 'EOF'
interface=wlan0
port=0
bind-interfaces
dhcp-range=192.168.2.50,192.168.2.250,24h
dhcp-option=3,192.168.2.1
dhcp-option=6,192.168.2.1
log-dhcp
EOF

# 5. Start/restart dnsmasq (DHCP only, --port=0)
echo "[5/7] Starting dnsmasq (DHCP)..."
sudo pkill dnsmasq 2>/dev/null || true
sleep 1
sudo /usr/sbin/dnsmasq --no-daemon --port=0 2>&1 | tee /tmp/dnsmasq.log &
sleep 2

# 6. Configure Pi-hole FTL
echo "[6/7] Configuring Pi-hole FTL..."
sudo mkdir -p /etc/pihole /var/log /run/pihole
sudo chown nobody:nogroup /var/log 2>/dev/null || true
sudo tee /etc/pihole/pihole-FTL.conf > /dev/null << 'EOF'
PORT=53
DNSMASQ_CONF=/etc/dnsmasq.d/02-pihole.conf
FTLUSER=nobody
DELAY_STARTUP=0
CHECK_HOSTNAME=false
EOF

# 7. Start/restart Pi-hole FTL (DNS)
echo "[7/7] Starting Pi-hole FTL (DNS)..."
sudo pkill pihole-FTL 2>/dev/null || true
sleep 1
sudo $PIHOLE_FTL &
sleep 2

# 8. Start hostapd (WiFi AP)
echo "[8] Starting hostapd (AP)..."
sudo pkill hostapd 2>/dev/null || true
sleep 1
sudo hostapd -B $HOSTAPD_CONF 2>&1 | tee /tmp/hostapd.log &
sleep 2

echo ""
echo "=== Status ==="
pgrep -a hostapd && echo "hostapd OK" || echo "hostapd FAILED"
pgrep -a pihole-FTL && echo "pihole-FTL OK" || echo "pihole-FTL FAILED"
pgrep -a dnsmasq && echo "dnsmasq OK" || echo "dnsmasq FAILED"
sudo ss -tlnp | grep :53 | head -3
cat /var/lib/misc/dnsmasq.leases 2>/dev/null | head -3 || echo "no leases"

echo ""
echo "Pi-hole DNS:  192.168.2.1:53"
echo "DHCP range:  192.168.2.50-250"
echo "Web admin:   http://192.168.2.1/admin (needs setup)"
echo ""
echo "Done!"
