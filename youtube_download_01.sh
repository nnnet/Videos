#!/usr/bin/env bash

# Посмотреть список профилей можно:
# yt-dlp --cookies-from-browser firefox --print-traffic --simulate https://youtu.be/dQw4w9WgXcQ
#
# ls ~/.mozilla/firefox/*.default*/ -d
# $ ls ~/snap/firefox/common/.mozilla/firefox/
  #'Crash Reports'  'Pending Pings'  'Profile Groups'   profiles.ini   u5pcadw3.default
#  $ cat ~/snap/firefox/common/.mozilla/firefox/profiles.ini
#
# yt-dlp --cookies-from-browser firefox:"название_профиля" https://youtu.be/-IKk1zzVCmA

echo "===$(date)===" >> /tmp/cron_debug.txt
whoami >> /tmp/cron_debug.txt
env >> /tmp/cron_debug.txt
ls -l /home/uadmin/.local/bin/yt-dlp >> /tmp/cron_debug.txt
/home/uadmin/.local/bin/yt-dlp --version >> /tmp/cron_debug.txt 2>&1


echo ""
echo ""
echo "--- Start download $(date '+%Y-%m-%d %H:%M:%S') ---"

cd /mnt/82A23910A2390A65/Videos/

# ==============================================================================
#                      СКРИПТ ДЛЯ ЗАГРУЗКИ НОВЫХ ВИДЕО С YOUTUBE
#
# Принцип работы:
# 1. Этап 1: Поиск. Скрипт быстро проходит по всем каналам из файла _channels.txt
#    и составляет временный список URL-адресов только тех видео, которые:
#    а) Были опубликованы за последние MAX_VIDEO_AGE дней.
#    б) Еще не были скачаны (проверяется по файлу архива).
#
# 2. Этап 2: Загрузка. Если в списке есть новые видео, скрипт запускает одну
#    задачу yt-dlp для их скачивания. Между загрузкой каждого видео
#    делается случайная пауза для имитации человеческого поведения и обхода
#    ограничений со стороны YouTube.
# ==============================================================================


# --- НАСТРОЙКИ ---

# 1. Базовая директория, куда будут сохраняться все видео и файлы конфигурации.
#    Скрипт создаст ее, если она не существует.
#    Пример для Linux: BASE_DIR="$HOME/Видео/YouTube"
#    Пример для Windows (WSL) или внешнего диска: BASE_DIR="/mnt/d/Videos/YouTube"
BASE_DIR="/mnt/82A23910A2390A65/Videos"

# 2. Имя файла со списком каналов (будет находиться внутри BASE_DIR).
#    В файле должен быть один URL-адрес канала на строку.
CHANNELS_FILE="$BASE_DIR/_channels.txt"

# 3. Путь к файлу-архиву, где yt-dlp хранит ID уже скачанных видео.
ARCHIVE_FILE="$BASE_DIR/_download_archive.txt"

# 4. Скачивать только видео, которые были загружены не ранее указанного срока.
#    Форматы: "14days", "2weeks", "1month", "3months" и т.д.
MAX_VIDEO_AGE="30days"
#MAX_VIDEO_AGE="10days"
MAX_VIDEO_AGE="3months"

# 5. Путь к файлу с cookies от youtube.com. Необходим для доступа к приватным
#    плейлистам или для обхода возрастных ограничений.
#    Используйте расширение для браузера, чтобы его получить (например, 'Get cookies.txt').
#    Важно: символ '~' может не работать, используйте полную переменную $HOME.
COOKIES_FILE="$HOME/Downloads/cookies-youtube-com.txt"
COOKIES_FILE="$HOME/Downloads/youtube_cookies_003.txt"
# COOKIES_FILE="~/Downloads/cookies-youtube-com.txt" # Путь к вашим куки


# 6. Настройки "вежливости" для обхода rate-limit (ограничения на частоту запросов).
#    Паузы будут применяться МЕЖДУ скачиванием каждого видео.
MIN_SLEEP=10   # Минимальное время ожидания между видео (в секундах)
MAX_SLEEP=30   # Максимальное время ожидания между видео (в секундах)

