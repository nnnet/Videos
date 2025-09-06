#!/usr/bin/env bash

set -euo pipefail

# Настройки
FTP_USER="pc"
FTP_PASS="569018"
FTP_HOST="ftp://10.0.0.2:8913"
REMOTE_BASE="/device/Movies"
SOURCE_DIR="/mnt/82A23910A2390A65/Videos"

DAYS_AGO=90  # 3 месяца "условно" = 90 дней
DAYS_AGO=30  # 1 месяц "условно" = 30 дней

# Пути (относительно $SOURCE_DIR), которые исключаем
EXCLUDE_PATHS=(
    "OLD_FOLDERS"
    "_scripts_temp"
    "111"
    ".git"
    ".idea"
)

# Добавьте список расширений, которые не нужно копировать
EXCLUDE_EXTENSIONS=(
    ".f140.m4a"
    ".tmp"
    # сюда можно добавить другие расширения (через точку)
)

should_exclude() {
    local filename="$1"
    for ext in "${EXCLUDE_EXTENSIONS[@]}"; do
        [[ "$filename" == *"$ext" ]] && return 0
    done
    return 1
}

echo "[INFO] Поиск новых файлов в: $SOURCE_DIR"

# Временные файлы
FILE_LIST=$(mktemp)
DIR_LIST=$(mktemp)

echo "[TRACE] Формируем выражение для исключений..."

# Собираем исключающие пути
EXCLUDE_EXPR=()
for path in "${EXCLUDE_PATHS[@]}"; do
    EXCLUDE_EXPR+=( -path "$SOURCE_DIR/$path" -prune -o )
    echo "[DEBUG] Добавляем исключение: $SOURCE_DIR/$path"
done

echo "[TRACE] Запускаем find для поиска файлов новее 3 месяцев..."
DATE_LIMIT=$(date --date="$DAYS_AGO days ago" +'%Y-%m-%d')

# Находим все файлы новее 3 месяцев с исключениями


DATE_LIMIT=$(date --date="$DAYS_AGO days ago" +'%Y-%m-%d')

TMP_SORTED=$(mktemp)


find "$SOURCE_DIR" \
    ${EXCLUDE_EXPR[@]} \
    -type f -newermt "$DATE_LIMIT" \
    $(for ext in "${EXCLUDE_EXTENSIONS[@]}"; do echo "! -iname *$ext"; done) \
    -printf '%T@ %p\0' 2>/dev/null |
  sort -z -k1,1nr |
  awk -v RS='\0' -v src="$SOURCE_DIR/" '
    {
      if ($0 == "") next
      # отделяем метку времени только по ПЕРВОМУ пробелу, всё остальное = путь
      time_and_path = $0
      space = index(time_and_path, " ")
      if (!space) next
      file = substr(time_and_path, space+1)
      rel = file
      sub("^"src, "", rel)
      if (index(rel, "/") > 0) print file
    }
  ' > "$TMP_SORTED"



# cat $TMP_SORTED
# 2. Перебираем этот файл, обеспечивая строгую безопасность:
> "$FILE_LIST"
tr '\0' '\n' < "$TMP_SORTED" > "$FILE_LIST"

# rm -f "$TMP_SORTED"
# ls -lh "$FILE_LIST"
cat $FILE_LIST

# exit

FILE_COUNT=$(wc -l < "$FILE_LIST")
echo -e "\n[INFO] Найдено $FILE_COUNT файлов новее 3 месяцев"

# echo "[TRACE] Собираем список папок первого уровня, в которых есть новые файлы..."

# Извлекаем директории первого уровня с новыми файлами
awk -v dir="$SOURCE_DIR" -F/ '
    $0 ~ "^"dir"/" {
        rel = substr($0, length(dir)+2)   # относительный путь к файлу
        if(split(rel,a,"/")>1) print a[1]
    }
' "$FILE_LIST" | sort -u > "$DIR_LIST"

echo -e "\n[RESULT] Папки первого уровня с файлами новее 3 месяцев:"
cat "$DIR_LIST"


