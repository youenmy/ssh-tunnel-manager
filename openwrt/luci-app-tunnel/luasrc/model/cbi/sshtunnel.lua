-- SSH Tunnel Manager — LuCI CBI Model (v2)
--
-- Changes in v2:
--   * Public-key display (no more manual ssh-keygen -y)
--   * "Test Connection" button — runs ssh -v without -R, output shown on the page
--   * Auto-backup of key on overwrite (to ${key_path}.backup)
--   * Validation of pasted key before writing (ssh-keygen -y)

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
ai.default = "15"

ac = s:option(Value, "alive_count", "ServerAliveCountMax",
    "Отключиться после стольких пропущенных keepalive")
ac.datatype = "uinteger"
ac.default = "3"

-- ═══════════════════════════════════════════
-- Приватный ключ
-- ═══════════════════════════════════════════

-- Status: validity check + public key display
kd = s:option(DummyValue, "_key_status", "Статус ключа")
kd.rawhtml = true
function kd.cfgvalue(self, section)
    local path = m:get("global", "key_path") or "/root/.ssh/tunnel_key"
    if not fs.access(path) then
        return "<span style='color:#e74c3c'>✗ Файл ключа не найден: " .. path .. "</span>"
    end
    -- Validate key by deriving public key
    local pubkey = sys.exec("ssh-keygen -y -f " .. path .. " 2>/dev/null"):gsub("^%s+", ""):gsub("%s+$", "")
    if pubkey == "" then
        return "<span style='color:#e74c3c'>✗ ФАЙЛ КЛЮЧА ПОВРЕЖДЁН — ssh-keygen -y не смог его прочесть. " ..
               "Сгенерируйте заново или восстановите из резервной копии (" .. path .. ".backup)</span>"
    end
    -- OK — show public key that must be in authorized_keys on VPS
    return "<span style='color:#27ae60'>✓ Ключ валиден</span><br>" ..
           "<small>Публичный ключ (вставьте в authorized_keys на VPS):</small>" ..
           "<textarea readonly rows='2' style='width:100%;font-family:monospace;font-size:12px' onclick='this.select()'>" ..
           luci.util.pcdata(pubkey) .. "</textarea>"
end

-- Paste new key (with validation + backup)
ka = s:option(TextValue, "_key_paste", "Вставить новый ключ",
    "Вставьте приватный ключ и нажмите «Сохранить ключ». Старый ключ сохранится в .backup. Кнопка «Сохранить и применить» НЕ сохраняет ключ.")
ka.rows = 8
ka.wrap = "off"
ka.rmempty = true
ka.optional = true

function ka.cfgvalue(self, section) return "" end
function ka.write(self, section, value) return end
function ka.remove(self, section) return end

ks = s:option(Button, "_save_key", "")
ks.inputtitle = "Сохранить ключ"
ks.inputstyle = "apply"

