#!/usr/bin/env bash
# Вытащить из всех Timeshift-снапшотов все папки уровня /home/uadmin/.claude*
# (включая .claude, .claude_back, .claude.bak и т.п.) в
# /mnt/82A23910A2390A65/Videos/claude_snapshots/<snapshot-date>/<имя_папки>/
#
# Идемпотентен: если папка уже извлечена — пропуск.

set -euo pipefail

SNAPSHOTS_DIR="/mnt/A4C45B32C45B2C87/timeshift_btrfs_backup/timeshift-btrfs/snapshots"
DEST_ROOT="/mnt/82A23910A2390A65/Videos/claude_snapshots"
HOME_REL="@home/uadmin"
PATTERN=".claude*"

[[ -d "$SNAPSHOTS_DIR" ]] || { echo "Источник не найден: $SNAPSHOTS_DIR" >&2; exit 1; }
mkdir -p "$DEST_ROOT"

total=0; with_data=0; all_done=0; missing=0
folders_copied=0; folders_skipped=0

mapfile -t snaps < <(find "$SNAPSHOTS_DIR" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' | sort)

for snap in "${snaps[@]}"; do
    total=$((total + 1))
    src_home="$SNAPSHOTS_DIR/$snap/$HOME_REL"

    if [[ ! -d "$src_home" ]]; then
        missing=$((missing + 1))
        printf '  [%3d/%d] %s — нет @home/uadmin, пропуск\n' "$total" "${#snaps[@]}" "$snap"
        continue
    fi

    # Найти все .claude* директории на верхнем уровне $HOME (без рекурсии)
    mapfile -t matched < <(find "$src_home" -maxdepth 1 -mindepth 1 -type d -name "$PATTERN" -printf '%f\n' 2>/dev/null | sort)

    if [[ ${#matched[@]} -eq 0 ]]; then
        missing=$((missing + 1))
        printf '  [%3d/%d] %s — нет .claude* папок\n' "$total" "${#snaps[@]}" "$snap"
        continue
    fi

    snap_dst="$DEST_ROOT/$snap"
    mkdir -p "$snap_dst"

    new_in_snap=0
    skip_in_snap=0
    for name in "${matched[@]}"; do
        src="$src_home/$name"
        dst="$snap_dst/$name"

        if [[ -d "$dst" ]] && [[ -n "$(ls -A "$dst" 2>/dev/null)" ]]; then
            skip_in_snap=$((skip_in_snap + 1))
            folders_skipped=$((folders_skipped + 1))
            continue
        fi

        # -a: preserve mode/owner/timestamps; --reflink=auto: дёшево если ФС совпадёт
        cp -a --reflink=auto "$src" "$dst"
        new_in_snap=$((new_in_snap + 1))
        folders_copied=$((folders_copied + 1))
    done

    if [[ $new_in_snap -gt 0 ]]; then
        with_data=$((with_data + 1))
        printf '  [%3d/%d] %s — извлечено %d (уже было: %d): %s\n' \
            "$total" "${#snaps[@]}" "$snap" "$new_in_snap" "$skip_in_snap" \
            "${matched[*]}"
    else
        all_done=$((all_done + 1))
        printf '  [%3d/%d] %s — все %d папок уже извлечены\n' \
            "$total" "${#snaps[@]}" "$snap" "$skip_in_snap"
    fi
done

echo
echo "=== Итого ==="
printf '  Всего снапшотов:        %d\n' "$total"
printf '  Со свежим контентом:    %d\n' "$with_data"
printf '  Уже было всё:           %d\n' "$all_done"
printf '  Без .claude* папок:     %d\n' "$missing"
printf '  Всего папок скопировано: %d\n' "$folders_copied"
printf '  Всего папок пропущено:   %d\n' "$folders_skipped"
echo
du -sh "$DEST_ROOT" 2>/dev/null
