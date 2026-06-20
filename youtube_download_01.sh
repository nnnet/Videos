#!/usr/bin/env bash

# PO Token (2026-06-20): YouTube требует PO Token, иначе бот-капча "Sign in to
# confirm you're not a bot". Локальный bgutil-сервер (:4416) генерит токен;
# yt-dlp берёт его автоматически.
# no_proxy ОБЯЗАТЕЛЕН — иначе yt-dlp лезет на свой же 127.0.0.1:4416 через
# датацентровый прокси (localhost:3128) и не достучится.
export no_proxy="127.0.0.1,localhost,::1,${no_proxy:-}"
export NO_PROXY="$no_proxy"

# --- PO Token сервер: поднимаем НА ВРЕМЯ загрузки, гасим в конце ---------------
# Не держим постоянный systemd-сервис (просьба не загромождать хост). Сервер
# стартует здесь, trap EXIT гарантированно убивает его при любом выходе
# (успех/ошибка/Ctrl-C). Если порт уже занят (ручной запуск / параллельный
# прогон) — не плодим второй, переиспользуем существующий.
POT_DIR="/home/uadmin/bgutil-ytdlp-pot-provider/server"
POT_PORT=4416
POT_PID=""
_pot_up() { curl -s --max-time 3 "http://127.0.0.1:$POT_PORT/ping" 2>/dev/null | grep -q server_uptime; }
_pot_stop() {
    if [ -n "$POT_PID" ] && kill -0 "$POT_PID" 2>/dev/null; then
        kill "$POT_PID" 2>/dev/null
        echo "PO Token сервер остановлен (pid $POT_PID)."
    fi
}
if _pot_up; then
    echo "PO Token сервер уже запущен на :$POT_PORT — переиспользую."
elif [ -f "$POT_DIR/build/main.js" ]; then
    node "$POT_DIR/build/main.js" >/tmp/bgutil-pot.log 2>&1 &
    POT_PID=$!
    trap '_pot_stop' EXIT
    for i in 1 2 3 4 5 6 7 8 9 10; do _pot_up && break; sleep 0.5; done
    if _pot_up; then
        echo "PO Token сервер запущен (pid $POT_PID, :$POT_PORT)."
    else
        echo "ВНИМАНИЕ: PO Token сервер не поднялся за 5с — YouTube может дать бот-капчу. См /tmp/bgutil-pot.log" >&2
    fi
else
    echo "ВНИМАНИЕ: нет $POT_DIR/build/main.js — PO Token сервер не запущен, возможна бот-капча." >&2
fi
# ------------------------------------------------------------------------------

# Обновляем yt-dlp
# pip install -U --break-system-packages yt-dlp

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

# === Anti-race: ждём пока сеть доступна (до 5 мин) ===
# При запуске из cron VPN/TUN routing может ещё переустанавливаться, и
# yt-dlp получит "Network is unreachable" / SSL EOF. Проверяем что
# youtube.com отвечает прежде чем стартовать (cron-incident 2026-05-29).
WAIT_MAX=300
WAIT_INTERVAL=10
elapsed=0
while ! curl --max-time 10 -fsS -o /dev/null https://www.youtube.com 2>/dev/null; do
    if [ "$elapsed" -ge "$WAIT_MAX" ]; then
        echo "FATAL: youtube.com недоступен после ${WAIT_MAX}с ожидания — выход" >&2
        exit 1
    fi
    echo "Сеть/VPN не готова (curl youtube.com failed), жду ${WAIT_INTERVAL}с... ${elapsed}/${WAIT_MAX}"
    sleep "$WAIT_INTERVAL"
    elapsed=$(( elapsed + WAIT_INTERVAL ))
done
echo "Сеть OK через ${elapsed}с"

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
BASE_DIR="/mnt/82A23910A2390A65/Videos/Youtube"

# 2. Имя файла со списком каналов (находится в корневой папке проекта).
CHANNELS_FILE="/mnt/82A23910A2390A65/Videos/_channels.txt"

# 3. Путь к файлу-архиву, где yt-dlp хранит ID уже скачанных видео.
ARCHIVE_FILE="/mnt/82A23910A2390A65/Videos/_download_archive.txt"

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
#    echo "Ошибка: yt-dlp не установлен или не найден в PATH." >&2
    echo -e "\033[31m❌ Ошибка: yt-dlp не установлен или не найден в PATH.\033[0m" >&2
    echo "Пожалуйста, установите его: https://github.com/yt-dlp/yt-dlp" >&2
    echo "--- End download $(date '+%Y-%m-%d %H:%M:%S') ---"
    exit 1
