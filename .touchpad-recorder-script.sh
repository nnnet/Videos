#!/bin/bash
# Touchpad event recorder — пишет только KEY/BTN/SYN_DROPPED events
# из evtest, каждую строку с timestamp.
#
# Fix v2 (2026-05-15): убрал awk-фильтр который дропал все Event: lines
# через `next` ещё до проверки BTN_. Теперь только grep + read-loop.
#
# Run via systemd. Auto-restart on failure (device re-enumerate).

set -uo pipefail

LOG=/var/log/touchpad-events.log
DEV=/dev/input/by-path/pci-0000:80:15.0-platform-i2c_designware.0-event-mouse
MAX_BYTES=$((20 * 1024 * 1024))  # 20MB, потом обрезается до 10MB

for i in $(seq 1 30); do
    [ -e "$DEV" ] && break
    sleep 1
done
[ ! -e "$DEV" ] && { echo "$(date -Iseconds) device $DEV not found" >> "$LOG"; exit 1; }

if [ -f "$LOG" ] && [ $(stat -c%s "$LOG" 2>/dev/null || echo 0) -gt "$MAX_BYTES" ]; then
    tail -c $((MAX_BYTES / 2)) "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG"
fi

echo "$(date -Iseconds) === recorder v2 started, device=$DEV ===" >> "$LOG"

# evtest events → grep на BTN_/SYN_DROPPED → read-loop с timestamp.
# stdbuf -oL — line-buffered output для real-time записи
stdbuf -oL evtest "$DEV" 2>&1 | \
    stdbuf -oL grep --line-buffered -E "BTN_|SYN_DROPPED" | \
    while IFS= read -r line; do
        printf '%s %s\n' "$(date -Iseconds)" "$line" >> "$LOG"
    done
