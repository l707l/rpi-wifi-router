#!/bin/bash
# ============================================================
# rpi-wifi-router + Pi-hole install script
# Full router AP + Pi-hole ad-blocker DNS
#
# Run on RPi: chmod +x setup-pihole.sh && sudo ./setup-pihole.sh
# ============================================================

set -e

PIHOLE_FTL_URL="https://github.com/pi-hole/FTL/releases/download/v6.7/pihole-FTL-arm64"
PIHOLE_WEB_URL="https://raw.githubusercontent.com/pi-hole/pi-hole/master/advanced/Solar-Park.ttf"
PIHOLE_WEB="https://install.pi-hole.net"

echo "=== Installing Pi-hole on RPi WiFi Router ==="
echo ""

# --- Detect ---
ARCH=$(uname -m)
echo "[*] Architecture: $ARCH"
echo "[*] User: $(whoami)"

# --- 1. Stop existing dnsmasq (conflicts with Pi-hole FTL on port 53) ---
echo ""
echo "[1/8] Stopping existing dnsmasq..."
sudo pkill dnsmasq 2>/dev/null || true
sudo systemctl stop dnsmasq 2>/dev/null || true
sudo systemctl disable dnsmasq 2>/dev/null || true
echo "  dnsmasq stopped"

# --- 2. Ensure lighttpd is installed (already done by setup.sh) ---
echo ""
echo "[2/8] Verifying lighttpd..."
if ! command -v lighttpd &>/dev/null; then
    echo "  ERROR: lighttpd not found. Run setup.sh first."
    exit 1
fi
echo "  lighttpd $(lighttpd -v | awk '{print $1,$2}')"

# --- 3. Install PHP for Pi-hole web interface ---
echo ""
echo "[3/8] Installing PHP..."

# Try apt first (if it works)
if command -v php &>/dev/null; then
    echo "  PHP already installed: $(php -v | head -1)"
else
    echo "  Installing PHP-FPM via apt..."
    sudo apt-get install -y php php-cgi php-sqlite3 2>/dev/null || {
        echo "  apt failed — downloading PHP debs manually..."
        BASE="http://deb.debian.org/debian/pool/main"
        PHP_DEBS="php8.4-cgi_8.4.23-1~deb13u1_arm64.deb php8.4-cli_8.4.23-1~deb13u1_arm64.deb php8.4-common_8.4.23-1~deb13u1_arm64.deb php8.4-opcache_8.4.23-1~deb13u1_arm64.deb"
        for deb in $PHP_DEBS; do
            echo "  Downloading $deb..."
            curl -sL "$BASE/${deb%_*}/php8.4/${deb}" -o "/tmp/$deb" || true
        done
        sudo dpkg -i /tmp/php*.deb 2>/dev/null || true
        sudo apt-get install -f -y 2>/dev/null || true
    }
fi
php -v 2>/dev/null | head -1 && echo "  PHP OK" || echo "  PHP not available (web interface may not work)"

# --- 4. Download and install Pi-hole FTL ---
echo ""
echo "[4/8] Installing Pi-hole FTL..."
PIHOLE_FTL="/tmp/pihole-FTL-arm64"
if [ ! -f "$PIHOLE_FTL" ] || ! "$PIHOLE_FTL" --version &>/dev/null; then
    echo "  Downloading Pi-hole FTL v6.7..."
    curl -sL "$PIHOLE_FTL_URL" -o "$PIHOLE_FTL"
    chmod +x "$PIHOLE_FTL"
else
    echo "  FTL binary already present"
fi

# Install FTL
echo "  Installing FTL..."
sudo mkdir -p /opt/pihole
sudo cp "$PIHOLE_FTL" /opt/pihole/pihole-FTL
sudo chmod +x /opt/pihole/pihole-FTL
sudo mkdir -p /etc/pihole /var/log /run/pihole
sudo touch /var/log/pihole-FTL.log
sudo chown -R pihole:pihole /etc/pihole /var/log /run/pihole 2>/dev/null || \
    sudo chown -R nobody:root /etc/pihole /var/log /run/pihole

# Create pihole-FTL.conf
cat | sudo tee /etc/pihole/pihole-FTL.conf > /dev/null <<EOF
DNSMASQ_CONF=/etc/dnsmasq.d/02-pihole.conf
PORT=53
WEBPORT=8080
FTLUSER=pihole
DELAY_STARTUP=0
CHECK_HOSTNAME=false
EOF

# Create dnsmasq config for Pi-hole
cat | sudo tee /etc/dnsmasq.d/02-pihole.conf > /dev/null <<EOF
# Pi-hole DNS config
interface=wlan0
no-resolv
server=8.8.8.8
server=8.8.4.4
localise-queries
no-dhcp-interface=
bind-interfaces
listen-address=127.0.0.1
listen-address=192.168.2.1
port=53
domain-needed
bogus-priv
EOF

echo "  Pi-hole FTL configured"
echo "  FTL version: $(/opt/pihole/pihole-FTL version 2>/dev/null || /opt/pihole/pihole-FTL --version 2>/dev/null || echo 'binary installed')"

# --- 5. Configure lighttpd for Pi-hole web ---
echo ""
echo "[5/8] Configuring lighttpd for Pi-hole web..."

# Enable mod_fastcgi or mod_cgi for PHP
sudo lighttpd-enable-mod fastcgi 2>/dev/null || true
sudo lighttpd-enable-mod fastcgi-php 2>/dev/null || true

