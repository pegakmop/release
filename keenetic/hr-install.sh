#!/bin/sh
# curl -fsSL https://pegakmop.github.io/release/keenetic/install-feed.sh | sh

# Цвета
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Анимация
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

# Установка WebUI
install_webui() {
  HRNEO_DIR="/opt/share/www/hrneo"
  LIGHTTPD_CONF_DIR="/opt/etc/lighttpd/conf.d"
  LIGHTTPD_CONF_FILE="$LIGHTTPD_CONF_DIR/80-hrneo.conf"

  run_with_animation "Установка Lighttpd и PHP8" \
    opkg install lighttpd lighttpd-mod-cgi lighttpd-mod-setenv lighttpd-mod-redirect lighttpd-mod-rewrite \
    php8 php8-cgi php8-cli php8-mod-curl php8-mod-openssl php8-mod-session jq

  run_with_animation "Создание директорий" \
    mkdir -p "$HRNEO_DIR" "$LIGHTTPD_CONF_DIR"

  run_with_animation "Создание manifest.json" sh -c "cat > \"$HRNEO_DIR/manifest.json\" << 'EOF'
{
  \"name\": \"HydraRoute Neo\",
  \"short_name\": \"hr neo\",
  \"start_url\": \"/\",
  \"display\": \"standalone\",
  \"background_color\": \"#1b2434\",
  \"theme_color\": \"#fff\",
  \"orientation\": \"any\",
  \"prefer_related_applications\": false,
  \"icons\": [
    {
      \"src\": \"180x180.png\",
      \"sizes\": \"180x180\",
      \"type\": \"image/png\"
    },
    {
      \"src\": \"apple-touch-icon.png\",
      \"sizes\": \"180x180\",
      \"type\": \"image/png\"
    }
  ]
}
EOF"

  run_with_animation "Создание index.php" sh -c "cat > \"$HRNEO_DIR/index.php\" << 'EOF'
<?php
echo \"HRNeo WebUI работает\";
?>
EOF"

  run_with_animation "Загрузка 180x180.png" \
    curl -s -L -o "$HRNEO_DIR/180x180.png" "https://raw.githubusercontent.com/pegakmop/hrneo/refs/heads/main/opt/share/www/hrneo/180x180.png"

  run_with_animation "Загрузка apple-touch-icon.png" \
    curl -s -L -o "$HRNEO_DIR/apple-touch-icon.png" "https://raw.githubusercontent.com/pegakmop/hrneo/refs/heads/main/opt/share/www/hrneo/apple-touch-icon.png"

  run_with_animation "Создание конфигурации Lighttpd" sh -c "cat > \"$LIGHTTPD_CONF_FILE\" << 'EOF'
\$SERVER[\"socket\"] == \":88\" {
  server.document-root = \"/opt/share/www/\"
  server.modules += ( \"mod_cgi\" )
  cgi.assign = ( \".php\" => \"/opt/bin/php8-cgi\" )
  setenv.set-environment = ( \"PATH\" => \"/opt/bin:/usr/bin:/bin\" )
  index-file.names = ( \"index.php\" )
  url.rewrite-once = ( \"^/(.*)\" => \"/hrneo/\\\$1\" )
}
EOF"

  run_with_animation "Настройка Lighttpd" \
    sh -c "/opt/etc/init.d/S80lighttpd enable && /opt/etc/init.d/S80lighttpd restart"
}

# Основной код
echo "Запуск установки..."
ndmc -c "dns-proxy tls upstream 9.9.9.9 sni dns.quad9.net" >/dev/null 2>&1

run_with_animation "Обновление списка пакетов" opkg update
run_with_animation "Установка wget с поддержкой HTTPS" opkg install wget-ssl curl
run_with_animation "Удаление wget без SSL" opkg remove wget-nossl

echo "Определение архитектуры..."
ARCH=$(opkg print-architecture | awk '/^arch/ && $2 !~ /_kn$/ && $2 ~ /-[0-9]+\.[0-9]+$/ {print $2; exit}')
[ -z "$ARCH" ] && echo "Не удалось определить архитектуру." && exit 1

case "$ARCH" in
  aarch64-3.10) FEED_URL="https://ground-zerro.github.io/release/keenetic/aarch64-k3.10" ;;
  mipsel-3.4)  FEED_URL="https://ground-zerro.github.io/release/keenetic/mipselsf-k3.4" ;;
  mips-3.4)    FEED_URL="https://ground-zerro.github.io/release/keenetic/mipssf-k3.4" ;;
  *) echo "Неподдерживаемая архитектура: $ARCH"; exit 1 ;;
esac

echo "Архитектура: $ARCH"
echo "Репозиторий: $FEED_URL"

FEED_CONF="/opt/etc/opkg/hydraroute.conf"
FEED_LINE="src/gz HydraRoute $FEED_URL"
mkdir -p /opt/etc/opkg
grep -qxF "$FEED_LINE" "$FEED_CONF" 2>/dev/null || echo "$FEED_LINE" >> "$FEED_CONF"

run_with_animation "Обновление списка пакетов с новым репозиторием" opkg update

echo ""
echo "Установить/обновить пакет ('hydraroute' или 'hrneo')? (y/n):"
read CONFIRM < /dev/tty

PACKAGE_NAME=""

if [ "$CONFIRM" = "y" ] || [ "$CONFIRM" = "Y" ]; then
  echo ""
  echo "Введите имя пакета:"
  read PACKAGE_NAME < /dev/tty
  case "$PACKAGE_NAME" in
    hydraroute|hrneo)
      if opkg status "$PACKAGE_NAME" >/dev/null 2>&1; then
        run_with_animation "Обновление $PACKAGE_NAME" opkg upgrade "$PACKAGE_NAME"
      else
        run_with_animation "Установка $PACKAGE_NAME" opkg install "$PACKAGE_NAME"
      fi
      if [ "$PACKAGE_NAME" = "hrneo" ]; then
        echo ""
        echo "Установить Web-интерфейс для HRNeo? (y/n):"
        read INSTALL_WEBUI < /dev/tty
        if [ "$INSTALL_WEBUI" = "y" ] || [ "$INSTALL_WEBUI" = "Y" ]; then
          run_with_animation "Установка HRNeo WebUI" install_webui
          ROUTER_IP=$(ip addr show br0 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
          echo ""
          echo "🔗 Откройте в браузере: http://${ROUTER_IP:-192.168.1.1}:88"
        else
          echo "WebUI пропущен."
        fi
      fi
      ;;
    *)
      echo "Неверное имя — пропуск."
      PACKAGE_NAME=""
      ;;
  esac
else
  echo "Пропуск установки пакета."
fi

echo ""
echo -e "${GREEN}Установка завершена.${NC}"

if [ "$PACKAGE_NAME" = "hydraroute" ]; then
  ln -sf /opt/etc/init.d/S99hydraroute /opt/bin/hr
  echo "Управление классиком: hr (start/restart/stop)"
fi

if [ "$PACKAGE_NAME" = "hrneo" ]; then
  ln -sf /opt/etc/init.d/S99hrneo /opt/bin/hr
  echo "Управление нео:       hr (start/restart/stop)"
  echo "Управление нео:       neo (start/restart/stop)"
fi

echo "Больше полезностей — @HydraRouteBot"

[ -f "$0" ] && { echo "- Удаление скрипта..."; rm -- "$0" 2>/dev/null; }

echo -e "${GREEN}Готово.${NC}"
