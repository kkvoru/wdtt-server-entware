# WDTT Server for Keenetic Entware

Ручной комплект для установки серверной части проекта [proxy-turn-vk-android](https://github.com/amurcanov/proxy-turn-vk-android) на роутер Keenetic с Entware.

## Источник

Серверная часть основана на оригинальном проекте [proxy-turn-vk-android](https://github.com/amurcanov/proxy-turn-vk-android).

Этот комплект оставляет только ручную сборку и установку `wdtt-server` на Keenetic/Entware. Клиентские компоненты оригинального проекта сюда не входят.

В комплект входят:

- `install_wdtt_entware.sh` — интерактивный установщик для Entware.
- `wdtt-server-entware-*` — бинарные файлы сервера под разные архитектуры Entware.

## Требования

- Роутер Keenetic с установленным и смонтированным Entware в `/opt`.
- Root-доступ по SSH к роутеру.
- Архитектура Entware, поддерживаемая комплектом: `mipsel`, `mips`, `armv5`, `armv7`, `arm64/aarch64`, `x86`, `x64`.
- Доступные системные команды: `sh`, `ip`, `iptables`. Для запуска в фоне желательно наличие `start-stop-daemon`, обычно он есть в Entware.
- Для установки с автоскачиванием нужен `wget` или `curl` и доступ роутера к GitHub Releases.

Проверить архитектуру:

```sh
opkg print-architecture
```

## Быстрая установка

На роутере выполните:

```sh
mkdir -p /opt/tmp/wdtt
cd /opt/tmp/wdtt
wget -O install_wdtt_entware.sh https://github.com/kkvoru/wdtt-server-entware/releases/latest/download/install_wdtt_entware.sh
chmod +x ./install_wdtt_entware.sh
sh ./install_wdtt_entware.sh
```

Установщик сам определит архитектуру Entware и скачает подходящий `wdtt-server-entware-*` из GitHub Releases.

Если в системе нет `wget`, используйте `curl`:

```sh
mkdir -p /opt/tmp/wdtt
cd /opt/tmp/wdtt
curl -fL -o install_wdtt_entware.sh https://github.com/kkvoru/wdtt-server-entware/releases/latest/download/install_wdtt_entware.sh
chmod +x ./install_wdtt_entware.sh
sh ./install_wdtt_entware.sh
```

Если файлы опубликованы в другом репозитории или по другому адресу, перед запуском можно указать базовый URL релиза:

```sh
WDTT_RELEASE_BASE_URL="https://example.com/wdtt" sh ./install_wdtt_entware.sh
```

## Файлы

Готовые файлы после сборки лежат в:

```text
dist/
  install_wdtt_entware.sh
  wdtt-server-entware-mipsel-softfloat
  wdtt-server-entware-mips-softfloat
  wdtt-server-entware-armv5
  wdtt-server-entware-armv7
  wdtt-server-entware-arm64
  wdtt-server-entware-x86
  wdtt-server-entware-x64
  SHA256SUMS.txt
  wdtt-server-entware-all.zip
```

Если нужна установка без скачивания бинарника из интернета, скопируйте `install_wdtt_entware.sh` и нужные `wdtt-server-entware-*` из `dist/` в одну директорию на роутере.

```text
/opt/tmp/wdtt/
```

## Офлайн-Установка

1. Скопируйте `install_wdtt_entware.sh` и все `wdtt-server-entware-*` на роутер в одну директорию.

2. Зайдите на роутер по SSH и перейдите в эту директорию:

```sh
cd /opt/tmp/wdtt
```

3. Выдайте права на запуск:

```sh
chmod +x ./install_wdtt_entware.sh ./wdtt-server-entware-*
```

4. Запустите установщик:

```sh
sh ./install_wdtt_entware.sh
```

Скрипт спросит:

- главный пароль туннеля с повторным вводом;
- Telegram Admin ID, необязательно;
- Telegram Bot Token, необязательно;
- UDP-порт DTLS-сервера, по умолчанию `56000`;
- внутренний UDP-порт WireGuard, по умолчанию `56001`;
- нужно ли ограничить NAT конкретным интерфейсом.

Подходящий бинарник выбирается автоматически по `opkg print-architecture` и `uname -m`. Если файла нет рядом с установщиком, скрипт попробует скачать его из `WDTT_RELEASE_BASE_URL`. Если архитектуру определить не удалось или скачать файл не получилось, установщик попросит указать путь к бинарному файлу вручную.

Подтверждение установки выполняется латиницей:

```text
Продолжить установку? [y/N]
```

Для продолжения введите `y`.

## NAT

По умолчанию установщик использует автоматический режим NAT:

```sh
iptables -t nat -A POSTROUTING -s 10.66.66.0/24 -j MASQUERADE
```

Это предпочтительный режим для Keenetic, потому что маршруты могут уходить через разные интерфейсы: например `ppp0`, `nikecli0`, `nikecli1` и другие.

Если выбрать продвинутый режим и ограничить NAT конкретным интерфейсом, установщик добавит правило вида:

```sh
iptables -t nat -A POSTROUTING -s 10.66.66.0/24 -o ppp0 -j MASQUERADE
```

Этот режим стоит использовать только если вы точно знаете, через какой интерфейс должен выходить трафик WDTT. Неверный выбор интерфейса может привести к ситуации, когда туннель подключается, но интернет через него не работает или работает частично.

## Что Устанавливается

После успешной установки:

```text
/opt/bin/wdtt-server              бинарный файл сервера
/opt/etc/wdtt/wdtt.env            параметры запуска
/opt/etc/init.d/S99wdtt           init-скрипт Entware
/opt/var/log/wdtt-install.log     лог установки
/opt/var/log/wdtt-server.log      лог сервера
/opt/var/run/wdtt.pid             PID запущенного процесса
```

Сервер создаёт интерфейс:

```text
wdtt0
```

Подсеть WireGuard-устройств:

```text
10.66.66.0/24
```

## Управление

Проверить статус:

```sh
/opt/etc/init.d/S99wdtt status
```

Запустить:

```sh
/opt/etc/init.d/S99wdtt start
```

Остановить:

```sh
/opt/etc/init.d/S99wdtt stop
```

Перезапустить:

```sh
/opt/etc/init.d/S99wdtt restart
```

Посмотреть процесс:

```sh
ps | grep wdtt
```

Посмотреть интерфейс:

```sh
ip addr show wdtt0
```

Посмотреть открытые UDP-порты:

```sh
netstat -ulnp | grep wdtt
```

## Логи

Лог установки:

```sh
tail -n 100 /opt/var/log/wdtt-install.log
```

Лог сервера:

```sh
tail -n 100 /opt/var/log/wdtt-server.log
```

Смотреть лог сервера в реальном времени:

```sh
tail -f /opt/var/log/wdtt-server.log
```

## Обновление

1. Скопируйте новый `install_wdtt_entware.sh` и нужные `wdtt-server-entware-*` в любую директорию на роутере.
2. Запустите установщик снова:

```sh
sh ./install_wdtt_entware.sh
```

Скрипт остановит старый процесс, обновит бинарник, перезапишет env/init-файлы, восстановит firewall/NAT-правила и запустит сервер.

## Удаление

```sh
sh ./install_wdtt_entware.sh uninstall
```

Удаляются:

- `/opt/bin/wdtt-server`;
- `/opt/etc/init.d/S99wdtt`;
- `/opt/etc/wdtt/wdtt.env`;
- PID-файл;
- правила firewall/NAT для WDTT;
- интерфейс `wdtt0`, если он существует.

База паролей сохраняется, если она уже была создана:

```text
/opt/etc/wdtt/passwords.json
```

## Сборка

Для сборки готового комплекта под Keenetic Entware:

```bat
build_server.bat
```

Во время сборки скрипт клонирует или обновляет оригинальный репозиторий:

```text
https://github.com/amurcanov/proxy-turn-vk-android
```

Исходники оригинала размещаются во временной директории `.source/proxy-turn-vk-android`, которая не входит в комплект.

Скрипт собирает Entware-бинарники в `dist/`:

- `wdtt-server-entware-mipsel-softfloat`;
- `wdtt-server-entware-mips-softfloat`;
- `wdtt-server-entware-armv5`;
- `wdtt-server-entware-armv7`;
- `wdtt-server-entware-arm64`;
- `wdtt-server-entware-x86`;
- `wdtt-server-entware-x64`;
- `install_wdtt_entware.sh`;
- `SHA256SUMS.txt`;
- `wdtt-server-entware-all.zip`.

Матрица сборки внутри `build_server.bat`:

```text
wdtt-server-entware-mipsel-softfloat  GOARCH=mipsle  GOMIPS=softfloat
wdtt-server-entware-mips-softfloat    GOARCH=mips    GOMIPS=softfloat
wdtt-server-entware-armv5             GOARCH=arm     GOARM=5
wdtt-server-entware-armv7             GOARCH=arm     GOARM=7
wdtt-server-entware-arm64             GOARCH=arm64
wdtt-server-entware-x86               GOARCH=386
wdtt-server-entware-x64               GOARCH=amd64
```

При установке на роутере скрипт выбирает подходящий файл автоматически. Если нужной архитектуры нет в комплекте, можно собрать дополнительный бинарник из `.source/proxy-turn-vk-android` по той же схеме и положить его рядом с установщиком.

## Диагностика

Проверить, что сервер запущен:

```sh
/opt/etc/init.d/S99wdtt status
ps | grep wdtt
```

Проверить, что интерфейс поднялся:

```sh
ip addr show wdtt0
```

Проверить forwarding:

```sh
cat /proc/sys/net/ipv4/ip_forward
```

Ожидаемое значение:

```text
1
```

Проверить NAT:

```sh
iptables -t nat -nvL POSTROUTING | grep 10.66.66.0/24
```

Проверить FORWARD:

```sh
iptables -nvL FORWARD | grep 10.66.66.0/24
```

Если клиент подключается, но интернета нет, сначала проверьте:

- совпадает ли пароль на клиенте и сервере;
- растут ли счётчики `iptables` для `10.66.66.0/24`;
- не выбран ли неверный NAT-интерфейс в продвинутом режиме;
- есть ли default route на роутере:

```sh
ip route show default
```

## Лицензия

Проект распространяется под лицензией GNU General Public License v3.0.
