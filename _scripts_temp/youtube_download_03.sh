#!/usr/bin/env bash

# ==============================================================================
#           МНОГОПОТОЧНЫЙ СКРИПТ ДЛЯ ЗАГРУЗКИ НОВЫХ ВИДЕО С YOUTUBE
#
# Этап 1: Параллельный поиск по каналам.
# Этап 2: Параллельная загрузка найденных видео с умной обработкой логов.
# ==============================================================================


# --- НАСТРОЙКИ ---

# 1. Базовая директория
BASE_DIR="/mnt/82A23910A2390A65/Videos"

# 2. Имя файла со списком каналов
CHANNELS_FILE="$BASE_DIR/_channels.txt"

# 3. Путь к файлу-архиву
ARCHIVE_FILE="$BASE_DIR/_download_archive.txt"

# 4. Максимальный "возраст" видео для проверки
MAX_VIDEO_AGE="30days"

# 5. Путь к файлу с cookies
COOKIES_FILE="$HOME/Downloads/youtube_cookies_001.txt"
COOKIES_FILE="$HOME/Downloads/cookies-youtube-com.txt"

# 6. Количество параллельных ПОТОКОВ ПОИСКА (Этап 1)
PARALLEL_JOBS=4

# 7. Количество параллельных ЗАГРУЗОК (Этап 2)
PARALLEL_DOWNLOADS=3


# --- КОНЕЦ НАСТРОЕК ---

# --- Блок обработки ошибок и очистки ---

# Устанавливаем флаг, что ошибок пока не было
SCRIPT_HAS_ERRORS=false

# Функция, которая будет вызвана при любом выходе из скрипта (EXIT)
cleanup() {
    # Удаляем временные файлы, которые нужны всегда
    rm -f "$INITIAL_LIST_FILE" "$FINAL_LIST_FILE" "$LOCK_FILE"

    if $SCRIPT_HAS_ERRORS; then
        echo ""
        echo "========================= ВНИМАНИЕ: ПРОИЗОШЛА ОШИБКА ========================="
        echo "Временные архивы сохранены в: $TEMP_ARCHIVE_DIR"
        echo "Логи с подробностями ошибки сохранены в: $LOG_DIR"
        echo "Эти папки не будут удалены автоматически. Проверьте их содержимое."
        echo "=============================================================================="
    else
        # Если ошибок не было, удаляем все временные директории
        rm -rf "$TEMP_ARCHIVE_DIR" "$LOG_DIR"
    fi
}
# Регистрируем нашу функцию 'cleanup' для выполнения при выходе
trap cleanup EXIT


# ... (проверка программ и создание директорий без изменений) ...
if ! command -v yt-dlp &> /dev/null; then echo "Ошибка: yt-dlp не установлен." >&2; exit 1; fi
if ! command -v ffmpeg &> /dev/null; then echo "Ошибка: ffmpeg не установлен." >&2; exit 1; fi
if ! command -v flock &> /dev/null; then echo "Ошибка: утилита flock не найдена." >&2; exit 1; fi
mkdir -p "$BASE_DIR"
if [ ! -f "$CHANNELS_FILE" ]; then echo "Файл каналов не найден, создаю пример." >&2; cat > "$CHANNELS_FILE" <<< "# URL канала"; exit 0; fi

# Создаем временные файлы и директории
INITIAL_LIST_FILE=$(mktemp)
FINAL_LIST_FILE=$(mktemp)
LOCK_FILE=$(mktemp)
TEMP_ARCHIVE_DIR=$(mktemp -d)
LOG_DIR=$(mktemp -d) # Эта директория теперь удаляется только при успехе


# --- ЭТАП 1: ПАРАЛЛЕЛЬНЫЙ ПОИСК НОВЫХ ВИДЕО (с проверкой количества потоков) ---

