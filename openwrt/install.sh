#!/bin/sh
# ============================================================
#  SSH Tunnel Manager — OpenWrt Installer
#  Usage: curl -fsSL https://raw.githubusercontent.com/YOUR_USER/ssh-tunnel-manager/main/openwrt/install.sh | sh
# ============================================================

set -e

REPO_BASE="https://raw.githubusercontent.com/YOUR_USER/ssh-tunnel-manager/main/openwrt"

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

# --- Clear LuCI cache ---
rm -rf /tmp/luci-modulecache /tmp/luci-indexcache* 2>/dev/null || true

echo ""
echo "╔═══════════════════════════════════════════╗"
echo "║  Installation complete!                    ║"
echo "║                                            ║"
echo "║  Open LuCI: Services -> SSH Tunnel         ║"
echo "║  Enter VPS IP, paste key, add tunnels      ║"
echo "╚═══════════════════════════════════════════╝"
