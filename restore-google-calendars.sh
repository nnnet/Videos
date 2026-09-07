#!/usr/bin/env bash
#
# restore-google-calendars.sh — возврат Google-календарей в GNOME Calendar
# Ubuntu 24.04 / GNOME 46 / gnome-online-accounts + evolution-data-server
#
# ПОЧЕМУ КАЛЕНДАРИ ПРОПАДАЮТ
#   Сам аккаунт Google в «Онлайн-аккаунтах» никуда не девается — он записан
#   в ~/.config/goa-1.0/accounts.conf и лежит там постоянно.
#   А список календарей аккаунта — не настройка, а результат запроса: при
#   каждом старте evolution-data-server спрашивает у Google «какие у тебя
#   календари» и раскладывает ответ по файлам в
#   ~/.cache/evolution/sources/<аккаунт>/ — это кэш, а не настройки.
#   Если запрос не прошёл (сеть/VPN ещё не поднялись, токен не обновился,
#   Google придержал ответ) — календари уезжают в подпапку trash/ и из списка
#   исчезают. При следующем удачном запросе возвращаются. Отсюда «то
#   пропадают, то появляются».
#
# ПОЧЕМУ КАЛЕНДАРИ ДВОЯТСЯ
#   Один и тот же календарь (например «Праздники России») бывает подписан
#   сразу в нескольких аккаунтах. Для системы это разные источники, поэтому в
#   списке он появляется столько раз, во скольких аккаунтах подписан.
#   Скрипт находит такие повторы по адресу календаря на сервере Google и
#   оставляет включённым только один, лишние гасит (Enabled=false в кэше).
#   Подписки в самом Google при этом не трогаются; вернуть всё обратно —
#   ключ --undedup.
#
# ЧТО ДЕЛАЕТ СКРИПТ
#   1. Проверяет, что заранее известные аккаунты есть в «Онлайн-аккаунтах»
#      и что у них включён календарь (при необходимости включает).
#   2. Спрашивает у Google настоящий список календарей — это эталон.
#   3. Перезапускает службы календаря и повторяет попытки, пока в системе не
#      появятся все ожидаемые календари.
#   4. Гасит повторы одного и того же календаря из разных аккаунтов.
#   5. Принудительно синхронизирует каждый календарь (скачивает события).
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
#   ./restore-google-calendars.sh --no-dedup       не гасить повторы
#   ./restore-google-calendars.sh --undedup        вернуть все погашенные повторы
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
CACHE_SOURCES="$HOME/.cache/evolution/sources"   # сюда EDS кладёт найденные календари
STATE_DIR="$HOME/.local/share/restore-google-calendars"
AUTOSTART="$HOME/.config/autostart/restore-google-calendars.desktop"
LIST_SOURCES="/usr/libexec/evolution-data-server/list-sources"
GOA_PATH="/org/gnome/OnlineAccounts/Accounts"
SELF="$(readlink -f "$0")"

DRY_RUN=0; LIST_ONLY=0; DEDUP=1; UNDEDUP=0

C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
[ -t 1 ] || { C_OK=""; C_WARN=""; C_ERR=""; C_DIM=""; C_OFF=""; }
ok()    { printf '%s✓%s %s\n' "$C_OK"   "$C_OFF" "$*"; }
warn()  { printf '%s!%s %s\n' "$C_WARN" "$C_OFF" "$*"; }
err()   { printf '%s✗%s %s\n' "$C_ERR"  "$C_OFF" "$*" >&2; }
info()  { printf '   %s%s%s\n' "$C_DIM" "$*" "$C_OFF"; }
head1() { printf '\n== %s ==\n' "$*"; }
die()   { err "$*"; exit 1; }

usage() { awk 'NR>2 && /^#/ {sub(/^# ?/, ""); print; next} NR>2 {exit}' "$SELF"; exit 0; }

# ---------------------------------------------------------------------------
# Аргументы
# ---------------------------------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --list)    LIST_ONLY=1 ;;
        --no-dedup) DEDUP=0 ;;
        --undedup) UNDEDUP=1 ;;
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

