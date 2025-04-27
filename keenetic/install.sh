#!/bin/sh

# Анимация ожидания выполнения команды
animation() {
	local pid=$1
	local message=$2
	local spin='-\|/'

	echo -n "$message... "

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

echo "Запуск установки репозитория..."
logger "Запуск установки репозитория..."

run_with_animation "Обновление списка пакетов" opkg update
logger "Обновление списка пакетов"
run_with_animation "Установка wget с поддержкой HTTPS" opkg install wget-ssl
logger "Установка wget с поддержкой HTTPS"
run_with_animation "Удаление wget без SSL" opkg remove wget-nossl
logger "Удаление wget без SSL"

echo "Определение архитектуры системы..."
logger "Определение архитектуры системы..."
ARCH=$(opkg print-architecture | awk '
  /^arch/ && $2 !~ /_kn$/ && $2 ~ /-[0-9]+\.[0-9]+$/ {
    print $2; exit
  }'
)

if [ -z "$ARCH" ]; then
  echo "Не удалось определить архитектуру."
  logger "Не удалось определить архитектуру."
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
    logger "Неподдерживаемая архитектура: $ARCH"
    exit 1
    ;;
esac

echo "Архитектура: $ARCH"
logger "Архитектура: $ARCH"
echo "Выбранный репозиторий: $FEED_URL"
logger "Выбранный репозиторий: $FEED_URL"

FEED_CONF="/opt/etc/opkg/hydraroute.conf"
FEED_LINE="src/gz HydraRoute $FEED_URL"

# Убедимся, что директория конфигурации opkg существует
if [ ! -d "/opt/etc/opkg" ]; then
  echo "Создание директории /opt/etc/opkg..."
  logger "Создание директории /opt/etc/opkg..."
  mkdir -p /opt/etc/opkg
fi

# Добавляем репозиторий, если он ещё не добавлен
if grep -q "$FEED_URL" "$FEED_CONF" 2>/dev/null; then
  echo "Репозиторий уже добавлен в $FEED_CONF. Пропускаем."
  logger "Репозиторий уже добавлен в $FEED_CONF. Пропускаем."
else
  echo "Добавление репозитория в $FEED_CONF..."
  logger "Добавление репозитория в $FEED_CONF..."
  echo "$FEED_LINE" >> "$FEED_CONF"
  logger "$FEED_LINE" >> "$FEED_CONF"
fi

run_with_animation "Обновление списка пакетов с новым репозиторием" opkg update
logger "Обновление списка пакетов с новым репозиторием"

# Подтверждение от пользователя
echo ""
echo "Установить один из пакетов из репозитория? (y/n):"
logger "Установить один из пакетов из репозитория? (y/n):"
read CONFIRM < /dev/tty

if [ "$CONFIRM" = "y" ] || [ "$CONFIRM" = "Y" ]; then
  echo ""
  echo "Доступные пакеты в репозитории:"
  opkg list | grep -E 'hydraroute|hrneo' || echo "Подходящих пакетов не найдено."

  echo ""
  echo "Введите имя пакета для установки ('hydraroute' или 'hrneo'):"
  read PACKAGE_NAME < /dev/tty
  

  case "$PACKAGE_NAME" in
    hydraroute|hrneo)
      run_with_animation "Установка пакета: $PACKAGE_NAME" opkg install "$PACKAGE_NAME"
      logger "Устанавливаем пакет: $PACKAGE_NAME"
      ;;
    *)
      echo "Неверное имя пакета. Установка пропущена."
      logger "Неверное имя пакета. Установка пропущена."
      ;;
  esac
else
  echo "Установка пакета отменена пользователем."
  logger "Установка пакета отменена пользователем."
fi

# Очистка — удаление скрипта
SCRIPT="$0"
if [ -f "$SCRIPT" ]; then
  echo "- Удаление установочного скрипта..."
  rm "$SCRIPT"
fi

echo "Установка завершена."
logger "Установка завершена"