# 7. Лимит проверки старых видео. yt-dlp прекратит проверку канала,
#    когда найдет N уже скачанных/старых видео подряд. Ускоряет поиск.
REJECT_LIMIT=10

# 8. Размер пакета (батча). Сколько URL обрабатывать за один запуск yt-dlp.
URLS_BATCH_SIZE=6


echo ""
echo "Скачиваем куки в файл $COOKIES_FILE"

#./get_cookies.py $COOKIES_FILE

echo "Скачали куки в файл $COOKIES_FILE"
echo ""

# --- КОНЕЦ НАСТРОЕК ---


# Проверка, установлены ли необходимые программы
#if ! command -v /home/uadmin/.local/bin/yt-dlp &> /dev/null; then
if [ ! -x /home/uadmin/.local/bin/yt-dlp ]; then
    echo "Ошибка: yt-dlp не установлен или не найден в PATH." >&2
    echo "Пожалуйста, установите его: https://github.com/yt-dlp/yt-dlp" >&2
    echo "--- End download $(date '+%Y-%m-%d %H:%M:%S') ---"
    exit 1
fi

if ! command -v ffmpeg &> /dev/null; then
    echo "Ошибка: ffmpeg не установлен. Он необходим для слияния видео и аудио." >&2
    echo "Пожалуйста, установите его (например, 'sudo apt install ffmpeg')." >&2
    echo "--- End download $(date '+%Y-%m-%d %H:%M:%S') ---"
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
# Пример:
# https://www.youtube.com/@MrBeast
# https://www.youtube.com/c/AlphaCentauri
EOL
    echo "Пожалуйста, отредактируйте файл, добавив свои каналы, и запустите скрипт снова."
    echo "--- End download $(date '+%Y-%m-%d %H:%M:%S') ---"
    exit 0
fi

# Создаем временные файлы и гарантируем их удаление при выходе
INITIAL_LIST_FILE=$(mktemp)
FINAL_LIST_FILE=$(mktemp)
trap 'rm -f "$INITIAL_LIST_FILE" "$FINAL_LIST_FILE"' EXIT


# --- ЭТАП 1: ПОИСК НОВЫХ ВИДЕО ---
echo "--- $(date '+%Y-%m-%d %H:%M:%S') ---"
echo "ЭТАП 1: Поиск новых видео за последние $MAX_VIDEO_AGE..."

# Инициализируем счетчик (индекс) перед началом цикла
index=0

