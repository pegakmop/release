#!/bin/sh
# curl -fsSL https://pegakmop.github.io/release/keenetic/install-feed.sh | sh

# Цвета
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # Сброс цвета

# Анимация с выводом в реальном времени
run_with_animation() {
	local message="$1"
	shift
	local logfile="/tmp/cmd.log.$$"
	local spin='-\|/'
	local i=0

	echo "$message"

	("$@" >"$logfile" 2>&1) &
	local pid=$!

	tail -n +1 -f "$logfile" &
	local tailpid=$!

	while kill -0 $pid 2>/dev/null; do
		printf "\r[%c] " "${spin:$i:1}"
		i=$(( (i + 1) % 4 ))
		usleep 100000
	done

	wait $pid
	local status=$?
	kill $tailpid 2>/dev/null
	wait $tailpid 2>/dev/null
	rm -f "$logfile"

	if [ $status -eq 0 ]; then
		echo -e "\r${GREEN}✔ Готово!${NC}"
	else
		echo -e "\r${RED}✖ Ошибка!${NC}"
	fi
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

if [ ! -d "/opt/etc/opkg" ]; then
  echo "Создание директории /opt/etc/opkg..."
  mkdir -p /opt/etc/opkg
fi

if grep -q "$FEED_URL" "$FEED_CONF" 2>/dev/null; then
  echo "Репозиторий уже добавлен в $FEED_CONF..."
else
  echo "Добавление репозитория в $FEED_CONF..."
  echo "$FEED_LINE" >> "$FEED_CONF"
fi

run_with_animation "Обновление списка пакетов с новым репозиторием" opkg update

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

      if [ "$PACKAGE_NAME" = "hrneo" ]; then
        echo ""
        echo "Хотите установить веб-интерфейс для HRNeo? (y/n):"
        read INSTALL_WEBUI < /dev/tty

        if [ "$INSTALL_WEBUI" = "y" ] || [ "$INSTALL_WEBUI" = "Y" ]; then
          echo "Установка веб-интерфейса..."
          curl -L -s "https://raw.githubusercontent.com/pegakmop/hrneo/refs/heads/main/hrneo-web.sh" > /tmp/hrneo-web.sh
          sh /tmp/hrneo-web.sh

          # Автоопределение IP роутера
          ROUTER_IP=$(ip addr show br0 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
          echo ""
          echo "🔗 Откройте в браузере: http://${ROUTER_IP:-192.168.1.1}:88"
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

ln -sf /opt/etc/init.d/S99hydraroute /opt/bin/hr
ln -sf /opt/etc/init.d/S99hrneo /opt/bin/neo

echo ""
echo -e "${GREEN}Установка завершена.${NC}"
echo "Для управления классиком - hr (start/restart/stop)"
echo "Для управления нео      - neo (start/restart/stop)"
echo "Больше полезностей в боте @HydraRouteBot"

if [ -f "$0" ]; then
  echo "- Удаление установочного скрипта..."
  rm -- "$0" 2>/dev/null
fi

echo -e "${GREEN}Готово.${NC}"
