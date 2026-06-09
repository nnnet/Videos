#!/usr/bin/env bash
# Сторож тачпада. Слушает kernel-журнал и сохраняет 30 секунд
# kernel-сообщений ПЕРЕД каждым re-probe ELAN 04F3:31FD.
# Через час работы покажет, что именно вызывает HID-reset.
#
# Запуск: ./watch_touchpad.sh
# Стоп:   Ctrl+C
# Логи:   /tmp/touchpad-watch-YYYY-MM-DD.log

set +e

LOG=/tmp/touchpad-watch-$(date +%F).log
SNAP=/tmp/touchpad-watch-snap.txt

echo "Запускаю сторожа. Лог: $LOG"
echo "Ctrl+C — стоп. Пусть работает 30-60 минут или пока тачпад не отвалится."
echo

# Буфер последних 30 секунд kernel-сообщений
journalctl -k -f --no-pager 2>/dev/null | \
while IFS= read -r line; do
    # сохраняем в скользящем буфере (последние 200 строк)
    printf '%s\n' "$line" >> "$SNAP"
    # обрезаем буфер
    tail -200 "$SNAP" > "$SNAP.tmp" && mv "$SNAP.tmp" "$SNAP"

    # ловим re-probe тачпада
    if echo "$line" | grep -qE "04F3:31FD|i2c-CUST0001"; then
        if echo "$line" | grep -qE "input:|hid-generic|hid-multitouch"; then
            ts=$(date +%H:%M:%S)
            {
                echo
                echo "==================== $ts: re-probe! ===================="
                echo "Триггер-строка: $line"
                echo "--- последние 30 строк kernel ДО события ---"
                head -200 "$SNAP" | tail -30
                echo "================================================================="
            } | tee -a "$LOG"
        fi
    fi
done
