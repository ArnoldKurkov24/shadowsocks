# ====================================================================================
# PowerShell-скрипт v3.4 для автоматической установки shadowsocks-rust
# с использованием нативной службы Windows (sswinservice.exe).
#
# Версия: 3.4 (Дата: 13.06.2025) - Добавлен интерактивный запрос IP и пароля.
# ====================================================================================

# --- Начало: Проверка прав Администратора ---
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "Этот скрипт требует прав Администратора для установки в Program Files и создания службы Windows."
    Write-Warning "Пожалуйста, перезапустите PowerShell от имени Администратора и выполните скрипт снова."
    Read-Host "Нажмите Enter для выхода."
    exit
}
# --- Конец: Проверка прав Администратора ---

function Install-And-Run-Shadowsocks {
    <#
    .SYNOPSIS
        Выполняет полную чистую установку shadowsocks-rust в виде службы Windows.
    .DESCRIPTION
        Скрипт сначала проверяет и полностью удаляет любую предыдущую установку,
        а затем разворачивает последнюю версию с нуля, запрашивая данные для подключения.
    .PARAMETER ServerIP
        IP-адрес или доменное имя вашего Shadowsocks-сервера.
    .PARAMETER Password
        Пароль для подключения к серверу.
    .EXAMPLE
        Install-And-Run-Shadowsocks -ServerIP "your_server_ip" -Password "your_password"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ServerIP,

        [Parameter(Mandatory=$true)]
        [string]$Password
    )

    # --- Шаг 1: Определение переменных ---
    $installPath = "C:\Program Files\Shadowsocks-Rust"
    $method = "chacha20-ietf-poly1305"
    $port = 4232
    $serviceName = "ShadowsocksRust"

    Write-Host "--- Начало установки службы Shadowsocks-Rust ---" -ForegroundColor Yellow

    # --- Шаг 1.5: Проверка и полная очистка предыдущей установки ---
    Write-Host "Проверка на наличие предыдущих установок..."
    $oldService = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($oldService -or (Test-Path -Path $installPath)) {
        Write-Host "Обнаружена предыдущая установка. Выполняется полная очистка..." -ForegroundColor Magenta
        try {
            if ($oldService) {
                Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
                $oldSswinserviceExe = Join-Path $installPath "sswinservice.exe"
                if (Test-Path -Path $oldSswinserviceExe) {
                    & $oldSswinserviceExe uninstall
                    Write-Host "[OK] Служба '$serviceName' удалена." -ForegroundColor Green
                }
            }
            if (Test-Path -Path $installPath) {
                Start-Sleep -Seconds 3
                Remove-Item -Path $installPath -Recurse -Force
                Write-Host "[OK] Директория '$installPath' удалена." -ForegroundColor Green
            }
            Write-Host "[OK] Предыдущая установка полностью очищена." -ForegroundColor Cyan
        }
        catch {
            Write-Error "Во время очистки произошла ошибка: $($_.Exception.Message)"
            Write-Warning "Возможно, потребуется удалить папку '$installPath' вручную."
            return
        }
    } else {
        Write-Host "Предыдущих установок не обнаружено. Продолжаем..." -ForegroundColor Green
    }


    # --- Шаг 2: Создание директории для установки ---
    try {
        New-Item -Path $installPath -ItemType Directory -Force | Out-Null
        Write-Host "[OK] Создана директория для установки: $installPath" -ForegroundColor Green
    }
    catch {
        Write-Error "Не удалось создать директорию: $($_.Exception.Message)"
        return
    }

    # --- Шаг 3: Скачивание и распаковка компонентов ---
    try {
        Write-Host "Загрузка последней версии shadowsocks-rust (msvc)..."
        $ssReleaseUrl = "https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest"
        $ssReleaseInfo = Invoke-RestMethod -Uri $ssReleaseUrl
        $ssDownloadUrl = ($ssReleaseInfo.assets | Where-Object { $_.name -like "*x86_64-pc-windows-msvc.zip" }).browser_download_url
        $ssZipPath = Join-Path $env:TEMP "shadowsocks-rust-msvc.zip"
        Invoke-WebRequest -Uri $ssDownloadUrl -OutFile $ssZipPath
        Expand-Archive -Path $ssZipPath -DestinationPath $installPath -Force
        Write-Host "[OK] Shadowsocks-Rust (msvc) скачан и распакован." -ForegroundColor Green

        Write-Host "Загрузка драйвера Wintun..."
        $wintunUrl = "https://www.wintun.net/builds/wintun-0.14.1.zip"
        $wintunZipPath = Join-Path $env:TEMP "wintun.zip"
        Invoke-WebRequest -Uri $wintunUrl -OutFile $wintunZipPath
        $wintunExtractPath = Join-Path $env:TEMP "wintun_extracted"
        Expand-Archive -Path $wintunZipPath -DestinationPath $wintunExtractPath -Force
        Copy-Item -Path (Join-Path $wintunExtractPath "wintun\bin\amd64\wintun.dll") -Destination $installPath
        Write-Host "[OK] Wintun.dll скачан и размещен." -ForegroundColor Green

        Write-Host "Загрузка баз GeoIP и GeoSite..."
        $geoipUrl = "https://github.com/v2fly/geoip/releases/latest/download/geoip.dat"
        $geositeUrl = "https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat"
        Invoke-WebRequest -Uri $geoipUrl -OutFile (Join-Path $installPath "geoip.dat")
        Invoke-WebRequest -Uri $geositeUrl -OutFile (Join-Path $installPath "geosite.dat")
        Write-Host "[OK] Базы данных для ACL успешно загружены." -ForegroundColor Green
    }
    catch {
        Write-Error "Ошибка во время скачивания или распаковки: $($_.Exception.Message)"
        return
    }

    # --- Шаг 4: Создание конфигурационных файлов ---
    try {
        $configJsonContent = @"
{
    "server": "$ServerIP",
    "server_port": $port,
    "password": "$Password",
    "method": "$method",
    "local_address": "127.0.0.1",
    "local_port": 1080,
    "protocol": "tun",
    "tun_interface_name": "ShadowTunnel",
    "acl": "acl.conf",
    "dns": "1.1.1.1"
}
"@
        $configJsonContent | Out-File -FilePath (Join-Path $installPath "config.json") -Encoding utf8

        $aclConfContent = @"
[bypass]
127.0.0.0/8
10.0.0.0/8
172.16.0.0/12
192.168.0.0/16
169.254.0.0/16
::1/128
fc00::/7
fe80::/10
geosite:ru
geoip:ru
"@
        $aclConfContent | Out-File -FilePath (Join-Path $installPath "acl.conf") -Encoding utf8
        Write-Host "[OK] Конфигурационные файлы созданы." -ForegroundColor Green
    }
    catch {
        Write-Error "Ошибка при создании конфигурационных файлов: $($_.Exception.Message)"
        return
    }

    # --- Шаг 5: Установка и запуск нативной службы Windows ---
    try {
        Write-Host "Установка нативной службы Windows..."
        $sswinserviceExe = Join-Path $installPath "sswinservice.exe"
        Push-Location -Path $installPath
        & $sswinserviceExe install -c "config.json"
        Write-Host "[OK] Служба '$serviceName' успешно установлена." -ForegroundColor Green
        Start-Service -Name $serviceName
        Write-Host "[OK] Служба '$serviceName' запущена." -ForegroundColor Green
        Pop-Location
    }
    catch {
        Write-Error "Ошибка при установке службы Windows: $($_.Exception.Message)"
        Pop-Location
        return
    }

    Write-Host "--- Установка и настройка службы Shadowsocks-Rust успешно завершены! ---" -ForegroundColor Yellow
    Write-Host "Клиент установлен и запущен как нативная служба Windows."
}

# ====================================================================================
# --- Интерактивный вызов основной функции ---
# ====================================================================================

try {
    Write-Host "`nПожалуйста, введите данные для подключения:" -ForegroundColor Cyan
    $input_ServerIP = Read-Host "Введите IP-адрес или домен сервера"
    
    # Пароль запрашивается в защищенном виде, на экране не отображается
    $input_Password_Secure = Read-Host "Введите пароль" -AsSecureString

    # Конвертация SecureString в обычный текст для передачи в функцию
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($input_Password_Secure)
    $input_Password_PlainText = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    # Обязательная очистка памяти после конвертации
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)

    # Проверка, что пользователь ввел данные
    if ([string]::IsNullOrWhiteSpace($input_ServerIP) -or [string]::IsNullOrWhiteSpace($input_Password_PlainText)) {
        throw "IP-адрес и пароль не могут быть пустыми."
    }

    # Вызов основной функции с введенными данными
    Install-And-Run-Shadowsocks -ServerIP $input_ServerIP -Password $input_Password_PlainText
}
catch {
    Write-Error "Установка прервана: $($_.Exception.Message)"
}
finally {
    Read-Host "Нажмите Enter для завершения."
}
