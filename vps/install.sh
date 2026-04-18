#!/bin/bash
set -e

# ============================================================
#  SSH Tunnel Manager — VPS Installer (v2 branch)
#  Usage: curl -fsSL https://raw.githubusercontent.com/youenmy/ssh-tunnel-manager/v2/vps/install.sh | sudo bash
# ============================================================

APP_DIR="/opt/ssh-tunnel-manager"
SERVICE_NAME="ssh-tunnel-manager"
VENV_DIR="$APP_DIR/venv"
PORT=7575
PANEL_USER="stm-admin"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# --- Pre-checks ---
[[ $EUID -ne 0 ]] && err "Run as root: curl ... | sudo bash"
command -v python3 >/dev/null || err "python3 not found. Install: apt install python3"

info "Installing SSH Tunnel Manager on VPS..."

# --- Dependencies ---
info "Installing system packages..."
apt-get update -qq
apt-get install -y -qq python3-venv python3-pip ufw openssh-server > /dev/null

# --- App directory ---
mkdir -p "$APP_DIR"/{data,keys}
chmod 700 "$APP_DIR/keys"

# --- Download app files ---
info "Downloading application files..."
REPO_BASE="https://raw.githubusercontent.com/youenmy/ssh-tunnel-manager/v2/vps"

for f in app.py requirements.txt; do
    curl -fsSL "$REPO_BASE/$f" -o "$APP_DIR/$f"
done

mkdir -p "$APP_DIR/templates" "$APP_DIR/static"
for f in base.html dashboard.html setup.html tunnels.html firewall.html login.html diagnostics.html; do
    curl -fsSL "$REPO_BASE/templates/$f" -o "$APP_DIR/templates/$f"
done
curl -fsSL "$REPO_BASE/static/style.css" -o "$APP_DIR/static/style.css"

# --- Python venv ---
info "Setting up Python environment..."
python3 -m venv "$VENV_DIR"
"$VENV_DIR/bin/pip" install -q --upgrade pip
"$VENV_DIR/bin/pip" install -q -r "$APP_DIR/requirements.txt"

# --- Generate panel credentials ---
if id "$PANEL_USER" &>/dev/null; then
    # User exists — don't change password on reinstall
    PANEL_PASS="(не изменён, см. файл credentials или задайте новый: passwd $PANEL_USER)"
    ok "Panel user '$PANEL_USER' already exists, password unchanged"
else
    PANEL_PASS=$(openssl rand -base64 12 | tr -d '/+=')
    useradd --system --no-create-home --shell /usr/sbin/nologin "$PANEL_USER"
    echo "$PANEL_USER:$PANEL_PASS" | chpasswd
    ok "Panel user '$PANEL_USER' created"

    # Save credentials to a file readable only by root
    cat > "$APP_DIR/data/credentials" << EOF
Panel Login: $PANEL_USER
Panel Password: $PANEL_PASS
EOF
    chmod 600 "$APP_DIR/data/credentials"
fi

# --- Config ---
if [[ ! -f "$APP_DIR/data/config.json" ]]; then
    cat > "$APP_DIR/data/config.json" << 'CONF'
{
    "tunnel_user": "tunnel",
    "ssh_port": 22,
    "gateway_ports": "clientspecified",
    "tunnels": [],
    "firewall_rules": [],
    "setup_complete": false
}
CONF
    ok "Default config created"
fi

# --- Systemd service ---
cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=SSH Tunnel Manager Web UI
After=network.target

[Service]
Type=simple
WorkingDirectory=$APP_DIR
ExecStart=$VENV_DIR/bin/python app.py
Restart=always
RestartSec=5
Environment=STM_PORT=$PORT
Environment=STM_PANEL_USER=$PANEL_USER

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"

# --- Ensure sshd config via drop-in (safer than editing main sshd_config,
#     survives unattended-upgrades that may replace /etc/ssh/sshd_config) ---
SSHD_DROPIN="/etc/ssh/sshd_config.d/99-ssh-tunnel.conf"
SSHD_CHANGED=0
if [[ ! -f "$SSHD_DROPIN" ]]; then
    mkdir -p /etc/ssh/sshd_config.d
    cat > "$SSHD_DROPIN" << 'EOF'
# Managed by ssh-tunnel-manager.
# Safe to delete: app will recreate it. Safe to edit: app does not overwrite
# if the file already exists (only creates it when missing).
GatewayPorts clientspecified
ClientAliveInterval 30
ClientAliveCountMax 3
EOF
    chmod 644 "$SSHD_DROPIN"
    SSHD_CHANGED=1
    ok "sshd drop-in installed: $SSHD_DROPIN"
else
    info "sshd drop-in already exists: $SSHD_DROPIN (not overwriting)"
fi

# Check that main sshd_config includes the drop-in directory (Ubuntu default does)
if ! sshd -T 2>/dev/null | grep -q "^gatewayports clientspecified"; then
    warn "sshd is not honouring the drop-in. Check that /etc/ssh/sshd_config has:  Include /etc/ssh/sshd_config.d/*.conf"
fi

# If the OLD version of this installer modified /etc/ssh/sshd_config directly,
# we leave those lines alone — drop-in takes precedence and duplicate directives are harmless.

[ "$SSHD_CHANGED" = "1" ] && systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true

# --- Firewall ---
ufw allow "$PORT/tcp" comment "SSH Tunnel Manager UI" > /dev/null 2>&1

ok "Installation complete!"

# Detect server IP
SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
[ -z "$SERVER_IP" ] && SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || echo "YOUR_SERVER_IP")

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  SSH Tunnel Manager installed!                    ║${NC}"
echo -e "${GREEN}║                                                   ║${NC}"
echo -e "${GREEN}║  URL:      ${CYAN}http://${SERVER_IP}:${PORT}${GREEN}${NC}"
echo -e "${GREEN}║                                                   ║${NC}"
echo -e "${GREEN}║  Login:    ${CYAN}${PANEL_USER}${NC}"
echo -e "${GREEN}║  Password: ${CYAN}${PANEL_PASS}${NC}"
echo -e "${GREEN}║                                                   ║${NC}"
echo -e "${GREEN}║  Credentials: ${APP_DIR}/data/credentials${NC}"
echo -e "${GREEN}║  Change pass: passwd ${PANEL_USER}${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