while IFS= read -r channel_url || [[ -n "$channel_url" ]]; do
    if [[ -z "$channel_url" || "$channel_url" =~ ^\s*# ]]; then
        continue
    fi

    if [[ "$channel_url" =~ ^https?://(www\.)?youtube\.com/@[a-zA-Z0-9_.-]+/?$ ]]; then
        channel_url="${channel_url%/}/videos"
        echo " [INFO] Канал с коротким URL, преобразован в: $channel_url"
    fi

    echo ""
    echo "Проверяю канал: $channel_url"
    echo ""


#    if (( index % 4 == 0 )); then
#        # Если остаток от деления на 4 равен 0, значит, число кратно
#        echo "--- Достигнут шаг, кратный 4 (индекс: $index) ---"
#        echo ""
#        echo "Скачиваем куки в файл $COOKIES_FILE"
#        ./get_cookies.py $COOKIES_FILE
#        echo "Скачали куки в файл $COOKIES_FILE"
#        echo ""
#    fi

    /home/uadmin/.local/bin/yt-dlp \
        --ignore-errors \
        --get-id \
        --lazy-playlist \
        --break-on-reject \
        --download-archive "$ARCHIVE_FILE" \
        --dateafter "now-${MAX_VIDEO_AGE}" \
        --cookies-from-browser firefox \
        "$channel_url" < /dev/null >> "$INITIAL_LIST_FILE"

    # Увеличиваем счетчик на 1 в начале каждой итерации
    ((index++))

done < "$CHANNELS_FILE"

echo "Очистка списка от невалидных записей..."

echo "====================="
cat "$INITIAL_LIST_FILE"
echo "====================="
#sed -i '/youtube\.com/!d' "$INITIAL_LIST_FILE"
# Удаляем строки, которые:
# 1. Полностью пустые (^$)
# 2. Состоят только из "NA" (^NA$)
# 3. Состоят только из "N/A" (^N\/A$)
sed -i -E '/^$|^NA$|^N\/A$/d' "$INITIAL_LIST_FILE"
echo "====================="
cat "$INITIAL_LIST_FILE"
echo "====================="


# --- ЭТАП 2: ФИЛЬТРАЦИЯ И ЗАГРУЗКА ---
echo ""
echo "ЭТАП 2: Фильтрация и загрузка найденных видео..."

# Проверяем, нашлись ли вообще видео после первого этапа
if [ ! -s "$INITIAL_LIST_FILE" ]; then
    echo "Новых видео для загрузки не найдено."
    echo "--- Проверка завершена ---"
    echo "--- End download $(date '+%Y-%m-%d %H:%M:%S') ---"
    exit 0
else
  VIDEO_COUNT=$(wc -l < "$INITIAL_LIST_FILE")
  echo "Найдено видео для загрузки: $VIDEO_COUNT видео."
  echo "--- Проверка завершена ---"
fi

echo "Провожу финальную сверку с архивом..."

if [ -f "$ARCHIVE_FILE" ]; then
    # Извлекаем только ID из файла архива (второе поле после 'youtube ')
    # и используем их как шаблон для grep, чтобы найти совпадения в списке URL.
    #
    # grep -v: показать строки, НЕ содержащие шаблон (видео для скачивания)
    # grep без -v: показать строки, содержащие шаблон (видео для удаления)

    # Создаем окончательный список для скачивания
    grep -v -F -f <(awk '{print $2}' "$ARCHIVE_FILE") "$INITIAL_LIST_FILE" > "$FINAL_LIST_FILE"

    # Находим URL, которые были удалены из списка
    REMOVED_COUNT=$(grep -c -F -f <(awk '{print $2}' "$ARCHIVE_FILE") "$INITIAL_LIST_FILE")
    REMOVED_COUNT=${REMOVED_COUNT:-0}

    if [ "$REMOVED_COUNT" -gt 0 ]; then
        echo "--- Пропускаю $REMOVED_COUNT видео, так как они уже есть в архиве ---"
        grep -F -f <(awk '{print $2}' "$ARCHIVE_FILE") "$INITIAL_LIST_FILE"
        echo "--------------------------------------------------------"
    else
        echo "Все найденные видео - новые, в архиве не найдены."
    fi
else
    # Если архива нет, то все видео из начального списка идут в финальный
    cp "$INITIAL_LIST_FILE" "$FINAL_LIST_FILE"
fi
# --- КОНЕЦ НОВОГО БЛОКА ---


# Проверяем, остались ли видео после финальной фильтрации
if [ ! -s "$FINAL_LIST_FILE" ]; then
    echo "После финальной сверки с архивом видео для загрузки не осталось."
    echo "--- Проверка завершена ---"
    echo "--- End download $(date '+%Y-%m-%d %H:%M:%S') ---"
    exit 0
fi

VIDEO_COUNT=$(wc -l < "$FINAL_LIST_FILE")
echo ""
echo "Итого к загрузке: $VIDEO_COUNT видео."
#echo "--- Список видео для загрузки ---"
#cat "$FINAL_LIST_FILE"
echo "---------------------------------"
echo ""


if [ "$VIDEO_COUNT" -gt 0 ]; then
  echo "Начинаю загрузку с паузами от $MIN_SLEEP до $MAX_SLEEP секунд между видео..."

#  # Используем уже отфильтрованный FINAL_LIST_FILE.
#  # --download-archive оставляем как дополнительную меру защиты.
#  yt-dlp \
#      --verbose \
#      --ignore-errors \
#      --no-overwrites \
#      --batch-file "$FINAL_LIST_FILE" \
#      --download-archive "$ARCHIVE_FILE" \
#      --cookies "$COOKIES_FILE" \
#      --sleep-interval "$MIN_SLEEP" \
#      --max-sleep-interval "$MAX_SLEEP" \
#      --format 'bestvideo[height<=480][ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4][height<=480]/best[height<=480]' \
#      --merge-output-format mp4 \
#      --output "$BASE_DIR/%(channel)s/%(title)s [%(id)s].%(ext)s" \
#      ;
#
#  echo ""
#  echo "--- Загрузка завершена ---"

  # Создаем временную директорию для файлов-батчей
  # Она будет автоматически удалена при выходе из скрипта
  TEMP_DIR=$(mktemp -d)
  trap 'echo "=> Очистка временных файлов..."; rm -rf -- "$TEMP_DIR"' EXIT

  echo "=> Исходный файл: $FINAL_LIST_FILE"
  echo "=> Размер пакета: $URLS_BATCH_SIZE"
  echo "=> Временная директория для пакетов: $TEMP_DIR"
  echo ""

  # Разбиваем основной файл на пакеты по N строк
  split -l "$URLS_BATCH_SIZE" "$FINAL_LIST_FILE" "$TEMP_DIR/batch_"

  # Начинаем обработку
  batch_files_list=("$TEMP_DIR"/batch_*)
  total_batches=${#batch_files_list[@]}
  current_batch_num=0

  for batch_file in "${batch_files_list[@]}"; do
      ((current_batch_num++))

      # Пропускаем пустые файлы, если split их создал
      if [ ! -s "$batch_file" ]; then
          echo "--- Пропуск пустого пакета $(basename "$batch_file") ---"
          continue
      fi

      echo "=============================================================================="
      echo "--- Обработка пакета $current_batch_num из $total_batches (файл: $(basename "$batch_file")) ---"
      echo "=============================================================================="

      # ЗАПУСК КОМАНДЫ YT-DLP ДЛЯ ТЕКУЩЕГО ПАКЕТА
#      yt-dlp \
#        --verbose \
#        --ignore-errors \
#        --no-overwrites \
#        --batch-file "$batch_file" \
#        --download-archive "$ARCHIVE_FILE" \
#        --cookies "$COOKIES_FILE" \
#        --sleep-interval "$MIN_SLEEP" \
#        --max-sleep-interval "$MAX_SLEEP" \
#        --format 'bestvideo[height<=480][ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4][height<=480]/best[height<=480]' \
#        --merge-output-format mp4 \
#        --output "$BASE_DIR/%(channel)s/%(title)s [%(id)s].%(ext)s"

#      echo ""
#      echo "Скачиваем куки в файл $COOKIES_FILE"
#
#      ./get_cookies.py $COOKIES_FILE
#
#      echo "Скачали куки в файл $COOKIES_FILE"
#      echo ""

      /home/uadmin/.local/bin/yt-dlp \
          --verbose \
          --ignore-errors \
          --no-overwrites \
          --batch-file "$batch_file" \
          --download-archive "$ARCHIVE_FILE" \
          --cookies-from-browser firefox \
          --sleep-interval "$MIN_SLEEP" \
          --max-sleep-interval "$MAX_SLEEP" \
          --format 'bestvideo[height<=480][ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4][height<=480]/best[height<=480]' \
          --merge-output-format mp4 \
          --output "$BASE_DIR/%(channel)s/%(title)s [%(id)s].%(ext)s" \
          ;

      if [ $? -ne 0 ]; then
          echo "ВНИМАНИЕ: yt-dlp завершился с ошибкой при обработке пакета $current_batch_num. Продолжаем со следующим пакетом из-за опции --ignore-errors."
      fi

      echo ""
  done

  echo "=============================================================================="
  echo "✅ Все пакеты обработаны."
  echo "=============================================================================="


else
  echo "--- Загрузка отменена ---"
fi


echo "--- End download $(date '+%Y-%m-%d %H:%M:%S') ---"
