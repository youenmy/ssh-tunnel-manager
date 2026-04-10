# SSH Tunnel Manager

Комплект для быстрой настройки обратного SSH-туннеля между OpenWrt-роутером и VPS.
Позволяет получить доступ к устройствам домашней сети из любой точки мира через VPS с выделенным IP.

```
Вы (откуда угодно) → VPS:порт → SSH-туннель → OpenWrt → домашняя сеть
                                                         ├─ RDP (ПК)
                                                         ├─ SMB (ПК)
                                                         └─ Web (роутер)
```

## Состав

| Компонент | Описание |
|-----------|----------|
| `vps/` | Flask Web UI + установщик для Ubuntu VPS |
| `openwrt/` | LuCI-приложение + установщик для OpenWrt |

---

## Установка

### 1. VPS (Ubuntu)

```bash
curl -fsSL https://raw.githubusercontent.com/youenmy/ssh-tunnel-manager/main/vps/install.sh | sudo bash
```

После установки в терминале отобразятся логин и пароль для панели.
Откройте `http://YOUR_VPS_IP:7575` и пройдите мастер настройки:

1. Создание пользователя туннеля
2. Генерация SSH-ключа (скопируйте приватный ключ для роутера)
3. Настройка GatewayPorts
4. Добавление туннелей (произвольные порты)

Учётные данные панели сохраняются в `/opt/ssh-tunnel-manager/data/credentials`.
Смена пароля: `passwd stm-admin`

### 2. OpenWrt роутер

```bash
curl -fsSL https://raw.githubusercontent.com/youenmy/ssh-tunnel-manager/main/openwrt/install.sh | sh
```

Откройте LuCI → **Сервисы → SSH Tunnel**:

1. Введите IP и порт VPS
2. Вставьте приватный ключ (из шага 1)
3. Нажмите «Scan & Add» для known_hosts
4. Добавьте нужные туннели
5. Включите и сохраните

---

## Добавление нового проброса порта

⚠️ **Важно: всегда сначала VPS, потом роутер.** Если добавить туннель сначала на роутере — autossh упадёт и все текущие пробросы отвалятся.

### Порядок действий:

1. **VPS панель** → вкладка **Туннели** → заполните форму (имя, порт VPS, IP устройства в домашней сети, локальный порт) → **Добавить туннель**
   - Это автоматически обновит `authorized_keys` и разрешит новый порт

2. **VPS панель** → вкладка **Файрвол** → нажмите **Синхронизировать с туннелями**
   - Это откроет порт в UFW

3. **Роутер LuCI** → **Сервисы → SSH Tunnel** → таблица **Port Forwards** → **Add**
   - Заполните те же данные (имя, порт VPS, локальный IP, локальный порт)
   - Нажмите **Save & Apply**
   - Нажмите **Restart** в блоке Status

### Пример: проброс Proxmox

| Параметр | Значение |
|----------|----------|
| Имя | Proxmox |
| Порт VPS | 8006 |
| IP устройства | 192.168.1.100 |
| Локальный порт | 8006 |

После добавления Proxmox будет доступен по адресу `https://YOUR_VPS_IP:8006`.

### Удаление проброса

Удаляйте в **обратном порядке**: сначала на роутере (удалите туннель, Restart), потом на VPS (удалите туннель в панели).

---

## Первоначальная настройка ключей

Есть два способа настроить SSH-ключи:

**Способ А: Ключ генерируется на VPS (рекомендуется при первой установке)**
1. VPS панель → Настройка → шаг 2 → «Сгенерировать ключ»
2. Скопируйте приватный ключ
3. На роутере LuCI → вставьте ключ в поле → нажмите «Save Key»

**Способ Б: Ключ генерируется на роутере**
1. На роутере: `ssh-keygen -t ed25519 -f /root/.ssh/tunnel_key -N ""`
2. Скопируйте публичный ключ: `cat /root/.ssh/tunnel_key.pub`
3. VPS панель → Настройка → шаг 2б → вставьте публичный ключ → «Сохранить публичный ключ»

---

## Удаление

### Удаление с VPS

```bash
systemctl stop ssh-tunnel-manager
systemctl disable ssh-tunnel-manager
rm /etc/systemd/system/ssh-tunnel-manager.service
systemctl daemon-reload
rm -rf /opt/ssh-tunnel-manager
userdel stm-admin
ufw delete allow 7575/tcp
```

Опционально — удалить пользователя туннеля и его ключи:

```bash
userdel -r tunnel
```

### Удаление с OpenWrt

```bash
/etc/init.d/sshtunnel stop
/etc/init.d/sshtunnel disable
rm /etc/init.d/sshtunnel
rm /etc/config/sshtunnel
rm /usr/lib/lua/luci/controller/sshtunnel.lua
rm /usr/lib/lua/luci/model/cbi/sshtunnel.lua
rm -rf /tmp/luci-modulecache /tmp/luci-indexcache*
```

Опционально — удалить ключ и known_hosts:

```bash
rm /root/.ssh/tunnel_key
rm /root/.ssh/known_hosts
```

---

## Безопасность

- Панель защищена логином/паролем (системный пользователь `stm-admin`)
- Пользователь туннеля без shell (`/usr/sbin/nologin`)
- SSH-ключ ограничен: `command="/bin/false"`, `permitlisten` только для указанных портов
- Рекомендуется ограничить UFW по IP или использовать SSH/VLESS для доступа к портам
- Приватный ключ хранится только на роутере

## Требования

- **VPS:** Ubuntu 22.04+, Python 3.10+, UFW, OpenSSH
- **Router:** OpenWrt 23.x+ (opkg) или 25.x+ (apk), LuCI

## Лицензия

MIT
