#!/bin/sh

# Обёртка для запуска команды
run_with_message() {
    local message="$1"
    shift
    echo "$message"
    "$@"
}

# Функция для получения списка доступных версий пакета
get_available_versions() {
    opkg list | grep -E 'hydraroute|hrneo' | awk '{print $1 " - " $2}'
}

# Функция для проверки, установлен ли пакет, и получения его версии
get_installed_version() {
    local package=$1
    opkg list-installed | grep "^$package " | awk '{print $2}'
}

# Запуск установки пакета
install_package() {
    local package_name=$1
    run_with_message "Установка пакета: $package_name" opkg install "$package_name"
}

echo "Запуск установки..."

run_with_message "Обновление списка пакетов..." opkg update
run_with_message "Установка wget с поддержкой HTTPS..." opkg install wget-ssl
run_with_message "Удаление wget без SSL..." opkg remove wget-nossl

echo "Определение архитектуры системы..."
ARCH=$(opkg print-architecture | awk '
  /^arch/ && $2 !~ /_kn$/ && $2 ~ /-[0-9]+\.[0-9]+$/ {
    print $2; exit
  }'
)

if [ -z "$ARCH" ]; then
  echo "Не удалось определить архитектуру."
  exit 1
fi

case "$ARCH" in
  aarch64-3.10)
    FEED_URL="https://ground-zerro.github.io/release/keenetic/aarch64-k3.10"
    ;;
  mipsel-3.4)
    FEED_URL="https://ground-zerro.github.io/release/keenetic/mipselsf-k3.4"
    ;;
  mips-3.4)
    FEED_URL="https://ground-zerro.github.io/release/keenetic/mipssf-k3.4"
    ;;
  *)
    echo "Неподдерживаемая архитектура: $ARCH"
    exit 1
    ;;
esac

echo "Архитектура: $ARCH"
echo "Выбранный репозиторий: $FEED_URL"

FEED_CONF="/opt/etc/opkg/hydraroute.conf"
FEED_LINE="src/gz HydraRoute $FEED_URL"

# Убедимся, что директория конфигурации opkg существует
if [ ! -d "/opt/etc/opkg" ]; then
  echo "Создание директории /opt/etc/opkg..."
  mkdir -p /opt/etc/opkg
fi

# Добавляем репозиторий, если он ещё не добавлен
if grep -q "$FEED_URL" "$FEED_CONF" 2>/dev/null; then
  echo "Репозиторий уже добавлен в $FEED_CONF. Пропускаем."
else
  echo "Добавление репозитория в $FEED_CONF..."
  echo "$FEED_LINE" >> "$FEED_CONF"
fi

run_with_message "Обновление списка пакетов с новым репозиторием..." opkg update

# Подтверждение от пользователя
echo ""
echo "Установить один из пакетов из репозитория? (y / n или нажмите enter для пропуска установки пакета):"
read CONFIRM < /dev/tty

if [ "$CONFIRM" = "y" ] || [ "$CONFIRM" = "Y" ]; then
  echo ""
  
  # Получаем список доступных пакетов
  echo "Чтение списка доступных пакетов..."
  AVAILABLE_PACKAGES=$(get_available_versions)

  if [ -z "$AVAILABLE_PACKAGES" ]; then
    echo "Подходящих пакетов не найдено."
  else
    echo "$AVAILABLE_PACKAGES"
  fi

  MAX_TRIES=3
  TRIES=0

  while [ $TRIES -lt $MAX_TRIES ]; do
    echo ""
    echo "Введите имя пакета для установки ('hydraroute' или 'hrneo', ЛИБО 'n' или 'enter' для пропуска):"
    read PACKAGE_NAME < /dev/tty

    case "$PACKAGE_NAME" in
      hydraroute|hrneo)
        # Проверка, установлен ли пакет и вывод версии
        INSTALLED_VERSION=$(get_installed_version "$PACKAGE_NAME")
        if [ -n "$INSTALLED_VERSION" ]; then
          echo "$PACKAGE_NAME - $INSTALLED_VERSION уже установлен."
          echo "Хотите обновить его? (y/n):"
          read UPDATE < /dev/tty

          if [ "$UPDATE" = "y" ] || [ "$UPDATE" = "Y" ]; then
            # Обновляем пакет
            install_package "$PACKAGE_NAME"
          else
            echo "Установка пакета $PACKAGE_NAME пропущена."
          fi
        else
          # Установка пакета, если он не установлен
          install_package "$PACKAGE_NAME"
        fi
        break
        ;;
      n|N|no|No|NO|"" )
        echo "Установка пакета пропущена."
        break
        ;;
      *)
        echo "Неверное имя пакета. Попробуйте ещё раз."
        TRIES=$((TRIES + 1))
        ;;
    esac
  done

  if [ $TRIES -ge $MAX_TRIES ]; then
    echo "Превышено количество попыток. Установка пропущена."
  fi
else
  echo "Установка пакета пропущена."
fi

# Очистка — удаление скрипта
SCRIPT="$0"
if [ -f "$SCRIPT" ]; then
  echo "- Удаление установочного скрипта..."
  rm "$SCRIPT"
fi

echo "Установка завершена."
