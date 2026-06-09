#!/usr/bin/env bash
# Эксперимент: остановить parakeet/whisper и наблюдать 30 минут,
# будут ли re-probe тачпада БЕЗ нагрузки на CUDA.

set +e

if ! sudo -n true 2>/dev/null; then
    sudo -v || { echo "sudo не дал прав"; exit 1; }
fi

T0=$(date +%s)
echo "=== T0 = $(date '+%Y-%m-%d %H:%M:%S') ==="

echo
echo "=== Текущие процессы parakeet/whisper ==="
pgrep -af "parakeet|whisper|nemo.collections" 2>&1 | head -10
echo
echo "=== Текущий держатель микрофона ==="
sudo fuser /dev/snd/* 2>&1 | head -5

echo
echo "=== Останавливаю parakeet/whisper ==="
PIDS=$(pgrep -f "parakeet|whisper-linux|nemo.collections.asr" 2>/dev/null)
if [[ -z "$PIDS" ]]; then
    echo "ничего не найдено"
else
    echo "найдены PID: $PIDS"
    # сначала SIGTERM, через 3 секунды SIGKILL если живы
    kill $PIDS 2>&1
    sleep 3
    REMAINING=$(pgrep -f "parakeet|whisper-linux|nemo.collections.asr" 2>/dev/null)
    if [[ -n "$REMAINING" ]]; then
        echo "ещё живы: $REMAINING — посылаю SIGKILL"
        kill -9 $REMAINING 2>&1
        sleep 1
    fi
fi

echo
echo "=== Проверка: parakeet/whisper остановлены? ==="
pgrep -af "parakeet|whisper-linux|nemo.collections" 2>&1 | head
echo "--- держатели /dev/snd/* теперь ---"
sudo fuser /dev/snd/* 2>&1 | head -5

echo
echo "=== GPU состояние (parakeet должен освободить VRAM) ==="
nvidia-smi --query-gpu=index,utilization.gpu,memory.used --format=csv 2>&1 | head -5

echo
echo "=== Запоминаю момент старта эксперимента: $(date '+%H:%M:%S') ==="
echo "$T0" > /tmp/test_no_parakeet.t0
echo "Через 30 минут запусти:  ./test_no_parakeet_check.sh"
echo "Он покажет были ли re-probe тачпада за это время."

cat <<'TAIL'

=== ВАЖНО ===
• Транскрибация голоса в Claude Code/whisper.youtube СЕЙЧАС работать не будет.
• Если parakeet нужен — потом перезапусти его как обычно (через тот же
  whisper.youtube wrapper или его автостарт).
• Эксперимент займёт 30 минут. Можешь работать как обычно (но не запускать
  транскрибацию).
TAIL
