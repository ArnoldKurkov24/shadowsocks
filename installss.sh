#!/bin/bash

# --- НАЧАЛО СКРИПТА ---

echo "Запуск скрипта установки/обновления Shadowsocks-rust..."
echo "------------------------------------------------------------"

# --- Переменные ---
SS_PORT=4232
SS_METHOD="chacha20-ietf-poly1305"
CONFIG_FILE="/etc/shadowsocks-rust/config.json"
BINARY_PATH="/usr/local/bin/ssserver"

# --- Шаг 1: Определение типа операции и подготовка ---
if [ -f "${BINARY_PATH}" ]; then
    echo "Обнаружена существующая установка. Выполняется обновление..."
else
    echo "Выполняется чистая установка Shadowsocks-rust..."
fi

# Установка зависимостей в тихом режиме
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null
apt-get install -y -qq curl xz-utils >/dev/null

# --- Шаг 2: Скачивание и установка последней версии ---
LATEST_VERSION=$(curl -s "https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
DOWNLOAD_URL="https://github.com/shadowsocks/shadowsocks-rust/releases/download/${LATEST_VERSION}/shadowsocks-${LATEST_VERSION}.x86_64-unknown-linux-gnu.tar.xz"

echo "Скачивание и установка последней версии: ${LATEST_VERSION}..."
curl -L -f -o /tmp/shadowsocks.tar.xz ${DOWNLOAD_URL}
tar -xf /tmp/shadowsocks.tar.xz -C /usr/local/bin/ ssserver
rm /tmp/shadowsocks.tar.xz

# --- Шаг 3: Создание или перезапись конфигурации ---
if [ -f "${CONFIG_FILE}" ]; then
    echo "Найден старый конфиг. Перезаписываем его и генерируем новый пароль..."
else
    echo "Создание нового конфигурационного файла..."
fi

mkdir -p /etc/shadowsocks-rust
SS_PASSWORD=$(head -c 32 /dev/urandom | base64) # Всегда генерируем новый пароль
cat > ${CONFIG_FILE} <<EOT
{
    "server": "0.0.0.0",
    "server_port": ${SS_PORT},
    "password": "${SS_PASSWORD}",
    "method": "${SS_METHOD}"
}
EOT

# --- Шаг 4: Настройка и запуск сервиса ---
echo "Настройка системного сервиса и брандмауэра..."
SERVICE_FILE="/etc/systemd/system/shadowsocks-server.service"
cat > ${SERVICE_FILE} <<EOT
[Unit]
Description=Shadowsocks-rust Server Service
After=network.target
[Service]
Type=simple
User=root
ExecStart=${BINARY_PATH} -c ${CONFIG_FILE}
Restart=on-failure
RestartSec=5s
[Install]
WantedBy=multi-user.target
EOT

if command -v ufw &> /dev/null; then ufw allow ${SS_PORT}/tcp >/dev/null; ufw allow ${SS_PORT}/udp >/dev/null; ufw reload >/dev/null; fi

# Перезапускаем сервис, чтобы применить все изменения
systemctl daemon-reload
systemctl enable shadowsocks-server >/dev/null 2>&1
systemctl restart shadowsocks-server
sleep 1

# --- Шаг 5: Вывод итоговой информации ---
echo
echo "=================================================="
echo "Операция успешно завершена!"
echo
echo "Данные для подключения (с новым паролем):"
echo "  Сервер (IP):       $(curl -s -4 ifconfig.me)"
echo "  Порт:              ${SS_PORT}"
echo "  Метод шифрования:  ${SS_METHOD}"
echo "  Пароль:            ${SS_PASSWORD}"
echo
echo "Статус сервиса:"
systemctl status shadowsocks-server --no-pager
echo "=================================================="
