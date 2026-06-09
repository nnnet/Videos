#!/usr/bin/env bash
# ШАГ 2 — перезагрузить ТОЛЬКО драйвер тачпада.
# Что трогается: модули i2c_hid_acpi, i2c_hid, hid_multitouch.
# Что НЕ трогается: клавиатура (отдельный USB-HID стек), видео, NVIDIA, fs, всё остальное.
#
# Во время выполнения тачпад на ~1 секунду исчезнет и появится заново.
# Клавиатура продолжит работать. Если тачпад не вернётся — поможет ребут,
# никаких permanent изменений скрипт не делает.

set +e

if ! sudo -n true 2>/dev/null; then
    echo "Нужен sudo. Введи пароль:"
    sudo -v || { echo "sudo не дал прав, выхожу"; exit 1; }
fi

echo
echo "==============================================================="
echo " ВНИМАНИЕ: сейчас на 1 секунду пропадёт тачпад. Клавиатура жива."
echo " Скрипт безопасный, ничего permanent не пишет. Continue? [y/N]"
echo "==============================================================="
# read -r ans
# [[ "$ans" != "y" && "$ans" != "Y" && "$ans" != "д" ]] && { echo "Отмена."; exit 0; }

echo
echo "=== ДО ==="
echo "-- lsmod (i2c_hid / hid_multitouch) --"
lsmod | grep -E "^(i2c_hid|hid_multitouch)" | head
echo "-- touchpad в /proc/bus/input/devices --"
grep -B1 -A2 "04F3:31FD Touchpad" /proc/bus/input/devices | head -10

echo
echo "=== Выгружаю модули (в правильном порядке: top → bottom) ==="
sudo modprobe -r hid_multitouch 2>&1 && echo "  ok hid_multitouch removed"  || echo "  warn: hid_multitouch (возможно не загружен)"
sudo modprobe -r i2c_hid_acpi   2>&1 && echo "  ok i2c_hid_acpi removed"    || echo "  warn: i2c_hid_acpi"
sudo modprobe -r i2c_hid        2>&1 && echo "  ok i2c_hid removed"         || echo "  warn: i2c_hid"

sleep 1

echo
echo "=== Загружаю обратно (i2c_hid_acpi вытянет i2c_hid; hid_multitouch подцепит udev) ==="
sudo modprobe i2c_hid_acpi 2>&1 && echo "  ok i2c_hid_acpi loaded"
sleep 1
# на всякий случай явно
sudo modprobe hid_multitouch 2>&1 && echo "  ok hid_multitouch loaded"

sleep 1

echo
echo "=== ПОСЛЕ ==="
echo "-- lsmod --"
lsmod | grep -E "^(i2c_hid|hid_multitouch)" | head
echo "-- touchpad в /proc/bus/input/devices --"
grep -B1 -A2 "04F3:31FD Touchpad" /proc/bus/input/devices | head -10
echo "-- dmesg хвост (последние 20 строк ядра) --"
sudo dmesg -T 2>/dev/null | tail -20

cat <<'TAIL'

=== ТЕСТ ===
Сейчас попробуй:
  1) тап одним пальцем  → должен быть клик
  2) физическое нажатие на тачпад (нижний край вдавить) → клик

Если кликает — всё ок.
Если ТАЧПАД ИСЧЕЗ и не появился (нет строки "04F3:31FD Touchpad" в "ПОСЛЕ"):
  - НЕ ПАНИКА, ничего permanent не сломано.
  - Клавиатурой логнись в TTY (Ctrl+Alt+F3) и сделай ребут:
        sudo reboot
  - После ребута тачпад точно вернётся, модуль грузится на boot.

Если двигается, но всё равно не кликает — это уже не драйвер.
Тогда проблема в compositor: перезайти в GNOME-сессию (Log out → Log in)
или Ctrl+Alt+F3 → `loginctl terminate-user $USER` → залогиниться обратно.
TAIL
