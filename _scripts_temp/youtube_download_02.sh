#!/usr/bin/env bash

# ==============================================================================
#           МНОГОПОТОЧНЫЙ СКРИПТ ДЛЯ ЗАГРУЗКИ НОВЫХ ВИДЕО С YOUTUBE
#
# Этап 1: Параллельный поиск по каналам.
# Этап 2: Параллельная загрузка найденных видео.
# ==============================================================================


# --- НАСТРОЙКИ ---

# 1. Базовая директория
BASE_DIR="/mnt/82A23910A2390A65/Videos"

# 2. Имя файла со списком каналов
CHANNELS_FILE="$BASE_DIR/_channels.txt"

# 3. Путь к файлу-архиву
ARCHIVE_FILE="$BASE_DIR/_download_archive.txt"

# 4. Скачивать только видео, которые были загружены не ранее указанного срока.
#    Форматы: "14days", "2weeks", "1month", "3months" и т.д.
#MAX_VIDEO_AGE="30days"
#MAX_VIDEO_AGE="10days"
MAX_VIDEO_AGE="2months"

# 5. Путь к файлу с cookies
COOKIES_FILE="$HOME/Downloads/youtube_cookies_001.txt"
COOKIES_FILE="$HOME/Downloads/cookies-youtube-com.txt"

# 6. Количество параллельных ПОТОКОВ ПОИСКА (Этап 1)
PARALLEL_JOBS=4

# 7. (НОВАЯ НАСТРОЙКА) Количество параллельных ЗАГРУЗОК (Этап 2)
#    ВНИМАНИЕ: Увеличивайте с осторожностью! Высокие значения (> 3-4)
#    могут привести к временной блокировке вашего IP со стороны YouTube.
PARALLEL_DOWNLOADS=3


# --- КОНЕЦ НАСТРОЕК ---


# Проверка, установлены ли необходимые программы
# ... (этот блок без изменений, оставлен для краткости) ...
if ! command -v yt-dlp &> /dev/null; then echo "Ошибка: yt-dlp не установлен." >&2; exit 1; fi
if ! command -v ffmpeg &> /dev/null; then echo "Ошибка: ffmpeg не установлен." >&2; exit 1; fi
if ! command -v flock &> /dev/null; then echo "Ошибка: утилита flock не найдена." >&2; exit 1; fi

# Создаем базовую директорию
mkdir -p "$BASE_DIR"

# Проверяем/создаем файл с каналами
# ... (этот блок без изменений) ...
if [ ! -f "$CHANNELS_FILE" ]; then echo "Файл каналов не найден, создаю пример." >&2; cat > "$CHANNELS_FILE" <<< "# URL канала"; exit 0; fi

# Создаем временные файлы и директории, гарантируем их удаление при выходе
INITIAL_LIST_FILE=$(mktemp)
FINAL_LIST_FILE=$(mktemp)
LOCK_FILE=$(mktemp)
# Директории для временных файлов Этапа 2
TEMP_ARCHIVE_DIR=$(mktemp -d)
LOG_DIR=$(mktemp -d)
trap 'rm -f "$INITIAL_LIST_FILE" "$FINAL_LIST_FILE" "$LOCK_FILE"; rm -rf "$TEMP_ARCHIVE_DIR" "$LOG_DIR"' EXIT


# --- ЭТАП 1: ПАРАЛЛЕЛЬНЫЙ ПОИСК НОВЫХ ВИДЕО (без изменений) ---

