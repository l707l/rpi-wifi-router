#!/bin/bash
# ============================================================
# rpi-wifi-router — Setup script
# WiFi Router AP on Raspberry Pi Zero 2 W (or any brcmfmac RPi)
# 5GHz hostapd + dnsmasq + nftables NAT
#
# Usage (run on the RPi as a user with sudo privileges):
#   chmod +x setup.sh && ./setup.sh
#
# After running, connect to SSID "SYV_MAX" with password "Cicada2026"
# ============================================================

set -e

# ---- Configuración -------------------------------------------------
HOSTAPD_CONF="/etc/hostapd/hostapd.conf"
DNSMASQ_CONF="/etc/dnsmasq.conf"
NFT_RULES="/tmp/nft_rules.nft"
START_SCRIPT="/usr/local/bin/rpi-wifi-router-start.sh"
RC_LOCAL="/etc/rc.local"
WIFI_IFACE="wlan0"
ETH_IFACE="eth0"
AP_SSID="SYV_MAX"
AP_PASS="Cicada2026"
AP_CHANNEL="36"
AP_FREQ="5180"
AP_IP="192.168.2.1"
DHCP_RANGE="192.168.2.50,192.168.2.250,24h"
DNS_SERVERS="8.8.8.8,8.8.4.4"
# --------------------------------------------------------------------

echo "=== RPi WiFi Router Setup ==="
echo "SSID      : $AP_SSID"
echo "Channel   : $AP_CHANNEL ($AP_FREQ MHz)"
echo "Gateway   : $AP_IP"
echo "DHCP range: $DHCP_RANGE"
echo ""

# 1. Descargar e instalar hostapd
echo "[1/6] Instalando hostapd..."
if ! command -v hostapd &>/dev/null; then
    HOSTAPD_DEB="/tmp/hostapd.deb"
    curl -sL "http://deb.debian.org/debian/pool/main/w/wpa/hostapd_2.10-24_arm64.deb" -o "$HOSTAPD_DEB"
    sudo dpkg -i "$HOSTAPD_DEB"
    rm -f "$HOSTAPD_DEB"
    echo "  hostapd instalado: $(hostapd -v 2>&1 | head -1)"
else
    echo "  hostapd ya instalado"
fi

# 2. Crear directorio hostapd
echo "[2/6] Configurando hostapd..."
sudo mkdir -p /etc/hostapd
cat | sudo tee "$HOSTAPD_CONF" > /dev/null <<EOF
interface=$WIFI_IFACE
driver=nl80211
ssid=$AP_SSID
hw_mode=a
channel=$AP_CHANNEL
wmm_enabled=1
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=$AP_PASS
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF
echo "  $HOSTAPD_CONF listo"

# 3. Configurar dnsmasq (DHCP + DNS)
echo "[3/6] Configurando dnsmasq..."
cat | sudo tee "$DNSMASQ_CONF" > /dev/null <<EOF
interface=$WIFI_IFACE
dhcp-range=$DHCP_RANGE
dhcp-option=3,$AP_IP
dhcp-option=6,$DNS_SERVERS
server=8.8.8.8
log-queries
log-dhcp
listen-address=127.0.0.1,$AP_IP
EOF
echo "  $DNSMASQ_CONF listo"

# 4. Configurar nftables NAT
echo "[4/6] Configurando nftables NAT..."
cat | sudo tee "$NFT_RULES" > /dev/null <<EOF
table ip nat {
  chain postrouting {
    type nat hook postrouting priority srcnat; policy accept;
    oifname "$ETH_IFACE" masquerade
  }
}
table ip filter {
  chain forward {
    type filter hook forward priority filter; policy accept;
    iifname "$WIFI_IFACE" accept
    oifname "$WIFI_IFACE" accept
  }
}
EOF
echo "  $NFT_RULES listo"

# 5. Crear script de inicio
echo "[5/6] Creando script de inicio..."
cat | sudo tee "$START_SCRIPT" > /dev/null <<'SCRIPT'
#!/bin/bash
sudo sysctl net.ipv4.ip_forward=1
sudo ip addr flush dev wlan0
sudo ip link set wlan0 down
sudo iw dev wlan0 set type __ap
sudo ip link set wlan0 up
sudo ip addr add 192.168.2.1/24 dev wlan0
sudo /usr/sbin/nft -f /tmp/nft_rules.nft
sudo /usr/sbin/dnsmasq -C /etc/dnsmasq.conf --no-daemon || true
sudo /usr/sbin/hostapd -B /etc/hostapd/hostapd.conf
SCRIPT
sudo chmod +x "$START_SCRIPT"
echo "  $START_SCRIPT listo"

# 6. Configurar arranque automático via rc.local
echo "[6/6] Configurando arranque automático..."
cat | sudo tee "$RC_LOCAL" > /dev/null <<'EOF'
#!/bin/sh
bash /usr/local/bin/rpi-wifi-router-start.sh
exit 0
EOF
sudo chmod +x "$RC_LOCAL"
echo "  $RC_LOCAL listo"

# 7. Ejecutar inmediatamente
echo ""
echo "[7/7] Arrancando servicios..."
bash "$START_SCRIPT"
sleep 5

echo ""
echo "=== Verificación ==="
pgrep -a hostapd && echo "  hostapd OK" || echo "  hostapd FALLO"
pgrep -a dnsmasq && echo "  dnsmasq  OK" || echo "  dnsmasq FALLO"
iw dev wlan0 info 2>/dev/null | grep -E "ssid|channel|freq" && echo "  wlan0    OK" || echo "  wlan0 FALLO"
ping -c 1 8.8.8.8 &>/dev/null && echo "  Internet OK" || echo "  Internet FALLO"

echo ""
echo "=== LISTO ==="
echo "Conecta tus dispositivos a: SSID=$AP_SSID  Password=$AP_PASS"
echo "Gateway: $AP_IP"
echo "DHCP: $DHCP_RANGE"
