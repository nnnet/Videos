#!/usr/bin/env bash

# Откройте crontab -e и добавьте задание с полным путем к скрипту и перенаправлением вывода в лог-файл.

# 0 4 * * * /home/uadmin/youtube_downloader.sh >> /home/uadmin/youtube_downloader.log 2>&1


# --- НАСТРОЙКИ ---

# 1. Укажите браузер, из которого нужно извлечь cookies.
#    Допустимые значения: firefox, chrome, chromium, brave, vivaldi, opera, edge
#    yt-dlp будет автоматически искать стандартный профиль этого браузера.
BROWSER="firefox"

# 2. Файл, в который будут сохранены cookies.
#    Используйте "$HOME" для ссылки на домашнюю директорию.
COOKIES_FILE="$HOME/Downloads/youtube_cookies_001.txt"

# 3. URL, который будет открыт в браузере для входа.
#    Страница подписок - хороший выбор, т.к. сразу видно, вошли вы или нет.
URL_TO_OPEN="https://www.youtube.com/feed/subscriptions"
URL_TO_OPEN="https://www.youtube.com/@grebenukm/videos"

# --- КОНЕЦ НАСТРОЕК ---


# Проверка наличия необходимых утилит
if ! command -v yt-dlp &> /dev/null; then
    echo "Ошибка: yt-dlp не установлен или не найден в PATH."
    exit 1
fi

if ! command -v "$BROWSER" &> /dev/null; then
    echo "Ошибка: Браузер '$BROWSER' не найден в PATH."
    exit 1
fi

# --- ШАГ 1: Открытие браузера для пользователя ---
echo "Сейчас будет открыт браузер '$BROWSER'..."
echo "Пожалуйста, войдите в свой аккаунт YouTube (если еще не вошли)."
echo "Убедитесь, что страница полностью загрузилась."
"$BROWSER" "$URL_TO_OPEN" & # Знак '&' запускает браузер в фоновом режиме

# --- ШАГ 2: Ожидание подтверждения от пользователя ---
echo ""
read -p "После того, как вы вошли в аккаунт, вернитесь в этот терминал и нажмите [Enter], чтобы сохранить cookies..."

# --- ШАГ 3: Извлечение и сохранение cookies ---
echo ""
echo "Извлекаю cookies из '$BROWSER' и сохраняю в файл: $COOKIES_FILE"

# Используем yt-dlp для извлечения cookies с нужного домена и сохранения в файл
# Параметр --dump-cookies делает именно то, что нужно: извлекает и сохраняет, не скачивая видео.
yt-dlp \
    --cookies-from-browser "$BROWSER" \
    --dump-cookies "$COOKIES_FILE" \
    "$URL_TO_OPEN"

yt-dlp \
    --cookies-from-browser "$BROWSER" \
    --cookies "$COOKIES_FILE" \
    --quiet \
    --no-playlist \
    "$URL_TO_OPEN"

# Проверяем, успешно ли выполнилась команда
if [ $? -eq 0 ] && [ -s "$COOKIES_FILE" ]; then
    echo ""
    echo "✅ Cookies успешно сохранены в '$COOKIES_FILE'."
    echo "Файл содержит cookies для доменов YouTube."
    echo ""
    echo "Пример содержимого файла:"
    head -n 5 "$COOKIES_FILE"
else
    echo ""
    echo "❌ Произошла ошибка при сохранении cookies."
    echo "Возможные причины:"
    echo " - Браузер был закрыт слишком рано."
    echo " - yt-dlp не смог найти профиль браузера (попробуйте указать путь к профилю вручную)."
    echo " - В Linux может потребоваться закрыть браузер перед извлечением cookies."
fi