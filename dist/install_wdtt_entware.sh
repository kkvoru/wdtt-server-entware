#!/bin/sh
# Интерактивный установщик WDTT-сервера для Keenetic Entware.

set -u

SCRIPT_VERSION="1.1"
APP_NAME="wdtt-server"
WDTT_RELEASE_BASE_URL="${WDTT_RELEASE_BASE_URL:-https://github.com/kkvoru/wdtt-server-entware/releases/latest/download}"
WDTT_IFACE="wdtt0"
WDTT_SUBNET="10.66.66.0/24"
WDTT_NAT_IFACE=""
WDTT_CONFIG_DIR="/opt/etc/wdtt"
WDTT_BIN="/opt/bin/wdtt-server"
WDTT_INIT="/opt/etc/init.d/S99wdtt"
WDTT_ENV="/opt/etc/wdtt/wdtt.env"
WDTT_LOG="/opt/var/log/wdtt-server.log"
WDTT_INSTALL_LOG="/opt/var/log/wdtt-install.log"
WDTT_PID="/opt/var/run/wdtt.pid"

say() { printf '%s\n' "$*"; }
log() { say "$*"; printf '%s\n' "$*" >> "$WDTT_INSTALL_LOG" 2>/dev/null || true; }
warn() { log "[!] $*"; }
die() { log "[x] $*"; exit 1; }

