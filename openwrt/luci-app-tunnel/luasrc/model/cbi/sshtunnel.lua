-- SSH Tunnel Manager — LuCI CBI Model
local sys   = require "luci.sys"
local fs    = require "nixio.fs"
local http  = require "luci.http"

m = Map("sshtunnel", "SSH Tunnel Manager",
    "Управление обратными SSH-туннелями для удалённого доступа к домашней сети через VPS.")

-- ═══════════════════════════════════════════
-- Настройки подключения
-- ═══════════════════════════════════════════

s = m:section(NamedSection, "global", "sshtunnel", "Настройки подключения")
s.addremove = false
s.anonymous = false

en = s:option(Flag, "enabled", "Включить туннель")
en.rmempty = false

ip = s:option(Value, "vps_ip", "IP адрес VPS")
ip.datatype = "ipaddr"
ip.placeholder = "203.0.113.1"
ip.rmempty = false

pt = s:option(Value, "vps_port", "SSH порт VPS")
pt.datatype = "port"
pt.default = "22"
pt.placeholder = "22"

us = s:option(Value, "vps_user", "Пользователь туннеля")
us.default = "tunnel"
us.placeholder = "tunnel"

kp = s:option(Value, "key_path", "Путь к приватному ключу")
kp.default = "/root/.ssh/tunnel_key"
kp.placeholder = "/root/.ssh/tunnel_key"

ai = s:option(Value, "alive_interval", "ServerAliveInterval (сек)",
    "Как часто отправлять keepalive-пакеты")
ai.datatype = "uinteger"
ai.default = "30"

ac = s:option(Value, "alive_count", "ServerAliveCountMax",
    "Отключиться после стольких пропущенных keepalive")
ac.datatype = "uinteger"
ac.default = "3"

-- ═══════════════════════════════════════════
-- Приватный ключ
-- ═══════════════════════════════════════════

kd = s:option(DummyValue, "_key_status", "Статус ключа")
function kd.cfgvalue(self, section)
    local path = m:get("global", "key_path") or "/root/.ssh/tunnel_key"
    if fs.access(path) then
        local content = fs.readfile(path) or ""
        local first = content:match("^([^\n]+)")
        local last = content:match("([^\n]+)%s*$")
        if first and last then
            return first .. "\n...\n" .. last
        end
        return "Файл ключа существует: " .. path
    else
        return "Файл ключа не найден"
    end
end

ka = s:option(TextValue, "_key_paste", "Вставить новый ключ",
    "Вставьте приватный ключ и нажмите 'Сохранить ключ'. Кнопка 'Сохранить и применить' НЕ сохраняет ключ.")
ka.rows = 8
ka.wrap = "off"
ka.rmempty = true
ka.optional = true

function ka.cfgvalue(self, section)
    return ""
end

function ka.write(self, section, value)
    return
end

function ka.remove(self, section)
    return
end

ks = s:option(Button, "_save_key", "")
ks.inputtitle = "Сохранить ключ"
ks.inputstyle = "apply"

function ks.write(self, section)
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
        m.message = "Ключ успешно сохранён!"
    else
        m.message = "Ошибка: вставьте корректный приватный ключ (должен содержать BEGIN/END PRIVATE KEY)"
    end
end

kh = s:option(Button, "_scan_host", "")
kh.inputtitle = "Добавить VPS в known_hosts"
kh.inputstyle = "apply"

function kh.write(self, section)
    local vps_ip = m:get("global", "vps_ip") or ""
    local vps_port = m:get("global", "vps_port") or "22"
    if vps_ip ~= "" then
        sys.call("ssh-keyscan -t ed25519 -p " .. vps_port .. " " .. vps_ip .. " >> /root/.ssh/known_hosts 2>/dev/null")
        m.message = "VPS добавлен в known_hosts"
    end
end

-- ═══════════════════════════════════════════
-- Проброс портов
-- ═══════════════════════════════════════════

t = m:section(TypedSection, "tunnel", "Проброс портов",
    "Каждый туннель связывает порт VPS с устройством в домашней сети.")
t.addremove = true
t.anonymous = true
t.template = "cbi/tblsection"

te = t:option(Flag, "enabled", "Вкл")
te.default = "1"
te.rmempty = false

tn = t:option(Value, "name", "Название")
tn.placeholder = "RDP / SMB / Web..."
tn.rmempty = false

tr = t:option(Value, "remote_port", "Порт VPS")
tr.datatype = "port"
tr.placeholder = "3389"
tr.rmempty = false

tl = t:option(Value, "local_ip", "Локальный IP")
tl.datatype = "ipaddr"
tl.placeholder = "192.168.1.100"
tl.rmempty = false

tp = t:option(Value, "local_port", "Локальный порт")
tp.datatype = "port"
tp.placeholder = "3389"
tp.rmempty = false

-- ═══════════════════════════════════════════
-- Статус и управление
-- ═══════════════════════════════════════════

st = m:section(TypedSection, "sshtunnel", "Статус")
st.addremove = false
st.anonymous = true

stat = st:option(DummyValue, "_status", "Текущий статус")
function stat.cfgvalue()
    local code = sys.call("pgrep -f '/usr/sbin/autossh' >/dev/null 2>&1")
    if code == 0 then
        return "Работает"
    else
        local enabled = m:get("global", "enabled") or "0"
        if enabled == "1" then
            return "Остановлен (должен работать — проверьте логи)"
        else
            return "Остановлен"
        end
    end
end

btn_start = st:option(Button, "_start", "Запустить")
btn_start.inputtitle = "Старт"
btn_start.inputstyle = "apply"
function btn_start.write()
    sys.call("/etc/init.d/sshtunnel start 2>/dev/null")
end

btn_restart = st:option(Button, "_restart", "Перезапустить")
btn_restart.inputtitle = "Рестарт"
btn_restart.inputstyle = "apply"
function btn_restart.write()
    sys.call("/etc/init.d/sshtunnel restart 2>/dev/null")
end

btn_stop = st:option(Button, "_stop", "Остановить")
btn_stop.inputtitle = "Стоп"
btn_stop.inputstyle = "remove"
function btn_stop.write()
    sys.call("/etc/init.d/sshtunnel stop 2>/dev/null")
end

return m
