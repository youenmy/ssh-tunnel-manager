#!/usr/bin/env python3
"""SSH Tunnel Manager — VPS Web UI"""

import json, os, subprocess, secrets, re
from pathlib import Path
from functools import wraps
from flask import Flask, render_template, request, redirect, url_for, flash, jsonify, session

app = Flask(__name__)
app.secret_key = os.environ.get("STM_SECRET", secrets.token_hex(32))
app.config["PERMANENT_SESSION_LIFETIME"] = 86400

BASE_DIR = Path(__file__).parent
DATA_DIR = BASE_DIR / "data"
KEYS_DIR = BASE_DIR / "keys"
CONFIG_FILE = DATA_DIR / "config.json"
PANEL_USER = os.environ.get("STM_PANEL_USER", "stm-admin")

def verify_password(username, password):
    try:
        r = subprocess.run(["su", "-s", "/bin/sh", "-c", "true", username],
                           input=password + "\n", capture_output=True, text=True, timeout=5)
        return r.returncode == 0
    except Exception:
        return False

def login_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if not session.get("logged_in"):
            return redirect(url_for("login"))
        return f(*args, **kwargs)
    return decorated

def load_config():
    if CONFIG_FILE.exists():
        return json.loads(CONFIG_FILE.read_text())
    return {"tunnel_user": "tunnel", "ssh_port": 22, "gateway_ports": "clientspecified",
            "tunnels": [], "firewall_rules": [], "setup_complete": False}

def save_config(cfg):
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    CONFIG_FILE.write_text(json.dumps(cfg, indent=2, ensure_ascii=False))

def run(cmd, check=True):
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if check and r.returncode != 0:
        raise RuntimeError(f"Command failed: {cmd}\n{r.stderr}")
    return r

def get_active_tunnels():
    r = run("ss -tlnp 2>/dev/null | grep -E ':[0-9]' || true", check=False)
    return [l.strip() for l in r.stdout.strip().split("\n") if l.strip()]

def get_active_ports():
    ports = set()
    for line in get_active_tunnels():
        for p in re.findall(r'(?:0\.0\.0\.0|\*):(\d+)', line):
            ports.add(int(p))
    return ports

def get_ufw_status():
    r = run("ufw status numbered 2>/dev/null || echo 'ufw not active'", check=False)
    return r.stdout.strip()

def _rebuild_authorized_keys(cfg):
    username = cfg.get("tunnel_user", "tunnel")
    pub_key = cfg.get("public_key")
    if not pub_key:
        return
    permits = ",".join(f'permitlisten="0.0.0.0:{t["remote_port"]}"' for t in cfg["tunnels"])
    if not permits:
        permits = 'permitlisten="localhost:1"'
    auth_line = f'command="/bin/false",no-agent-forwarding,no-X11-forwarding,no-pty,permitopen="localhost:1",{permits} {pub_key}'
    auth_path = Path(f"/home/{username}/.ssh/authorized_keys")
    auth_path.parent.mkdir(parents=True, exist_ok=True)
    auth_path.write_text(auth_line + "\n")
    run(f"chmod 600 {auth_path}")
    run(f"chown {username}:{username} {auth_path}")

# ── Auth Routes ─────────────────────────────────────────────

@app.route("/login", methods=["GET", "POST"])
def login():
    if session.get("logged_in"):
        return redirect(url_for("index"))
    if request.method == "POST":
        username = request.form.get("username", "").strip()
        password = request.form.get("password", "")
        if verify_password(username, password):
            session["logged_in"] = True
            session["username"] = username
            session.permanent = True
            return redirect(url_for("index"))
        else:
            flash("Неверный логин или пароль", "error")
    return render_template("login.html")

@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("login"))

# ── Main Routes ─────────────────────────────────────────────

@app.route("/")
@login_required
def index():
    cfg = load_config()
    if not cfg.get("setup_complete"):
        return redirect(url_for("setup"))
    return render_template("dashboard.html", config=cfg,
                           active_tunnels=get_active_tunnels(), active_ports=get_active_ports())