process_channel() {
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
echo "ЭТАП 1: Параллельный поиск новых видео (в $PARALLEL_JOBS потоков)..."

# Считаем реальное количество каналов (исключая пустые строки и комментарии)
channel_count=$(grep -vE '^\s*#|^\s*$' "$CHANNELS_FILE" | wc -l)
if [ "$channel_count" -eq 0 ]; then
    echo "[ПРЕДУПРЕЖДЕНИЕ] Файл с каналами пуст или содержит только комментарии. Завершение работы с ошибкой."
    exit 1
fi


# Определяем фактическое количество потоков, которое будем использовать.
# Оно не должно превышать количество каналов.
effective_jobs=$PARALLEL_JOBS
if [ "$channel_count" -lt "$PARALLEL_JOBS" ]; then
    echo "[INFO] Количество потоков ($PARALLEL_JOBS) превышает количество каналов ($channel_count). Будет использовано: $channel_count."
    effective_jobs=$channel_count
fi

grep -vE '^\s*#|^\s*$' "$CHANNELS_FILE" | xargs -P "$effective_jobs" -I {} bash -c 'process_channel "{}"'


echo "Поиск завершен. Очистка списка..."
sed -i -E '/^$|^NA$|^N\/A$/d' "$INITIAL_LIST_FILE"


# --- ЭТАП 2: ФИЛЬТРАЦИЯ И ПАРАЛЛЕЛЬНАЯ ЗАГРУЗКА (ПОЛНОСТЬЮ ПЕРЕРАБОТАН) ---
echo ""
echo "ЭТАП 2: Фильтрация и параллельная загрузка видео..."

if [ ! -s "$INITIAL_LIST_FILE" ]; then
    echo "Новых видео для загрузки не найдено." && exit 0
fi

echo "Провожу финальную сверку с архивом..."
if [ -f "$ARCHIVE_FILE" ]; then
    grep -v -F -f <(awk '{print $2}' "$ARCHIVE_FILE" 2>/dev/null) "$INITIAL_LIST_FILE" > "$FINAL_LIST_FILE"
else
    cp "$INITIAL_LIST_FILE" "$FINAL_LIST_FILE"
fi

if [ ! -s "$FINAL_LIST_FILE" ]; then
    echo "После финальной сверки с архивом видео для загрузки не осталось." && exit 0
fi

VIDEO_COUNT=$(wc -l < "$FINAL_LIST_FILE")
echo ""
echo "Итого к загрузке: $VIDEO_COUNT видео. Начинаю загрузку в $PARALLEL_DOWNLOADS потоков."
echo "ВНИМАНИЕ: Вывод будет записан в лог-файлы в директории $LOG_DIR"
echo "---------------------------------"
echo ""

# Функция для загрузки ОДНОГО видео. Будет запускаться параллельно.
download_video() {
    local video_id="$1"
    local temp_archive="$TEMP_ARCHIVE_DIR/archive_${video_id}.txt"
    local log_file="$LOG_DIR/log_${video_id}.txt"

    echo "Поток [$$]: Начинаю загрузку видео $video_id. Лог: ${log_file##*/}"

    yt-dlp \
        --ignore-errors \
        --no-overwrites \
        --force-id \
        --download-archive "$temp_archive" \
        --cookies "$COOKIES_FILE" \
        --format 'bestvideo[height<=480][ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4][height<=480]/best[height<=480]' \
        --merge-output-format mp4 \
        --output "$BASE_DIR/%(channel)s/%(title)s [%(id)s].%(ext)s" \
        "https://www.youtube.com/watch?v=$video_id" > "$log_file" 2>&1

    # Проверяем статус выхода yt-dlp
    if [ $? -eq 0 ]; then
        echo "Поток [$$]: Успешно завершил $video_id"
    else
        echo "Поток [$$]: Ошибка при загрузке $video_id. Смотрите лог: ${log_file##*/}"
    fi
}

# Экспортируем функцию и переменные для xargs
export -f download_video
export BASE_DIR COOKIES_FILE TEMP_ARCHIVE_DIR LOG_DIR

# Запускаем параллельную загрузку с помощью xargs
cat "$FINAL_LIST_FILE" | xargs -P "$PARALLEL_DOWNLOADS" -I {} bash -c 'download_video "{}"'

echo ""
echo "--- Все потоки загрузки завершены ---"
echo "Обновляю основной файл архива..."

# Безопасно объединяем все временные архивы в основной файл
# cat ... | sort -u : прочитать все, отсортировать и удалить дубликаты
cat "$ARCHIVE_FILE" "$TEMP_ARCHIVE_DIR"/* 2>/dev/null | sort -u > "$ARCHIVE_FILE.tmp" && mv "$ARCHIVE_FILE.tmp" "$ARCHIVE_FILE"

echo "Очищаю временные файлы..."
# trap позаботится об этом, но для наглядности можно оставить
rm -rf "$TEMP_ARCHIVE_DIR" "$LOG_DIR"

echo "--- Загрузка полностью завершена ---"