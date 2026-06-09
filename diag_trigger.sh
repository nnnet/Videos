#!/usr/bin/env bash
# Ищем ТРИГГЕР re-probe ELAN. Каждые 2-3ч тачпад отваливается от
# i2c-шины и подцепляется заново. Хотим увидеть что было ПРЯМО ПЕРЕД этим.
#
# Фокус — окно [-90s … +5s] от первого re-probe 13 мая 19:40:36.

set +e

if ! sudo -n true 2>/dev/null; then
    echo "Нужен sudo:"
    sudo -v || { echo "sudo не дал прав"; exit 1; }
fi

sep() { printf '\n========== %s ==========\n' "$*"; }

sep "1. KERNEL за 90 сек ДО первого re-probe (19:39:06 → 19:40:36, 13 мая)"
echo "Тут должен быть триггер. Ищем pcieport / aer / nvidia / i2c / acpi / xhci."
sudo journalctl -k --since "2026-05-13 19:39:06" --until "2026-05-13 19:40:36" --no-pager 2>/dev/null \
  | grep -vE "NVRM: dispcmnCtrlCmdSystemGetVblankCounter" \
  | tail -100

sep "2. KERNEL за 90 сек ДО второго re-probe (22:12:40 → 22:14:10, 13 мая)"
sudo journalctl -k --since "2026-05-13 22:12:40" --until "2026-05-13 22:14:10" --no-pager 2>/dev/null \
  | grep -vE "NVRM: dispcmnCtrlCmdSystemGetVblankCounter" \
  | tail -100

sep "3. USERLAND за 60 сек ДО первого re-probe (что запускалось/останавливалось)"
sudo journalctl --since "2026-05-13 19:39:36" --until "2026-05-13 19:40:36" --no-pager 2>/dev/null \
  | grep -vE "kernel:|gnome-shell\[|Xorg|gsd-|gjs|gnome-session" \
  | tail -50

sep "4. ВСЕ моменты re-probe ELAN за 2 дня (история частоты)"
sudo journalctl -k --since "2 days ago" --no-pager 2>/dev/null \
  | grep "04F3:31FD.*hidraw0" \
  | awk '{print $1, $2, $3}' \
  | sort -u

sep "5. GPE-счётчики (ACPI events) — кто чаще всего"
# формат файла: '   N     EN/dis     invalid/active     masked/unmasked'
# берём только первое число
for f in /sys/firmware/acpi/interrupts/gpe[0-9A-F]*; do
    n=$(awk '{print $1+0}' "$f" 2>/dev/null)
    [[ -n "$n" && "$n" -gt 100 ]] && printf '%-12s %d\n' "$(basename "$f")" "$n"
done | sort -k2 -n -r | head -15

sep "6. /proc/interrupts — топ по суммам (без CPU-колонок)"
awk 'NR==1{print "         IRQ        DEVICE"; next} {
    sum=0; for(i=2;i<=NF;i++) if($i ~ /^[0-9]+$/) sum+=$i; else break;
    rest=""; for(j=i;j<=NF;j++) rest = rest " " $j;
    printf "%12d  %s %s\n", sum, $1, rest
}' /proc/interrupts | sort -n -r | head -12

sep "7. ELAN i2c устройство сейчас"
DEV=$(find /sys/bus/i2c/devices -name "*CUST0001*" 2>/dev/null | head -1)
echo "device: $DEV"
echo "--- driver: $(readlink "$DEV"/driver 2>/dev/null | xargs basename) ---"
echo "--- состояние ---"
for f in runtime_status control runtime_usage wakeup_count; do
    v=$(cat "$DEV/power/$f" 2>/dev/null)
    printf "  %-22s = %s\n" "$f" "$v"
done

sep "8. PCI link состояние i2c_designware (через который сидит тачпад)"
# i2c-designware.0 живёт на 0000:80:15.0 (из логов)
lspci -vvv -s 0000:80:15.0 2>&1 | grep -iE "LnkSta|LnkCtl|ASPM|DevSta|Status:" | head -10
echo "---"
echo "ASPM политика системная:"
cat /sys/module/pcie_aspm/parameters/policy 2>&1

sep "9. parakeet / whisper / любые транскрибаторы СЕЙЧАС"
pgrep -af "parakeet|whisper|nemo|ggml|llama-server|ollama" | head -10

sep "10. processes которые держат /dev/snd/* (микрофон → транскрибатор)"
sudo fuser /dev/snd/* 2>&1 | head

cat <<'TAIL'

=== ЧТО ИСКАТЬ В ВЫВОДЕ ===

В блоках 1 и 2 (kernel за 90с ДО re-probe), смотрим на:
  • "pcieport ... AER" / "Corrected error" / "Link Training"
       → PCIe link сбоит, переподцеплен сам i2c_designware.0
  • "i2c_designware" + "transfer.*error" / "scl" / "sda"
       → проблема I2C-шины (electrical glitch, например от close GPU)
  • "ACPI Error" / "GPE" / "_PSx"
       → ACPI-методы пинают устройство
  • "nvidia ... TIMESLICE" / "fault" / большой gap в логе
       → NVIDIA-driver упал именно в этот момент
  • Если ПЕРЕД re-probe — ТИШИНА (нет ничего за 90 сек)
       → триггер не в ядре, а в userland: смотрим блок 3

В блоке 3 (userland):
  • parakeet/whisper start/stop вокруг времени
  • любой systemd unit что стартанул/остановился

Блок 4 покажет полную история re-probe — сколько их всего, ритм.

Блок 5 — если GPE-N сильно лидирует (десятки тысяч в сутки),
это указывает на конкретный EC interrupt (часто связан с PCIe/USB).
TAIL