@app.route("/setup", methods=["GET", "POST"])
@login_required
def setup():
    cfg = load_config()
    if request.method == "POST":
        action = request.form.get("action")
        if action == "create_user":
            username = request.form.get("username", "tunnel").strip()
            if not re.match(r'^[a-z_][a-z0-9_-]*$', username):
                flash("Invalid username", "error")
                return redirect(url_for("setup"))
            cfg["tunnel_user"] = username
            r = run(f"id {username} 2>/dev/null", check=False)
            if r.returncode != 0:
                run(f"useradd --system --create-home --shell /usr/sbin/nologin {username}")
                run(f"mkdir -p /home/{username}/.ssh && chmod 700 /home/{username}/.ssh")
                run(f"chown -R {username}:{username} /home/{username}/.ssh")
                flash(f"User '{username}' created", "success")
            else:
                flash(f"User '{username}' already exists", "info")
            save_config(cfg)
        elif action == "generate_key":
            username = cfg.get("tunnel_user", "tunnel")
            key_path = KEYS_DIR / f"{username}_key"
            if key_path.exists():
                key_path.unlink()
                Path(f"{key_path}.pub").unlink(missing_ok=True)
            run(f'ssh-keygen -t ed25519 -f {key_path} -N "" -C "tunnel-{username}"')
            cfg["public_key"] = Path(f"{key_path}.pub").read_text().strip()
            save_config(cfg)
            _rebuild_authorized_keys(cfg)
            flash("SSH key generated", "success")
        elif action == "import_pubkey":
            pubkey = request.form.get("pubkey", "").strip()
            if pubkey.startswith("ssh-") and len(pubkey) > 30:
                cfg["public_key"] = pubkey
                save_config(cfg)
                _rebuild_authorized_keys(cfg)
                flash("Public key saved and authorized_keys updated", "success")
            else:
                flash("Invalid public key format (must start with ssh-ed25519 or ssh-rsa)", "error")
        elif action == "apply_sshd":
            gw = request.form.get("gateway_ports", "clientspecified")
            cfg["gateway_ports"] = gw
            save_config(cfg)
            sshd_conf = Path("/etc/ssh/sshd_config").read_text()
            if re.search(r'^GatewayPorts\s', sshd_conf, re.MULTILINE):
                sshd_conf = re.sub(r'^GatewayPorts\s+.*$', f'GatewayPorts {gw}', sshd_conf, flags=re.MULTILINE)
            else:
                sshd_conf += f"\nGatewayPorts {gw}\n"
            Path("/etc/ssh/sshd_config").write_text(sshd_conf)
            run("systemctl restart sshd")
            flash("sshd_config updated & restarted", "success")
        elif action == "complete_setup":
            cfg["setup_complete"] = True
            _rebuild_authorized_keys(cfg)
            save_config(cfg)
            flash("Setup complete!", "success")
            return redirect(url_for("index"))
        return redirect(url_for("setup"))

    key_path = KEYS_DIR / f"{cfg.get('tunnel_user', 'tunnel')}_key"
    private_key = key_path.read_text() if key_path.exists() else None
    return render_template("setup.html", config=cfg, private_key=private_key)