fi

if ! command -v ffmpeg &> /dev/null; then
#    echo "Ошибка: ffmpeg не установлен. Он необходим для слияния видео и аудио." >&2
    echo -e "\033[31m❌ Ошибка: ffmpeg не установлен. Он необходим для слияния видео и аудио.\033[0m" >&2
    echo "Пожалуйста, установите его (например, 'sudo apt install ffmpeg')." >&2
    echo "--- End download $(date '+%Y-%m-%d %H:%M:%S') ---"
    exit 1
fi

if ! command -v ffprobe &> /dev/null; then
    echo -e "\033[31m❌ Ошибка: ffprobe не найден (входит в пакет ffmpeg).\033[0m" >&2
    echo "--- End download $(date '+%Y-%m-%d %H:%M:%S') ---"
    exit 1
fi

# --- ПРОВЕРКА A/V КАЧЕСТВА СКАЧАННОГО MP4 ---
# Возвращает 0 если файл содержит и video, и audio поток с близкими длительностями.
# Возвращает 1 в любом другом случае (нет потока, обрыв, не открывается).
verify_av_streams() {
    local file="$1"
    local has_video has_audio
    has_video=$(ffprobe -v error -select_streams v:0 \
                        -show_entries stream=codec_type \
                        -of default=nw=1:nk=1 "$file" 2>/dev/null || true)
    has_audio=$(ffprobe -v error -select_streams a:0 \
                        -show_entries stream=codec_type \
                        -of default=nw=1:nk=1 "$file" 2>/dev/null || true)
    [[ "$has_video" != "video" ]] && return 1
    [[ "$has_audio" != "audio" ]] && return 1

    local v_dur a_dur fmt_dur
    v_dur=$(ffprobe -v error -select_streams v:0 \
                    -show_entries stream=duration \
                    -of default=nw=1:nk=1 "$file" 2>/dev/null || true)
    a_dur=$(ffprobe -v error -select_streams a:0 \
                    -show_entries stream=duration \
                    -of default=nw=1:nk=1 "$file" 2>/dev/null || true)
    fmt_dur=$(ffprobe -v error -show_entries format=duration \
                      -of default=nw=1:nk=1 "$file" 2>/dev/null || true)
    [[ -z "$v_dur" || "$v_dur" == "N/A" ]] && v_dur="$fmt_dur"
    [[ -z "$a_dur" || "$a_dur" == "N/A" ]] && a_dur="$fmt_dur"
    [[ -z "$v_dur" || -z "$a_dur" ]] && return 1

    awk -v v="$v_dur" -v a="$a_dur" 'BEGIN{
        d = v - a; if (d < 0) d = -d;
        # допуск 1.5 сек: достаточно для нормальных контейнеров
        exit (d <= 1.5) ? 0 : 1
    }'
}

