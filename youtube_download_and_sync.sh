#!/bin/bash
# Orchestrator: youtube_download_01.sh → если есть новые видео → copy_to_Folder3.sh
# Если destination устройство не в сети — спрашиваем юзера через zenity.
#
# Запускается из cron (тот же слот что был у youtube_download_01.sh).
# Логи: /home/uadmin/logs/downloader.log (как раньше) + строки [SYNC] для копирования.

set -u
cd /mnt/82A23910A2390A65/Videos/

VIDEOS_DIR="/mnt/82A23910A2390A65/Videos/Youtube"
DOWNLOAD_SCRIPT="./youtube_download_01.sh"
COPY_SCRIPT="./copy_to_Folder3.sh"

# Парсим FTP_HOST из copy_to_Folder3.sh (формат: ftp://10.0.0.2:8913)
FTP_LINE=$(grep -m1 '^FTP_HOST=' "$COPY_SCRIPT")
FTP_URL=$(echo "$FTP_LINE" | cut -d'"' -f2)
FTP_HOST=$(echo "$FTP_URL" | sed -E 's|ftp://([^:/]+).*|\1|')
FTP_PORT=$(echo "$FTP_URL" | sed -E 's|.*:([0-9]+).*|\1|')

# Для zenity / notify-send из cron нужны DISPLAY + DBUS
export DISPLAY="${DISPLAY:-:0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SYNC] $*"; }

ping_destination() {
    timeout 5 bash -c "</dev/tcp/$FTP_HOST/$FTP_PORT" 2>/dev/null
}

# === 1. Запоминаем timestamp до запуска downloader ===
TS_FILE=$(mktemp)
touch "$TS_FILE"
log "Старт пайплайна. Destination = $FTP_HOST:$FTP_PORT"

# === 2. Запускаем downloader ===
"$DOWNLOAD_SCRIPT"
DL_EXIT=$?
log "youtube_download_01.sh exit=$DL_EXIT"

# === 3. Проверяем появились ли новые видео-файлы (mp4/webm/mkv) после TS_FILE ===
NEW_COUNT=$(find "$VIDEOS_DIR" -type f \( -name '*.mp4' -o -name '*.webm' -o -name '*.mkv' \) \
            -newer "$TS_FILE" 2>/dev/null | wc -l)
rm -f "$TS_FILE"
log "Новых видео-файлов: $NEW_COUNT"

if [ "$NEW_COUNT" -eq 0 ]; then
    log "Нечего синхронизировать — выход."
    exit 0
fi

# === 4. Проверяем доступность destination + копируем ===
attempt_sync() {
    log "Запускаю $COPY_SCRIPT"
    "$COPY_SCRIPT"
    local rc=$?
    log "copy_to_Folder3.sh exit=$rc"
    return $rc
}

if ping_destination; then
    log "Destination в сети — копирую сразу."
    attempt_sync
    exit $?
fi

log "Destination $FTP_HOST:$FTP_PORT недоступен. Прошу юзера подключить устройство."

# zenity loop: до 30 минут ожидания, или пока юзер не подтвердит / не отменит
TIMEOUT_TOTAL=$(( 30 * 60 ))   # 30 минут
WAIT_INTERVAL=10               # пинговать каждые 10 сек в фоне между диалогами
ELAPSED=0

# Сначала уведомление чтобы привлечь внимание
notify-send -u critical -t 10000 -i network-offline \
    "YouTube sync: устройство не в сети" \
    "Подключи $FTP_HOST:$FTP_PORT. Появится диалог с вариантами." 2>/dev/null || true

while [ "$ELAPSED" -lt "$TIMEOUT_TOTAL" ]; do
    # Не блокирующий пинг между диалогами — если девайс появился сам, копируем без вопроса
    if ping_destination; then
        log "Устройство появилось само через $ELAPSED сек — копирую."
        attempt_sync
        exit $?
    fi

    # zenity диалог с тремя кнопками: "Подключил" / "Подождать ещё 10 мин" / "Отмена"
    CHOICE=$(zenity --question \
        --title="YouTube sync — устройство не в сети" \
        --text="Destination <b>$FTP_HOST:$FTP_PORT</b> не отвечает.\n\nНовых видео для копирования: <b>$NEW_COUNT</b>\nПрошло ожидания: ${ELAPSED}с / ${TIMEOUT_TOTAL}с\n\nПодключи устройство и нажми ОК — попробую снова.\nИли Отмена — пропустить копирование (запустишь руками позже)." \
        --ok-label="Подключил, попробуй снова" \
        --cancel-label="Отмена / позже" \
        --width=500 \
        --timeout=300 \
        2>/dev/null; echo $?)

    case "$CHOICE" in
        0)
            log "Юзер нажал 'Подключил' — пробую."
            if ping_destination; then
                attempt_sync
                exit $?
            else
                log "Всё ещё нет связи — повторяю диалог."
                ELAPSED=$(( ELAPSED + 30 ))
            fi
            ;;
        1)
            log "Юзер отменил — выход без копирования."
            notify-send -u normal -t 5000 \
                "YouTube sync: пропущено" \
                "$NEW_COUNT видео ждут. Запусти ./copy_to_Folder3.sh когда будет связь." 2>/dev/null || true
            exit 0
            ;;
        5)
            # zenity timeout (300с) — пингуем сами и продолжаем цикл
            log "zenity timeout — пингую и продолжаю."
            ELAPSED=$(( ELAPSED + 300 ))
            ;;
        *)
            log "zenity exit $CHOICE — выход."
            exit 0
            ;;
    esac
done

log "Общий таймаут ${TIMEOUT_TOTAL}с — пропускаю копирование."
notify-send -u normal -t 0 \
    "YouTube sync: таймаут" \
    "Прошло 30 минут, $NEW_COUNT видео НЕ скопированы. Запусти ./copy_to_Folder3.sh руками." 2>/dev/null || true
exit 0
