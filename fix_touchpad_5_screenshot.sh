#!/usr/bin/env bash
# Permanent fix для GNOME screenshot stuck-mouse bug.
# v2 (2026-05-15): заменено flameshot → maim+slop+xclip.
#   Причина: flameshot имеет проблему с Enter (не save'ит при нажатии).
#   maim+slop: CLI-инструмент, slop рисует selection rectangle сам через
#   minimal X primitives, БЕЗ X11 grab UI → не страдает от GNOME pointer-grab бага.
#
# Воспроизводимый триггер stuck-mouse: GNOME screenshot UI (<Shift>Print / Print).
# Workaround: заменить Print-shortcut на maim wrapper.
#
# Что делает:
#   1. Создаёт ~/.local/bin/screenshot-area     (slop selection → maim → ~/Pictures/Screenshots/)
#   2. Создаёт ~/.local/bin/screenshot-full     (full screen → ~/Pictures/Screenshots/)
#   3. Отключает GNOME show-screenshot-ui и screenshot keybindings
#   4. Bind Print → screenshot-area
#   5. Bind <Shift>Print → screenshot-full
#
# Видеозапись экрана через GNOME (Ctrl+Shift+Alt+R) НЕ трогается — она через
# другой код-path не страдает от pointer-grab бага.
#
# Запускать из своей user-сессии (НЕ через sudo).
# Откат: ./fix_touchpad_5_screenshot.sh --revert

set +e

GS_KEYS="org.gnome.shell.keybindings"

CKB_PATH_AREA="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/screenshot-area/"
CKB_PATH_FULL="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/screenshot-full/"
CKB_SCHEMA="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding"

SCREENSHOT_DIR="$HOME/Pictures/Screenshots"
BIN_AREA="$HOME/.local/bin/screenshot-area"
BIN_FULL="$HOME/.local/bin/screenshot-full"

if [[ "${1:-}" == "--revert" ]]; then
    echo "=== Откат screenshot настроек ==="
    gsettings reset $GS_KEYS show-screenshot-ui 2>/dev/null
    gsettings reset $GS_KEYS screenshot 2>/dev/null
    # Удалить custom-keybindings (и старые flameshot если были, и новые)
    OLD_LIST=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings)
    NEW_LIST=$(echo "$OLD_LIST" \
        | sed "s|'$CKB_PATH_AREA'||g; s|'$CKB_PATH_FULL'||g; s|'/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/flameshot-gui/'||g; s|'/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/flameshot-full/'||g" \
        | sed "s|, ,|,|g; s|\[, |[|; s|, \]|]|; s|, |, |g")
    if [[ "$NEW_LIST" == "[]" ]] || [[ "$NEW_LIST" == "[ ]" ]]; then
        gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "@as []"
    else
        gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$NEW_LIST"
    fi
    rm -f "$BIN_AREA" "$BIN_FULL"
    echo "  ok откат завершён"
    exit 0
fi

if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
    echo "ERROR: DBUS_SESSION_BUS_ADDRESS пуст. Запускай из своей GUI-сессии."
    exit 1
fi

for tool in maim slop xclip; do
    if ! command -v $tool >/dev/null 2>&1; then
        echo "ERROR: $tool не установлен. Выполни: sudo apt install maim slop xclip"
        exit 1
    fi
done

mkdir -p "$SCREENSHOT_DIR" "$HOME/.local/bin"

echo "=== Шаг 1: создаю wrapper-скрипты ==="

cat > "$BIN_AREA" <<EOF
#!/usr/bin/env bash
# Selection screenshot: slop draws rectangle → maim captures → clipboard + file.
# slop НЕ использует X11 pointer-grab UI как GNOME overlay → нет stuck-mouse bug.
DIR="$SCREENSHOT_DIR"
FILE="\$DIR/Screenshot_\$(date +%Y%m%d_%H%M%S).png"
mkdir -p "\$DIR"
# slop -f "%g" → geometry; maim -g \$geometry; -B чтобы зачитать также фокусный border
if ! GEOM=\$(slop -f "%g" -t 0 -b 2 -c "1,0.5,0,0.7" 2>/dev/null); then
    notify-send -t 2000 "Screenshot" "Cancelled" 2>/dev/null
    exit 0
