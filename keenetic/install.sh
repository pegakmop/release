#!/bin/sh
# curl -fsSL https://pegakmop.github.io/release/keenetic/install-feed.sh | sh

# === АНИМАЦИЯ ===
animation() {
    local pid=$1 message=$2 spin='|/-\\' i=0
    echo -n "[ ] $message..."
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) %4 ))
        printf "\r[%s] %s..." "${spin:$i:1}" "$message"
        usleep 100000
    done
    wait $pid
    if [ $? -eq 0 ]; then
        printf "\r[✔] %s\n" "$message"
    else
        printf "\r[✖] %s\n" "$message"
    fi
}

run_with_animation() {
    local msg="$1"
    shift
    ("$@") >/dev/null 2>&1 &
    animation $! "$msg"
}

echo "Запуск установки..."

ndmc -c "dns-proxy tls upstream 9.9.9.9 sni dns.quad9.net" >/dev/null 2>&1

run_with_animation "Обновление списка пакетов" opkg update
run_with_animation "Установка wget с поддержкой HTTPS" opkg install wget-ssl curl
run_with_animation "Удаление wget без SSL" opkg remove wget-nossl

# === Определение архитектуры ===
echo "Определение архитектуры системы..."
ARCH=$(opkg print-architecture | awk '/^arch/ && $2 !~ /_kn$/ && $2 ~ /-[0-9]+\.[0-9]+$/ {print $2; exit}')
if [ -z "$ARCH" ]; then echo "Не удалось определить архитектуру."; exit 1; fi

case "$ARCH" in
  aarch64-3.10) FEED_URL="https://pegakmop.github.io/release/keenetic/aarch64-k3.10" ;;
  mipsel-3.4)   FEED_URL="https://pegakmop.github.io/release/keenetic/mipselsf-k3.4" ;;
  mips-3.4)     FEED_URL="https://pegakmop.github.io/release/keenetic/mipssf-k3.4" ;;
  *) echo "Неподдерживаемая архитектура: $ARCH"; exit 1 ;;
esac

echo "Архитектура: $ARCH"
echo "Выбранный репозиторий: $FEED_URL"

FEED_CONF="/opt/etc/opkg/neofit.conf"
FEED_LINE="src/gz pegakmop $FEED_URL"

[ ! -d "/opt/etc/opkg" ] && mkdir -p /opt/etc/opkg

if ! grep -q "$FEED_URL" "$FEED_CONF" 2>/dev/null; then
  echo "$FEED_LINE" >> "$FEED_CONF"
else
  echo "Репозиторий уже добавлен в $FEED_CONF..."
fi

run_with_animation "Обновление списка пакетов..." opkg update

# === Выбор пакета пользователем ===
echo ""
echo "Установить/обновить пакет ('hydraroute' или 'hrneo')? (y/n):"
read -r CONFIRM < /dev/tty
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "Пропущено."; exit 0
fi

echo "Введите имя пакета:"
read -r PACKAGE < /dev/tty
if  [ "$PACKAGE" != "neofitxray" ] && [ "$PACKAGE" != "neofitsb" ] && [ "$PACKAGE" != "sing-box-go" ] && [ "$PACKAGE" != "hydraroute" ] && [ "$PACKAGE" != "hrneo" ]; then
    echo "Неверное имя пакета. Пример установки командой: opkg install neofitxray. Доступные пакеты: neofitxray, neofitsb, sing-box-go, hydraroute или hrneo."; exit 1
fi

run_with_animation "Установка/обновление $PACKAGE" sh -c "opkg install \"$PACKAGE\" >/dev/null 2>&1 || opkg upgrade \"$PACKAGE\" >/dev/null 2>&1"

