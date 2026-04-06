#!/bin/bash

# Проверка наличия аргумента
if [ -z "$1" ]; then
  echo "❌ Укажите путь к .mp4 файлу как аргумент."
  echo "Пример: ./transcribe.sh /путь/к/файлу.mp4"
  exit 1
fi

# Проверка, что файл существует
if [ ! -f "$1" ]; then
  echo "❌ Файл не найден: $1"
  exit 1
fi

# Проверка, что это mp4 файл
if [[ "$1" != *.mp4 ]]; then
  echo "❌ Файл должен иметь расширение .mp4"
  exit 1
fi

# Получаем абсолютный путь к файлу
MP4_PATH="$(realpath "$1")"
DIR_PATH="$(dirname "$MP4_PATH")"
FILENAME="$(basename "$MP4_PATH" .mp4)"

# Пути к другим файлам
WAV_PATH="$DIR_PATH/$FILENAME.wav"
TXT_PATH="$DIR_PATH/$FILENAME.txt"

echo "🎞️ Видео файл: $MP4_PATH"
echo "🎧 Аудио будет сохранено как: $WAV_PATH"
echo "📄 Транскрипция будет сохранена как: $TXT_PATH"

# 1. Извлечение аудио с помощью ffmpeg
ffmpeg -i "$MP4_PATH" -vn -acodec pcm_s16le -ar 16000 -ac 1 "$WAV_PATH"

# 2. Запуск Whisper через Docker
docker run --rm -v "$DIR_PATH":/data ghcr.io/openai/whisper:latest \
    --model medium --language auto --task transcribe --diarize true "/data/$FILENAME.wav"

# 3. Файл транскрипции должен быть создан как "$FILENAME.txt" в той же папке

# 4. Вставим путь к mp4 в начало файла
if [ -f "$TXT_PATH" ]; then
  sed -i "1i$MP4_PATH" "$TXT_PATH"
  echo "✅ Готово! Транскрипция сохранена в: $TXT_PATH"
else
  echo "❌ Ошибка: транскрипция не создана."
  exit 1
fi