# Create Pi-hole web config
cat | sudo tee /etc/lighttpd/conf-available/99-pihole.conf > /dev/null <<EOF
# Pi-hole web interface
alias.url += ( "/admin" => "/var/www/html/pihole/index.php" )
\$HTTP["url"] =~ "^/admin/" {
    proxy.server  = ( "" => (("host" => "127.0.0.1", "port" => 8080)) )
}
EOF
sudo lighttpd-enable-mod pihole 2>/dev/null || true

# If PHP is available, configure it
if command -v php &>/dev/null; then
    cat | sudo tee /etc/lighttpd/conf-available/20-php.conf > /dev/null <<EOF
server.modules += ( "mod_fastcgi" )
fastcgi.server += ( ".php" => ((
    "bin-path" => "/usr/bin/php-cgi",
    "socket" => "/run/lighttpd/php.socket",
    "max-procs" => 1,
    "bin-environment" => ( "REMOTE_ADDR" => "\$env.remote_addr" ),
    "broken-scriptfilename" => "enable"
)))
EOF
    sudo lighttpd-enable-mod php 2>/dev/null || true
fi

# Create Pi-hole web root
echo "  Setting up Pi-hole web directory..."
sudo mkdir -p /var/www/html/pihole
cat | sudo tee /var/www/html/pihole/index.php > /dev/null <<'PIPHP'
<?php header('Location: /admin/'); ?>
PIPHP

sudo systemctl enable lighttpd 2>/dev/null || true

# --- 6. Setup Pi-hole as DHCP server ---
echo ""
echo "[6/8] Configuring Pi-hole DHCP..."

# Update dnsmasq config for DHCP (replace previous dnsmasq config)
cat | sudo tee /etc/dnsmasq.d/02-pihole.conf > /dev/null <<EOF
# Pi-hole DHCP + DNS
interface=wlan0
dhcp-range=192.168.2.50,192.168.2.250,24h
dhcp-option=3,192.168.2.1
dhcp-option=6,192.168.2.1
server=8.8.8.8
server=8.8.4.4
localise-queries
no-resolv
bind-interfaces
listen-address=127.0.0.1
listen-address=192.168.2.1
port=53
domain-needed
bogus-priv
log-queries
log-dhcp
EOF

# --- 7. Update NAT to redirect DNS to Pi-hole ---
echo ""
echo "[7/8] Updating NAT rules to route DNS through Pi-hole..."

# Add Pi-hole DNS redirect: all DNS from wlan0 clients goes to Pi-hole (already the case since Pi-hole IS the DNS server)
# But we need to ensure port 53 traffic is accepted
sudo /usr/sbin/nft delete table ip nat 2>/dev/null || true
sudo /usr/sbin/nft -f /tmp/nft_rules.nft 2>/dev/null || {
    cat | sudo tee /tmp/nft_rules.nft > /dev/null <<'EOFNFT'
table ip nat {
  chain postrouting {
    type nat hook postrouting priority srcnat; policy accept;
    oifname "eth0" masquerade
  }
  chain prerouting {
    type nat hook prerouting priority dstnat; policy accept;
    iifname "wlan0" udp dport 53 dnat to 192.168.2.1
    iifname "wlan0" tcp dport 53 dnat to 192.168.2.1
  }
}
table ip filter {
  chain forward {
    type filter hook forward priority filter; policy accept;
    iifname "wlan0" accept
    oifname "wlan0" accept
  }
  chain input {
    type filter hook input priority filter; policy accept;
    iifname "wlan0" udp dport 53 accept
    iifname "wlan0" tcp dport 53 accept
  }
}
EOFNFT
    sudo /usr/sbin/nft -f /tmp/nft_rules.nft
}
echo "  NAT rules updated"

# --- 8. Start services ---
echo ""
echo "[8/8] Starting services..."

# Start Pi-hole FTL (it handles DNS)
echo "  Starting pihole-FTL..."
sudo /opt/pihole/pihole-FTL &
sleep 2

# Restart dnsmasq (Pi-hole manages it via /etc/dnsmasq.d/02-pihole.conf)
echo "  Starting dnsmasq..."
sudo pkill dnsmasq 2>/dev/null || true
sudo /usr/sbin/dnsmasq -C /etc/dnsmasq.conf --no-daemon || true
sleep 1

# Reload lighttpd
echo "  Reloading lighttpd..."
sudo pkill -HUP lighttpd 2>/dev/null || sudo lighttpd -t -f /etc/lighttpd/lighttpd.conf 2>/dev/null || true

# Verify
echo ""
echo "=== Verification ==="
pgrep -a pihole-FTL 2>/dev/null && echo "  pihole-FTL OK" || echo "  pihole-FTL not running"
pgrep -a dnsmasq 2>/dev/null && echo "  dnsmasq OK" || echo "  dnsmasq not running"
pgrep -a lighttpd 2>/dev/null && echo "  lighttpd OK" || echo "  lighttpd not running"
pgrep -a hostapd 2>/dev/null && echo "  hostapd OK" || echo "  hostapd not running"

echo ""
echo "=== DONE ==="
echo "Pi-hole DNS:  192.168.2.1 (UDP/TCP port 53)"
echo "Web UI:       http://192.168.2.1/admin  (or http://192.168.1.46/admin)"
echo "             Note: lighttpd web config may need manual tuning"
echo ""
echo "To set admin password: sudo pihole -a -p"
echo "To view logs:          sudo journalctl -u pihole-FTL"
echo "To restart FTL:         sudo pkill pihole-FTL; sudo /opt/pihole/pihole-FTL &"
