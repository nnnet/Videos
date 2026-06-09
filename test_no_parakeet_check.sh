#!/usr/bin/env bash
# Проверка результата эксперимента: были ли re-probe тачпада за время
# когда parakeet был остановлен.

set +e

if ! sudo -n true 2>/dev/null; then
    sudo -v || exit 1
fi

if [[ ! -f /tmp/test_no_parakeet.t0 ]]; then
    echo "Не вижу /tmp/test_no_parakeet.t0 — сначала запусти ./test_no_parakeet.sh"
    exit 1
fi

T0=$(cat /tmp/test_no_parakeet.t0)
T_NOW=$(date +%s)
ELAPSED_MIN=$(( (T_NOW - T0) / 60 ))
T0_STR=$(date -d "@$T0" '+%Y-%m-%d %H:%M:%S')
T_NOW_STR=$(date '+%Y-%m-%d %H:%M:%S')

echo "=== Окно эксперимента ==="
echo "  Старт:    $T0_STR"
echo "  Сейчас:   $T_NOW_STR"
echo "  Прошло:   $ELAPSED_MIN минут"
echo

if [[ "$ELAPSED_MIN" -lt 20 ]]; then
    echo "ВНИМАНИЕ: прошло меньше 20 минут. Лучше подождать ещё."
fi

echo "=== parakeet/whisper всё ещё остановлены? ==="
ALIVE=$(pgrep -af "parakeet|whisper-linux|nemo.collections" 2>/dev/null)
if [[ -z "$ALIVE" ]]; then
    echo "ОК — никто не запущен."
else
    echo "ВНИМАНИЕ — parakeet/whisper снова работает:"
    echo "$ALIVE"
    echo "Эксперимент испорчен. Если хочешь повторить — снова прибей и подожди 30 мин."
fi

echo
echo "=== Re-probe тачпада за окно эксперимента ==="
SINCE="@$T0"
COUNT=$(sudo journalctl -k --since "$T0_STR" --no-pager 2>/dev/null \
        | grep "04F3:31FD.*hidraw0" | wc -l)
echo "Найдено re-probe: $COUNT"
echo "(Помни: каждый re-probe = ~2 строки 'hidraw0', т.к. сначала hid-generic, потом hid-multitouch)"
echo
echo "--- сами строки ---"
sudo journalctl -k --since "$T0_STR" --no-pager 2>/dev/null \
    | grep "04F3:31FD.*hidraw0" | head -20

echo
echo "=== Touch-jump warnings от libinput за окно ==="
sudo journalctl --since "$T0_STR" --no-pager 2>/dev/null \
    | grep -iE "touch.?jump|jumping cursor" | head -10

echo
echo "=== GPU состояние сейчас ==="
nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv 2>&1 | head -3

cat <<'TAIL'

=== ИНТЕРПРЕТАЦИЯ ===
• Re-probe = 0 (или 1-2 за 30 минут):
    → Виноват parakeet/CUDA-нагрузка. Варианты:
       - переключить parakeet на CPU (медленнее, но без NVIDIA)
       - использовать whisper.cpp с CPU/Vulkan backend
       - смириться, использовать hotkey-fix
• Re-probe ≥ 3 за 30 минут даже без parakeet:
    → Виновата сама прошивка ELAN (firmware bug). Тогда:
       - udev rule на авто-фикс после каждого re-probe (могу сделать)
       - попробовать обновить BIOS/EC firmware (через fwupdmgr)
       - попробовать boot-параметр для i2c_hid_acpi
TAIL