fi
maim -g "\$GEOM" "\$FILE" 2>/dev/null
if [[ -s "\$FILE" ]]; then
    xclip -selection clipboard -t image/png -i < "\$FILE"
    notify-send -t 3000 "Screenshot saved" "\$FILE\nCopied to clipboard" -i "\$FILE" 2>/dev/null
fi
EOF
chmod +x "$BIN_AREA"
echo "  ok $BIN_AREA"

cat > "$BIN_FULL" <<EOF
#!/usr/bin/env bash
# Fullscreen screenshot → clipboard + file.
DIR="$SCREENSHOT_DIR"
FILE="\$DIR/Screenshot_\$(date +%Y%m%d_%H%M%S)_full.png"
mkdir -p "\$DIR"
maim "\$FILE" 2>/dev/null
if [[ -s "\$FILE" ]]; then
    xclip -selection clipboard -t image/png -i < "\$FILE"
    notify-send -t 3000 "Full screenshot saved" "\$FILE\nCopied to clipboard" -i "\$FILE" 2>/dev/null
fi
EOF
chmod +x "$BIN_FULL"
echo "  ok $BIN_FULL"

echo
echo "=== Шаг 2: отключаю встроенные GNOME screenshot key-bindings ==="
gsettings set $GS_KEYS show-screenshot-ui "@as []"
gsettings set $GS_KEYS screenshot "@as []"
echo "  ok show-screenshot-ui и screenshot keys опустошены"

echo
echo "=== Шаг 3: bind Print → screenshot-area, <Shift>Print → screenshot-full ==="
CURRENT=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings)
for path in "$CKB_PATH_AREA" "$CKB_PATH_FULL"; do
    if [[ "$CURRENT" != *"$path"* ]]; then
        if [[ "$CURRENT" == "@as []" ]] || [[ "$CURRENT" == "[]" ]]; then
            NEW="['$path']"
        else
            NEW="${CURRENT%]}, '$path']"
        fi
        gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$NEW"
        CURRENT="$NEW"
    fi
done

gsettings set "$CKB_SCHEMA:$CKB_PATH_AREA" name "Area Screenshot (maim+slop)"
gsettings set "$CKB_SCHEMA:$CKB_PATH_AREA" command "$BIN_AREA"
gsettings set "$CKB_SCHEMA:$CKB_PATH_AREA" binding 'Print'
echo "  ok Print → $BIN_AREA"

gsettings set "$CKB_SCHEMA:$CKB_PATH_FULL" name "Full Screenshot (maim)"
gsettings set "$CKB_SCHEMA:$CKB_PATH_FULL" command "$BIN_FULL"
gsettings set "$CKB_SCHEMA:$CKB_PATH_FULL" binding '<Shift>Print'
echo "  ok <Shift>Print → $BIN_FULL"

echo
echo "=== ПОСЛЕ ==="
echo "  Print          → $(gsettings get $CKB_SCHEMA:$CKB_PATH_AREA command)"
echo "  <Shift>Print   → $(gsettings get $CKB_SCHEMA:$CKB_PATH_FULL command)"
echo "  Screenshots в  → $SCREENSHOT_DIR"

cat <<'TAIL'

=== ТЕСТ ===
1. Нажми Print → курсор станет +, выдели прямоугольник МЫШЬЮ
   - drag — выбор области
   - ESC во время slop — отмена
   - Lift mouse — capture
2. Файл сохранится в ~/Pictures/Screenshots/ + копия в clipboard
3. <Shift>Print — fullscreen без selection
4. STUCK-MOUSE НЕ ДОЛЖНО БЫТЬ — slop рисует rectangle сам, без X11 pointer-grab UI

=== Видеозапись экрана ===
Встроенная GNOME запись экрана (Ctrl+Shift+Alt+R) НЕ трогалась — работает как раньше.
Если хочешь её отключить тоже (она тоже может grab'ить):
  gsettings set org.gnome.shell.keybindings show-screen-recording-ui "@as []"

=== Откат ===
./fix_touchpad_5_screenshot.sh --revert
TAIL