# Чистит мусор от незавершённых загрузок и битые mp4.
# - Whitelist «мусорных» расширений (защищает PDF/XLSX/DOCX и пр. курсы);
# - Если удалённый файл имеет [id] и нет сопутствующего mp4 — id убирается из архива;
# - Каждый mp4 верифицируется ffprobe (video+audio, длительности ±1.5с).
verify_and_clean_channel() {
    local channel_dir="$1"
    [[ ! -d "$channel_dir" ]] && return 0

    echo "→ $(basename "$channel_dir")"

    # 1. Собрать ID для которых есть mp4 (рекурсивно по дереву канала)
    declare -A has_mp4=()
    local mp4 fname id
    while IFS= read -r -d '' mp4; do
        fname=$(basename "$mp4")
        if [[ "$fname" =~ \[([a-zA-Z0-9_-]{11})\]\.mp4$ ]]; then
            has_mp4["${BASH_REMATCH[1]}"]=1
        fi
    done < <(find "$channel_dir" -type f -name '*.mp4' -print0)

    # 2. Удалить файлы по whitelist «мусорных» расширений.
    #    Если у файла есть [id] и mp4 с таким id отсутствует — убрать id из архива.
    local removed=0 archive_purged=0 f
    while IFS= read -r -d '' f; do
        fname=$(basename "$f")
        if [[ "$fname" =~ \[([a-zA-Z0-9_-]{11})\]\.[^/]+$ ]]; then
            id="${BASH_REMATCH[1]}"
            if [[ -z "${has_mp4[$id]:-}" ]]; then
                if [[ -f "$ARCHIVE_FILE" ]] && grep -qE "^youtube[[:space:]]+${id}\$" "$ARCHIVE_FILE"; then
                    sed -i "/^youtube[[:space:]]\+${id}\$/d" "$ARCHIVE_FILE"
                    archive_purged=$((archive_purged + 1))
                fi
            fi
        fi
        rm -f "$f"
        removed=$((removed + 1))
    done < <(find "$channel_dir" -type f \( \
            -name '*.part' -o \
            -name '*.ytdl' -o \
            -name '*.m4a' -o \
            -name '*.webm' -o \
            -name '*.flac' -o \
            -name '*.opus' -o \
            -name '*.wav' -o \
            -name '*.mkv' -o \
            -name '*.aac' -o \
            -name '*.ogg' -o \
            -name '*.ts' -o \
            -name '*.temp.*' -o \
            -name '*.f[0-9]*.mp4' -o \
            -name '*.f[0-9]*.webm' -o \
            -name '*.f[0-9]*.m4a' \
        \) -print0)

    [[ $removed -gt 0 ]] && echo "   мусор удалён: $removed файл(ов); из архива убрано: $archive_purged ID"

    # 3. Проверить каждый mp4 на наличие video+audio и совпадение длительностей
    local broken=0
    while IFS= read -r -d '' mp4; do
        if verify_av_streams "$mp4"; then
            continue
        fi
        fname=$(basename "$mp4")
        echo -e "\033[31m   ❌ [BROKEN] $fname\033[0m"
        # ID может быть в любом месте имени: name [ID].mp4 или name [ID].fNNN.mp4
        if [[ "$fname" =~ \[([a-zA-Z0-9_-]{11})\] ]]; then
            id="${BASH_REMATCH[1]}"
            if [[ -f "$ARCHIVE_FILE" ]] && grep -qE "^youtube[[:space:]]+${id}\$" "$ARCHIVE_FILE"; then
                sed -i "/^youtube[[:space:]]\+${id}\$/d" "$ARCHIVE_FILE"
                echo "   ⤷ ID $id убран из архива — будет перекачан"
            fi
        fi
        rm -f "$mp4"
        broken=$((broken + 1))
    done < <(find "$channel_dir" -type f -name '*.mp4' -print0)

    [[ $broken -gt 0 ]] && echo "   битых mp4 удалено: $broken"
}

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
# Сюда yt-dlp будет писать финальные пути каждого смерджённого видео
# (через --print-to-file "after_move:%(filepath)s"). По этим путям после загрузки
# мы поймём ровно те папки каналов, в которые шла запись.
DOWNLOADED_PATHS_FILE=$(mktemp)
trap 'rm -f "$INITIAL_LIST_FILE" "$FINAL_LIST_FILE" "$DOWNLOADED_PATHS_FILE"' EXIT


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

    /home/uadmin/.local/bin/yt-dlp \
        --js-runtimes quickjs \
        --remote-components ejs:github \
        --flat-playlist \
        --lazy-playlist \
        --print "%(id)s" \
        --break-on-existing \
        --download-archive "$ARCHIVE_FILE" \
        --playlist-end 30 \
        --extractor-args "youtubetab:skip=authcheck" \
        --socket-timeout 60 \
        --retries 10 \
        --cookies-from-browser firefox \
        "$channel_url" < /dev/null >> "$INITIAL_LIST_FILE" || true

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
    echo "--- Все видео из начального списка идут в финальный ---"
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
  # Префлайт: YouTube блокирует датацентровые/VPN IP бот-капчей независимо от
  # кук (диагностика 2026-06-20: весь трафик уходил через Happ VPN → Hetzner,
  # exit 95.217.241.97 → "Sign in to confirm you're not a bot"). Сам не падаем,
  # но пишем громкую причину в лог, чтобы сбой читался сразу, а не как спам
  # бот-капчи по каждому видео. Фикс — split-tunnel youtube в Happ (geosite:youtube
  # → direct), тогда exit становится домашним.
  exit_org=$(timeout 10 curl -s "https://ipinfo.io/org" 2>/dev/null)
  if printf '%s' "$exit_org" | grep -qiE 'hetzner|ovh|digitalocean|linode|vultr|amazon|google cloud|datacenter|m247|leaseweb|contabo'; then
      echo "ВНИМАНИЕ: внешний IP — датацентр/VPN ($exit_org). YouTube почти наверняка"
      echo "         отдаст бот-капчу. Нужен split-tunnel youtube в Happ (geosite:youtube → direct)"
      echo "         или пауза VPN на время загрузки. Продолжаю попытку, но возможен провал."
  else
      echo "Префлайт OK: внешний IP не датацентр (${exit_org:-неизвестно})."
  fi

  echo "Начинаю загрузку с паузами от $MIN_SLEEP до $MAX_SLEEP секунд между видео..."

  # Создаем временную директорию для файлов-батчей
  # Она будет автоматически удалена при выходе из скрипта
  TEMP_DIR=$(mktemp -d)
  trap 'echo "=> Очистка временных файлов..."; rm -f "$INITIAL_LIST_FILE" "$FINAL_LIST_FILE" "$DOWNLOADED_PATHS_FILE"; rm -rf -- "$TEMP_DIR"' EXIT

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
      /home/uadmin/.local/bin/yt-dlp \
          --js-runtimes quickjs \
          --remote-components ejs:github \
          --ignore-errors \
          --no-overwrites \
	  --cookies-from-browser firefox \
          --batch-file "$batch_file" \
          --download-archive "$ARCHIVE_FILE" \
          --cookies-from-browser firefox \
          --extractor-args "youtubetab:skip=authcheck" \
          --socket-timeout 60 \
          --retries 10 \
          --fragment-retries 10 \
          --sleep-interval "$MIN_SLEEP" \
          --max-sleep-interval "$MAX_SLEEP" \
          --match-filter "!is_live & !was_live & live_status != 'is_upcoming'" \
          --format 'bestvideo[height<=480][ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4][height<=480]/best[height<=480]' \
          --merge-output-format mp4 \
          --output "$BASE_DIR/%(channel)s/%(title)s [%(id)s].%(ext)s" \
          --print-to-file "after_move:%(filepath)s" "$DOWNLOADED_PATHS_FILE" \
          ;

      if [ $? -ne 0 ]; then
          echo "ВНИМАНИЕ: yt-dlp завершился с ошибкой при обработке пакета $current_batch_num. Продолжаем со следующим пакетом из-за опции --ignore-errors."
      fi
      # Папки каналов, в которые шла запись, мы узнаём из $DOWNLOADED_PATHS_FILE
      # после всех батчей — не нужно угадывать по URL.
      echo ""
  done

  echo "=============================================================================="
  echo "✅ Все пакеты обработаны."
  echo "=============================================================================="


