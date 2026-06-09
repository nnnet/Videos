#!/usr/bin/env bash
# Permanent fix для stuck-mouse-button bug в X11.
# v2 (2026-05-15): refactor — recovery теперь через xinput disable/enable,
# не через restart gnome-shell. gnome-shell restart НЕ сбрасывает X server
# pointer state — stuck button просто переходит на следующее окно. Нужен
# reset именно на уровне X input device.
#
# Что делает:
#   1. Устанавливает recovery script /usr/local/bin/pointer-recover (xinput cycle)
#   2. Привязывает Ctrl+Alt+M к нему через GNOME custom-keybinding
#   3. Опционально отключает ding extension (если хочешь)
#
# Запускать из своей user-сессии (НЕ через sudo — gsettings нужны user-DBUS).
# Откат:  ./fix_touchpad_4_gnome_recovery.sh --revert
#
# Tested на: Ubuntu 24.04, GNOME 46, X11.

set +e

KB_PATH="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/gnome-shell-recover/"
KB_SCHEMA="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding"
RECOVER_BIN="$HOME/.local/bin/pointer-recover"

if [[ "${1:-}" == "--revert" ]]; then
    echo "=== Откат ==="
    gnome-extensions enable ding@rastersoft.com 2>/dev/null
    OLD_LIST=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings)
    NEW_LIST=$(echo "$OLD_LIST" | sed "s|'$KB_PATH'||; s|, ,|,|g; s|\[, |[|; s|, \]|]|")
    if [[ "$NEW_LIST" == "[]" ]] || [[ "$NEW_LIST" == "[ ]" ]]; then
        gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "@as []"
    else
        gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$NEW_LIST"
    fi
    rm -f "$RECOVER_BIN"
    echo "  ok откат завершён"
    exit 0
fi

if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
    echo "ERROR: DBUS_SESSION_BUS_ADDRESS пуст. Запускай из своей GUI-сессии (не через sudo / не из ssh)."
    exit 1
fi

echo "=== Шаг 1: ставлю recovery скрипт ==="
mkdir -p "$(dirname $RECOVER_BIN)"
cat > "$RECOVER_BIN" <<'EOF'
#!/usr/bin/env bash
# Pointer state recovery — сбрасывает stuck BTN_LEFT/RIGHT/MIDDLE на ВСЕХ
# pointer-устройствах через xinput disable/enable cycle.
#
# Почему именно так:
#   - xdotool mouseup посылает synthetic release, но если X server's pointer
#     state думает что button уже released — он ignor'ит. Stuck state остаётся.
#   - gnome-shell restart перезапускает только compositor; X11 pointer device
#     state остаётся stuck.
#   - xinput disable полностью отключает device → X сбрасывает все его state.
#   - xinput enable заново регистрирует device с чистым state.
#
# Делается для ВСЕХ slave pointer'ов, не только тачпада — чтобы USB-мыши тоже
# освобождались, если их состояние тоже застряло.

set +e
DELAY=0.3

# Найти все slave pointer devices (исключая floating / virtual core)
SLAVES=$(xinput --list --id-only 2>/dev/null | while read id; do
    info=$(xinput --list "$id" 2>/dev/null)
    case "$info" in
        *"slave  pointer"*) echo "$id" ;;
    esac
done)

if [[ -z "$SLAVES" ]]; then
    notify-send -t 3000 "Pointer recover" "Не нашёл slave pointer devices" 2>/dev/null
    exit 1
fi

# Disable все, sleep, enable все обратно
for id in $SLAVES; do
    xinput disable "$id" 2>/dev/null
done
sleep "$DELAY"
for id in $SLAVES; do
    xinput enable "$id" 2>/dev/null
done

# Подстраховка: после re-enable явно посылаем button releases
sleep 0.1
for btn in 1 2 3; do
    xdotool mouseup $btn 2>/dev/null
done

notify-send -t 2000 "Pointer recovered" "Reset $(echo "$SLAVES" | wc -l) pointer devices" 2>/dev/null
EOF
chmod +x "$RECOVER_BIN"
echo "  ok $RECOVER_BIN"

echo
echo "=== Шаг 2: привязываю Ctrl+Alt+M к recovery ==="
CURRENT=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings)
if [[ "$CURRENT" != *"$KB_PATH"* ]]; then
    if [[ "$CURRENT" == "@as []" ]] || [[ "$CURRENT" == "[]" ]]; then
        NEW="['$KB_PATH']"
    else
        NEW="${CURRENT%]}, '$KB_PATH']"
    fi
    gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$NEW"
    echo "  ok добавил $KB_PATH в custom-keybindings"
else
    echo "  ok $KB_PATH уже в списке"
fi
gsettings set "$KB_SCHEMA:$KB_PATH" name "Pointer Recover (Stuck Mouse Fix)"
gsettings set "$KB_SCHEMA:$KB_PATH" command "$RECOVER_BIN"
gsettings set "$KB_SCHEMA:$KB_PATH" binding '<Control><Alt>m'
echo "  ok Ctrl+Alt+M → $RECOVER_BIN"

echo
echo "=== Шаг 3 (опционально): отключить Desktop Icons NG (ding) ==="
echo "ding — известный триггер pointer-grab бага на X11."
echo "Сейчас:  $(gnome-extensions info ding@rastersoft.com 2>/dev/null | grep '^  State:' || echo 'не установлен')"
read -rp "Отключить ding? [y/N] " ANS
if [[ "$ANS" =~ ^[Yy]$ ]]; then
    gnome-extensions disable ding@rastersoft.com 2>&1 && echo "  ok ding отключён"
else
    echo "  пропускаю"
fi

echo
echo "=== ПОСЛЕ ==="
echo "  recovery script      = $RECOVER_BIN"
echo "  Ctrl+Alt+M shortcut  = $(gsettings get $KB_SCHEMA:$KB_PATH binding) → $(gsettings get $KB_SCHEMA:$KB_PATH command)"
echo "  ding extension       = $(gnome-extensions info ding@rastersoft.com 2>/dev/null | grep State || echo '?')"

cat <<'TAIL'

=== Тест recovery (сделать СЕЙЧАС, пока ничего не залипло) ===
1. Нажми Ctrl+Alt+M
2. На пол-секунды курсор/тачпад замрут (xinput disable cycle)
3. Через 1 сек всё работает + notification "Pointer recovered"
Это подтвердит что recovery работает.

=== Если стряслось (stuck-button) ===
Нажми Ctrl+Alt+M один раз. За 0.5-1 сек stuck state будет сброшен на X11 уровне.

Если Ctrl+Alt+M не сработал (gnome-shell заморожен сам):
  Ctrl+Alt+F3       → TTY
  Ctrl+Alt+F1       → обратно
VT switch заставит X сбросить input device state на kernel-X уровне.

Если и это не помогло (X server hung):
  Ctrl+Alt+F3 → login → sudo systemctl restart gdm
(перезапустит сессию)

=== Откат всего ===
./fix_touchpad_4_gnome_recovery.sh --revert
TAIL
