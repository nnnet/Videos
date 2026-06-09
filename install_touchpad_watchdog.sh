#!/usr/bin/env bash
# Touchpad watchdog daemon — systemd service.
# Раз в 0.5 секунды проверяет какой драйвер у ELAN 04F3:31FD.
# Если оказался hid-generic — мгновенно переключает на hid-multitouch.
# Закрывает gap между re-probe (откуда бы он ни шёл) и udev-rule.
#
# Что ставит:
#   /usr/local/sbin/touchpad-watchdog.sh         — сам скрипт
#   /etc/systemd/system/touchpad-watchdog.service — unit
#
# Откат: ./install_touchpad_watchdog.sh --uninstall
#
# Ресурсы: спит 0.5с, читает символическую ссылку, иногда echo в sysfs.
# Нагрузка минимальна (< 0.1% CPU), памяти ~1MB на bash-процесс.

set +e

WATCHDOG_BIN=/usr/local/sbin/touchpad-watchdog.sh
SERVICE_FILE=/etc/systemd/system/touchpad-watchdog.service

if [[ "${1:-}" == "--uninstall" ]]; then
    echo "Останавливаю и удаляю touchpad-watchdog..."
    sudo systemctl stop touchpad-watchdog 2>&1
    sudo systemctl disable touchpad-watchdog 2>&1
    sudo rm -f "$WATCHDOG_BIN" "$SERVICE_FILE"
    sudo systemctl daemon-reload
    echo "Готово. Откат завершён."
    exit 0
fi

if ! sudo -n true 2>/dev/null; then
    echo "Нужен sudo:"
    sudo -v || { echo "sudo не дал прав"; exit 1; }
fi

echo "=== Устанавливаю watchdog-скрипт ==="
sudo tee "$WATCHDOG_BIN" >/dev/null <<'EOF'
#!/usr/bin/env bash
# Touchpad watchdog: проверяет драйвер ELAN 04F3:31FD раз в 0.5 сек
# и перепривязывает на hid-multitouch если что-то его сместило.

LOG_TAG="touchpad-watchdog"

log() { logger -t "$LOG_TAG" "$*"; }

log "started"

while true; do
    # найти текущее HID-устройство
    DEV_PATH=$(find /sys/bus/hid/devices -maxdepth 1 -name "0018:04F3:31FD.*" 2>/dev/null | head -1)
    if [[ -n "$DEV_PATH" ]]; then
        DEV_NAME=$(basename "$DEV_PATH")
        CURRENT_DRV=$(basename "$(readlink "$DEV_PATH/driver" 2>/dev/null)" 2>/dev/null)
        if [[ "$CURRENT_DRV" == "hid-generic" ]]; then
            log "detected hid-generic on $DEV_NAME, switching to hid-multitouch"
            echo "$DEV_NAME" > /sys/bus/hid/drivers/hid-generic/unbind 2>/dev/null
            echo "$DEV_NAME" > /sys/bus/hid/drivers/hid-multitouch/bind 2>/dev/null
        fi
    fi
    sleep 0.5
done
EOF
sudo chmod +x "$WATCHDOG_BIN"
echo "  ok $WATCHDOG_BIN"

echo
echo "=== Устанавливаю systemd unit ==="
sudo tee "$SERVICE_FILE" >/dev/null <<'EOF'
[Unit]
Description=Touchpad ELAN 04F3:31FD driver-bind watchdog
After=multi-user.target
StartLimitIntervalSec=60
StartLimitBurst=10

[Service]
Type=simple
ExecStart=/usr/local/sbin/touchpad-watchdog.sh
Restart=always
RestartSec=2
# safety: запретить escalation
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=/sys/bus/hid
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
echo "  ok $SERVICE_FILE"

echo
echo "=== Активация ==="
sudo systemctl daemon-reload
sudo systemctl enable --now touchpad-watchdog && echo "  ok enabled+started"

sleep 1

echo
echo "=== Статус ==="
systemctl status touchpad-watchdog --no-pager -l | head -15

echo
echo "=== Driver сейчас ==="
find /sys -path "*0018:04F3:31FD*" -name driver 2>/dev/null | while read p; do
    echo "  $(basename $(dirname $p))  →  $(basename $(readlink $p))"
done

cat <<'TAIL'

=== Что теперь ===
• Каждые 0.5 сек watchdog проверяет драйвер тачпада.
• Если что-то сместит на hid-generic — переключит за < 1 сек обратно.
• Лог:    journalctl -t touchpad-watchdog -f
• Статус: systemctl status touchpad-watchdog

=== ТЕСТ ===
В течение 30-60 минут не должно быть нужно ./fix_touchpad_2_driver.sh.
Если клик пропадёт меньше чем на 1 секунду — это watchdog в работе,
он восстановит автоматом.

=== Если глюк остался ===
• Проверь что daemon живой:  systemctl is-active touchpad-watchdog
• Проверь его лог:           journalctl -t touchpad-watchdog -n 20
• Запусти watcher одновременно — ./watch_touchpad.sh — там увидим
  что предшествует каждому re-probe (это поможет найти истинный
  триггер если он не EC/firmware).

=== ОТКАТ ===
./install_touchpad_watchdog.sh --uninstall
TAIL