echo -e "\n[TRACE] Копирую новые файлы на удалённую машину с сохранением структуры..."


# === Функция создания всех вложенных папок (аналог mkdir -p) ===

# заменяем опасные символы в пути и имени файла
# Разрешённые символы:

# safe_filename() {
#   echo "$1" | sed 's/[:]/_/g; s/[^A-Za-z0-9.,_@$ \[\]\-ЁёАБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯабвгдежзийклмнопрстуфхцчшщъыьэюя]/_/g'
# }
SAFE_CHARS='A-Za-z0-9.,_@$ \[\]\-ЁёАБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯабвгдежзийклмнопрстуфхцчшщъыьэюя'
safe_filename() {
  echo "$1" | sed "s/[:]/_/g; s/[^$SAFE_CHARS]/_/g"
}

safe_relpath() {
    local relpath="$1"
    local path_part file_part safe_path safe_file
    path_part=$(dirname "$relpath")
    file_part=$(basename "$relpath")
    safe_path=""
    IFS='/' read -ra PARTS <<< "$path_part"
    for part in "${PARTS[@]}"; do
        safe_part=$(safe_filename "$part")
        [[ -z "$safe_part" ]] && continue
        safe_path="${safe_path:+$safe_path/}$safe_part"
    done
    safe_file=$(safe_filename "$file_part")
    if [[ -n "$safe_path" ]]; then
        echo "$safe_path/$safe_file"
    else
        echo "$safe_file"
    fi
}

_PREV_FTPMKDIR=''


ftp_mkdirs() {
    if [[ "${_PREV_FTPMKDIR:-}" == "$1" ]]; then
        echo "MKDIR_SKIP: [$1]"
        return 0
    fi
    export _PREV_FTPMKDIR="$1"

    local full_dir="$1"
    local current=""
    local dir="${full_dir#/}"

    # echo "DIR: [$dir]"

    IFS='/' read -r -a PARTS <<< "$dir"
    for idx in "${!PARTS[@]}"; do
        part="${PARTS[$idx]}"
        # echo "[$idx] [$part]"
    done

    for part in "${PARTS[@]}"; do
        [[ -z "$part" ]] && continue
        current="${current:+$current/}$part"

        set +e
        lftp -u "$FTP_USER","$FTP_PASS" "$FTP_HOST" -e "cls -d \"/$current\"; bye" > /dev/null 2>&1
        exists=$?
        set -e

        if [[ $exists -eq 0 ]]; then
            # echo "MKDIR_EXISTS: [$current]"
            continue
        else
            echo "MKDIR: [$current]"
            set +e
            lftp -u "$FTP_USER","$FTP_PASS" "$FTP_HOST" -e "mkdir \"/$current\"; bye" > /dev/null 2>&1
            set -e
            echo "MKDIR_END: [$current]"
        fi
    done
}


while IFS= read -r folder_rel; do
    echo -e "\n[COPY]  $folder_rel"

    # Получаем имена файлов на FTP в этой папке
    remotepath="$REMOTE_BASE/$folder_rel"

    # echo -e "\n[COPY 0]  $folder_rel $remotepath"
    ftp_mkdirs "$remotepath"
    # echo -e "\n[COPY 00]  $folder_rel"

    # lftp -u "$FTP_USER","$FTP_PASS" "$FTP_HOST" <<EOF > /tmp/ftp_dir_files_full.txt 2>/dev/null
    lftp -u "$FTP_USER","$FTP_PASS" "$FTP_HOST" <<EOF > /tmp/ftp_dir_files_full.txt
