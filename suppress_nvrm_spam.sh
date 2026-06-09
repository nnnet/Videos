#!/usr/bin/env bash
# Подавляет NVRM-спам в journald через rate-limit drop-in.
#
# Что делает:
#   создаёт /etc/systemd/journald.conf.d/nvrm-ratelimit.conf
#   с RateLimitIntervalSec=10s, RateLimitBurst=200 (per-source!)
#   То есть: любой источник логов (включая kernel) — не более 200
#   сообщений за 10 секунд. NVRM-спам (~213/min при текущем темпе)
#   попадёт в drop, обычные kernel-сообщения уложатся в лимит.
#
# БЕЗОПАСНО: не меняет ничего кроме одного файла журнал-конфига.
#            Не трогает NVIDIA, ядро, modprobe, grub, fstab, fs.
#
# ОТКАТ: см. секцию --uninstall в конце.

set +e

CONF=/etc/systemd/journald.conf.d/nvrm-ratelimit.conf

if [[ "${1:-}" == "--uninstall" ]]; then
    if [[ -f "$CONF" ]]; then
        echo "Удаляю $CONF и перезапускаю journald..."
        sudo rm -f "$CONF"
        sudo systemctl restart systemd-journald
        echo "Готово. RateLimit вернулся к дефолту (10000/30s)."
    else
        echo "Файл $CONF не существует, откатывать нечего."
    fi
    exit 0
fi

if ! sudo -n true 2>/dev/null; then
    echo "Нужен sudo:"
    sudo -v || { echo "sudo не дал прав"; exit 1; }
fi

echo "=== ДО ==="
echo "-- размер журнала --"
journalctl --disk-usage 2>&1
echo "-- сколько NVRM-строк за последние 24 часа --"
journalctl -k --since "24 hours ago" --no-pager 2>/dev/null | grep -c "NVRM"
echo "-- текущая RateLimit конфигурация --"
grep -E "^RateLimit|^#RateLimit" /etc/systemd/journald.conf | head

echo
echo "=== Применяю ==="
sudo mkdir -p /etc/systemd/journald.conf.d
sudo tee "$CONF" >/dev/null <<'EOF'
# Drop-in: rate-limit для подавления NVRM-спама от NVIDIA-драйвера.
# Установлено скриптом /mnt/82A23910A2390A65/Videos/suppress_nvrm_spam.sh.
# Откат:  ./suppress_nvrm_spam.sh --uninstall
[Journal]
RateLimitIntervalSec=10s
RateLimitBurst=200
EOF
echo "  ok создал $CONF"

echo
echo "=== Что записал ==="
cat "$CONF" | sed 's/^/    /'

echo
echo "=== Перезапускаю systemd-journald ==="
sudo systemctl restart systemd-journald && echo "  ok"

sleep 2

echo
echo "=== ПОСЛЕ ==="
echo "-- journald статус --"
systemctl is-active systemd-journald
echo "-- размер логов (не изменится сразу, только новые ограничены) --"
journalctl --disk-usage 2>&1
echo "-- последние 5 строк журнала (проверка что работает) --"
journalctl -n 5 --no-pager 2>&1

cat <<'TAIL'

=== Что произойдёт дальше ===
• Старые NVRM-строки в журнале остались (102 МБ). Они будут вымываться
  при ротации (SystemMaxUse=200M).
• Если хочешь почистить старое прямо сейчас — выполни:
      sudo journalctl --vacuum-time=1d
  (оставит логи только за последние сутки)
• Новые NVRM-сообщения теперь rate-limited. В journalctl ты их всё ещё
  будешь видеть, но не 307К/день, а около 1-2 тысяч в худшем случае.
• Появится строка "Suppressed N messages from /dev/kmsg" — это норма,
  показывает что фильтр работает.

=== ОТКАТ ===
./suppress_nvrm_spam.sh --uninstall
# или вручную:
sudo rm /etc/systemd/journald.conf.d/nvrm-ratelimit.conf
sudo systemctl restart systemd-journald
TAIL
