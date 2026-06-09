#!/usr/bin/env bash
# Диагностика "тачпад потерял управление мышкой".
# Запустить ОБЫЧНО когда тачпад глючит (или сразу после восстановления).
# sudo нужен только для dmesg/modprobe. journalctl у тебя пускается без sudo.

set +e

sep() { printf '\n=== %s ===\n' "$*"; }

sep "uptime / load"
uptime
cat /proc/loadavg

sep "kernel dmesg (последние 80 строк, фильтр input/nvidia/i2c)"
sudo dmesg -T 2>/dev/null | tail -200 \
  | grep -iE "i2c_hid|elan|31FD|hid_multi|psmouse|NVRM|nvidia|nouveau|pcieport|reset|timeout|hang" \
  | tail -80

sep "journalctl -k за час: i2c_hid / elan / nvidia / pcieport"
journalctl -k --since "1 hour ago" --no-pager 2>/dev/null \
  | grep -iE "i2c_hid|elan|31FD|hid_multi|NVRM|nvidia|pcieport|reset|timeout" \
  | tail -60

sep "input devices (тачпад/мышь)"
grep -A2 -iE "touchpad|mouse|elan|04F3" /proc/bus/input/devices

sep "загруженные HID/NVIDIA модули"
lsmod | grep -iE "^(i2c_hid|hid_multi|nvidia|psmouse)" | head

sep "nvidia-smi (если драйвер жив)"
nvidia-smi --query-gpu=index,name,pstate,utilization.gpu,memory.used --format=csv 2>&1 | head -10

sep "whisper-linux: запущен?"
pgrep -af "whisper-linux|whisper-cli" | head

sep "TOP-10 CPU / GPU-tasks"
ps -eo pid,pcpu,pmem,comm --sort=-pcpu | head -11

cat <<'TAIL'

=== Подсказки ===
Если в dmesg/journalctl есть строки "i2c_hid_acpi i2c-... not responding"
или "ELAN ... reset" — это драйвер тачпада подвис, лечится без ребута:
    sudo modprobe -r i2c_hid_acpi i2c_hid && sudo modprobe i2c_hid_acpi

Если ничего такого нет, но nvidia-smi падает или NVRM спамит — фриз
курсора это композитор Mutter/Wayland на проблемном NVIDIA-драйвере,
тачпад тут не виноват (см. guide_monitor_nvidia.md в memory).
TAIL
