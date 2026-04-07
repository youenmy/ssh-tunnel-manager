# SSH Tunnel Manager

Комплект для быстрой настройки обратного SSH-туннеля между OpenWrt-роутером и VPS.

```
Вы (откуда угодно) → VPS:порт → SSH-туннель → OpenWrt → домашняя сеть
```

## Быстрая установка

### 1. VPS (Ubuntu)
```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_USER/ssh-tunnel-manager/main/vps/install.sh | sudo bash
```
Откройте `http://YOUR_VPS_IP:7575` → мастер настройки.

### 2. OpenWrt
```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_USER/ssh-tunnel-manager/main/openwrt/install.sh | sh
```
LuCI → **Сервисы → SSH Tunnel** → настройте и включите.

## Лицензия
MIT
