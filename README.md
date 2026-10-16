## [release](https://pegakmop.github.io/release/)

# Установить репозиторий
```
ARCH=$(grep '^arch=' /opt/etc/entware_release | cut -d= -f2) && case "$ARCH" in aarch64) URL="aarch64-k3.10";; mipsel) URL="mipselsf-k3.4";; mips) URL="mipssf-k3.4";; esac && mkdir -p /opt/etc/opkg && echo "src/gz neofit http://pegakmop.github.io/release/keenetic/$URL" > /opt/etc/opkg/neofit.conf && opkg update || true;
```
# Удалить репозиторий
```
rm -rf /opt/etc/opkg/pegakmop.conf || true;
rm -rf /opt/etc/opkg/neofit.conf || true;
opkg update  || true;
```
# Неудачно обновились списки?
```
rm -rf /opt/var/opkg-lists/pegakmop || true;
rm -rf /opt/var/opkg-lists/neofit || true;
opkg update || true;
``` 
