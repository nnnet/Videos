#!/usr/bin/env bash
# Touchpad настройки которые применяются из user-сессии (gsettings).
# v3 (2026-05-15): убрал click-method=none — в GNOME 46/libinput 1.25 это
#                  ломает tap-to-click (подтверждено эмпирически на MSI Raider).
#                  Оставляю click-method=default и tap-and-drag-lock=true.
#
# Sandbox claude-кода не пробрасывает DBUS_SESSION_BUS_ADDRESS, поэтому
# эти команды нужно запускать из своего терминала, не через chat.
#
# Идемпотентно — можно запускать сколько угодно раз.
# Откат:  ./fix_touchpad_3_user_settings.sh --revert

set +e

SCHEMA="org.gnome.desktop.peripherals.touchpad"

if [[ "${1:-}" == "--revert" ]]; then
    echo "=== Откатываю user-настройки тачпада к defaults ==="
    gsettings set "$SCHEMA" tap-and-drag-lock false
    gsettings set "$SCHEMA" click-method 'default'
    echo "  ok"
    echo "  tap-and-drag-lock = $(gsettings get $SCHEMA tap-and-drag-lock)"
    echo "  click-method      = $(gsettings get $SCHEMA click-method)"
    exit 0
fi

echo "=== ДО ==="
echo "  tap-to-click      = $(gsettings get $SCHEMA tap-to-click)"
echo "  tap-and-drag      = $(gsettings get $SCHEMA tap-and-drag)"
echo "  tap-and-drag-lock = $(gsettings get $SCHEMA tap-and-drag-lock)"
echo "  click-method      = $(gsettings get $SCHEMA click-method)"

echo
echo "=== Применяю ==="

# tap-to-click — основной режим клика для нашего сценария
if [[ "$(gsettings get $SCHEMA tap-to-click)" != "true" ]]; then
    gsettings set "$SCHEMA" tap-to-click true
    echo "  ok tap-to-click = true"
fi

# tap-and-drag — должно быть включено для drag-операций
if [[ "$(gsettings get $SCHEMA tap-and-drag)" != "true" ]]; then
    gsettings set "$SCHEMA" tap-and-drag true
    echo "  ok tap-and-drag = true"
fi

# tap-and-drag-lock — drag не разрывается посреди hold (фикс Telegram-микрофон).
# Side effect: drag завершается только tap-out'ом или timeout'ом, не lift'ом.
gsettings set "$SCHEMA" tap-and-drag-lock true
echo "  ok tap-and-drag-lock = true"

# click-method — ВНИМАНИЕ: 'none' в GNOME 46 ломает tap-to-click. Оставляем 'default'.
# Если кто-то ранее поставил 'none' — починим обратно.
CURRENT_CM=$(gsettings get $SCHEMA click-method)
if [[ "$CURRENT_CM" != "'default'" ]]; then
    gsettings set "$SCHEMA" click-method 'default'
    echo "  ok click-method = 'default' (было $CURRENT_CM — починил)"
fi

echo
echo "=== ПОСЛЕ ==="
echo "  tap-to-click      = $(gsettings get $SCHEMA tap-to-click)"
echo "  tap-and-drag      = $(gsettings get $SCHEMA tap-and-drag)"
echo "  tap-and-drag-lock = $(gsettings get $SCHEMA tap-and-drag-lock)"
echo "  click-method      = $(gsettings get $SCHEMA click-method)"

cat <<'TAIL'

=== Что теперь ===
• tap (1 палец, короткое касание)              → левый клик
• 2-finger tap                                  → правый клик
• 3-finger tap                                  → средний клик
• double-tap + удержание + движение             → drag, НЕ разрывается
• физическое нажатие clickpad                   → левый клик (default behavior)

=== Если что-то пошло не так — откат ===
./fix_touchpad_3_user_settings.sh --revert
TAIL
