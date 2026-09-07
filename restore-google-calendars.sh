#!/usr/bin/env bash
#
# restore-google-calendars.sh — возврат Google-календарей в GNOME Calendar
# Ubuntu 24.04 / GNOME 46 / gnome-online-accounts + evolution-data-server
#
# ПОЧЕМУ КАЛЕНДАРИ ПРОПАДАЮТ
#   Сам аккаунт Google в «Онлайн-аккаунтах» никуда не devается — он записан
#   в ~/.config/goa-1.0/accounts.conf и лежит там постоянно.
#   А вот СПИСОК календарей аккаунта на диске не хранится вообще: при каждом
#   старте сессии evolution-data-server заново спрашивает у Google «какие у
#   тебя календари» и держит ответ только в оперативной памяти.
#   Если в этот момент запрос не прошёл (сеть/VPN ещё не поднялись, токен не
#   обновился, Google придержал запрос) — календарей в списке просто нет.
#   Позже, при удачном запросе, они возвращаются. Отсюда «то пропадают, то
#   появляются».
#
# ЧТО ДЕЛАЕТ СКРИПТ
#   1. Проверяет, что заранее известные аккаунты есть в «Онлайн-аккаунтах»
#      и что у них включён календарь (при необходимости включает).
#   2. Спрашивает у Google настоящий список календарей — это эталон.
#   3. Перезапускает службы календаря и повторяет попытки, пока в системе не
#      появятся все ожидаемые календари.
#   4. Принудительно синхронизирует каждый календарь (скачивает события).
#
#   Скрипт НЕ создаёт свои копии календарей: evolution заводит их сам, и
#   параллельные копии дали бы задвоение списка (проверено).
#   Скрипт НЕ может добавить новый аккаунт Google: первый вход требует
#   браузера и согласия пользователя. Недостающие аккаунты он назовёт.
#
# ИСПОЛЬЗОВАНИЕ
#   ./restore-google-calendars.sh                  восстановить и синхронизировать
#   ./restore-google-calendars.sh --list           показать текущее состояние
#   ./restore-google-calendars.sh --dry-run        показать план, ничего не менять
#   ./restore-google-calendars.sh --retries 5      больше попыток (по умолчанию 3)
#   ./restore-google-calendars.sh --accounts a@gmail.com,b@gmail.com
#   ./restore-google-calendars.sh --install-autostart    запускать через 60 с после входа
#   ./restore-google-calendars.sh --remove-autostart
#
set -uo pipefail

# ---------------------------------------------------------------------------
# НАСТРОЙКА — заранее известный список Google-аккаунтов
# ---------------------------------------------------------------------------
ACCOUNTS=(
    "telefoncyka1971@gmail.com"
    "nn.loginnn@gmail.com"
    "lethanhmai14153@gmail.com"
    # "fourth.account@gmail.com"
)

RETRIES=3          # попыток перезапуска, пока календари не появятся
WAIT_AFTER_START=9 # секунд на то, чтобы EDS опросил Google

# ---------------------------------------------------------------------------
GOA_CONF="$HOME/.config/goa-1.0/accounts.conf"
SOURCES_DIR="$HOME/.config/evolution/sources"
STATE_DIR="$HOME/.local/share/restore-google-calendars"
AUTOSTART="$HOME/.config/autostart/restore-google-calendars.desktop"
LIST_SOURCES="/usr/libexec/evolution-data-server/list-sources"
GOA_PATH="/org/gnome/OnlineAccounts/Accounts"
SELF="$(readlink -f "$0")"

DRY_RUN=0; LIST_ONLY=0

C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
[ -t 1 ] || { C_OK=""; C_WARN=""; C_ERR=""; C_DIM=""; C_OFF=""; }
ok()    { printf '%s✓%s %s\n' "$C_OK"   "$C_OFF" "$*"; }
warn()  { printf '%s!%s %s\n' "$C_WARN" "$C_OFF" "$*"; }
err()   { printf '%s✗%s %s\n' "$C_ERR"  "$C_OFF" "$*" >&2; }
info()  { printf '   %s%s%s\n' "$C_DIM" "$*" "$C_OFF"; }
head1() { printf '\n== %s ==\n' "$*"; }
die()   { err "$*"; exit 1; }

usage() { sed -n '3,45p' "$SELF" | sed 's/^#\ \?//'; exit 0; }

