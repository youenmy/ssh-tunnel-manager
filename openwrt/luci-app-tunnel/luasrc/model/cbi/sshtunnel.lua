-- SSH Tunnel Manager — LuCI CBI Model (fixed)
local sys   = require "luci.sys"
local fs    = require "nixio.fs"
local nixio = require "nixio"

m = Map("sshtunnel", translate("SSH Tunnel Manager"),
    translate("Manage reverse SSH tunnels to your VPS for remote access to home network services."))

-- ═══════════════════════════════════════════
-- Global settings
-- ═══════════════════════════════════════════

s = m:section(NamedSection, "global", "sshtunnel", translate("Connection Settings"))
s.addremove = false
s.anonymous = false

en = s:option(Flag, "enabled", translate("Enable tunnel"))
en.rmempty = false

ip = s:option(Value, "vps_ip", translate("VPS IP address"))
ip.datatype = "ipaddr"
ip.placeholder = "203.0.113.1"
ip.rmempty = false

pt = s:option(Value, "vps_port", translate("VPS SSH port"))
pt.datatype = "port"
pt.default = "22"
pt.placeholder = "22"

us = s:option(Value, "vps_user", translate("VPS tunnel user"))
us.default = "tunnel"
us.placeholder = "tunnel"

kp = s:option(Value, "key_path", translate("Private key path"))
kp.default = "/root/.ssh/tunnel_key"
kp.placeholder = "/root/.ssh/tunnel_key"

ai = s:option(Value, "alive_interval", translate("ServerAliveInterval (sec)"),
    translate("How often to send keepalive packets"))
ai.datatype = "uinteger"
ai.default = "30"

ac = s:option(Value, "alive_count", translate("ServerAliveCountMax"),
    translate("Disconnect after this many missed keepalives"))
ac.datatype = "uinteger"
ac.default = "3"

-- ═══════════════════════════════════════════
-- Private key — read-only display + paste field
-- ═══════════════════════════════════════════

k = m:section(TypedSection, "sshtunnel", translate("Private Key"))
k.addremove = false
k.anonymous = true

-- Show current key status
kd = k:option(DummyValue, "_key_display", translate("Current key"))
function kd.cfgvalue(self, section)
    local path = m:get("global", "key_path") or "/root/.ssh/tunnel_key"
    if fs.access(path) then
        local size = nixio.fs.stat(path, "size") or 0
        return translate("Key file exists") .. " (" .. size .. " bytes): " .. path
    else
        return translate("No key file found")
    end
end

-- Paste field for new key
ka = k:option(TextValue, "_key_paste", translate("Paste new key"),
    translate("Paste the private key and click 'Save Key' below. The main Save & Apply button does NOT save the key."))
ka.rows = 8
ka.wrap = "off"
ka.rmempty = true

function ka.cfgvalue(self, section)
    return ""
end

-- Disable default write — key is saved only via the button
function ka.write(self, section, value)
    return
end

function ka.remove(self, section)
    return
end

-- Save Key button
ks = k:option(Button, "_save_key", translate("Save key to file"))
ks.inputtitle = translate("Save Key")
ks.inputstyle = "apply"

function ks.write(self, section)
    -- Read the key from the form submission
    local http = require "luci.http"
    local val = http.formvalue("cbid.sshtunnel.global._key_paste") or ""
    val = val:gsub("\r\n", "\n"):gsub("^%s+", ""):gsub("%s+$", "")

    if val:match("PRIVATE KEY") and #val > 50 then
        local path = m:get("global", "key_path") or "/root/.ssh/tunnel_key"
        local dir = path:match("(.+)/[^/]+$")
        if dir then
            sys.call("mkdir -p " .. dir .. " && chmod 700 " .. dir)
        end
        fs.writefile(path, val .. "\n")
        sys.call("chmod 600 " .. path)
        m.message = translate("Key saved successfully!")
    else
        m.message = translate("Error: paste a valid private key (must contain BEGIN/END PRIVATE KEY)")
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
-- Status & Controls
-- ═══════════════════════════════════════════

st = m:section(TypedSection, "sshtunnel", translate("Status"))
st.addremove = false
st.anonymous = true

stat = st:option(DummyValue, "_status", translate("Current status"))
function stat.cfgvalue()
    local code = sys.call("pgrep -f '/usr/sbin/autossh.*sshtunnel' >/dev/null 2>&1")
    if code == 0 then
        return translate("Running")
    else
        -- Check if enabled but not running
        local enabled = m:get("global", "enabled") or "0"
        if enabled == "1" then
            return translate("Stopped (should be running — check logs)")
        else
            return translate("Stopped")
        end
    end
end

btn_restart = st:option(Button, "_restart", translate("Restart tunnel"))
btn_restart.inputtitle = translate("Restart")
btn_restart.inputstyle = "apply"
function btn_restart.write()
    sys.call("/etc/init.d/sshtunnel restart 2>/dev/null")
end

btn_stop = st:option(Button, "_stop", translate("Stop tunnel"))
btn_stop.inputtitle = translate("Stop")
btn_stop.inputstyle = "remove"
function btn_stop.write()
    sys.call("/etc/init.d/sshtunnel stop 2>/dev/null")
end

return m
