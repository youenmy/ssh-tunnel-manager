-- SSH Tunnel Manager — LuCI CBI Model
local sys = require "luci.sys"
local fs  = require "nixio.fs"

m = Map("sshtunnel", translate("SSH Tunnel Manager"),
    translate("Manage reverse SSH tunnels to your VPS for remote access to home network services."))

-- ═══════════════════════════════════════════
-- Global settings
-- ═══════════════════════════════════════════

s = m:section(NamedSection, "global", "sshtunnel", translate("Connection Settings"))
s.addremove = false
s.anonymous = false

-- Enable
en = s:option(Flag, "enabled", translate("Enable tunnel"))
en.rmempty = false

-- VPS IP
ip = s:option(Value, "vps_ip", translate("VPS IP address"))
ip.datatype = "ipaddr"
ip.placeholder = "203.0.113.1"
ip.rmempty = false

-- VPS SSH port
pt = s:option(Value, "vps_port", translate("VPS SSH port"))
pt.datatype = "port"
pt.default = "22"
pt.placeholder = "22"

-- VPS user
us = s:option(Value, "vps_user", translate("VPS tunnel user"))
us.default = "tunnel"
us.placeholder = "tunnel"

-- Key path
kp = s:option(Value, "key_path", translate("Private key path"))
kp.default = "/root/.ssh/tunnel_key"
kp.placeholder = "/root/.ssh/tunnel_key"

-- ServerAlive interval
ai = s:option(Value, "alive_interval", translate("ServerAliveInterval (sec)"),
    translate("How often to send keepalive packets"))
ai.datatype = "uinteger"
ai.default = "30"

-- ServerAlive count
ac = s:option(Value, "alive_count", translate("ServerAliveCountMax"),
    translate("Disconnect after this many missed keepalives"))
ac.datatype = "uinteger"
ac.default = "3"

-- ═══════════════════════════════════════════
-- Private key management
-- ═══════════════════════════════════════════

k = m:section(TypedSection, "sshtunnel", translate("Private Key"))
k.addremove = false
k.anonymous = true

ka = k:option(TextValue, "_key_content", translate("Private key"))
ka.rows = 8
ka.wrap = "off"
ka.rmempty = true
ka.description = translate("Paste your Ed25519 private key here. It will be saved to the path above.")

function ka.cfgvalue(self, section)
    local path = m:get("global", "key_path") or "/root/.ssh/tunnel_key"
    return fs.readfile(path) or ""
end

function ka.write(self, section, value)
    if value and #value > 10 then
        local path = m:get("global", "key_path") or "/root/.ssh/tunnel_key"
        local dir = path:match("(.+)/[^/]+$")
        if dir then
            sys.call("mkdir -p " .. dir .. " && chmod 700 " .. dir)
        end
        fs.writefile(path, value)
        sys.call("chmod 600 " .. path)
    end
end

-- ═══════════════════════════════════════════
-- Known hosts
-- ═══════════════════════════════════════════

kh = k:option(Button, "_scan_host", translate("Add VPS to known_hosts"))
kh.inputtitle = translate("Scan & Add")
kh.inputstyle = "apply"

function kh.write(self, section)
    local vps_ip = m:get("global", "vps_ip") or ""
    local vps_port = m:get("global", "vps_port") or "22"
    if vps_ip ~= "" then
        sys.call("ssh-keyscan -t ed25519 -p " .. vps_port .. " " .. vps_ip .. " >> /root/.ssh/known_hosts 2>/dev/null")
    end
end

-- ═══════════════════════════════════════════
-- Tunnels (dynamic list)
-- ═══════════════════════════════════════════

t = m:section(TypedSection, "tunnel", translate("Port Forwards"),
    translate("Each tunnel maps a VPS port to a device in your home network."))
t.addremove = true
t.anonymous = true
t.template = "cbi/tblsection"

te = t:option(Flag, "enabled", translate("On"))
te.default = "1"
te.rmempty = false

tn = t:option(Value, "name", translate("Name"))
tn.placeholder = "RDP / SMB / Web..."
tn.rmempty = false

tr = t:option(Value, "remote_port", translate("VPS port"))
tr.datatype = "port"
tr.placeholder = "3389"
tr.rmempty = false

tl = t:option(Value, "local_ip", translate("Local IP"))
tl.datatype = "ipaddr"
tl.placeholder = "192.168.1.100"
tl.rmempty = false

tp = t:option(Value, "local_port", translate("Local port"))
tp.datatype = "port"
tp.placeholder = "3389"
tp.rmempty = false

-- ═══════════════════════════════════════════
-- Status
-- ═══════════════════════════════════════════

st = m:section(TypedSection, "sshtunnel", translate("Status"))
st.addremove = false
st.anonymous = true

btn_start = st:option(Button, "_start", translate("Start tunnel"))
btn_start.inputtitle = translate("Start")
btn_start.inputstyle = "apply"
function btn_start.write()
    sys.call("/etc/init.d/sshtunnel restart")
end

btn_stop = st:option(Button, "_stop", translate("Stop tunnel"))
btn_stop.inputtitle = translate("Stop")
btn_stop.inputstyle = "remove"
function btn_stop.write()
    sys.call("/etc/init.d/sshtunnel stop")
end

stat = st:option(DummyValue, "_status", translate("Current status"))
function stat.cfgvalue()
    local r = sys.exec("pgrep -f autossh >/dev/null 2>&1 && echo 'Running' || echo 'Stopped'")
    return r:gsub("%s+$", "")
end

return m
