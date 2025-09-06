#!/usr/bin/env bash

# ==============================================================================
#   Автоматическое обновление файла cookies YouTube из запущенного Firefox
#   Версия с улучшенной диагностикой ошибок и правильным использованием yt-dlp.
# ==============================================================================

# --- НАСТРОЙКИ ---
DEFAULT_COOKIES_FILE="$HOME/youtube_cookies.txt"
# --- КОНЕЦ НАСТРОЕК ---

COOKIES_FILE="${1:-$DEFAULT_COOKIES_FILE}"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Проверка наличия yt-dlp
if ! command -v yt-dlp &> /dev/null; then
    log "ОШИБКА: yt-dlp не установлен или не найден в PATH. Установите его с официального сайта."
    exit 1
fi

# --- ШАГ 1: Поиск профиля Firefox ---
log "Поиск профиля Firefox..."
PROFILES_INI=""; declare -a potential_paths=("$HOME/.mozilla/firefox/profiles.ini" "$HOME/snap/firefox/common/.mozilla/firefox/profiles.ini" "$HOME/.var/app/org.mozilla.firefox/.mozilla/firefox/profiles.ini")
for path in "${potential_paths[@]}"; do if [ -f "$path" ]; then log "Найден файл конфигурации: $path"; PROFILES_INI="$path"; break; fi; done
if [ -z "$PROFILES_INI" ]; then
    log "Профиль не найден в стандартных местах. Запускаю общий поиск в $HOME..."
    PROFILES_INI=$(find "$HOME" -path '*/.mozilla/firefox/profiles.ini' -print -quit 2>/dev/null)
    if [ -z "$PROFILES_INI" ]; then log "ОШИБКА: Файл profiles.ini не найден."; exit 1; else log "Найден файл конфигурации: $PROFILES_INI"; fi
fi
PROFILE_PATH_DIR=$(dirname "$PROFILES_INI"); PROFILE_PATH_RELATIVE=$(awk -F= '/^\[Profile0\]/{a=1} a && /^Path=/{print $2;exit}' "$PROFILES_INI");
if [ -z "$PROFILE_PATH_RELATIVE" ]; then log "ОШИБКА: Не удалось определить путь к профилю из $PROFILES_INI"; exit 1; fi
PROFILE_PATH="$PROFILE_PATH_DIR/$PROFILE_PATH_RELATIVE"; log "Профиль найден: $PROFILE_PATH"
if [ ! -d "$PROFILE_PATH" ]; then log "ОШИБКА: Директория профиля не существует: $PROFILE_PATH"; exit 1; fi

# --- ШАГ 2: Копирование cookies ---
log "Создание временной копии cookies для обхода блокировки Firefox..."
TMP_DIR=$(mktemp -d); trap 'rm -rf -- "$TMP_DIR"' EXIT
cp -p "$PROFILE_PATH/cookies.sqlite"* "$TMP_DIR/" 2>/dev/null
if [ ! -f "$TMP_DIR/cookies.sqlite" ]; then log "ОШИБКА: Не удалось скопировать cookies.sqlite. Firefox запущен?"; exit 1; fi

# --- ШАГ 3: Извлечение cookies ---
log "Извлечение cookies в файл: $COOKIES_FILE"
TEMP_COOKIES_FILE=$(mktemp)

# Захватываем весь вывод (stdout и stderr) в переменную для отладки
YT_DLP_OUTPUT=$(yt-dlp \
    --cookies-from-browser "firefox:$TMP_DIR" \
    --dump-cookies "$TEMP_COOKIES_FILE" \
    "https://www.youtube.com" 2>&1)
YT_DLP_EXIT_CODE=$?

if [ $YT_DLP_EXIT_CODE -eq 0 ] && [ -s "$TEMP_COOKIES_FILE" ]; then
    mv "$TEMP_COOKIES_FILE" "$COOKIES_FILE"
    log "✅ Cookies успешно обновлены и сохранены."
else
    log "❌ ОШИБКА: yt-dlp не смог извлечь cookies (код завершения: $YT_DLP_EXIT_CODE)."
    log "--- Детальный вывод от yt-dlp ---"
    echo "$YT_DLP_OUTPUT" | sed 's/^/    /'
    log "--- Конец вывода ---"
    rm -f "$TEMP_COOKIES_FILE"
    exit 1
fi

exit 0