# === Установка WebUI для hrneo ===
if [ "$PACKAGE" = "hrneo" ]; then
  echo ""
  echo "Установить Web-интерфейс для HRNeo? (y/n):"
  read -r WEBCONFIRM < /dev/tty
  if [ "$WEBCONFIRM" = "y" ] || [ "$WEBCONFIRM" = "Y" ]; then
    echo "Установка HRNeo WebUI"
    install_webui() {
        run_with_animation "Установка Lighttpd + PHP8" opkg install lighttpd lighttpd-mod-cgi lighttpd-mod-setenv lighttpd-mod-redirect lighttpd-mod-rewrite php8 php8-cgi php8-cli php8-mod-curl php8-mod-openssl php8-mod-session jq
        run_with_animation "Создание директорий" mkdir -p /opt/share/www/hrneo /opt/etc/lighttpd/conf.d
        run_with_animation "Создание manifest.json" sh -c 'cat > /opt/share/www/hrneo/manifest.json <<EOF
{
  "name": "HydraRoute Neo",
  "short_name": "hr neo",
  "start_url": "/",
  "display": "standalone",
  "background_color": "#1b2434",
  "theme_color": "#fff",
  "orientation": "any",
  "prefer_related_applications": false,
  "icons": [
    { "src": "180x180.png", "sizes": "180x180", "type": "image/png" }
  ]
}
EOF'
        run_with_animation "Создание index.php" sh -c 'cat > /opt/share/www/hrneo/index.php <<EOF
<?php
\$currentVersion = "0.0.0.0";
\$remoteVersionUrl = "https://raw.githubusercontent.com/pegakmop/hrneo/main/version.txt";
\$updateNotice = "";
\$message = "";
\$context = stream_context_create(["http" => ["timeout" => 3]]);
\$remoteContent = @file_get_contents(\$remoteVersionUrl, false, \$context);
if (\$_SERVER["REQUEST_METHOD"] === "POST" && isset(\$_POST["run_update"])) {
    shell_exec("curl -L -s \\"https://raw.githubusercontent.com/pegakmop/hrneo/refs/heads/main/hrneo-web.sh\\" > /tmp/hrneo-web.sh && sh /tmp/hrneo-web.sh");
    \$message = "✔ Обновление запущено. Перезагрузите страницу через пару секунд.";
}
if (\$remoteContent !== false) {
    \$lines = explode("\\n", \$remoteContent);
    foreach (\$lines as \$line) {
        \$parts = explode("=", trim(\$line), 2);
        if (count(\$parts) == 2) \$versionInfo[trim(\$parts[0])] = trim(\$parts[1]);
    }
    if (!empty(\$versionInfo["Version"]) && version_compare(\$versionInfo["Version"], \$currentVersion, ">")) {
        \$updateNotice = "<div class=\\"update-box\\"><h2>Доступно обновление: v" . htmlspecialchars(\$versionInfo["Version"]) . "</h2><p>" . nl2br(htmlspecialchars(\$versionInfo["Show"])) . "</p><form method=\\"post\\"><button type=\\"submit\\" name=\\"run_update\\">⬇️ Обновить сейчас</button></form></div>";
    } else {
        \$updateNotice = "<p class=\\"up-to-date\\">✅ Установлена последняя версия: v" . \$currentVersion . "</p>";
    }
} else {
    \$updateNotice = "<p class=\\"error\\">⚠️ Не удалось получить информацию об обновлении.</p>";
}
?>
<!DOCTYPE html><html lang=\\"ru\\"><head><meta charset=\\"UTF-8\\"><meta name=\\"viewport\\" content=\\"width=device-width, initial-scale=1.0\\"><title>HRNeo Обновление</title><style>body{background:#1e1e2f;color:#e0e0e0;font-family:\\"Segoe UI\\",sans-serif;display:flex;justify-content:center;align-items:center;min-height:100vh;margin:0;padding:1rem}.update-box{background:#292c42;padding:2rem;border-radius:10px;max-width:500px;width:100%;box-shadow:0 0 15px rgba(0,0,0,0.5);text-align:center}.update-box h2{color:#68b0ab;margin-bottom:1rem}.update-box p{margin-bottom:1.5rem;line-height:1.5}button{background:#68b0ab;color:#1e1e2f;border:none;padding:0.7rem 1.5rem;font-weight:bold;font-size:1rem;cursor:pointer;border-radius:5px}button:hover{background:#55958f}.up-to-date{text-align:center;font-size:1.1rem;color:#8aff8a}.error{text-align:center;font-size:1.1rem;color:#ff6c6c}.message{text-align:center;font-weight:bold;color:#ffd966;margin-bottom:1rem}</style></head><body><div class=\\"update-box\\"><?php if (\$message): ?><div class=\\"message\\"><?= htmlspecialchars(\$message) ?></div><?php endif; ?><?= \$updateNotice ?></div></body></html>
EOF'
        run_with_animation "Загрузка 180x180.png" curl -sL https://raw.githubusercontent.com/pegakmop/hrneo/refs/heads/main/opt/share/www/hrneo/180x180.png -o /opt/share/www/hrneo/180x180.png
        run_with_animation "Загрузка apple-touch-icon.png" curl -sL https://raw.githubusercontent.com/pegakmop/hrneo/refs/heads/main/opt/share/www/hrneo/apple-touch-icon.png -o /opt/share/www/hrneo/apple-touch-icon.png
        run_with_animation "Создание конфигурации Lighttpd" sh -c 'cat > /opt/etc/lighttpd/conf.d/80-hrneo.conf <<EOF
server.port := 8088
server.username := ""
server.groupname := ""

\$HTTP["host"] =~ "^(.+):8088$" {
    url.redirect = ( "^/hrneo/" => "http://%1:88" )
    url.redirect-code = 301
}

\$SERVER["socket"] == ":88" {
    server.document-root = "/opt/share/www/"
    server.modules += ( "mod_cgi" )
    cgi.assign = ( ".php" => "/opt/bin/php8-cgi" )
    setenv.set-environment = ( "PATH" => "/opt/bin:/usr/bin:/bin" )
    index-file.names = ( "index.php" )
    url.rewrite-once = ( "^/(.*)" => "/hrneo/$1" )
}
EOF'
        ln -sf /opt/etc/init.d/S80lighttpd /opt/bin/php
        /opt/etc/init.d/S80lighttpd restart
        echo ""
    }
    install_webui
  fi
fi

# === Финальный вывод ===
echo ""
echo "Установка завершена."
[ "$PACKAGE" = "neofitxray" ] && echo "Для управления neofitxray: nfxray (start/restart/stop)" && echo "🔗 Откройте в браузере: http://ip-роутера:96"
[ "$PACKAGE" = "neofitsb" ] && echo "Для управления neofitsb: nfsb (start/restart/stop)" && echo "🔗 Откройте в браузере: http://ip-роутера:94"
[ "$PACKAGE" = "hydraroute" ] && echo "Для управления классиком: hr (start/restart/stop)" && echo "🔗 Откройте в браузере: http://hr.net"
[ "$PACKAGE" = "hrneo" ] && echo "Для управления нео: neo (start/restart/stop)" && echo "🔗 Откройте в браузере: http://ip-роутера:88"
echo "Больше полезностей в боте: @entwarebot"
