#!/bin/bash

# Проверка на запуск от имени суперпользователя
if [ "$(id -u)" -ne 0 ]; then
  echo "Пожалуйста, запустите этот скрипт с правами суперпользователя (sudo)." >&2
  exit 1
fi

# Переменные
SS_PORT=4232
SS_METHOD="2022-blake3-aes-256-gcm"
SS_PASSWORD=$(head -c 16 /dev/urandom | base64)
CONFIG_FILE="/etc/shadowsocks-rust/config.json"
SERVICE_FILE="/etc/systemd/system/shadowsocks-server.service"

echo "Начинается установка сервера Shadowsocks-rust..."

# Установка необходимых пакетов
apt-get update
apt-get install -y curl xz-utils

# Определение последней версии и URL для скачивания
LATEST_VERSION=$(curl -s "https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
DOWNLOAD_URL="https://github.com/shadowsocks/shadowsocks-rust/releases/download/${LATEST_VERSION}/shadowsocks-${LATEST_VERSION}.x86_64-unknown-linux-gnu.tar.xz"

# Скачивание и распаковка
echo "Скачивание Shadowsocks-rust версии ${LATEST_VERSION}..."
curl -L -o /tmp/shadowsocks.tar.xz ${DOWNLOAD_URL}
echo "Распаковка архива..."
tar -xf /tmp/shadowsocks.tar.xz -C /usr/local/bin/ ssserver
rm /tmp/shadowsocks.tar.xz

# Создание каталога для конфигурации
mkdir -p /etc/shadowsocks-rust

# Создание конфигурационного файла
echo "Создание конфигурационного файла..."
cat > ${CONFIG_FILE} <<EOF
{
    "server": "0.0.0.0",
    "server_port": ${SS_PORT},
    "password": "${SS_PASSWORD}",
    "method": "${SS_METHOD}"
}
EOF

# Настройка брандмауэра
echo "Настройка брандмауэра (ufw)..."
ufw allow ${SS_PORT}/tcp
ufw allow ${SS_PORT}/udp
ufw reload

# Создание systemd юнита
echo "Создание systemd сервиса..."
cat > ${SERVICE_FILE} <<EOF
[Unit]
Description=Shadowsocks-rust Server Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/ssserver -c ${CONFIG_FILE}
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# Перезагрузка systemd и запуск сервиса
echo "Запуск сервиса Shadowsocks..."
systemctl daemon-reload
systemctl enable --now shadowsocks-server

# Вывод информации для подключения
echo "--------------------------------------------------"
echo "Установка Shadowsocks-rust завершена!"
echo
echo "Ваши данные для подключения:"
echo "  Сервер (IP): $(curl -s ifconfig.me)"
echo "  Порт: ${SS_PORT}"
echo "  Пароль: ${SS_PASSWORD}"
echo "  Метод шифрования: ${SS_METHOD}"
echo
echo "Статус сервиса:"
systemctl status shadowsocks-server --no-pager
echo "--------------------------------------------------"
