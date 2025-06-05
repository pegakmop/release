#!/bin/sh
# curl -fsSL https://pegakmop.github.io/release/keenetic/install-feed.sh | sh
# Анимация ожидания выполнения команды
animation() {
	local pid=$1
	local message=$2
	local spin='-\|/'

	echo -n "$message... \n"

	while kill -0 $pid 2>/dev/null; do
		for i in $(seq 0 3); do
			echo -ne "\b${spin:$i:1}"
			usleep 100000  # 0.1 сек
		done
	done

	wait $pid
	if [ $? -eq 0 ]; then
		echo -e "\b✔ Готово!"
	else
		echo -e "\b✖ Ошибка!"
	fi
}

# Обёртка для запуска команды с анимацией
run_with_animation() {
	local message="$1"
	shift
	("$@") &
	animation $! "$message"
}

# Функция для получения списка доступных версий пакета
get_available_versions() {
	opkg list | grep -E 'hydraroute|hrneo' | awk '{print $1 " - " $2}' 
}

echo "Запуск установки..."

run_with_animation "Обновление списка пакетов" opkg update
run_with_animation "Установка wget с поддержкой HTTPS" opkg install wget-ssl
run_with_animation "Удаление wget без SSL" opkg remove wget-nossl 2>/dev/null

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
  echo "Репозиторий уже добавлен в $FEED_CONF..."
else
  echo "Добавление репозитория в $FEED_CONF..."
  echo "$FEED_LINE" >> "$FEED_CONF"
fi

run_with_animation "Обновление списка пакетов с новым добавленным репозиторием" opkg update

# Подтверждение от пользователя
echo ""
echo "Установить один из пакетов из репозитория? (y/n):"
read CONFIRM < /dev/tty

if [ "$CONFIRM" = "y" ] || [ "$CONFIRM" = "Y" ]; then
  echo ""
  run_with_animation "Чтение списка доступных пакетов" get_available_versions || echo "Подходящих пакетов не найдено."

  MAX_TRIES=1
  TRIES=0

  while [ $TRIES -lt $MAX_TRIES ]; do
    echo ""
    echo "Введите имя пакета для установки ('hydraroute' или 'hrneo', или 'n' для пропуска):"
    read PACKAGE_NAME < /dev/tty

    case "$PACKAGE_NAME" in
      hydraroute|hrneo)
        # Получаем доступные версии пакета
        VERSIONS=$(opkg list | grep "^$PACKAGE_NAME" | awk '{print $1 " - " $2}')
        if [ -z "$VERSIONS" ]; then
          echo "Не удалось найти доступные версии пакета."
          break
        fi
        
        echo "Доступные версии пакета $PACKAGE_NAME:"
        echo "$VERSIONS"
        echo ""
        echo "Введите номер версии для установки или нажмите Enter для установки последней версии:"
        read VERSION_CHOICE < /dev/tty

        # Если версия не указана, то выбираем последнюю
        if [ -z "$VERSION_CHOICE" ]; then
          VERSION_CHOICE=$(echo "$VERSIONS" | head -n 1 | awk '{print $1}')
        fi

        run_with_animation "Установка пакета: $VERSION_CHOICE\n" opkg install "$VERSION_CHOICE"
        break
        ;;
      n|N|no|No|NO)
        echo "Установка пакета отменена пользователем."
        break
        ;;
      "")
        echo "Установка пропущена."
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

ln -sf /opt/etc/init.d/S99hydraroute /opt/bin/hr

echo "Установка завершена. для управления классиком hr для управления нео neo"

# Очистка — удаление скрипта
SCRIPT="$0"
if [ -f "$SCRIPT" ]; then
  echo "- Удаление установочного скрипта..."
  rm "$SCRIPT"
fi

echo "Установка завершена."
