# rpi-wifi-router

WiFi Router AP on **Raspberry Pi Zero 2 W** — 5GHz hostapd + dnsmasq + nftables NAT.

Convierte cualquier Raspberry Pi con WiFi integrado (brcmfmac) en un router WiFi de alta velocidad en banda 5GHz. Los dispositivos se conectan a la red WiFi y obtienen IP del DHCP, con internet compartido desde ethernet.

## Red resultante

| Elemento | Valor |
|---|---|
| SSID | `SYV_MAX` |
| Contraseña | `Cicada2026` |
| Banda | 5 GHz, canal 36 (5180 MHz) |
| Gateway | `192.168.2.1` |
| DHCP range | `192.168.2.50` – `192.168.2.250` |
| Lease | 24 horas |

## Hardware requerido

- Raspberry Pi Zero 2 W (o cualquier RPi con WiFi brcmfmac)
- SD card con Debian/Raspberry Pi OS
- Cable ethernet conectado a la red con internet

## Instalación

Ejecuta en la RPi:

```bash
git clone https://github.com/l707l/rpi-wifi-router.git
cd rpi-wifi-router
chmod +x setup.sh
sudo ./setup.sh
```

## Servicios activos

| Servicio | Descripción |
|---|---|
| `hostapd` | Access point WiFi 5GHz |
| `dnsmasq` | Servidor DHCP + DNS |
| `nftables` | NAT/masquerade desde eth0 a wlan0 |

## Arranque automático

El script crea `/etc/rc.local` que ejecuta `/usr/local/bin/rpi-wifi-router-start.sh` en cada boot.

Para reiniciar manualmente:
```bash
bash /usr/local/bin/rpi-wifi-router-start.sh
```

Para detener:
```bash
sudo pkill hostapd
sudo pkill dnsmasq
```

## Verificación

```bash
# Ver AP
iw dev wlan0 info

# Ver clientes conectados
iw dev wlan0 station dump

# Ver leases DHCP
cat /var/lib/misc/dnsmasq.leases

# Ver reglas NAT
sudo nft list ruleset
```

## Solución de problemas

### hostapd falla con "Could not set channel"
```bash
# Resetear la interfaz WiFi
sudo ip link set wlan0 down
sudo iw dev wlan0 set type managed
sudo ip link set wlan0 up
# Luego re-ejecutar
sudo hostapd /etc/hostapd/hostapd.conf
```

### brcmfmac no soporta el canal 36
```bash
# Ver canales disponibles
sudo iw reg set ES
iw list | grep -A 50 "Frequencies:"
```

### dnsmasq no inicia
```bash
# Verificar permisos del archivo de leases
sudo chown dnsmasq:dnsmasq /var/lib/misc/dnsmasq.leases
sudo systemctl restart dnsmasq
```

## Estructura del proyecto

```
rpi-wifi-router/
├── setup.sh                 # Script principal de instalación
├── config/
│   ├── hostapd.conf         # Configuración del AP
│   ├── dnsmasq.conf         # Configuración DHCP+DNS
│   └── nft_rules.nft        # Reglas NAT
├── start.sh                 # Script de inicio manual
├── stop.sh                  # Script de parada
├── verify.sh                # Script de verificación
└── README.md
```

## Personalización

Edita las variables al inicio de `setup.sh` o `start.sh`:

```bash
AP_SSID="MiRed"           # Nombre de la red WiFi
AP_PASS="miPassword123"    # Contraseña WPA2
AP_CHANNEL="36"            # Canal 5GHz
AP_FREQ="5180"            # Frecuencia en MHz
AP_IP="192.168.2.1"       # IP del gateway
```

## Licencia

MIT