function ks.write(self, section)
    local val = http.formvalue("cbid.sshtunnel.global._key_paste") or ""
    val = val:gsub("\r\n", "\n"):gsub("^%s+", ""):gsub("%s+$", "")

    if not (val:match("PRIVATE KEY") and #val > 50) then
        m.message = "Ошибка: вставьте корректный приватный ключ (должен содержать BEGIN/END PRIVATE KEY)"
        return
    end

    local path = m:get("global", "key_path") or "/root/.ssh/tunnel_key"
    local dir = path:match("(.+)/[^/]+$")
    if dir then
        sys.call("mkdir -p " .. dir .. " && chmod 700 " .. dir)
    end

    -- Write to a temp file first, then validate with ssh-keygen -y
    local tmp_path = path .. ".new"
    fs.writefile(tmp_path, val .. "\n")
    sys.call("chmod 600 " .. tmp_path)
    local test = sys.exec("ssh-keygen -y -f " .. tmp_path .. " 2>&1")
    if not test:match("^ssh%-") then
        -- Key is invalid — delete temp and reject
        sys.call("rm -f " .. tmp_path)
        m.message = "Ошибка: ключ не прошёл проверку ssh-keygen -y. Возможно, при копировании строки склеились или обрезались.\n" .. test
        return
    end

    -- Key is valid — backup old one (if exists), then replace
    if fs.access(path) then
        sys.call("cp " .. path .. " " .. path .. ".backup")
    end
    sys.call("mv " .. tmp_path .. " " .. path)
    sys.call("chmod 600 " .. path)
    m.message = "Ключ успешно сохранён и проверен. Старый ключ сохранён как " .. path .. ".backup"
end

kh = s:option(Button, "_scan_host", "")
kh.inputtitle = "Добавить VPS в known_hosts"
kh.inputstyle = "apply"

function kh.write(self, section)
    local vps_ip = m:get("global", "vps_ip") or ""
    local vps_port = m:get("global", "vps_port") or "22"
    if vps_ip ~= "" then
        sys.call("mkdir -p /root/.ssh && chmod 700 /root/.ssh")
        sys.call("ssh-keyscan -t ed25519 -p " .. vps_port .. " " .. vps_ip .. " >> /root/.ssh/known_hosts 2>/dev/null")
        m.message = "VPS добавлен в known_hosts"
    else
        m.message = "Сначала заполните IP VPS"
    end
end

-- Test Connection button — runs ssh without -R forwards, just checks auth
kt = s:option(Button, "_test_conn", "")
kt.inputtitle = "Проверить подключение"
kt.inputstyle = "apply"

function kt.write(self, section)
    local key_path = m:get("global", "key_path") or "/root/.ssh/tunnel_key"
    local vps_ip = m:get("global", "vps_ip") or ""
    local vps_port = m:get("global", "vps_port") or "22"
    local vps_user = m:get("global", "vps_user") or "tunnel"

    if vps_ip == "" then
        m.message = "Сначала заполните IP VPS"
        return
    end
    if not fs.access(key_path) then
        m.message = "Ключ не найден: " .. key_path
        return
    end

    -- Run ssh with -v, no forwards, just auth test
    local cmd = string.format(
        "timeout 12 ssh -v -i %s -p %s " ..
        "-o BatchMode=yes -o ConnectTimeout=10 " ..
        "-o StrictHostKeyChecking=accept-new " ..
        "-o PreferredAuthentications=publickey " ..
        "%s@%s -N -o ServerAliveInterval=0 2>&1 | head -50",
        key_path, vps_port, vps_user, vps_ip
    )
    -- Note: without -f, ssh -N will hang; use a tiny trick — send background then kill
    -- Actually, simpler: use `ssh ... true` instead of -N
    cmd = string.format(
        "timeout 12 ssh -v -i %s -p %s " ..
        "-o BatchMode=yes -o ConnectTimeout=10 " ..
        "-o StrictHostKeyChecking=accept-new " ..
        "-o PreferredAuthentications=publickey " ..
        "%s@%s true 2>&1",
        key_path, vps_port, vps_user, vps_ip
    )
    local output = sys.exec(cmd)

    -- Classify result
    local verdict
    if output:match("debug1: Authentication succeeded") or output:match("debug1: Exit status 0") then
        verdict = "✓ УСПЕХ: аутентификация прошла, VPS отвечает."
    elseif output:match("Permission denied") then
        verdict = "✗ Permission denied — публичный ключ НЕ прописан в authorized_keys на VPS, или там прописан другой ключ.\n" ..
                  "Публичный ключ этого роутера нужно скопировать на VPS (см. поле «Статус ключа» выше)."
    elseif output:match("Connection refused") then
        verdict = "✗ Connection refused — на указанном порту VPS не слушает sshd."
    elseif output:match("Connection timed out") or output:match("No route to host") then
        verdict = "✗ Нет сети до VPS (timeout / no route). Проверьте IP и что роутер имеет доступ в интернет."
    elseif output:match("Host key verification failed") then
        verdict = "✗ Host key verification failed. Нажмите «Добавить VPS в known_hosts» выше."
    elseif output:match("error in libcrypto") then
        verdict = "✗ Ключ повреждён (libcrypto не смог его прочитать). Пересоздайте ключ."
    else
        verdict = "⚠ Неожиданный результат. Полный вывод ниже."
    end

    -- Trim output
    local short = output
    if #short > 3000 then short = short:sub(1, 3000) .. "\n...(обрезано)" end

    m.message = "РЕЗУЛЬТАТ ПРОВЕРКИ\n" .. verdict .. "\n\n--- Полный вывод ssh -v ---\n" .. short
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
stat.rawhtml = true
function stat.cfgvalue()
    local code = sys.call("pgrep -f '/usr/sbin/autossh' >/dev/null 2>&1")
    if code == 0 then
        local pid = sys.exec("pgrep -f '/usr/sbin/autossh' | head -1"):gsub("%s+$", "")
        return "<span style='color:#27ae60'>● Работает</span> (PID " .. pid .. ")"
    else
        local enabled = m:get("global", "enabled") or "0"
        if enabled == "1" then
            return "<span style='color:#e74c3c'>○ Остановлен</span> — включён в настройках, но процесс не запущен. " ..
                   "Проверьте логи: <code>logread -e sshtunnel</code> или нажмите «Проверить подключение» выше."
        else
            return "<span style='color:#95a5a6'>○ Остановлен</span> (выключен в настройках)"
        end
    end
end

-- Live log tail
stlog = st:option(DummyValue, "_log", "Последние записи лога")
stlog.rawhtml = true
function stlog.cfgvalue()
    local log = sys.exec("logread -e sshtunnel -e autossh 2>/dev/null | tail -10")
    if log == "" or log == nil then log = "(нет записей)" end
    return "<pre style='max-height:200px;overflow:auto;font-size:11px;background:#1e1e1e;color:#ddd;padding:8px;border-radius:4px'>" ..
           luci.util.pcdata(log) .. "</pre>"
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
