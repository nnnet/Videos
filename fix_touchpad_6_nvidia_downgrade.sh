#!/usr/bin/env bash
# Downgrade NVIDIA driver 580.142 → 580.126.09 (вчерашний upgrade откатывается).
#
# Гипотеза: NVIDIA 580.142 (выкатилась 2026-05-14) даёт stuck-mouse bug на этой
# конфигурации. До этого 580.126.09 работал стабильно (snapshot 11 мая подтверждает).
#
# Что делает:
#   1. Pin'ит ВСЕ установленные nvidia-580-* пакеты на 580.126.09
#   2. Использует --allow-downgrades + --reinstall на случай stuck dependencies
#   3. Исключает versioned firmware-пакеты (они автоматически переустановятся)
#
# После выполнения нужен ребут (новый kernel module).

set -e
VER="580.126.09-0ubuntu0.24.04.2"

echo "=== Собираю список пакетов ==="
# Все installed nvidia-580-* пакеты, КРОМЕ versioned firmware (`-580.142`, `-580.126.09`)
PKGS=$(dpkg -l | awk '/^ii .*nvidia.*580/ {print $2}' | grep -vE 'nvidia-firmware-580-580\.')

CMD="sudo apt install -y --allow-downgrades"
for p in $PKGS; do
    CMD="$CMD ${p}=${VER}"
done

echo "Команда:"
echo "$CMD"
echo
read -rp "Запустить downgrade? [y/N] " ANS
[[ "$ANS" =~ ^[Yy]$ ]] || { echo "пропускаю"; exit 0; }

echo
echo "=== Выполняю downgrade ==="
eval "$CMD"

echo
echo "=== ПОСЛЕ ==="
dpkg -l | awk '/^ii .*nvidia.*580/ {printf "  %-40s %s\n", $2, $3}'

cat <<'TAIL'

=== ВАЖНО ===
Делай ребут — новый kernel module пересоберётся под 580.126.09.
  sudo reboot

При boot в GRUB меню → Advanced options for Ubuntu → выбери:
  6.8.0-110-generic   (был стабильный на 11 мая)
  ИЛИ 6.8.0-107 (ещё более стабильный baseline)

После boot:
  cat /sys/module/nvidia/version   # должно быть 580.126.09
  uname -r                          # 6.8.0-110 (или 107)

=== Откат downgrade (если что-то сломалось) ===
sudo apt install -y nvidia-driver-580-open=580.142-0ubuntu0.24.04.1
TAIL