# Повторы одного календаря из разных аккаунтов.
#   $1 — режим: apply (погасить), plan (только показать), undo (вернуть все).
#   $2 — файл-карта «почта <TAB> id аккаунта <TAB> json от Google» (для plan/apply).
# Календарь опознаётся по его адресу на сервере Google, а не по названию:
# два разных календаря с одинаковым именем повтором не считаются.
# Гасится не подписка в Google, а только строка в кэше EDS (Enabled=false).
dedup_calendars() {
    python3 - "$1" "${2:-}" <<'PY'
import json, os, sys, urllib.parse

mode    = sys.argv[1]
mapfile = sys.argv[2] if len(sys.argv) > 2 else ""

os.environ.setdefault("DBUS_SESSION_BUS_ADDRESS", "unix:path=/run/user/%d/bus" % os.getuid())
import gi
from gi.repository import Gio, GLib

BUS = "org.gnome.evolution.dataserver.Sources5"
MGR = "/org/gnome/evolution/dataserver/SourceManager"

# порядок аккаунтов и права доступа к календарям — из ответа Google
order, roles = [], {}
if mapfile and os.path.exists(mapfile):
    for line in open(mapfile):
        p = line.rstrip("\n").split("\t")
        if len(p) < 3:
            continue
        email, jf = p[0], p[2]
        order.append(email)
        if os.path.exists(jf):
            try:
                for it in json.load(open(jf)).get("items", []):
                    roles[(email, it.get("id", ""))] = it.get("accessRole", "reader")
            except Exception:
                pass

bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)

def field(data, sect, key):
    cur = None
    for line in data.splitlines():
        s = line.strip()
        if s[:1] == "[" and s[-1:] == "]":
            cur = s[1:-1]
            continue
        if cur == sect and s.startswith(key + "="):
            return s[len(key) + 1:]
    return None

try:
    objs = bus.call_sync(BUS, MGR, "org.freedesktop.DBus.ObjectManager",
                         "GetManagedObjects", None,
                         GLib.VariantType("(a{oa{sa{sv}}})"),
                         Gio.DBusCallFlags.NONE, 30000, None).unpack()[0]
except Exception as e:
    print("fail\t%s" % e)
    raise SystemExit(1)

sources = {}
for path, ifaces in objs.items():
    s = ifaces.get("org.gnome.evolution.dataserver.Source")
    if s:
        sources[s["UID"]] = (path, s["Data"], set(ifaces))

# uid коллекции -> адрес почты
ident_of = {uid: field(d, "Collection", "Identity")
            for uid, (_p, d, _i) in sources.items()
            if field(d, "Collection", "Identity")}

def name_of(uid):  return field(sources[uid][1], "Data Source", "DisplayName") or uid
def email_of(uid):
    return ident_of.get(field(sources[uid][1], "Data Source", "Parent") or "", "?")
def enabled(uid):  return (field(sources[uid][1], "Data Source", "Enabled") or "true") == "true"

def set_enabled(uid, value):
    path, data, ifaces = sources[uid]
    if "org.gnome.evolution.dataserver.Source.Writable" not in ifaces:
        return False
    out, cur = [], None
    for line in data.splitlines():
        s = line.strip()
        if s[:1] == "[" and s[-1:] == "]":
            cur = s[1:-1]
        elif cur == "Data Source" and s.startswith("Enabled="):
            line = "Enabled=" + ("true" if value else "false")
        out.append(line)
    try:
        bus.call_sync(BUS, path, "org.gnome.evolution.dataserver.Source.Writable",
                      "Write", GLib.Variant("(s)", ("\n".join(out) + "\n",)),
                      None, Gio.DBusCallFlags.NONE, 30000, None)
        return True
    except Exception:
        return False

caldav = [uid for uid, (_p, d, _i) in sources.items()
          if field(d, "Calendar", "BackendName") == "caldav"]

if mode == "undo":
    for uid in caldav:
        if not enabled(uid):
            print("undo\t%s\t%s\t%s" % (name_of(uid), email_of(uid),
                                        "ok" if set_enabled(uid, True) else "fail"))
    raise SystemExit(0)

# группировка по адресу календаря на сервере
groups = {}
for uid in caldav:
    d = sources[uid][1]
    key = field(d, "Resource", "Identity") or \
          ((field(d, "Authentication", "Host") or "") +
           (field(d, "WebDAV Backend", "ResourcePath") or ""))
    if key:
        groups.setdefault(key, []).append(uid)

ROLE = {"owner": 0, "writer": 1, "reader": 2, "freeBusyReader": 3}

def calendar_id(uid):
    """id календаря в Google, вытащенный из пути CalDAV (если он там читаемый)."""
    seg = [x for x in (field(sources[uid][1], "WebDAV Backend", "ResourcePath") or "").split("/") if x]
    return urllib.parse.unquote(seg[-2]) if len(seg) >= 2 and seg[-1] == "events" else ""