# ---------------------------------------------------------------------------
# Аргументы
# ---------------------------------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --list)    LIST_ONLY=1 ;;
        --retries) shift; RETRIES="${1:-3}" ;;
        --accounts) shift; IFS=',' read -r -a ACCOUNTS <<< "${1:-}" ;;
        --install-autostart)
            mkdir -p "$(dirname "$AUTOSTART")" "$STATE_DIR"
            cat > "$AUTOSTART" <<EOF
[Desktop Entry]
Type=Application
Name=Restore Google calendars
Comment=Возврат Google-календарей в GNOME Calendar после входа в систему
Exec=bash -c "sleep 60; '$SELF' >> '$STATE_DIR/autostart.log' 2>&1"
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
            ok "автозапуск установлен: $AUTOSTART"
            info "лог запусков: $STATE_DIR/autostart.log"
            exit 0 ;;
        --remove-autostart)
            if [ -f "$AUTOSTART" ]; then
                mv "$AUTOSTART" "$AUTOSTART.disabled-$(date +%Y%m%d-%H%M%S)"
                ok "автозапуск отключён (файл переименован, не удалён)"
            else
                warn "автозапуск и так не установлен"
            fi
            exit 0 ;;
        -h|--help) usage ;;
        *) die "неизвестный аргумент: $1 (см. --help)" ;;
    esac
    shift
done

