#!/bin/bash
set -e

# ============================================================
#  SSH Tunnel Manager — VPS Installer
#  Usage: curl -fsSL https://raw.githubusercontent.com/youenmy/ssh-tunnel-manager/main/vps/install.sh | sudo bash
# ============================================================

APP_DIR="/opt/ssh-tunnel-manager"
SERVICE_NAME="ssh-tunnel-manager"
VENV_DIR="$APP_DIR/venv"
PORT=7575

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
REPO_BASE="https://raw.githubusercontent.com/youenmy/ssh-tunnel-manager/main/vps"

for f in app.py requirements.txt; do
    curl -fsSL "$REPO_BASE/$f" -o "$APP_DIR/$f"
done

mkdir -p "$APP_DIR/templates" "$APP_DIR/static"
for f in base.html dashboard.html setup.html tunnels.html firewall.html; do
    curl -fsSL "$REPO_BASE/templates/$f" -o "$APP_DIR/templates/$f"
done
curl -fsSL "$REPO_BASE/static/style.css" -o "$APP_DIR/static/style.css"

# --- Python venv ---
info "Setting up Python environment..."
python3 -m venv "$VENV_DIR"
"$VENV_DIR/bin/pip" install -q --upgrade pip
"$VENV_DIR/bin/pip" install -q -r "$APP_DIR/requirements.txt"

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

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl start "$SERVICE_NAME"

# --- Ensure sshd config ---
if ! grep -q "^GatewayPorts" /etc/ssh/sshd_config; then
    echo "GatewayPorts clientspecified" >> /etc/ssh/sshd_config
    systemctl restart sshd
    ok "GatewayPorts clientspecified added to sshd_config"
fi

# --- Firewall ---
ufw allow "$PORT/tcp" comment "SSH Tunnel Manager UI" > /dev/null 2>&1

ok "Installation complete!"
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  SSH Tunnel Manager is running!               ║${NC}"
echo -e "${GREEN}║                                               ║${NC}"
echo -e "${GREEN}║  Open: http://YOUR_SERVER_IP:${PORT}            ║${NC}"
echo -e "${GREEN}║                                               ║${NC}"
echo -e "${GREEN}║  Complete setup in the web interface.          ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""