script_dir() {
    case "$0" in
        */*) dirname "$0" ;;
        *) pwd ;;
    esac
}

quote_sh() {
    printf "'%s'" "$(printf "%s" "$1" | sed "s/'/'\\\\''/g")"
}

ask() {
    prompt="$1"
    default="${2:-}"
    if [ -n "$default" ]; then
        printf '%s [%s]: ' "$prompt" "$default" >/dev/tty
    else
        printf '%s: ' "$prompt" >/dev/tty
    fi
    IFS= read -r answer </dev/tty || answer=""
    [ -n "$answer" ] && printf '%s' "$answer" || printf '%s' "$default"
}

ask_secret() {
    prompt="$1"
    printf '%s: ' "$prompt" >/dev/tty
    stty -echo 2>/dev/null || true
    IFS= read -r answer </dev/tty || answer=""
    stty echo 2>/dev/null || true
    printf '\n' >/dev/tty
    printf '%s' "$answer"
}

is_port() {
    value="$1"
    case "$value" in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ "$value" -ge 1 ] 2>/dev/null && [ "$value" -le 65535 ] 2>/dev/null
}

ask_port() {
    prompt="$1"
    default="$2"
    while :; do
        value="$(ask "$prompt" "$default")"
        if is_port "$value"; then
            printf '%s' "$value"
            return 0
        fi
        say "Порт должен быть числом от 1 до 65535."
    done
}

is_safe_value() {
    value="$1"
    case "$value" in
        *[!A-Za-z0-9_.!?:#/@,-]*) return 1 ;;
        *) return 0 ;;
    esac
}

ask_safe_required() {
    prompt="$1"
    while :; do
        value="$(ask_secret "$prompt")"
        if [ -n "$value" ] && is_safe_value "$value"; then
            printf '%s' "$value"
            return 0
        fi
        say "Используйте только латинские буквы, цифры и символы: _ . ! ? : # / @ , -"
    done
}

ask_password_confirmed() {
    while :; do
        first="$(ask_safe_required "Главный пароль туннеля")"
        second="$(ask_secret "Повторите главный пароль туннеля")"
        if [ "$first" = "$second" ]; then
            printf '%s' "$first"
            return 0
        fi
        say "Пароли не совпадают. Попробуйте ещё раз."
    done
}

ask_safe_optional() {
    prompt="$1"
    default="${2:-}"
    while :; do
        value="$(ask "$prompt" "$default")"
        if [ -z "$value" ] || is_safe_value "$value"; then
            printf '%s' "$value"
            return 0
        fi
        say "Используйте только латинские буквы, цифры и символы: _ . ! ? : # / @ , -"
    done
}

check_root() {
    [ "$(id -u)" = "0" ] || die "Запустите скрипт от root."
}

check_entware() {
    [ -d /opt ] || die "Каталог /opt не найден. Entware не смонтирован."
    [ -d /opt/etc ] || die "Каталог /opt/etc не найден. Entware не инициализирован."
    if command -v opkg >/dev/null 2>&1; then
        log "Архитектуры Entware:"
        opkg print-architecture 2>/dev/null | while IFS= read -r line; do log "  $line"; done
    else
        warn "opkg не найден. Продолжаю с текущей структурой /opt."
    fi
}

detect_binary_name() {
    arch_info=""
    if command -v opkg >/dev/null 2>&1; then
        arch_info="$(opkg print-architecture 2>/dev/null | awk '{print $2}' | tr '\n' ' ')"
    fi
    arch_info="$arch_info $(uname -m 2>/dev/null)"

    case "$arch_info" in
        *mipsel*|*mipsle*)
            printf '%s' "wdtt-server-entware-mipsel-softfloat"
            ;;
        *mips*)
            printf '%s' "wdtt-server-entware-mips-softfloat"
            ;;
        *aarch64*|*arm64*)
            printf '%s' "wdtt-server-entware-arm64"
            ;;
        *armv7*|*armv7l*)
            printf '%s' "wdtt-server-entware-armv7"
            ;;
        *armv5*)
            printf '%s' "wdtt-server-entware-armv5"
            ;;
        *x64*|*x86_64*|*amd64*)
            printf '%s' "wdtt-server-entware-x64"
            ;;
        *x86*|*i386*|*i486*|*i586*|*i686*)
            printf '%s' "wdtt-server-entware-x86"
            ;;
        *)
            printf ''
            ;;
    esac
}

download_file() {
    url="$1"
    out="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fL --connect-timeout 20 -o "$out" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$out" "$url"
    else
        return 1
    fi
}

download_binary() {
    name="$1"
    [ -n "$name" ] || return 1
    [ -n "$WDTT_RELEASE_BASE_URL" ] || return 1

    dir="$(script_dir)"
    out="$dir/$name"
    if ! touch "$out" 2>/dev/null; then
        out="/opt/tmp/$name"
    fi
    rm -f "$out" 2>/dev/null || true

    url="${WDTT_RELEASE_BASE_URL%/}/$name"
    say "Бинарник $name не найден рядом с установщиком." >&2
    say "Пробую скачать: $url" >&2
    if download_file "$url" "$out"; then
        chmod 0755 "$out" 2>/dev/null || true
        printf '%s' "$out"
        return 0
    fi

    rm -f "$out" 2>/dev/null || true
    return 1
}

find_binary() {
    dir="$(script_dir)"
    preferred="$(detect_binary_name)"

    if [ -n "$preferred" ] && [ -f "$dir/$preferred" ]; then
        printf '%s' "$dir/$preferred"
        return 0
    fi

    if [ -n "$preferred" ]; then
        downloaded="$(download_binary "$preferred" || true)"
        if [ -n "$downloaded" ] && [ -f "$downloaded" ]; then
            printf '%s' "$downloaded"
            return 0
        fi
    fi

    for name in wdtt-server wdtt-server-entware-mipsel-softfloat wdtt-server-entware-mips-softfloat wdtt-server-entware-armv5 wdtt-server-entware-armv7 wdtt-server-entware-arm64 wdtt-server-entware-x86 wdtt-server-entware-x64; do
        if [ -f "$dir/$name" ]; then
            printf '%s' "$dir/$name"
            return 0
        fi
    done
    printf ''
}

detect_wan_interface() {
    ip route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1); exit}}'
}

list_interfaces() {
    if [ -d /sys/class/net ]; then
        ls /sys/class/net 2>/dev/null | grep -v '^lo$' | sort
    else
        ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | cut -d'@' -f1 | grep -v '^lo$' | sort
    fi
}

ipt_add() {
    table="$1"
    shift
    if [ "$table" = "filter" ]; then
        iptables -C "$@" 2>/dev/null || iptables -I "$@" 2>/dev/null || true
    else
        iptables -t "$table" -C "$@" 2>/dev/null || iptables -t "$table" -A "$@" 2>/dev/null || true
    fi
}

ipt_del_repeated() {
    table="$1"
    shift
    i=0
    while [ "$i" -lt 5 ]; do
        if [ "$table" = "filter" ]; then
            iptables -D "$@" 2>/dev/null || true
        else
            iptables -t "$table" -D "$@" 2>/dev/null || true
        fi
        i=$((i + 1))
    done
}

cleanup_firewall() {
    command -v iptables >/dev/null 2>&1 || return 0
    iface="$(detect_wan_interface)"
    [ -n "${WDTT_NAT_IFACE:-}" ] && iface="$WDTT_NAT_IFACE"
    ipt_del_repeated filter INPUT -p udp --dport "$DTLS_PORT" -j ACCEPT
    ipt_del_repeated filter INPUT -p udp --dport "$WG_PORT" -j ACCEPT
    ipt_del_repeated filter FORWARD -i "$WDTT_IFACE" -j ACCEPT
    ipt_del_repeated filter FORWARD -o "$WDTT_IFACE" -j ACCEPT
    ipt_del_repeated filter FORWARD -s "$WDTT_SUBNET" -j ACCEPT
    ipt_del_repeated filter FORWARD -d "$WDTT_SUBNET" -j ACCEPT
    ipt_del_repeated nat POSTROUTING -s "$WDTT_SUBNET" -j MASQUERADE
    [ -n "$iface" ] && ipt_del_repeated nat POSTROUTING -s "$WDTT_SUBNET" -o "$iface" -j MASQUERADE
    ipt_del_repeated mangle FORWARD -s "$WDTT_SUBNET" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
    ipt_del_repeated mangle FORWARD -d "$WDTT_SUBNET" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
}

setup_firewall() {
    command -v iptables >/dev/null 2>&1 || {
        warn "iptables не найден. NAT/firewall нужно настроить вручную."
        return 0
    }
    iface="${WDTT_NAT_IFACE:-}"
    [ -z "$iface" ] && iface="$(detect_wan_interface)"
    if [ -n "$WDTT_NAT_IFACE" ]; then
        [ -d "/sys/class/net/$WDTT_NAT_IFACE" ] || warn "Интерфейс $WDTT_NAT_IFACE не найден сейчас. Правило NAT всё равно будет записано."
    elif [ -z "$iface" ]; then
        warn "WAN-интерфейс по умолчанию не определён. Будет добавлен общий MASQUERADE."
    fi

    ipt_add filter INPUT -p udp --dport "$DTLS_PORT" -j ACCEPT
    ipt_add filter INPUT -p udp --dport "$WG_PORT" -j ACCEPT
    ipt_add filter FORWARD -i "$WDTT_IFACE" -j ACCEPT
    ipt_add filter FORWARD -o "$WDTT_IFACE" -j ACCEPT
    ipt_add filter FORWARD -s "$WDTT_SUBNET" -j ACCEPT
    ipt_add filter FORWARD -d "$WDTT_SUBNET" -j ACCEPT
    if [ -n "$WDTT_NAT_IFACE" ]; then
        ipt_add nat POSTROUTING -s "$WDTT_SUBNET" -o "$WDTT_NAT_IFACE" -j MASQUERADE
        log "[ok] NAT ограничен интерфейсом: $WDTT_NAT_IFACE"
    else
        [ -n "$iface" ] && ipt_add nat POSTROUTING -s "$WDTT_SUBNET" -o "$iface" -j MASQUERADE
        ipt_add nat POSTROUTING -s "$WDTT_SUBNET" -j MASQUERADE
        log "[ok] NAT работает для всех маршрутизируемых интерфейсов"
    fi
    ipt_add mangle FORWARD -s "$WDTT_SUBNET" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
    ipt_add mangle FORWARD -d "$WDTT_SUBNET" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
    log "[ok] Firewall/NAT настроены для $WDTT_SUBNET"
}

stop_wdtt() {
    [ -x "$WDTT_INIT" ] && "$WDTT_INIT" stop 2>/dev/null || true
    pkill -x "$APP_NAME" 2>/dev/null || killall "$APP_NAME" 2>/dev/null || true
    ip link show "$WDTT_IFACE" >/dev/null 2>&1 && ip link del "$WDTT_IFACE" 2>/dev/null || true
}

write_env() {
    server_args="-listen 0.0.0.0:${DTLS_PORT} -wg-port ${WG_PORT} -config-dir ${WDTT_CONFIG_DIR} -password ${MAIN_PASSWORD}"
    [ -n "$ADMIN_ID" ] && server_args="$server_args -admin $ADMIN_ID"
    [ -n "$BOT_TOKEN" ] && server_args="$server_args -bot-token $BOT_TOKEN"
    {
        echo "WDTT_SERVER_ARGS=$(quote_sh "$server_args")"
        echo "WDTT_LOG=$(quote_sh "$WDTT_LOG")"
        echo "WDTT_PID=$(quote_sh "$WDTT_PID")"
        echo "WDTT_BIN=$(quote_sh "$WDTT_BIN")"
        echo "WDTT_IFACE=$(quote_sh "$WDTT_IFACE")"
        echo "WDTT_SUBNET=$(quote_sh "$WDTT_SUBNET")"
        echo "WDTT_NAT_IFACE=$(quote_sh "$WDTT_NAT_IFACE")"
        echo "WDTT_DTLS_PORT=$(quote_sh "$DTLS_PORT")"
        echo "WDTT_WG_PORT=$(quote_sh "$WG_PORT")"
    } > "$WDTT_ENV"
    chmod 600 "$WDTT_ENV"
}

write_init() {
    cat > "$WDTT_INIT" <<'INITEOF'
#!/bin/sh

ENABLED=yes
PATH=/opt/sbin:/opt/bin:/usr/sbin:/usr/bin:/sbin:/bin
ENV_FILE=/opt/etc/wdtt/wdtt.env

[ -f "$ENV_FILE" ] && . "$ENV_FILE"

: "${WDTT_BIN:=/opt/bin/wdtt-server}"
: "${WDTT_LOG:=/opt/var/log/wdtt-server.log}"
: "${WDTT_PID:=/opt/var/run/wdtt.pid}"
: "${WDTT_IFACE:=wdtt0}"
: "${WDTT_SUBNET:=10.66.66.0/24}"
: "${WDTT_NAT_IFACE:=}"
: "${WDTT_DTLS_PORT:=56000}"
: "${WDTT_WG_PORT:=56001}"
: "${WDTT_SERVER_ARGS:=}"

is_running() {
    [ -f "$WDTT_PID" ] && kill -0 "$(cat "$WDTT_PID")" 2>/dev/null
}

ensure_rule() {
    table="$1"
    shift
    if [ "$table" = "filter" ]; then
        iptables -C "$@" 2>/dev/null || iptables -I "$@" 2>/dev/null || true
    else
        iptables -t "$table" -C "$@" 2>/dev/null || iptables -t "$table" -A "$@" 2>/dev/null || true
    fi
}

setup_runtime_firewall() {
    command -v iptables >/dev/null 2>&1 || return 0
    ensure_rule filter INPUT -p udp --dport "$WDTT_DTLS_PORT" -j ACCEPT
    ensure_rule filter INPUT -p udp --dport "$WDTT_WG_PORT" -j ACCEPT
    ensure_rule filter FORWARD -i "$WDTT_IFACE" -j ACCEPT
    ensure_rule filter FORWARD -o "$WDTT_IFACE" -j ACCEPT
    ensure_rule filter FORWARD -s "$WDTT_SUBNET" -j ACCEPT
    ensure_rule filter FORWARD -d "$WDTT_SUBNET" -j ACCEPT
    if [ -n "$WDTT_NAT_IFACE" ]; then
        ensure_rule nat POSTROUTING -s "$WDTT_SUBNET" -o "$WDTT_NAT_IFACE" -j MASQUERADE
    else
        ensure_rule nat POSTROUTING -s "$WDTT_SUBNET" -j MASQUERADE
    fi
}

start() {
    [ "$ENABLED" = "yes" ] || exit 0
    is_running && exit 0
    mkdir -p "$(dirname "$WDTT_LOG")" "$(dirname "$WDTT_PID")"
    ip link show "$WDTT_IFACE" >/dev/null 2>&1 && ip link del "$WDTT_IFACE" 2>/dev/null || true
    echo 1 > /proc/sys/net/ipv4/ip_forward 2>/dev/null || true
    setup_runtime_firewall
    if command -v start-stop-daemon >/dev/null 2>&1; then
        eval "start-stop-daemon -S -b -m -p \"$WDTT_PID\" -x \"$WDTT_BIN\" -- $WDTT_SERVER_ARGS >>\"$WDTT_LOG\" 2>&1"
    else
        eval "\"$WDTT_BIN\" $WDTT_SERVER_ARGS >>\"$WDTT_LOG\" 2>&1 &"
        echo $! > "$WDTT_PID"
    fi
}

stop() {
    if command -v start-stop-daemon >/dev/null 2>&1 && [ -f "$WDTT_PID" ]; then
        start-stop-daemon -K -p "$WDTT_PID" 2>/dev/null || true
        rm -f "$WDTT_PID"
    elif [ -f "$WDTT_PID" ]; then
        kill "$(cat "$WDTT_PID")" 2>/dev/null || true
        rm -f "$WDTT_PID"
    fi
    pkill -x wdtt-server 2>/dev/null || killall wdtt-server 2>/dev/null || true
    ip link show "$WDTT_IFACE" >/dev/null 2>&1 && ip link del "$WDTT_IFACE" 2>/dev/null || true
}

status() {
    if is_running; then
        echo "wdtt: running"
    else
        echo "wdtt: stopped"
        exit 1
    fi
}

case "${1:-start}" in
    start) start ;;
    stop) stop ;;
    restart) stop; sleep 1; start ;;
    status) status ;;
    *) echo "Использование: $0 {start|stop|restart|status}"; exit 1 ;;
esac
INITEOF
    chmod 0755 "$WDTT_INIT"
}

collect_config() {
    say "Установщик WDTT для Keenetic Entware v$SCRIPT_VERSION"
    say ""
    MAIN_PASSWORD="$(ask_password_confirmed)"
    ADMIN_ID="$(ask_safe_optional "Telegram Admin ID (необязательно)" "")"
    BOT_TOKEN="$(ask_safe_optional "Telegram Bot Token (необязательно)" "")"
    DTLS_PORT="$(ask_port "UDP-порт DTLS-сервера" "56000")"
    WG_PORT="$(ask_port "Внутренний UDP-порт WireGuard" "56001")"
    WDTT_NAT_IFACE=""
    nat_answer="$(ask "Ограничить NAT конкретным интерфейсом? Обычно лучше оставить авто [y/N]" "n")"
    case "$nat_answer" in
        y|Y)
            say ""
            say "Доступные интерфейсы:"
            list_interfaces | while IFS= read -r iface_name; do say "  $iface_name"; done
            default_iface="$(detect_wan_interface)"
            WDTT_NAT_IFACE="$(ask_safe_optional "Интерфейс для NAT" "$default_iface")"
            [ -n "$WDTT_NAT_IFACE" ] || die "Интерфейс NAT не задан."
            ;;
        *) ;;
    esac
    BINARY_PATH="$(find_binary)"
    [ -n "$BINARY_PATH" ] || BINARY_PATH="$(ask "Путь к бинарному файлу wdtt-server" "")"
    [ -f "$BINARY_PATH" ] || die "Бинарный файл не найден: $BINARY_PATH"

    say ""
    say "Параметры установки:"
    say "  Бинарник: $BINARY_PATH -> $WDTT_BIN"
    say "  Конфиг:   $WDTT_CONFIG_DIR"
    say "  DTLS:     $DTLS_PORT/udp"
    say "  WG:       $WG_PORT/udp"
    [ -n "$WDTT_NAT_IFACE" ] && say "  NAT:      только через $WDTT_NAT_IFACE" || say "  NAT:      автоматический, все маршрутизируемые интерфейсы"
    [ -n "$ADMIN_ID" ] && say "  Telegram Admin ID: задан" || say "  Telegram Admin ID: не задан"
    [ -n "$BOT_TOKEN" ] && say "  Telegram Bot Token: задан" || say "  Telegram Bot Token: не задан"
    answer="$(ask "Продолжить установку? [y/N]" "n")"
    case "$answer" in
        y|Y) ;;
        *) die "Установка отменена." ;;
    esac
}

install_wdtt() {
    mkdir -p /opt/bin "$WDTT_CONFIG_DIR" /opt/var/log /opt/var/run
    echo "=== Установщик WDTT Entware v${SCRIPT_VERSION} - $(date) ===" >> "$WDTT_INSTALL_LOG" 2>/dev/null || true
    stop_wdtt
    cleanup_firewall
    echo 1 > /proc/sys/net/ipv4/ip_forward 2>/dev/null || true
    cp "$BINARY_PATH" "$WDTT_BIN" || die "Cannot copy binary to $WDTT_BIN"
    chmod 0755 "$WDTT_BIN"
    setup_firewall
    write_env
    write_init
    "$WDTT_INIT" restart || true
    sleep 2
    if "$WDTT_INIT" status >/dev/null 2>&1; then
        log "[ok] WDTT установлен и запущен."
        log "[ok] Лог сервера: $WDTT_LOG"
    else
        warn "WDTT не удержался в запущенном состоянии. Последние строки лога:"
        tail -n 20 "$WDTT_LOG" 2>/dev/null || true
        exit 1
    fi
}

uninstall_wdtt() {
    mkdir -p /opt/var/log
    echo "=== Удаление WDTT Entware - $(date) ===" >> "$WDTT_INSTALL_LOG" 2>/dev/null || true
    DTLS_PORT="${WDTT_DTLS_PORT:-56000}"
    WG_PORT="${WDTT_WG_PORT:-56001}"
    if [ -f "$WDTT_ENV" ]; then
        . "$WDTT_ENV"
        DTLS_PORT="${WDTT_DTLS_PORT:-$DTLS_PORT}"
        WG_PORT="${WDTT_WG_PORT:-$WG_PORT}"
        WDTT_NAT_IFACE="${WDTT_NAT_IFACE:-}"
    fi
    stop_wdtt
    cleanup_firewall
    rm -f "$WDTT_INIT" "$WDTT_BIN" "$WDTT_ENV" "$WDTT_PID"
    [ -d "$WDTT_CONFIG_DIR" ] && find "$WDTT_CONFIG_DIR" -mindepth 1 -maxdepth 1 ! -name passwords.json -exec rm -rf {} + 2>/dev/null || true
    [ -f "$WDTT_CONFIG_DIR/passwords.json" ] && chmod 600 "$WDTT_CONFIG_DIR/passwords.json" 2>/dev/null || true
    log "[ok] WDTT удалён. База паролей сохранена, если она существовала."
}

status_wdtt() {
    [ -x "$WDTT_INIT" ] && "$WDTT_INIT" status || die "Init-скрипт WDTT не установлен."
    ps w | grep '[w]dtt-server' || true
    ip addr show "$WDTT_IFACE" 2>/dev/null || true
}

main() {
    action="${1:-install}"
    check_root
    check_entware
    case "$action" in
        install|--install|-i) collect_config; install_wdtt ;;
        uninstall|--uninstall|-u) uninstall_wdtt ;;
        status|--status|-s) status_wdtt ;;
        *) die "Использование: $0 [install|uninstall|status]" ;;
    esac
}

main "$@"