# ... (этот блок без изменений) ...
process_channel() {
#    local channel_url="$1"; local original_url="$channel_url"
#    if [[ "$channel_url" =~ ^https?://(www\.)?youtube\.com/@[a-zA-Z0-9_.-]+/?$ ]]; then
#        channel_url="${channel_url%/}/videos"; echo "Проверяю (параллельно): $original_url -> ${channel_url##*//}"
#    else echo "Проверяю (параллельно): ${channel_url##*//}"; fi
#    local video_ids; video_ids=$(yt-dlp --ignore-errors --get-id --lazy-playlist --download-archive "$ARCHIVE_FILE" --dateafter "now-${MAX_VIDEO_AGE}" --cookies "$COOKIES_FILE" "$channel_url" < /dev/null)
#    if [[ -n "$video_ids" ]]; then ( flock 200; echo "$video_ids" >> "$INITIAL_LIST_FILE"; ) 200>"$LOCK_FILE"; fi
    local channel_url="$1"
    # ... (логика функции без изменений) ...
    local original_url="$channel_url"
    if [[ "$channel_url" =~ ^https?://(www\.)?youtube\.com/@[a-zA-Z0-9_.-]+/?$ ]]; then
        channel_url="${channel_url%/}/videos"
        echo "Проверяю (параллельно): $original_url -> ${channel_url##*//}"
    else
        echo "Проверяю (параллельно): ${channel_url##*//}"
    fi
    local video_ids
    video_ids=$(yt-dlp --ignore-errors --get-id --lazy-playlist --break-on-reject --download-archive "$ARCHIVE_FILE" --dateafter "now-${MAX_VIDEO_AGE}" --cookies "$COOKIES_FILE" "$channel_url" < /dev/null)
    if [[ -n "$video_ids" ]]; then
        ( flock 200; echo "$video_ids" >> "$INITIAL_LIST_FILE"; ) 200>"$LOCK_FILE"
    fi
}
export -f process_channel
export ARCHIVE_FILE MAX_VIDEO_AGE COOKIES_FILE INITIAL_LIST_FILE LOCK_FILE

echo "--- $(date '+%Y-%m-%d %H:%M:%S') ---"
echo "ЭТАП 1: Параллельный поиск новых видео..."

# Считаем реальное количество каналов (исключая пустые строки и комментарии)
channel_count=$(grep -vE '^\s*#|^\s*$' "$CHANNELS_FILE" | wc -l)
if [ "$channel_count" -eq 0 ]; then
    echo "[ПРЕДУПРЕЖДЕНИЕ] Файл с каналами пуст или содержит только комментарии. Завершение работы с ошибкой."
    exit 1
fi


effective_jobs=$PARALLEL_JOBS
if [ "$channel_count" -lt "$PARALLEL_JOBS" ]; then
    echo "[INFO] Количество потоков ($PARALLEL_JOBS) превышает количество каналов ($channel_count). Будет использовано: $channel_count."
    effective_jobs=$channel_count
fi

echo "Запускаю поиск по $channel_count каналам в $effective_jobs потоков..."
grep -vE '^\s*#|^\s*$' "$CHANNELS_FILE" | xargs -P "$effective_jobs" -I {} bash -c 'process_channel "{}"'

echo "Поиск завершен. Очистка списка..."
sed -i -E '/^$|^NA$|^N\/A$/d' "$INITIAL_LIST_FILE"


# --- ЭТАП 2: ФИЛЬТРАЦИЯ И ПАРАЛЛЕЛЬНАЯ ЗАГРУЗКА (СУЩЕСТВЕННО ОБНОВЛЕН) ---
echo ""
echo "ЭТАП 2: Фильтрация и параллельная загрузка видео..."

cat $INITIAL_LIST_FILE
VIDEO_COUNT=$(wc -l < "$INITIAL_LIST_FILE")
echo "Найдено видео для загрузки: $VIDEO_COUNT видео."
echo "------------------------------"
echo ""


if [ ! -s "$INITIAL_LIST_FILE" ]; then
  echo "Новых видео для загрузки не найдено." && exit 0;
fi


echo "Провожу финальную сверку с архивом..."
if [ -f "$ARCHIVE_FILE" ]; then
    grep -v -F -f <(awk '{print $2}' "$ARCHIVE_FILE" 2>/dev/null) "$INITIAL_LIST_FILE" > "$FINAL_LIST_FILE"
else
    cp "$INITIAL_LIST_FILE" "$FINAL_LIST_FILE"
fi

cat $FINAL_LIST_FILE
VIDEO_COUNT=$(wc -l < "$INITIAL_LIST_FILE")
echo "Отфильтровано видео для загрузки: $VIDEO_COUNT видео."
echo "------------------------------"
echo ""

#
#if [ ! -s "$FINAL_LIST_FILE" ]; then echo "После финальной сверки с архивом видео для загрузки не осталось." && exit 0; fi
#
#VIDEO_COUNT=$(wc -l < "$FINAL_LIST_FILE")
## Проверяем, что количество потоков загрузки не превышает количество видео
#effective_downloads=$PARALLEL_DOWNLOADS
#if [ "$VIDEO_COUNT" -lt "$PARALLEL_DOWNLOADS" ]; then
#    echo "[INFO] Количество потоков загрузки ($PARALLEL_DOWNLOADS) превышает количество видео ($VIDEO_COUNT). Будет использовано: $VIDEO_COUNT."
#    effective_downloads=$VIDEO_COUNT
#fi
#
#echo ""
#echo "Итого к загрузке: $VIDEO_COUNT видео. Запускаю в $effective_downloads потоков."
#echo "--- Список видео для загрузки ---"
#cat "$FINAL_LIST_FILE"
#echo "---------------------------------"
#echo ""
#
## Функция для загрузки ОДНОГО видео.
#download_video() {
#    local video_id="$1"
#    local temp_archive="$TEMP_ARCHIVE_DIR/archive_${video_id}.txt"
#    local log_file="$LOG_DIR/log_${video_id}.txt"
#
#    echo "Поток [$$]: Начинаю загрузку видео $video_id. Лог: ${log_file}"
#
#    # Запускаем yt-dlp и проверяем код возврата
#    if ! yt-dlp \
#        --no-progress \
#        --no-overwrites \
#        --force-id \
#        --download-archive "$temp_archive" \
#        --cookies "$COOKIES_FILE" \
#        --format 'bestvideo[height<=480][ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4][height<=480]/best[height<=480]' \
#        --merge-output-format mp4 \
#        --output "$BASE_DIR/%(channel)s/%(title)s [%(id)s].%(ext)s" \
#        "https://www.youtube.com/watch?v=$video_id" > "$log_file" 2>&1;
#    then
#        # Если команда выше завершилась с ошибкой, создаем файл-маркер
#        echo "Поток [$$]: ОШИБКА при загрузке $video_id. Смотрите полный лог: ${log_file}"
#        touch "$LOG_DIR/failed_${video_id}"
#    else
#        echo "Поток [$$]: Успешно завершил $video_id"
#        # Если все хорошо, лог не нужен - можно удалить для экономии места
#        rm -f "$log_file"
#    fi
#}
#export -f download_video
#export BASE_DIR COOKIES_FILE TEMP_ARCHIVE_DIR LOG_DIR
#
## Запускаем параллельную загрузку
#cat "$FINAL_LIST_FILE" | xargs -P "$effective_downloads" -I {} bash -c 'download_video "{}"'
#
#echo ""
#echo "--- Все потоки загрузки завершены ---"
#
## Проверяем, были ли созданы файлы-маркеры ошибок
#if ls "$LOG_DIR"/failed_* 1> /dev/null 2>&1; then
#    SCRIPT_HAS_ERRORS=true
#    # Принудительно выходим с кодом ошибки, чтобы сработал trap
#    exit 1
#fi
#
#echo "Обновляю основной файл архива..."
#cat "$ARCHIVE_FILE" "$TEMP_ARCHIVE_DIR"/* 2>/dev/null | sort -u > "$ARCHIVE_FILE.tmp" && mv "$ARCHIVE_FILE.tmp" "$ARCHIVE_FILE"

echo "Очистка прошла успешно, ошибок не обнаружено."
echo "--- Загрузка полностью завершена ---"