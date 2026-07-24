#!/bin/bash
# rpi-wifi-router — Script de inicio
# Uso: sudo ./start.sh

set -e

WIFI_IFACE="wlan0"
ETH_IFACE="eth0"
HOSTAPD_CONF="/etc/hostapd/hostapd.conf"
DNSMASQ_CONF="/etc/dnsmasq.conf"
NFT_RULES="/tmp/nft_rules.nft"
START_SCRIPT="/usr/local/bin/rpi-wifi-router-start.sh"

echo "[*] Iniciando rpi-wifi-router..."

# IP forwarding
echo "[+] Habilitando IP forwarding..."
sudo sysctl net.ipv4.ip_forward=1

# Reset wlan0 y poner en modo AP
echo "[+] Configurando wlan0 en modo AP..."
sudo ip addr flush dev "$WIFI_IFACE"
sudo ip link set "$WIFI_IFACE" down
sudo iw dev "$WIFI_IFACE" set type __ap
sudo ip link set "$WIFI_IFACE" up
sudo ip addr add 192.168.2.1/24 dev "$WIFI_IFACE"

# NAT con nftables
echo "[+] Aplicando reglas NAT..."
sudo /usr/sbin/nft -f "$NFT_RULES"

# Iniciar dnsmasq
echo "[+] Iniciando dnsmasq..."
sudo pkill dnsmasq 2>/dev/null || true
sudo /usr/sbin/dnsmasq -C "$DNSMASQ_CONF" --no-daemon

# Iniciar hostapd
echo "[+] Iniciando hostapd..."
sudo pkill hostapd 2>/dev/null || true
sudo /usr/sbin/hostapd -B "$HOSTAPD_CONF"

sleep 3

# Verificar
if pgrep hostapd > /dev/null; then
    echo "[+] hostapd OK"
else
    echo "[-] hostapd FALLO"
    exit 1
fi

if pgrep dnsmasq > /dev/null; then
    echo "[+] dnsmasq OK"
else
    echo "[-] dnsmasq FALLO"
    exit 1
fi

echo ""
echo "[+] Red WiFi activa: SSID=SYV_MAX  Password=Cicada2026"
iw dev "$WIFI_IFACE" info | grep -E "ssid|channel|freq"