def rank(uid):
    """Оставляем тот, где больше прав; при равных — аккаунт выше по списку."""
    email = email_of(uid)
    return (ROLE.get(roles.get((email, calendar_id(uid)), ""), 2),
            order.index(email) if email in order else 99,
            uid)

for uids in groups.values():
    if len(uids) < 2:
        continue
    uids.sort(key=rank)
    keep, drop = uids[0], uids[1:]
    print("dup\t%s\t%d" % (name_of(keep), len(uids)))
    if not enabled(keep):
        set_enabled(keep, True)          # страховка: хоть один должен быть включён
    print("keep\t%s\t%s" % (name_of(keep), email_of(keep)))
    for uid in drop:
        if not enabled(uid):
            state = "already"
        elif mode == "plan":
            state = "plan"
        else:
            state = "ok" if set_enabled(uid, False) else "fail"
        print("drop\t%s\t%s\t%s" % (name_of(uid), email_of(uid), state))
PY
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
    "$LIST_SOURCES" -m -x Calendar 2>/dev/null |
        awk -F'\t' '{ b=""; e="1"
                      for (i=3;i<=NF;i++) {
                          if ($i ~ /^Backend:/) b = substr($i, 9)
                          if ($i ~ /^Enabled:/) e = substr($i, 9)
                      }
                      printf "   %-45s [%s]%s\n", $2, b, (e == "1" ? "" : "  — погашен как повтор") }'
    exit 0
fi

# ---------------------------------------------------------------------------
# --undedup: вернуть все погашенные повторы
# ---------------------------------------------------------------------------
if [ "$UNDEDUP" = 1 ]; then
    head1 "Возврат погашенных повторов"
    n=0
    while IFS=$'\t' read -r kind name email state; do
        case "$kind:$state" in
            undo:ok) ok "включён обратно: «$name»  ($email)"; n=$((n + 1)) ;;
            undo:*)  err "не удалось включить: «$name»  ($email)" ;;
            fail:*)  err "нет связи с реестром источников: $name" ;;
        esac
    done < <(dedup_calendars undo)
    [ "$n" -gt 0 ] && ok "возвращено календарей: $n" || info "погашенных повторов не было"
    exit 0
fi

# ---------------------------------------------------------------------------
# Шаг 1. Аккаунты
# ---------------------------------------------------------------------------
head1 "Шаг 1/5: аккаунты Google"

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
head1 "Шаг 2/5: что говорит Google"

WORK="$(mktemp -d)"
trap 'find "$WORK" -type f -delete 2>/dev/null; rmdir "$WORK" 2>/dev/null' EXIT
MAP="$WORK/map.tsv"; : > "$MAP"

declare -A EXPECTED=()
TOTAL_EXPECTED=0

for email in "${ACCOUNTS[@]}"; do
    id="${ACC_ID[$email]:-}"
    [ -n "$id" ] || continue
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
    printf '%s\t%s\t%s\n' "$email" "$id" "$WORK/$id.json" >> "$MAP"
    ok "$email — календарей у Google: $n"
done

[ "$TOTAL_EXPECTED" -gt 0 ] || die "Google не отдал ни одного списка календарей — проверьте сеть/VPN и авторизацию"

# Сколько календарей ждать в системе с учётом того, что один и тот же календарь
# может быть подписан в нескольких аккаунтах: повтор засчитывается первому.
declare -A EXPECTED_UNIQ=()
TOTAL_UNIQ=0
while IFS=$'\t' read -r email cnt; do
    EXPECTED_UNIQ["$email"]="$cnt"
    TOTAL_UNIQ=$((TOTAL_UNIQ + cnt))
done < <(python3 - "$MAP" "$DEDUP" <<'PY'
import json, os, sys
dedup = sys.argv[2] == "1"
seen = set()
for line in open(sys.argv[1]):
    p = line.rstrip("\n").split("\t")
    if len(p) < 3:
        continue
    email, jf, n = p[0], p[2], 0
    if os.path.exists(jf):
        try:
            for it in json.load(open(jf)).get("items", []):
                cid = it.get("id", "")
                if dedup and cid in seen:
                    continue
                seen.add(cid)
                n += 1
        except Exception:
            pass
    print("%s\t%d" % (email, n))
PY
)

if [ "$TOTAL_EXPECTED" -ne "$TOTAL_UNIQ" ]; then
    info "из них повторов между аккаунтами: $((TOTAL_EXPECTED - TOTAL_UNIQ)) — уникальных календарей: $TOTAL_UNIQ"
fi

