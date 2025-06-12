#!/bin/bash

# --- НАЧАЛО СКРИПТА ---

echo "Запуск скрипта установки/обновления Shadowsocks-rust..."
echo "------------------------------------------------------------"

# --- Переменные ---
SS_PORT=4232
SS_METHOD="chacha20-ietf-poly1305"
CONFIG_FILE="/etc/shadowsocks-rust/config.json"
BINARY_PATH="/usr/local/bin/ssserver"

# --- Функция оптимизации параметров ядра (sysctl) ---
optimize_sysctl() {
    echo
    echo "--- Шаг 4: Проверка и оптимизация параметров ядра ---"

    # Определение желаемых параметров ядра
    read -r -d '' DESIRED_SETTINGS << EOM
fs.file-max = 51200
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.netdev_max_backlog = 250000
net.core.somaxconn = 4096
net.core.default_qdisc = fq
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_tw_recycle = 0
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.ip_local_port_range = 10000 65000
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_max_tw_buckets = 65536
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mem = 25600 51200 102400
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_congestion_control = bbr
EOM

    MISMATCHED_SETTINGS=()
    echo "🔎 Проверяю системные параметры для оптимизации сети..."

    while IFS= read -r line; do
        if [[ -z "$line" ]]; then continue; fi

        param=$(echo "$line" | cut -d'=' -f1 | xargs)
        desired_value=$(echo "$line" | cut -d'=' -f2- | xargs)
        current_value=$(sysctl -n "$param" 2>/dev/null)
        
        current_value_normalized=$(echo "$current_value" | tr -s '[:space:]' ' ')
        desired_value_normalized=$(echo "$desired_value" | tr -s '[:space:]' ' ')

        if [ "$current_value_normalized" != "$desired_value_normalized" ]; then
            display_current=${current_value:-"[НЕ ЗАДАН]"}
            MISMATCHED_SETTINGS+=("$param|$display_current|$desired_value")
        fi
    done <<< "$DESIRED_SETTINGS"

    if [ ${#MISMATCHED_SETTINGS[@]} -gt 0 ]; then
        echo -e "\n❗️ Обнаружены расхождения или отсутствующие параметры:"
        printf "%-40s | %-30s | %-30s\n" "Параметр" "Текущее значение" "Желаемое значение"
        printf '%.s─' {1..105} && echo ""

        for item in "${MISMATCHED_SETTINGS[@]}"; do
            param=$(echo "$item" | cut -d'|' -f1)
            current=$(echo "$item" | cut -d'|' -f2)
            desired=$(echo "$item" | cut -d'|' -f3)
            printf "%-40s | %-30s | %-30s\n" "$param" "$current" "$desired"
        done

        echo ""
        read -p "Применить эти сетевые оптимизации? (y/n): " answer
        case $answer in
            [Yy]* )
                echo -e "\n⚙️  Применяю настройки..."
                for item in "${MISMATCHED_SETTINGS[@]}"; do
                    param=$(echo "$item" | cut -d'|' -f1)
                    desired=$(echo "$item" | cut -d'|' -f3)
                    # Скрипт должен запускаться от root, поэтому sudo не нужен
                    if sysctl -w "$param=$desired"; then
                        echo "  ✅ Успешно: $param"
                    else
                        echo "  ❌ Ошибка при установке: $param"
                    fi
                done
                echo -e "✨ Оптимизация ядра завершена."
                ;;
            * )
                echo -e "\n❌ Оптимизация пропущена пользователем."
                ;;
        esac
    else
        echo -e "\n✅ Параметры ядра уже оптимальны."
    fi
}

# --- Шаг 1: Определение типа операции и подготовка ---
echo
echo "--- Шаг 1: Подготовка системы ---"
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
echo
echo "--- Шаг 2: Установка бинарного файла Shadowsocks-rust ---"
LATEST_VERSION=$(curl -s "https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
DOWNLOAD_URL="https://github.com/shadowsocks/shadowsocks-rust/releases/download/${LATEST_VERSION}/shadowsocks-${LATEST_VERSION}.x86_64-unknown-linux-gnu.tar.xz"

echo "Скачивание и установка последней версии: ${LATEST_VERSION}..."
curl -L -f -o /tmp/shadowsocks.tar.xz ${DOWNLOAD_URL}
tar -xf /tmp/shadowsocks.tar.xz -C /usr/local/bin/ ssserver
rm /tmp/shadowsocks.tar.xz

# --- Шаг 3: Создание или перезапись конфигурации ---
echo
echo "--- Шаг 3: Создание конфигурационного файла ---"
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

# --- ВЫПОЛНЕНИЕ ОПТИМИЗАЦИИ ---
optimize_sysctl

# --- Шаг 5: Настройка и запуск сервиса ---
echo
echo "--- Шаг 5: Настройка системного сервиса и брандмауэра ---"
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

# --- Шаг 6: Вывод итоговой информации ---
echo
echo "=================================================="
echo "Операция успешно завершена!"
echo
echo "Данные для подключения (с новым паролем):"
echo "  Сервер (IP):      $(curl -s -4 ifconfig.me)"
echo "  Порт:             ${SS_PORT}"
echo "  Метод шифрования: ${SS_METHOD}"
echo "  Пароль:           ${SS_PASSWORD}"
echo
echo "Статус сервиса:"
systemctl status shadowsocks-server --no-pager
echo "=================================================="
