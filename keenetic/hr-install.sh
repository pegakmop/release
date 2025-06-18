#!/bin/sh
# curl -fsSL ... | sh

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

run_with_animation() {
  msg="$1"; shift
  logfile="/tmp/cmd.$$.log"
  spin='-\|/'; i=0

  echo "$msg"
  ("$@" >"$logfile" 2>&1) &
  pid=$!
  tail -n +1 -f "$logfile" &
  tpid=$!

  while kill -0 $pid 2>/dev/null; do
    printf "\r[%c] " "${spin:$((i++%4)):1}"
    usleep 100000
  done

  wait $pid; st=$?
  kill $tpid 2>/dev/null
  rm -f "$logfile"

  if [ $st -eq 0 ]; then
    echo -e "\r${GREEN}✔ Готово!${NC}"
  else
    echo -e "\r${RED}✖ Ошибка!${NC}"
  fi
}

install_webui() {
  HR="/opt/share/www/hrneo"
  CF="/opt/etc/lighttpd/conf.d/80-hrneo.conf"

  run_with_animation "Установка Lighttpd/PHP8" \
    opkg install lighttpd lighttpd-mod-cgi lighttpd-mod-setenv lighttpd-mod-redirect lighttpd-mod-rewrite \
    php8 php8-cgi php8-cli php8-mod-curl php8-mod-openssl php8-mod-session jq

  run_with_animation "Создание директорий" mkdir -p "$HR" "$(dirname "$CF")"

  run_with_animation "Запись manifest.json" sh -c "cat >\"$HR/manifest.json\" << 'EOF'
{ "name":"HydraRoute Neo","short_name":"hr neo","start_url":"/","display":"standalone",
  "background_color":"#1b2434","theme_color":"#fff","orientation":"any",
  "prefer_related_applications":false,"icons":[
    {"src":"180x180.png","sizes":"180x180","type":"image/png"},
    {"src":"apple-touch-icon.png","sizes":"180x180","type":"image/png"} ]}
EOF"

  run_with_animation "Запись index.php" sh -c "cat >\"$HR/index.php\" << 'EOF'
<?php
\$currentVersion='0.0.0.1'; \$remoteVersionUrl='https://raw.githubusercontent.com/pegakmop/hrneo/main/version.txt';
\$message=''; \$notice='';
\$ctx=stream_context_create(['http'=>['timeout'=>3]]);
\$rc=@file_get_contents(\$remoteVersionUrl,false,\$ctx);
if(\$_SERVER['REQUEST_METHOD']=='POST'&&isset(\$_POST['run_update'])){
  shell_exec('curl -L -s \"https://raw.githubusercontent.com/pegakmop/hrneo/refs/heads/main/hrneo-web.sh\" >/tmp/hrneo-web.sh && sh /tmp/hrneo-web.sh');
  \$message='✔ Обновление запущено. Перезагрузите страницу через пару секунд.';
}
if(\$rc!==false){
  \$v=[];foreach(explode(\"\\n\",\$rc)as\$l){
    \$p=explode('=',trim(\$l),2);
    if(count(\$p)==2)\$v[trim(\$p[0])]=trim(\$p[1]);
  }
  if(!empty(\$v['Version'])&&version_compare(\$v['Version'],\$currentVersion,'>')){
    \$notice='<div class=\"update-box\"><h2>Доступно обновление: v'.htmlspecialchars(\$v['Version']).'</h2><p>'.nl2br(htmlspecialchars(\$v['Show'])).'</p><form method=\"post\"><button name=\"run_update\">⬇️ Обновить</button></form></div>';
  } else {
    \$notice='<p class=\"up-to-date\">✅ Последняя версия: v'.\$currentVersion.'</p>';
  }
} else {
  \$notice='<p class=\"error\">⚠️ Не удалось загрузить инфу об обновлении.</p>';
}
?>
<!DOCTYPE html><html lang="ru"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0"><title>HRNeo Обновление</title>
<style>
body{background:#1e1e2f;color:#e0e0e0;font-family:Segoe UI,sans-serif;display:flex;justify-content:center;align-items:center;min-height:100vh;margin:0;padding:1rem;}
.update-box{background:#292c42;padding:2rem;border-radius:10px;max-width:500px;box-shadow:0 0 15px rgba(0,0,0,0.5);text-align:center;}
.update-box h2{color:#68b0ab;margin-bottom:1rem;}
.update-box p{margin-bottom:1.5rem;line-height:1.5;}
button{background:#68b0ab;color:#1e1e2f;border:none;padding:0.7rem 1.5rem;font-weight:bold;font-size:1rem;cursor:pointer;border-radius:5px;}
button:hover{background:#55958f;}
.up-to-date{text-align:center;font-size:1.1rem;color:#8aff8a;}
.error{text-align:center;font-size:1.1rem;color:#ff6c6c;}
.message{text-align:center;font-weight:bold;color:#ffd966;margin-bottom:1rem;}
</style></head><body><div class="update-box"><?php if(\$message):?><div class="message"><?=htmlspecialchars(\$message)?></div><?php endif;?><?=\$notice?></div></body></html>
EOF"

  run_with_animation "Загрузка иконки 180x180.png" \
    curl -s -L -o "$HR/180x180.png" "https://raw.githubusercontent.com/pegakmop/hrneo/refs/heads/main/opt/share/www/hrneo/180x180.png"

  run_with_animation "Загрузка apple-touch-icon.png" \
    curl -s -L -o "$HR/apple-touch-icon.png" "https://raw.githubusercontent.com/pegakmop/hrneo/refs/heads/main/opt/share/www/hrneo/apple-touch-icon.png"

  run_with_animation "Настройка Lighttpd" sh -c "cat >\"$CF\" << 'EOF'
\$SERVER[\"socket\"]==\":88\"{
  server.document-root=\"/opt/share/www/\";
  server.modules+=(\"mod_cgi\");
  cgi.assign=(\".php\"=>\"/opt/bin/php8-cgi\");
  setenv.set-environment=(\"PATH\"=>\"/opt/bin:/usr/bin:/bin\");
  index-file.names=(\"index.php\");
}
EOF" && /opt/etc/init.d/S80lighttpd enable && /opt/etc/init.d/S80lighttpd restart
}

# Основной
PACKAGE=""

echo "Запуск установки…"
ndmc -c "dns-proxy tls upstream 9.9.9.9 sni dns.quad9.net" >/dev/null 2>&1

run_with_animation "Обновление списка пакетов" opkg update
run_with_animation "Установка wget/curl" opkg install wget-ssl curl
run_with_animation "Удаление wget без SSL" opkg remove wget-nossl

ARCH=$(opkg print-architecture|awk '/^arch/&&$2!~/_kn$/&&$2~/-[0-9]+\.[0-9]+$/{print $2;exit}')
[ -z "$ARCH" ] && echo "❌ Не удалось определить архитектуру." && exit 1

case "$ARCH" in
  aarch64-3.10) F="https://ground-zerro.github.io/release/keenetic/aarch64-k3.10";;
  mipsel-3.4)  F="https://ground-zerro.github.io/release/keenetic/mipselsf-k3.4";;
  mips-3.4)    F="https://ground-zerro.github.io/release/keenetic/mipssf-k3.4";;
  *) echo "❌ Архитектура $ARCH не поддерживается."; exit 1;;
esac

echo "Архитектура: $ARCH"
mkdir -p /opt/etc/opkg
grep -qxF "src/gz HydraRoute $F" /opt/etc/opkg/hydraroute.conf 2>/dev/null || echo "src/gz HydraRoute $F" >> /opt/etc/opkg/hydraroute.conf

run_with_animation "Обновление списка пакетов с репозиторием" opkg update

echo ""
echo "Установить/обновить пакет ('hydraroute' или 'hrneo')? (y/n):"
read c < /dev/tty
if [ "$c" = "y" ] || [ "$c" = "Y" ]; then
  echo "Введите имя пакета:"
  read PACKAGE < /dev/tty
  case "$PACKAGE" in
    hydraroute|hrneo)
      run_with_animation "✓ $PACKAGE" opkg ${PACKAGE:+$(opkg status $PACKAGE >/dev/null 2>&1 && echo upgrade)||echo install} "$PACKAGE"
      if [ "$PACKAGE" = "hrneo" ]; then
        echo ""; echo "Установить Web-интерфейс для HRNeo? (y/n):"
        read w < /dev/tty
        if [ "$w" = "y" ] || [ "$w" = "Y" ]; then
          run_with_animation "Установка HRNeo WebUI" install_webui
        fi
      fi
    ;;
    *) echo "❗ Пропуск: неверное имя.";;
  esac
else
  echo "Пропуск установки."
fi

echo ""; echo -e "${GREEN}✔ Установка завершена.${NC}"

if [ "$PACKAGE" = "hydraroute" ]; then
  ln -sf /opt/etc/init.d/S99hydraroute /opt/bin/hr
  echo "Управление «классиком»: hr (start/restart/stop)"
elif [ "$PACKAGE" = "hrneo" ]; then
  ln -sf /opt/etc/init.d/S99hrneo /opt/bin/neo
  echo "Управление «нео»: neo (start/restart/stop)"
fi

echo "Больше полезностей — @HydraRouteBot"
[ -f "$0" ] && rm -- "$0" 2>/dev/null
echo -e "${GREEN}Готово.${NC}"
