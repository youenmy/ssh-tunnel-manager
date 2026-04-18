#!/bin/sh
# ============================================================
#  SSH Tunnel Manager — OpenWrt Installer (v2 branch)
#  Usage: curl -fsSL https://raw.githubusercontent.com/youenmy/ssh-tunnel-manager/v2/openwrt/install.sh | sh
# ============================================================

set -e

REPO_BASE="https://raw.githubusercontent.com/youenmy/ssh-tunnel-manager/v2/openwrt"

echo "╔═══════════════════════════════════════════╗"
echo "║  SSH Tunnel Manager — OpenWrt Installer   ║"
echo "╚═══════════════════════════════════════════╝"

# --- Detect package manager ---
if command -v apk >/dev/null 2>&1; then
    echo "[INFO] OpenWrt 25.x detected (apk)"
    apk update
    apk add autossh openssh-client-utils luci-compat curl
elif command -v opkg >/dev/null 2>&1; then
    echo "[INFO] OpenWrt <25.x detected (opkg)"
    opkg update
    opkg install autossh openssh-keyscan luci-compat curl
else
    echo "[ERROR] No package manager found"
    exit 1
fi

# --- UCI config ---
echo "[INFO] Creating UCI config..."
if [ ! -f /etc/config/sshtunnel ]; then
    curl -fsSL "$REPO_BASE/root/etc/config/sshtunnel" -o /etc/config/sshtunnel
    echo "[OK] Config created"
else
    echo "[INFO] Config already exists, skipping"
fi

# --- Init script ---
echo "[INFO] Installing init script..."
curl -fsSL "$REPO_BASE/root/etc/init.d/sshtunnel" -o /etc/init.d/sshtunnel
chmod +x /etc/init.d/sshtunnel
echo "[OK] Init script installed"

# --- UCI defaults ---
curl -fsSL "$REPO_BASE/root/etc/uci-defaults/40-luci-sshtunnel" -o /etc/uci-defaults/40-luci-sshtunnel
chmod +x /etc/uci-defaults/40-luci-sshtunnel
sh /etc/uci-defaults/40-luci-sshtunnel

# --- LuCI app ---
echo "[INFO] Installing LuCI application..."
mkdir -p /usr/lib/lua/luci/controller
mkdir -p /usr/lib/lua/luci/model/cbi

curl -fsSL "$REPO_BASE/luci-app-tunnel/luasrc/controller/sshtunnel.lua" \
    -o /usr/lib/lua/luci/controller/sshtunnel.lua

curl -fsSL "$REPO_BASE/luci-app-tunnel/luasrc/model/cbi/sshtunnel.lua" \
    -o /usr/lib/lua/luci/model/cbi/sshtunnel.lua

# --- SSH directory ---
mkdir -p /root/.ssh
chmod 700 /root/.ssh

# --- Watchdog cron ---
echo "[INFO] Installing watchdog..."
CRON_LINE="*/5 * * * * pgrep -f '/usr/sbin/autossh' >/dev/null || /etc/init.d/sshtunnel start 2>/dev/null"
if ! crontab -l 2>/dev/null | grep -q "sshtunnel"; then
    (crontab -l 2>/dev/null; echo "$CRON_LINE") | crontab -
    echo "[OK] Watchdog installed (checks every 5 min)"
else
    echo "[INFO] Watchdog already installed"
fi

# Enable cron service (often disabled by default on OpenWrt)
if [ -x /etc/init.d/cron ]; then
    /etc/init.d/cron enable 2>/dev/null
    /etc/init.d/cron start 2>/dev/null
fi

# --- Clear LuCI cache ---
rm -rf /tmp/luci-modulecache /tmp/luci-indexcache* 2>/dev/null || true

echo ""
echo "╔═══════════════════════════════════════════════╗"
echo "║  SSH Tunnel Manager установлен!                ║"
echo "║                                                ║"
echo "║  Откройте LuCI: Сервисы -> SSH Tunnel          ║"
echo "║  Введите IP VPS, вставьте ключ, добавьте       ║"
echo "║  туннели                                       ║"
echo "║                                                ║"
echo "║  Watchdog: проверка каждые 5 минут              ║"
echo "╚═══════════════════════════════════════════════╝"