[ ${#ACCOUNTS[@]} -gt 0 ] || die "список ACCOUNTS пуст — отредактируйте скрипт или передайте --accounts"

# ---------------------------------------------------------------------------
# Окружение
# ---------------------------------------------------------------------------
for bin in gdbus curl python3 pkill; do
    command -v "$bin" >/dev/null 2>&1 || die "не найдена утилита: $bin"
done
[ -x "$LIST_SOURCES" ] || die "не найден $LIST_SOURCES (пакет evolution-data-server)"

[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] || \
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus \
    --method org.freedesktop.DBus.ListNames >/dev/null 2>&1 \
    || die "нет доступа к сессионной шине D-Bus — запускайте из графической сессии"

# ---------------------------------------------------------------------------
# Функции
# ---------------------------------------------------------------------------

# id аккаунта в GNOME Online Accounts по адресу почты
goa_account_id() {
    gdbus introspect --session --dest org.gnome.OnlineAccounts \
        --object-path /org/gnome/OnlineAccounts --recurse 2>/dev/null |
    python3 -c '
import re, sys
want, cur = sys.argv[1].lower(), None
for line in sys.stdin:
    m = re.search(r"node /org/gnome/OnlineAccounts/Accounts/(\S+)", line)
    if m:
        cur = m.group(1)
    m = re.search(r"readonly s Identity = \x27([^\x27]*)\x27", line)
    if m and m.group(1).lower() == want and cur:
        print(cur); break
' "$1"
}

# OAuth2-токен доступа для аккаунта
goa_token() {
    gdbus call --session --dest org.gnome.OnlineAccounts \
        --object-path "$GOA_PATH/$1" \
        --method org.gnome.OnlineAccounts.OAuth2Based.GetAccessToken 2>/dev/null |
        sed "s/^('//; s/',.*//"
}

# uid источника-коллекции GOA в evolution-data-server
collection_uid() {
    local email="$1" f
    for f in "$SOURCES_DIR"/*.source; do
        [ -f "$f" ] || continue
        grep -q '^BackendName=google$' "$f" || continue
        grep -qi "^Identity=$email\$" "$f" || continue
        basename "$f" .source
        return
    done
}

# текущие календари EDS: "<uid>\t<имя>" для детей заданной коллекции
eds_calendars_of() {
    "$LIST_SOURCES" -e -u -m -x Calendar 2>/dev/null |
    awk -F'\t' -v coll="ParentUID:$1" '
        { uid=""; name=$2; parent=""; backend=""
          for (i = 3; i <= NF; i++) {
              if ($i ~ /^UID:/)       uid     = substr($i, 5)
              if ($i ~ /^ParentUID:/) parent  = $i
              if ($i ~ /^Backend:/)   backend = substr($i, 9)
          }
          if (parent == coll && backend == "caldav") print uid "\t" name
        }'
}

calendar_stack_restart() {
    pkill -f 'evolution-calendar-fac'    2>/dev/null
    pkill -f 'evolution-addressbook-fa'  2>/dev/null
    pkill -f 'evolution-source-reg'      2>/dev/null
    pkill -f 'gnome-shell-calendar-ser'  2>/dev/null
    sleep 2
    "$LIST_SOURCES" >/dev/null 2>&1     # активация реестра через D-Bus
    sleep "$WAIT_AFTER_START"
}

# ---------------------------------------------------------------------------
# --list
# ---------------------------------------------------------------------------
if [ "$LIST_ONLY" = 1 ]; then
    head1 "Аккаунты в «Онлайн-аккаунтах»"
    for email in "${ACCOUNTS[@]}"; do
        id="$(goa_account_id "$email")"
        [ -n "$id" ] && ok "$email  ($id)" || err "$email — отсутствует"
    done
    head1 "Календари, видимые системе"
    "$LIST_SOURCES" -e -m -x Calendar 2>/dev/null |
        awk -F'\t' '{ b=""; for (i=3;i<=NF;i++) if ($i ~ /^Backend:/) b=substr($i,9)
                      printf "   %-45s [%s]\n", $2, b }'
    exit 0
fi

# ---------------------------------------------------------------------------
# Шаг 1. Аккаунты
# ---------------------------------------------------------------------------
head1 "Шаг 1/4: аккаунты Google"

declare -A ACC_ID=()
MISSING=(); GOA_CHANGED=0

for email in "${ACCOUNTS[@]}"; do
    id="$(goa_account_id "$email")"
    if [ -z "$id" ]; then
        err "$email — нет в «Онлайн-аккаунтах»"
        MISSING+=("$email")
        continue
    fi
    ACC_ID["$email"]="$id"

    if [ -f "$GOA_CONF" ] && ! awk -v acc="[Account $id]" '
            $0 == acc { inside = 1; next }
            /^\[/     { inside = 0 }
            inside && $0 == "CalendarEnabled=true" { found = 1 }
            END { exit !found }' "$GOA_CONF"; then
        if [ "$DRY_RUN" = 1 ]; then
            warn "$email — календарь выключен (был бы включён)"
        else
            cp -a "$GOA_CONF" "$GOA_CONF.bak.$(date +%Y%m%d-%H%M%S)"
            python3 - "$GOA_CONF" "$id" <<'PY'
import sys
path, acc = sys.argv[1], sys.argv[2]
lines = open(path, encoding='utf-8').read().splitlines()
out, inside, done = [], False, False
for ln in lines:
    if ln.strip() == f'[Account {acc}]':
        inside = True; out.append(ln); continue
    if inside and ln.startswith('['):
        if not done:
            out.append('CalendarEnabled=true'); done = True
        inside = False
    if inside and ln.startswith('CalendarEnabled='):
        out.append('CalendarEnabled=true'); done = True; continue
    out.append(ln)
if inside and not done:
    out.append('CalendarEnabled=true')
open(path, 'w', encoding='utf-8').write('\n'.join(out) + '\n')
PY
            GOA_CHANGED=1
            ok "$email — календарь включён"
        fi
    else
        ok "$email — аккаунт на месте, календарь включён"
    fi
done

[ ${#ACC_ID[@]} -gt 0 ] || {
    err "ни одного из перечисленных аккаунтов нет в системе."
    info "Добавить можно только вручную: Настройки → Онлайн-аккаунты → Google"
    info "или командой: gnome-control-center online-accounts"
    exit 1
}

if [ "$GOA_CHANGED" = 1 ]; then
    pkill -f 'goa-daemon' 2>/dev/null
    sleep 3
fi

# ---------------------------------------------------------------------------
# Шаг 2. Эталонный список календарей у Google
# ---------------------------------------------------------------------------
head1 "Шаг 2/4: что говорит Google"

WORK="$(mktemp -d)"
trap 'find "$WORK" -type f -delete 2>/dev/null; rmdir "$WORK" 2>/dev/null' EXIT

declare -A EXPECTED=()
TOTAL_EXPECTED=0

for email in "${!ACC_ID[@]}"; do
    id="${ACC_ID[$email]}"
    token="$(goa_token "$id")"
    if [ -z "$token" ]; then
        err "$email — не удалось получить токен"
        info "аккаунт требует повторного входа: Настройки → Онлайн-аккаунты"
        continue
    fi

    code="$(curl -s -m 30 -o "$WORK/$id.json" -w '%{http_code}' \
        -H "Authorization: Bearer $token" \
        'https://www.googleapis.com/calendar/v3/users/me/calendarList?maxResults=250')"

    if [ "$code" != "200" ]; then
        err "$email — Google ответил HTTP $code (сеть/VPN/авторизация)"
        continue
    fi

    n="$(python3 -c "
import json
d = json.load(open('$WORK/$id.json'))
items = d.get('items', [])
print(len(items))
for i in items:
    print('   •', i.get('summary', '?'), '[' + i.get('accessRole', '?') + ']')
" | tee "$WORK/$id.names" | head -1)"
    tail -n +2 "$WORK/$id.names"
    EXPECTED["$email"]="$n"
    TOTAL_EXPECTED=$((TOTAL_EXPECTED + n))
    ok "$email — календарей у Google: $n"
done

[ "$TOTAL_EXPECTED" -gt 0 ] || die "Google не отдал ни одного списка календарей — проверьте сеть/VPN и авторизацию"

if [ "$DRY_RUN" = 1 ]; then
    head1 "--dry-run"
    warn "службы не перезапускались, синхронизация не выполнялась"
    exit 0
fi

# ---------------------------------------------------------------------------
# Шаг 3. Перезапуск служб с повторами, пока календари не появятся
# ---------------------------------------------------------------------------
head1 "Шаг 3/4: возврат календарей в систему"

attempt=0
while :; do
    attempt=$((attempt + 1))
    got_all=1

    for email in "${!EXPECTED[@]}"; do
        coll="$(collection_uid "$email")"
        have=0
        [ -n "$coll" ] && have="$(eds_calendars_of "$coll" | grep -c . )"
        [ "$have" -ge "${EXPECTED[$email]}" ] || got_all=0
    done

    if [ "$got_all" = 1 ]; then
        ok "все ожидаемые календари на месте (попытка $attempt)"
        break
    fi

    if [ "$attempt" -gt "$RETRIES" ]; then
        warn "после $RETRIES перезапусков появились не все календари"
        break
    fi

    info "попытка $attempt: перезапуск служб календаря…"
    calendar_stack_restart
done

# ---------------------------------------------------------------------------
# Шаг 4. Синхронизация
# ---------------------------------------------------------------------------
head1 "Шаг 4/4: синхронизация"

SYNCED=0; FOUND=0
for email in "${!EXPECTED[@]}"; do
    coll="$(collection_uid "$email")"
    if [ -z "$coll" ]; then
        err "$email — в системе нет источника-коллекции; выйдите и войдите в сессию"
        continue
    fi
    while IFS=$'\t' read -r uid name; do
        [ -n "$uid" ] || continue
        FOUND=$((FOUND + 1))
        if gdbus call --session --dest org.gnome.evolution.dataserver.Calendar8 \
             --object-path /org/gnome/evolution/dataserver/CalendarFactory \
             --method org.gnome.evolution.dataserver.CalendarFactory.OpenCalendar \
             "$uid" >/dev/null 2>&1; then
            SYNCED=$((SYNCED + 1))
            ok "$name"
        else
            warn "$name — не открылся"
        fi
    done < <(eds_calendars_of "$coll")
done

# ---------------------------------------------------------------------------
# Итог
# ---------------------------------------------------------------------------
head1 "Итог  ($(date '+%Y-%m-%d %H:%M:%S'))"
printf '   ожидалось календарей     : %s\n' "$TOTAL_EXPECTED"
printf '   вернулось в систему      : %s\n' "$FOUND"
printf '   синхронизировано         : %s\n' "$SYNCED"

if [ "$FOUND" -lt "$TOTAL_EXPECTED" ]; then
    echo
    warn "часть календарей не поднялась. Что проверить:"
    info "интернет/VPN до google.com и apidata.googleusercontent.com"
    info "Настройки → Онлайн-аккаунты: нет ли значка «требуется вход»"
    info "повторить с бо́льшим числом попыток: $SELF --retries 6"
fi

if [ ${#MISSING[@]} -gt 0 ]; then
    echo
    warn "нет в «Онлайн-аккаунтах» (добавляются только вручную, через браузер):"
    for m in "${MISSING[@]}"; do info "$m"; done
    info "gnome-control-center online-accounts"
fi

echo
info "состояние: $SELF --list"
info "если «Календарь» открыт — закройте и откройте заново"
