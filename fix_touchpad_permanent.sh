#!/usr/bin/env bash
# PERMANENT FIX для ELAN 04F3:31FD touchpad на MSI Raider 18 HX.
#
# v2: добавлено отключение wakeup на parent i2c-устройстве —
#     по логам wakeup_active_count=7529 за uptime, это и есть
#     ИСТИННЫЙ триггер периодических re-probe. Плюс исправлен синтаксис
#     udev-rule (был неправильный ATTRS{id/vendor}, теперь KERNEL pattern).
#
# Три слоя защиты:
#   1) /etc/modprobe.d/elan-touchpad.conf       — softdep hid_multitouch
#   2) /etc/udev/rules.d/99-elan-touchpad-rebind.rules — auto-rebind на hid-multitouch
#   3) /etc/udev/rules.d/99-elan-touchpad-nowakeup.rules — отключить wakeup
#
# Что НЕ трогает: ядро, grub, fstab, initramfs, NVIDIA, video, fs.
# Откат: ./fix_touchpad_permanent.sh --uninstall

set +e

MODPROBE_CONF=/etc/modprobe.d/elan-touchpad.conf
UDEV_REBIND=/etc/udev/rules.d/99-elan-touchpad-rebind.rules
UDEV_NOWAKE=/etc/udev/rules.d/99-elan-touchpad-nowakeup.rules

if [[ "${1:-}" == "--uninstall" ]]; then
    echo "Удаляю permanent-fix файлы..."
    sudo rm -f "$MODPROBE_CONF" "$UDEV_REBIND" "$UDEV_NOWAKE"
    sudo udevadm control --reload-rules
    # вернём wakeup как было — enabled
    echo enabled | sudo tee /sys/bus/i2c/devices/i2c-CUST0001:00/power/wakeup >/dev/null 2>&1
    echo "Готово. Откат завершён. Перезагрузка не нужна."
    exit 0
fi

if ! sudo -n true 2>/dev/null; then
    echo "Нужен sudo:"
    sudo -v || { echo "sudo не дал прав"; exit 1; }
fi

echo "=== ДО ==="
echo "-- текущий driver тачпада --"
find /sys -path "*0018:04F3:31FD*" -name driver 2>/dev/null | while read p; do
    echo "  $(basename $(dirname $p))  →  $(basename $(readlink $p))"
done
echo "-- wakeup_active_count (это и есть число re-probe!) --"
cat /sys/bus/i2c/devices/i2c-CUST0001:00/power/wakeup 2>&1
cat /sys/bus/i2c/devices/i2c-CUST0001:00/power/wakeup_active_count 2>&1

echo
echo "=== Слой 1: softdep modprobe (уже стоит — проверяю/обновляю) ==="
sudo tee "$MODPROBE_CONF" >/dev/null <<'EOF'
# /etc/modprobe.d/elan-touchpad.conf
# Гарантирует что hid_multitouch грузится ДО i2c_hid_acpi.
# Иначе hid-generic захватит тачпад первым (без BTN_LEFT).
# Откат: rm этот файл.
softdep i2c_hid_acpi pre: hid_multitouch
softdep i2c_hid pre: hid_multitouch
EOF
echo "  ok $MODPROBE_CONF"

echo
echo "=== Слой 2: udev auto-rebind (исправлен синтаксис — KERNEL pattern) ==="
sudo tee "$UDEV_REBIND" >/dev/null <<'EOF'
# /etc/udev/rules.d/99-elan-touchpad-rebind.rules
# Если ELAN 04F3:31FD оказался привязан к hid-generic — переключить
# на hid-multitouch. KERNEL pattern проверен для этого устройства.
# Откат: rm + udevadm control --reload-rules.

ACTION=="bind", SUBSYSTEM=="hid", DRIVER=="hid-generic", KERNEL=="0018:04F3:31FD.*", \
  RUN+="/bin/sh -c 'sleep 0.3; echo %k > /sys/bus/hid/drivers/hid-generic/unbind 2>/dev/null; echo %k > /sys/bus/hid/drivers/hid-multitouch/bind 2>/dev/null'"
EOF
echo "  ok $UDEV_REBIND"

echo
echo "=== Слой 3: udev — отключить wakeup на i2c-CUST0001:00 (НАСТОЯЩИЙ FIX) ==="
sudo tee "$UDEV_NOWAKE" >/dev/null <<'EOF'
# /etc/udev/rules.d/99-elan-touchpad-nowakeup.rules
# По логам wakeup_active_count рос ~2/мин — это и был триггер
# постоянных re-probe ELAN-тачпада. Запрещаем wakeup как источник.
# Тачпад продолжит работать как обычно, просто не будет будить
# систему/делать ACPI-wake.  Откат: rm + reload-rules.

ACTION=="add|change", SUBSYSTEM=="i2c", KERNEL=="i2c-CUST0001:00", \
  ATTR{power/wakeup}="disabled"
EOF
echo "  ok $UDEV_NOWAKE"

echo
echo "=== Применяю немедленно (без ребута) ==="
sudo udevadm control --reload-rules && echo "  ok udev reloaded"
# применить wakeup=disabled на текущее устройство
if [[ -w /sys/bus/i2c/devices/i2c-CUST0001:00/power/wakeup ]] || sudo test -w /sys/bus/i2c/devices/i2c-CUST0001:00/power/wakeup; then
    echo disabled | sudo tee /sys/bus/i2c/devices/i2c-CUST0001:00/power/wakeup >/dev/null
    echo "  ok wakeup=disabled применён live"
fi

echo
echo "=== ПОСЛЕ ==="
echo "-- wakeup state --"
echo "  wakeup     = $(cat /sys/bus/i2c/devices/i2c-CUST0001:00/power/wakeup 2>&1)"
echo "  wakeup_cnt = $(cat /sys/bus/i2c/devices/i2c-CUST0001:00/power/wakeup_active_count 2>&1)  (на этот момент)"
echo "-- driver --"
find /sys -path "*0018:04F3:31FD*" -name driver 2>/dev/null | while read p; do
    echo "  $(basename $(dirname $p))  →  $(basename $(readlink $p))"
done
echo "-- наши файлы --"
ls -la "$MODPROBE_CONF" "$UDEV_REBIND" "$UDEV_NOWAKE" 2>&1

cat <<'TAIL'

=== Что теперь будет ===
• Тачпад больше не получает ACPI wakeup-сигналы → нет периодических
  HID-reset → нет re-probe → не отваливается клик.
• Если всё же re-probe случится — softdep гарантирует что hid_multitouch
  уже в памяти, плюс udev rule подстрахует, если hid-generic захватит.
• wakeup_active_count теперь не должен расти. Проверь через час:
      cat /sys/bus/i2c/devices/i2c-CUST0001:00/power/wakeup_active_count
  Должно быть примерно то же значение что сейчас.
• Если за 30-60 минут ни одного ручного fix_touchpad_2 запуска не нужно —
  значит первопричина устранена. Это и есть permanent fix.

=== ТЕСТ ===
Подвигай тачпадом, тапни, попробуй левый клик. Должно работать.

=== ОТКАТ ===
./fix_touchpad_permanent.sh --uninstall

=== Если всё-таки сломается ===
./fix_touchpad_2_driver.sh   — старый аварийный fix
./watch_touchpad.sh          — лог-сторож, покажет первопричину
TAIL
