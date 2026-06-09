#!/usr/bin/env bash
# Root-cause диагностика: что именно стало триггером re-probe ELAN тачпада.
# Собирает таймлайн событий, недавние обновления, активные процессы,
# которые могли бы дёргать i2c-шину или ACPI.

set +e

if ! sudo -n true 2>/dev/null; then sudo -v || exit 1; fi

sep() { printf '\n=========== %s ===========\n' "$*"; }

sep "BOOT TIME и uptime"
who -b 2>&1
uptime
journalctl --list-boots --no-pager 2>&1 | tail -5

sep "ПЕРВЫЕ re-probe в текущем boot'е — когда?"
echo "Ищу: input: CUST0001:00 ...первое появление + первый hid-generic"
# самое первое появление устройства
journalctl -k -b 0 --no-pager 2>/dev/null | grep -E "04F3:31FD" | head -5
echo "----- и потом первый re-probe (после паузы > 1 мин) -----"
# показать первые 20 событий
journalctl -k -b 0 --no-pager 2>/dev/null | grep -E "04F3:31FD" | awk '{print $1, $2, $3}' | uniq -c | head -20

sep "WHEN re-probe начался — относительно boot"
# Boot был, потом первое input-устройство на 0018:04F3:31FD.0001 — это INIT.
# Второе — это уже re-probe. Покажем секунды от boot до 2-го появления.
BOOT_TS=$(date -d "$(uptime -s)" +%s)
NOW_TS=$(date +%s)
echo "Boot at: $(uptime -s)    ($((NOW_TS - BOOT_TS)) сек назад)"
echo "Сколько re-probe всего за boot:"
journalctl -k -b 0 --no-pager 2>/dev/null | grep -cE "hid-(generic|multitouch).*04F3:31FD"
echo "Из них hid-generic (плохой):"
journalctl -k -b 0 --no-pager 2>/dev/null | grep -cE "hid-generic.*04F3:31FD"

sep "Что было в KERNEL log сразу ПЕРЕД самым первым re-probe"
# Найти timestamp 2-го появления Touchpad input
SECOND_PROBE=$(journalctl -k -b 0 --no-pager -o short-iso 2>/dev/null | grep -E "04F3:31FD Touchpad as" | sed -n '2p' | awk '{print $1}')
echo "Второй (= первый re-probe) Touchpad input: $SECOND_PROBE"
if [[ -n "$SECOND_PROBE" ]]; then
    # 60 секунд до этого события
    START=$(date -d "$SECOND_PROBE - 60 seconds" --iso-8601=seconds 2>/dev/null)
    echo "Kernel-события за 60 сек до:"
    journalctl -k -b 0 --since "$START" --until "$SECOND_PROBE" --no-pager 2>/dev/null | tail -40
fi

sep "APT/dpkg ПОСЛЕДНИЕ обновления (за 30 дней)"
ls -la /var/log/apt/history.log* 2>&1 | head
echo "---"
zcat -f /var/log/apt/history.log* 2>/dev/null | grep -E "^(Start-Date|Commandline|Upgrade|Install)" | tail -60

sep "KERNEL — текущая и предыдущие версии"
uname -r
dpkg -l | grep -E "^ii.*linux-image-" | awk '{print $2, $3, $4}'
echo "---"
ls -la /boot/vmlinuz-* 2>&1

sep "Какой kernel был при предыдущем boot?"
journalctl --list-boots --no-pager 2>&1 | tail -10 | while read line; do
    BID=$(echo "$line" | awk '{print $2}')
    [[ -n "$BID" ]] || continue
    KV=$(journalctl -k -b "$BID" --no-pager 2>/dev/null | grep -m1 "Linux version" | head -1 | grep -oE "[0-9]+\.[0-9]+\.[0-9]+(-[0-9]+-generic)?")
    echo "boot $BID: kernel $KV"
done

sep "DKMS статус NVIDIA — собран для текущего ядра?"
dkms status 2>&1

sep "Активные процессы которые могут трогать i2c/HID"
pgrep -af "thermald|fwupd|tlp|laptop-mode|mbpfan|MSICtl|dell-smm|i2c|coolercontrol|MSI|whisper|gnome-input|libinput-gestures|input-leap" | head

sep "Systemd timers/services которые могут дёргать что-то периодически"
systemctl list-timers --all --no-pager 2>&1 | head -25

sep "ACPI ошибки / Embedded Controller events"
journalctl -k -b 0 --no-pager 2>/dev/null | grep -iE "ACPI.*error|ACPI.*BIOS|EC:.*error|firmware bug|GPE storm" | head -20
echo "--- частота ACPI GPE interrupts (косвенно — как часто EC что-то сообщает) ---"
cat /sys/firmware/acpi/interrupts/gpe_all 2>&1

sep "Wakeup-источники, которые активны"
cat /proc/acpi/wakeup 2>&1 | grep -v disabled

sep "Изменения в /etc/ за последние 7 дней"
sudo find /etc -type f -mtime -7 ! -path "*/cni/*" ! -path "*/letsencrypt/*" 2>/dev/null | head -30

sep "BIOS/firmware version"
sudo dmidecode -s bios-version 2>&1
sudo dmidecode -s bios-release-date 2>&1

sep "ITOG — суммарная статистика re-probe по часам сегодня"
journalctl -k -b 0 --no-pager -o short-iso 2>/dev/null | grep "hid-generic.*04F3:31FD" | awk '{print substr($1,1,13)}' | sort | uniq -c
