#!/usr/bin/env bash

# --- НАСТРОЙКИ ---

# 1. Базовая директория, куда будут сохраняться все видео и файлы конфигурации.
#    Скрипт создаст ее, если она не существует.
BASE_DIR="$HOME/Видео/YouTube"
BASE_DIR="/mnt/82A23910A2390A65/Videos"

# 2. Имя файла со списком каналов (будет находиться внутри BASE_DIR).
#    В файле должен быть один URL-адрес канала на строку.
CHANNELS_FILE="$BASE_DIR/_channels.txt"

# 3. Путь к файлу-архиву, где yt-dlp хранит ID уже скачанных видео.
ARCHIVE_FILE="$BASE_DIR/_download_archive.txt"

# 4. Скачивать только видео, которые были загружены не ранее указанного срока.
#    Форматы: "14days", "2weeks", "1month", "3months" и т.д.
MAX_VIDEO_AGE="1weeks"
MAX_VIDEO_AGE="30days"


COOKIES_FILE="$HOME/youtube_cookies.txt" # Путь к вашим куки
COOKIES_FILE="~/Downloads/cookies-youtube-com.txt" # Путь к вашим куки


# --- НАСТРОЙКИ ПАУЗЫ (ДЛЯ ОБХОДА RATE-LIMIT) ---
# --- Настройки "вежливости" для обхода rate-limit ---
# Минимальное время ожидания между видео (в секундах)
MIN_SLEEP=5
# Максимальное время ожидания между видео (в секундах)
MAX_SLEEP=15

NB_ERROR_LIMIT_MAX=10
NB_ERROR_LIMIT_MAX=5

# --- КОНЕЦ НАСТРОЕК ---


# Проверка, установлен ли yt-dlp
if ! command -v yt-dlp &> /dev/null
then
    echo "Ошибка: yt-dlp не установлен или не найден в PATH."
    echo "Пожалуйста, установите его, например: sudo apt install yt-dlp"
    exit 1
fi

if ! command -v ffmpeg &> /dev/null; then
    echo "Ошибка: ffmpeg не установлен. Он необходим для слияния видео и аудио." >&2
    echo "Пожалуйста, установите его: sudo apt install ffmpeg" >&2
    exit 1
fi

# Создаем базовую директорию, если она не существует
mkdir -p "$BASE_DIR"

# Проверяем, существует ли файл с каналами. Если нет, создаем пример и выходим.
if [ ! -f "$CHANNELS_FILE" ]; then
    echo "Файл со списком каналов не найден."
    echo "Создаю пример файла в: $CHANNELS_FILE"
    # Создаем файл с примерами и комментариями
    cat > "$CHANNELS_FILE" << EOL
# Это файл для списка YouTube-каналов.
# Добавьте URL каждого канала на новой строке.
# Строки, начинающиеся с #, и пустые строки игнорируются.

https://www.youtube.com/@MrBeast
https://www.youtube.com/@alphacentauri
EOL
    echo "Пожалуйста, отредактируйте файл и добавьте свои каналы, затем запустите скрипт снова."
    exit 0
fi

echo "--- $(date) ---"
echo "Начинаю проверку новых видео за последние $MAX_VIDEO_AGE..."
echo "Каналы будут прочитаны из файла: $CHANNELS_FILE"

# Читаем файл с каналами построчно
while IFS= read -r channel_url || [[ -n "$channel_url" ]]; do

    # Пропускаем пустые строки и строки, начинающиеся с #
    if [[ -z "$channel_url" || "$channel_url" =~ ^\s*# ]]; then
        continue
    fi

    # Так пытаемся сортировать по дате в убывающем порядке и брать только видео, если задан общий URL без уточнения
    # Регулярное выражение для поиска "коротких" URL (например, .../@Handle или .../@Handle/)
    handle_regex='^https?://(www\.)?youtube\.com/@[a-zA-Z0-9_.-]+/?$'

    if [[ "$channel_url" =~ $handle_regex ]]; then
        echo ""
        echo "Обнаружен короткий URL: $channel_url"
        # Удаляем необязательный слеш в конце, чтобы избежать двойного //
        channel_url="${channel_url%/}"
        # Добавляем /videos для получения списка видео, отсортированного по дате
        channel_url+="/videos"
        echo "URL преобразован в: $channel_url"
    fi


    echo ""
    echo "Обрабатываю канал: $channel_url"
    echo ""

    # Запускаем yt-dlp с новыми параметрами
#    yt-dlp \
#        --ignore-errors \
#	--no-overwrites \
#        --download-archive "$ARCHIVE_FILE" \
#        --dateafter "now-${MAX_VIDEO_AGE}" \
#        --output "$BASE_DIR/%(channel)s/%(title)s [%(id)s].%(ext)s" \
#        -vU --format 'bestvideo[height<=480]+bestaudio/best[height<=480]' --merge-output-format mp4 --cookies ~/Downloads/cookies-youtube-com.txt  \
#        "$channel_url"
#
##        --format "bestvideo[height<=1080]+bestaudio/best" \
##        --cookies "$HOME/youtube_cookies.txt" \

#         --format 'bestvideo[height<=480][ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4][height<=480]/best[height<=480]' \


#    yt-dlp \
#        --ignore-errors \
#        --no-overwrites \
#        --download-archive "$ARCHIVE_FILE" \
#        --dateafter "now-${MAX_VIDEO_AGE}" \
#        --output "$BASE_DIR/%(channel)s/%(title)s [%(id)s].%(ext)s" \
#        --format 'bestvideo[height<=480][ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4][height<=480]/best[height<=480]' \
#        --merge-output-format mp4 \
#        --cookies ~/Downloads/cookies-youtube-com.txt \
#        -vU \
#        "$channel_url"


       # --- Оптимизация производительности повторяем до 10 ошибок, например не соответствия дате ---
       # --- Фильтры и отслеживание ---

    yt-dlp \
        --ignore-errors \
        --no-overwrites \
        \
        --sleep-interval "$MIN_SLEEP" \
        --max-sleep-interval "$MAX_SLEEP" \
        \
        --lazy-playlist \
        --break-on-reject $NB_ERROR_LIMIT_MAX \
        \
        --download-archive "$ARCHIVE_FILE" \
        --dateafter "now-${MAX_VIDEO_AGE}" \
        --cookies "$COOKIES_FILE" \
        --format 'bestvideo[height<=480][ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4][height<=480]/best[height<=480]' \
        --merge-output-format mp4 \
        --output "$BASE_DIR/%(channel)s/%(title)s [%(id)s].%(ext)s" \
	-vU \
        "$channel_url"


# Эта команда ищет только заранее объединенные файлы.
# Качество будет НИЖЕ, и это может не сработать для всех видео.
# --format 'best[ext=mp4][height<=480]/best[height<=480]'
# без установки ffmpeg


     echo $channel_url

done < "$CHANNELS_FILE"

echo ""
echo "--- Проверка завершена ---"