else
  echo "--- Загрузка отменена ---"
fi

# Шаг 3: Очистка мусора + проверка A/V целостности.
# Берём ровно те папки каналов, в которые писал yt-dlp в этом запуске:
# из $DOWNLOADED_PATHS_FILE (наполняется флагом --print-to-file after_move).
if [[ -s "$DOWNLOADED_PATHS_FILE" ]]; then
    echo "Очистка мусора и проверка A/V целостности в папках с новыми загрузками..."

    declare -A channels_seen=()
    while IFS= read -r filepath; do
        [[ -z "$filepath" ]] && continue
        chan_dir=$(dirname "$filepath")
        # Защита: убедимся, что путь внутри $BASE_DIR
        case "$chan_dir/" in
            "$BASE_DIR"/*) channels_seen["$chan_dir"]=1 ;;
        esac
    done < "$DOWNLOADED_PATHS_FILE"

    cleaned_count=0
    for chan_dir in "${!channels_seen[@]}"; do
        verify_and_clean_channel "$chan_dir"
        cleaned_count=$((cleaned_count + 1))
    done

    echo -e "\033[32m✅ Очистка и проверка завершены ($cleaned_count папок).\033[0m"
else
    echo "Пропускаю очистку: новых файлов в этом запуске не было."
fi

echo "--- End download $(date '+%Y-%m-%d %H:%M:%S') ---"