@app.route("/tunnels", methods=["GET", "POST"])
@login_required
def tunnels():
    cfg = load_config()
    if request.method == "POST":
        action = request.form.get("action")
        if action == "add":
            name = request.form.get("name", "").strip()
            remote_port = request.form.get("remote_port", "").strip()
            local_ip = request.form.get("local_ip", "").strip()
            local_port = request.form.get("local_port", "").strip()
            if not all([name, remote_port, local_ip, local_port]):
                flash("All fields required", "error")
                return redirect(url_for("tunnels"))
            try:
                rp, lp = int(remote_port), int(local_port)
                if not (1 <= rp <= 65535 and 1 <= lp <= 65535):
                    raise ValueError
            except ValueError:
                flash("Ports must be 1-65535", "error")
                return redirect(url_for("tunnels"))
            cfg["tunnels"].append({"name": name, "remote_port": rp, "local_ip": local_ip, "local_port": lp})
            save_config(cfg)
            _rebuild_authorized_keys(cfg)
            flash(f"Tunnel '{name}' added", "success")
        elif action == "edit":
            idx = int(request.form.get("index", -1))
            if 0 <= idx < len(cfg["tunnels"]):
                name = request.form.get("name", "").strip()
                remote_port = request.form.get("remote_port", "").strip()
                local_ip = request.form.get("local_ip", "").strip()
                local_port = request.form.get("local_port", "").strip()
                if not all([name, remote_port, local_ip, local_port]):
                    flash("All fields required", "error")
                    return redirect(url_for("tunnels", edit=idx))
                try:
                    rp, lp = int(remote_port), int(local_port)
                    if not (1 <= rp <= 65535 and 1 <= lp <= 65535):
                        raise ValueError
                except ValueError:
                    flash("Ports must be 1-65535", "error")
                    return redirect(url_for("tunnels", edit=idx))
                cfg["tunnels"][idx] = {"name": name, "remote_port": rp, "local_ip": local_ip, "local_port": lp}
                save_config(cfg)
                _rebuild_authorized_keys(cfg)
                flash(f"Tunnel '{name}' updated", "success")
        elif action == "delete":
            idx = int(request.form.get("index", -1))
            if 0 <= idx < len(cfg["tunnels"]):
                removed = cfg["tunnels"].pop(idx)
                save_config(cfg)
                _rebuild_authorized_keys(cfg)
                flash(f"Tunnel '{removed['name']}' removed", "success")
        return redirect(url_for("tunnels"))

    # GET - check for edit mode
    edit_index = request.args.get("edit", None)
    edit_tunnel = None
    if edit_index is not None:
        try:
            edit_index = int(edit_index)
            if 0 <= edit_index < len(cfg["tunnels"]):
                edit_tunnel = cfg["tunnels"][edit_index]
            else:
                edit_index = None
        except ValueError:
            edit_index = None

    return render_template("tunnels.html", config=cfg, active_tunnels=get_active_tunnels(),
                           active_ports=get_active_ports(), edit_index=edit_index, edit_tunnel=edit_tunnel)

@app.route("/firewall", methods=["GET", "POST"])
@login_required
def firewall():
    cfg = load_config()
    if request.method == "POST":
        action = request.form.get("action")
        if action == "open_port":
            port = request.form.get("port", "").strip()
            source = request.form.get("source", "").strip()
            comment = request.form.get("comment", "").strip()
            try:
                p = int(port)
                if not (1 <= p <= 65535):
                    raise ValueError
            except ValueError:
                flash("Invalid port", "error")
                return redirect(url_for("firewall"))
            if source:
                run(f'ufw allow from {source} to any port {p} proto tcp comment "{comment}"')
            else:
                run(f'ufw allow {p}/tcp comment "{comment}"')
            flash(f"Port {p} opened", "success")
        elif action == "close_port":
            rule_num = request.form.get("rule_num", "").strip()
            if rule_num:
                run(f"ufw --force delete {rule_num}", check=False)
                flash("Rule deleted", "success")
        elif action == "auto_open":
            for t in cfg["tunnels"]:
                run(f'ufw allow {t["remote_port"]}/tcp comment "Tunnel: {t["name"]}"', check=False)
            flash("Firewall rules synced with tunnels", "success")
        return redirect(url_for("firewall"))
    return render_template("firewall.html", config=cfg, ufw_status=get_ufw_status())

@app.route("/api/status")
@login_required
def api_status():
    cfg = load_config()
    return jsonify({"tunnels": cfg["tunnels"], "active": get_active_tunnels()})

@app.route("/api/private-key")
@login_required
def api_private_key():
    cfg = load_config()
    key_path = KEYS_DIR / f"{cfg.get('tunnel_user', 'tunnel')}_key"
    if key_path.exists():
        return key_path.read_text(), 200, {"Content-Type": "text/plain"}
    return "No key generated", 404

if __name__ == "__main__":
    port = int(os.environ.get("STM_PORT", 7575))
    app.run(host="0.0.0.0", port=port, debug=False)