find "$remotepath"
EOF

    # echo -e "\n[COPY 1]  $folder_rel"

    awk -v base="$REMOTE_BASE/" '
        { file=$0; sub("^" base, "", file); if(length(file) && file !~ /\/$/) print file }
    ' /tmp/ftp_dir_files_full.txt |
    while IFS= read -r relfile; do
        safe_full=$(safe_relpath "$relfile")
        echo "$safe_full"
    done > /tmp/ftp_dir_files_relative.txt

    # echo -e "\n[COPY 2]  $folder_rel"


    # echo -e "\n[TRACE] Относительные имена файлов на FTP (рекурсивно):"
    # cat /tmp/ftp_dir_files_relative.txt

    # continue

    awk -v d="$SOURCE_DIR/$folder_rel/" '$0 ~ "^"d {print $0}' "$FILE_LIST" | while IFS= read -r filepath; do

        # printf '\n[DEBUG] start awk: %q\n' "$filepath"

        relpath="${filepath#$SOURCE_DIR/}"
        relpath_dir="$(dirname "$relpath")"
        ftp_target_dir="$REMOTE_BASE/$relpath_dir"

        # printf '\n[DEBUG] 0.5.0 filepath for stat: %q\n' "$filepath"

        if should_exclude "$(basename "$relpath")"; then
            echo -e "\n[SKIP]  $relpath (по расширению)"
            continue
        fi
        
        # printf '\n[DEBUG] 0.7.0 filepath for stat: %q\n' "$filepath"

        # !!! ВАЖНО: Оригинальный абсолютный путь — ТОЛЬКО переменная от find:
        orig_filepath="$filepath"    
        # ls -l "$orig_filepath"

        # printf '\n[DEBUG] 0.8.0 orig_filepa for stat: %q\n' "$orig_filepath"

        # Оригинальные значения
        orig_relpath="$relpath"

        # printf '\n[DEBUG] filepath for stat: %q\n' "$orig_filepath"
        # # ls -l "$orig_filepath"
        # printf '[DEBUG] 1.0 filepath for stat: %q\n' "$orig_filepath"


        # Безопасный относительный путь и имя
        safe_full=$(safe_relpath "$relpath")
        # Отдельно путь и имя, если нужно:
        safe_path=$(dirname "$safe_full")
        ftp_safe_name=$(basename "$safe_full")
        ftp_target_dir="$REMOTE_BASE/$safe_path"

        ftp_safe_relpath="$safe_path/$ftp_safe_name"

        # # ls -l "$orig_filepath"
        # printf '[DEBUG] 1.0.0 filepath for stat: %q\n' "$orig_filepath"


        # # file_ctime=$(stat -c '%Y' "$orig_filepath")
        # # # file_ctime_str=$(date -d @"$file_ctime" '+%Y-%m-%d %H:%M')
        # # # echo "[SYNC] $file_ctime_str $orig_relpath → $ftp_target_dir/$ftp_safe_name"
        # file_birth=$(stat -c '%W' "$orig_filepath")
        # # ls -l "$orig_filepath"

        # # printf '[DEBUG] 1.1,5 filepath for stat: %q\n' "$orig_filepath"
        # # printf '[DEBUG] 1.1,5 filepath for stat: %q\n' "$orig_filepath"

        # if [[ "$file_birth" == "0" || -z "$file_birth" ]]; then
        #     # если birth-time недоступен, fallback на ctime
        #     # file_birth=$file_ctime
        #     file_birth=$(stat -c '%Y' "$orig_filepath")
        # fi
        file_birth=$(stat -c '%Y' "$orig_filepath")

        # printf '[DEBUG] 1.1,6 filepath for stat: %q\n' "$orig_filepath"
        file_birth_str=$(date -d @"$file_birth" '+%Y-%m-%d %H:%M')

        # 5. Проверка: существует ли файл в таком безопасном виде на FTP
        if grep -Fxq "$ftp_safe_relpath" /tmp/ftp_dir_files_relative.txt; then
            echo "[EXIST] $file_birth_str $ftp_safe_relpath"
            continue
        else

            # printf '[DEBUG] 1.1.1 filepath for stat: %q\n' "$orig_filepath"
            # # ls -l "$orig_filepath"
            # printf '[DEBUG] 1.1.2 filepath for stat: %q\n' "$orig_filepath"
            # echo -n "$orig_filepath" | hexdump -C
            # echo -n "$orig_filepath"

            # printf '[DEBUG] 1.1 filepath for stat: %q\n' "$orig_filepath"
            echo "[SYNC] Копирую $file_birth_str $orig_relpath → $ftp_target_dir/$ftp_safe_name"

            # printf '[DEBUG] 1.2 filepath for stat: %q\n' "$orig_filepath"
            # printf '\n[DEBUG] 1.2.1 =============\n'
            # printf '[DEBUG] 1.2.5 filepath for stat: %q' "$ftp_target_dir"
            # printf '\n\n'

            # ftp_mkdirs "$ftp_target_dir"
            # echo "[DEBUG] CALLING ftp_mkdirs [$ftp_target_dir]"
            ftp_mkdirs "$ftp_target_dir"
            # echo "[DEBUG] END CALL ftp_mkdirs [$ftp_target_dir]"

            # exit

            # printf '[DEBUG] 1.3 filepath for stat: %q\n' "$orig_filepath"

            # # which lftp || { echo '[ERROR] lftp не найден в PATH'; exit 127; }
            # echo "------"
            # echo "[PRE-CHECK] orig_filepath=$orig_filepath"
            # ls -la "$orig_filepath"
            # echo "[PRE-CHECK] ftp_target_dir=$ftp_target_dir"
            # echo "[PRE-CHECK] ftp_safe_name=$ftp_safe_name"
            # echo "------"

            set +e
            timeout 600 lftp -u "$FTP_USER","$FTP_PASS" "$FTP_HOST" <<EOF > /tmp/lftp_put_out.txt 2>&1
