#!/bin/sh
# curl -fsSL https://pegakmop.github.io/release/keenetic/install-feed.sh | sh

# Анимация ожидания выполнения команды
animation() {
	local pid=$1
	local message=$2
	local spin='-\|/'
	echo "$message..."
	while kill -0 $pid 2>/dev/null; do
		for i in $(seq 0 3); do
			echo -ne "\b${spin:$i:1}"
			usleep 100000
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

echo "Запуск установки..."
ndmc -c "dns-proxy tls upstream 9.9.9.9 sni dns.quad9.net" >/dev/null 2>&1
run_with_animation "Обновление списка пакетов" opkg update
run_with_animation "Установка wget с поддержкой HTTPS" opkg install wget-ssl curl
run_with_animation "Удаление wget без SSL" opkg remove wget-nossl

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

run_with_animation "Обновление списка пакетов с новым репозиторием" opkg update

# Подтверждение от пользователя
echo ""
echo "Установить или обновить один из пакетов ('hydraroute' или 'hrneo')? (y/n):"
read CONFIRM < /dev/tty

if [ "$CONFIRM" = "y" ] || [ "$CONFIRM" = "Y" ]; then
  echo ""
  echo "Введите имя пакета для установки/обновления:"
  read PACKAGE_NAME < /dev/tty

  case "$PACKAGE_NAME" in
    hydraroute|hrneo)
      if opkg status "$PACKAGE_NAME" >/dev/null 2>&1; then
        run_with_animation "Обновление пакета $PACKAGE_NAME" opkg upgrade "$PACKAGE_NAME"
      else
        run_with_animation "Установка пакета $PACKAGE_NAME" opkg install "$PACKAGE_NAME"
      fi

      # Если выбран hrneo — предложить установить Web-интерфейс
      if [ "$PACKAGE_NAME" = "hrneo" ]; then
        echo ""
        echo "Хотите установить веб-интерфейс для HRNeo? (y/n):"
        read INSTALL_WEBUI < /dev/tty

        if [ "$INSTALL_WEBUI" = "y" ] || [ "$INSTALL_WEBUI" = "Y" ]; then
          echo "Установка веб-интерфейса..."
          curl -L -s "https://raw.githubusercontent.com/pegakmop/hrneo/refs/heads/main/hrneo-web.sh" > /tmp/hrneo-web.sh
          sh /tmp/hrneo-web.sh
        else
          echo "Установка интерфейса пропущена."
        fi
      fi
      ;;
    *)
      echo "Неверное имя пакета или установка отменена."
      ;;
  esac
else
  echo "Установка пакета пропущена."
fi

# Символические ссылки для управления
ln -sf /opt/etc/init.d/S99hydraroute /opt/bin/hr
ln -sf /opt/etc/init.d/S99hrneo /opt/bin/neo

echo ""
echo "Установка завершена."
echo "Для управления классиком - hr (start/restart/stop)"
echo "Для управления нео      - neo (start/restart/stop)"
echo "Больше полезностей в боте @HydraRouteBot"

# Удаление установочного скрипта (если был сохранён локально)
if [ -f "$0" ]; then
  echo "- Удаление установочного скрипта..."
  rm -- "$0" 2>/dev/null
fi

echo "Готово."
