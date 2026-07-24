#!/bin/bash
# rpi-wifi-router — Script de verificación
# Uso: ./verify.sh

echo "=== rpi-wifi-router: Verificación ==="
echo ""

PASS=0
FAIL=0

# hostapd
if pgrep hostapd &>/dev/null; then
    echo "[PASS] hostapd corriendo (PID $(pgrep hostapd))"
    ((PASS++))
else
    echo "[FAIL] hostapd NO corriendo"
    ((FAIL++))
fi

# dnsmasq
if pgrep dnsmasq &>/dev/null; then
    echo "[PASS] dnsmasq corriendo (PID $(pgrep dnsmasq))"
    ((PASS++))
else
    echo "[FAIL] dnsmasq NO corriendo"
    ((FAIL++))
fi

# wlan0 en modo AP
if iw dev wlan0 info 2>/dev/null | grep -q "type AP"; then
    echo "[PASS] wlan0 en modo AP"
    iw dev wlan0 info | grep -E "ssid|channel|freq|txpower" | sed 's/^/        /'
    ((PASS++))
else
    echo "[FAIL] wlan0 NO esta en modo AP"
    ((FAIL++))
fi

# IP del gateway
if ip addr show wlan0 | grep -q "192.168.2.1"; then
    echo "[PASS] IP del gateway configurada (192.168.2.1)"
    ((PASS++))
else
    echo "[FAIL] IP del gateway no configurada"
    ((FAIL++))
fi

# Internet
if ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
    echo "[PASS] Internet accesible"
    ((PASS++))
else
    echo "[FAIL] Sin internet"
    ((FAIL++))
fi

# NAT
if sudo nft list ruleset 2>/dev/null | grep -q masquerade; then
    echo "[PASS] NAT masquerade activo"
    ((PASS++))
else
    echo "[FAIL] NAT no configurado"
    ((FAIL++))
fi

# DHCP leases
if [ -s /var/lib/misc/dnsmasq.leases ]; then
    echo "[PASS] DHCP leases activos:"
    cat /var/lib/misc/dnsmasq.leases | sed 's/^/        /'
    ((PASS++))
else
    echo "[INFO] Sin clientes DHCP conectados (normal si nadie está conectado)"
    ((PASS++))
fi

echo ""
echo "=== Resumen: $PASS passed, $FAIL failed ==="
[ $FAIL -eq 0 ] && echo "Todo funcionando OK" || echo "Hay problemas — revisar logs"
