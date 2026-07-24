#!/bin/bash
# rpi-wifi-router — Script de parada
# Uso: sudo ./stop.sh

echo "[*] Deteniendo rpi-wifi-router..."
sudo pkill hostapd 2>/dev/null && echo "[+] hostapd detenido" || echo "[*] hostapd no estaba corriendo"
sudo pkill dnsmasq  2>/dev/null && echo "[+] dnsmasq detenido"  || echo "[*] dnsmasq no estaba corriendo"
sudo ip link set wlan0 down
sudo iw dev wlan0 set type managed
sudo ip link set wlan0 up
echo "[+] wlan0 restaurado a modo managed"
echo "[*] Apagado completo"
