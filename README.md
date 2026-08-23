## [release](https://pegakmop.github.io/release/)

# Установить репозиторий
```
curl -Ls "https://pegakmop.github.io/release/keenetic/opkg.sh" | sh
```
# Удалить репозиторий
```
rm -rf /opt/etc/opkg/neofit.conf
```
# Неудачно обновились списки?
```
rm -rf /opt/var/opkg-lists/neofit && opkg update
``` 