if [ "$DRY_RUN" = 1 ]; then
    head1 "--dry-run"
    if [ "$DEDUP" = 1 ]; then
        while IFS=$'\t' read -r kind name email state; do
            case "$kind" in
                dup)  info "«$name» — подписан в $email аккаунтах" ;;
                keep) info "оставить: «$name»  ($email)" ;;
                drop) [ "$state" = already ] && info "уже погашен: «$name»  ($email)" \
                                            || warn "будет погашен: «$name»  ($email)" ;;
            esac
        done < <(dedup_calendars plan "$MAP")
    fi
    warn "службы не перезапускались, повторы не гасились, синхронизация не выполнялась"
    exit 0
fi

# ---------------------------------------------------------------------------
# Шаг 3. Перезапуск служб с повторами, пока календари не появятся
# ---------------------------------------------------------------------------
head1 "Шаг 3/5: возврат календарей в систему"

attempt=0
while :; do
    attempt=$((attempt + 1))
    got_all=1

    for email in "${ACCOUNTS[@]}"; do
        [ -n "${EXPECTED_UNIQ[$email]:-}" ] || continue
        coll="$(collection_uid "$email")"
        have=0
        [ -n "$coll" ] && have="$(eds_calendars_of "$coll" | grep -c . )"
        [ "$have" -ge "${EXPECTED_UNIQ[$email]}" ] || got_all=0
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
# Шаг 4. Повторы одного календаря из разных аккаунтов
# ---------------------------------------------------------------------------
head1 "Шаг 4/5: повторы между аккаунтами"

DEDUPED=0
if [ "$DEDUP" = 0 ]; then
    info "пропущено (--no-dedup)"
else
    while IFS=$'\t' read -r kind name email state; do
        case "$kind" in
            dup)  info "«$name» — подписан в $email аккаунтах" ;;
            keep) ok   "оставлен: «$name»  ($email)" ;;
            drop) case "$state" in
                      ok)      ok "погашен повтор: «$name»  ($email)"; DEDUPED=$((DEDUPED + 1)) ;;
                      already) info "уже погашен: «$name»  ($email)";  DEDUPED=$((DEDUPED + 1)) ;;
                      *)       err "не удалось погасить: «$name»  ($email)" ;;
                  esac ;;
            fail) err "нет связи с реестром источников: $name" ;;
        esac
    done < <(dedup_calendars apply "$MAP")
    [ "$DEDUPED" = 0 ] && info "повторов не найдено"
fi

# Приложение «Календарь» замечает появление и удаление календарей, но не их
# отключение: запущенная копия так и будет рисовать погашенный повтор.
# Гасим её — GNOME запустит заново при открытии окна (это gapplication-service).
if [ "$DEDUPED" -gt 0 ] && pgrep -x gnome-calendar >/dev/null 2>&1; then
    pkill -x gnome-calendar 2>/dev/null
    ok "приложение «Календарь» перезапущено, чтобы список обновился"
fi

# ---------------------------------------------------------------------------
# Шаг 5. Синхронизация
# ---------------------------------------------------------------------------
head1 "Шаг 5/5: синхронизация"

SYNCED=0; FOUND=0
for email in "${ACCOUNTS[@]}"; do
    [ -n "${EXPECTED[$email]:-}" ] || continue
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
printf '   ожидалось календарей     : %s\n' "$TOTAL_UNIQ"
printf '   вернулось в систему      : %s\n' "$FOUND"
printf '   погашено повторов        : %s\n' "$DEDUPED"
printf '   синхронизировано         : %s\n' "$SYNCED"

if [ "$FOUND" -lt "$TOTAL_UNIQ" ]; then
    echo
    warn "часть календарей не поднялась. Что проверить:"
    info "интернет/VPN до google.com и apidata.googleusercontent.com"
    info "Настройки → Онлайн-аккаунты: нет ли значка «требуется вход»"
    info "повторить с бо́льшим числом попыток: $SELF --retries 6"
    info "кэш списка календарей (пропавшие уезжают в trash/): $CACHE_SOURCES"
fi

if [ ${#MISSING[@]} -gt 0 ]; then
    echo
    warn "нет в «Онлайн-аккаунтах» (добавляются только вручную, через браузер):"
    for m in "${MISSING[@]}"; do info "$m"; done
    info "gnome-control-center online-accounts"
fi

echo
info "состояние: $SELF --list"
[ "$DEDUPED" -gt 0 ] && info "вернуть погашенные повторы: $SELF --undedup"
info "если «Календарь» был открыт — откройте окно заново"
