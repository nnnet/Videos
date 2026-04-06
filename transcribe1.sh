#!/bin/bash

# === 0. Проверка аргументов ===

# по умолчанию
FORCE_RECREATE=false
AUDIO_FORMAT="flac"  

# Обработка аргументов
while [[ $# -gt 0 ]]; do
  case $1 in
    --force|-f)
      FORCE_RECREATE=true
      shift
      ;;
    --format=*)
      AUDIO_FORMAT="${1#*=}"
      shift
      ;;
    *)
      MP4_INPUT="$1"
      shift
      ;;
  esac
done

# Проверка файла
if [ -z "$MP4_INPUT" ]; then
  echo "❌ Укажите путь к .mp4 файлу как аргумент."
  exit 1
fi

if [ ! -f "$MP4_INPUT" ]; then
  echo "❌ Файл не найден: $MP4_INPUT"
  exit 1
fi

if [[ "$MP4_INPUT" != *.mp4 ]]; then
  echo "❌ Файл должен иметь расширение .mp4"
  exit 1
fi

# === 1. Пути ===

MP4_PATH="$(realpath "$MP4_INPUT")"
DIR_PATH="$(dirname "$MP4_PATH")"
FILENAME="$(basename "$MP4_PATH" .mp4)"
WAV_PATH="$DIR_PATH/$FILENAME.wav"
TXT_PATH="$DIR_PATH/$FILENAME.txt"

echo "🎞️ Видео файл: $MP4_PATH"
echo "📁 Папка: $DIR_PATH"

# === 2. Если нет --force и есть уже .txt и .wav — пропускаем работу ===

if [ -f "$TXT_PATH" ] && [ -f "$WAV_PATH" ] && [ "$FORCE_RECREATE" = false ]; then
  echo "✅ Найдены оба файла: $TXT_PATH и $WAV_PATH"
  echo "ℹ️  Используется готовый результат. Укажи --force для пересоздания."
  exit 0
fi

# === 3. Создание временной директории и копирование файла ===

TEMP_DIR=$(mktemp -d)
if [ ! -d "$TEMP_DIR" ]; then
  echo "❌ Не удалось создать временную директорию."
  exit 1
fi

# Генерация случайного имени файла
TEMP_FILE="$TEMP_DIR/$(date +%s%N).mp4"

# Копирование исходного файла во временный файл
cp "$MP4_PATH" "$TEMP_FILE"

echo "📦 Копирование файла во временную директорию: $TEMP_FILE"

# Параметры ffmpeg

SAMPLE_RATE="16000"
CHANNELS="1"

# WAV
$CODEC="pcm_s16le"

# FLAC
BITRATE="320k"
CODEC="flac"

# Opus
BITRATE="96k"
CODEC="libopus"

#AUDIO_PATH="$DIR_PATH/$FILENAME.$AUDIO_FORMAT"
AUDIO_PATH="${TEMP_FILE%.mp4}.$AUDIO_FORMAT"

# === 4. Извлечение аудио ===
if [ "$FORCE_RECREATE" = true ] || [ ! -f "$WAV_PATH" ]; then
  echo "🎧 Извлекаю аудио из $TEMP_FILE в файл $AUDIO_PATH ..."
  # ffmpeg -i "$TEMP_FILE" -vn -acodec $CODEC -ar $SAMPLE_RATE -ac 1 "$WAV_PATH" -y

  # FLAC (без потерь, сжатый) в 5–10 раз меньше, чем WAV (PCM), без потери качества
  #ffmpeg -i "$TEMP_FILE" -vn -acodec $CODEC -ar $SAMPLE_RATE -ac $CHANNELS "$WAV_PATH" -y

  # Opus (лучше компрессия, возможна небольшая потеря)
  #ffmpeg -i "$TEMP_FILE" -vn -c:a $CODEC -b:a $BITRATE -ar $SAMPLE_RATE -ac $CHANNELS "$WAV_PATH" -y

  case "$AUDIO_FORMAT" in
    flac)
      BITRATE="320k"
      ffmpeg -i "$TEMP_FILE" -vn -acodec flac -ar $SAMPLE_RATE -ac $CHANNELS "$AUDIO_PATH" -y
      ;;
    opus)
      BITRATE="96k"
      ffmpeg -i "$TEMP_FILE" -vn -c:a libopus -b:a $BITRATE -ar $SAMPLE_RATE -ac $CHANNELS "$AUDIO_PATH" -y
      ;;
    wav)
      $CODEC="pcm_s16le"
      ffmpeg -i "$TEMP_FILE" -vn -acodec $CODEC -ar $SAMPLE_RATE -ac $CHANNELS "$AUDIO_PATH" -y
      ;;
    *)
      echo "❌ Неподдерживаемый формат аудио: $AUDIO_FORMAT"
      exit 1
      ;;
  esac

else
  echo "🎧 Аудиофайл уже существует: $WAV_PATH (используется без пересоздания)"
fi

# exit 1

# === 5. Запуск Whisper Web Service (если не запущен) ===
echo "🌀 Проверка whisper-asr-webservice..."

if ! docker ps | grep -q whisper-asr; then
  echo "🚀 Запускаю whisper-asr-webservice..."
  docker run -d --rm \
    --name whisper-asr --gpus all \
    -p 9000:9000 \
    -e ASR_MODEL=medium \
    onerahmet/openai-whisper-asr-webservice:latest-gpu
  echo "⏳ Ждём запуск сервиса..."
  sleep 5
else
  echo "✅ whisper-asr уже работает."
fi

# === 6. Отправка на API ===
echo "📡 Отправка файла $AUDIO_PATH на Whisper API..."
# RESPONSE=$(curl -s -X POST "http://localhost:9000/asr?diarization=true" \
RESPONSE=$(curl -# -X POST "http://localhost:9000/asr?diarization=true" \
  -H "accept: application/json" \
  -H "Content-Type: multipart/form-data" \
  -F "audio_file=@$AUDIO_PATH" \
  --max-time 600)

# === 7. Обработка ответа ===
TRANSCRIPT=$(echo "$RESPONSE" | jq -r '.text')

if [ "$TRANSCRIPT" == "null" ] || [ -z "$TRANSCRIPT" ]; then
  echo "❌ Ошибка: не удалось получить транскрипт."
  echo "Ответ сервера:"
  echo "$RESPONSE"
  exit 1
fi

# === 8. Сохранение транскрипции ===
echo "$MP4_PATH" > "$TXT_PATH"
echo "" >> "$TXT_PATH"
echo "$TRANSCRIPT" >> "$TXT_PATH"

echo "✅ Транскрипция сохранена в: $TXT_PATH"

# === 9. Очистка временных файлов ===
echo "🧹 Удаляю временные файлы..."
rm -rf "$TEMP_DIR"
echo "✅ Временные файлы удалены."