cd "$ftp_target_dir"
put "$orig_filepath" -o "$ftp_safe_name"
ls
EOF
            ret=$?
            set -e

            # # Здесь — строго соответствует отправленной lftp-команде!
            # echo "[COPY-DEBUG] put \"$orig_filepath\" -O \"$ftp_target_dir\" -- \"$ftp_safe_name\""

            if [[ ! -f "$orig_filepath" ]]; then
                echo "[ERROR] Файл не найден: $orig_filepath"
            fi

            # echo "[LFTP-OUT]"
            # cat /tmp/lftp_put_out.txt
            # echo "[LFTP-END]"

            if [[ $ret -ne 0 ]]; then
                echo -e "\n[TEST] lftp завершился с кодом $ret, $orig_filepath → $ftp_target_dir/$ftp_safe_name"

                echo -e "\n------"
                echo "[PRE-CHECK] orig_filepath=$orig_filepath"
                ls -la "$orig_filepath"
                echo "[PRE-CHECK] ftp_target_dir=$ftp_target_dir"
                echo "[PRE-CHECK] ftp_safe_name=$ftp_safe_name"
                echo "------"

                echo -e "\n[ERROR] lftp завершился с ошибкой ($ret) при копировании $orig_filepath → $ftp_target_dir/$ftp_safe_name\n"
            else
                # echo "[OK] lftp завершился успешно ($ret)"
                continue
            fi


        fi

    done

    # break
done < "$DIR_LIST"

# ... последующие действия (удаление временных файлов и т.д.) ...

echo -e "\n[FINISH] Список файлов первой папки обработан."

rm -f "$FILE_LIST" "$DIR_LIST" /tmp/ftp_dir_files.txt /tmp/ftp_dir_files_relative.txt


# lftp -u "pc","569018" ftp://10.0.0.2:8913
# # дальше внутри lftp:
# mkdir -p "/device/Movies/Михаил Гребенюк/Аномалия/Курсы/Как создать сильный продукт"   # если mkdir поддерживается
# cd "/device/Movies/Михаил Гребенюк/Аномалия/Курсы/Как создать сильный продукт"
# put "/mnt/82A23910A2390A65/Videos/Михаил Гребенюк/Аномалия/Курсы/Как создать сильный продукт/4.1 Разборы: Отстройка от конкурентов.mp4"
