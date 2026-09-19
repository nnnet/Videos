# Откат на kernel 6.8.0-111 (one-shot) + чистка сломанного @new entry

## Context

С 15 по 23 мая 2026 система работала **8 дней без зависаний** на kernel
**6.8.0-111-generic** (`last -x` показывает непрерывный uptime
`Sat May 23 20:31 - … 1+00:43`, и предыдущий boot **7 дней 22 часа**).

23 мая ~20:30 произошло обновление до **6.8.0-117-generic**. С тех пор
зафиксированы **три** полных hang'а, каждый требовал hardware reset:
- 24 мая 16:13 (X11)
- 24 мая ~23:30 (Plasma Wayland после mode-set HDMI)
- 25 мая 01:11 (GNOME Wayland, спонтанно)

Анализ `journalctl -b -1 --no-pager | tail -40` для последнего hang'а
показал: **kernel жив, OOM не активен (37 GB свободно из 63 GB), NVIDIA
не репортит XID-error, нет kernel panic**. Последняя запись перед
power-key: рутинные `rtkit-daemon: Supervising` + `earlyoom: mem avail
58%`. То есть зависает **display-stack** (mutter/kwin/input) при живом
ядре — невозможно kill процессов даже из TTY, потому что compositor
управляет seat'ом, а seat не отдаётся.

Гипотеза: regression в **6.8.0-111 → 6.8.0-117** для связки
RTX 5090 Laptop + Intel Arc Battlemage iGPU + libinput, проявляется
как input/compositor freeze без kernel-уровневых ошибок.

Memory `feedback_stuck_mouse_super_key_root_cause.md` ранее (15 мая)
отвергла «kernel downgrade» как фикс, но тогда тестировали 6.8.0-107
через @new btrfs subvolume (с roll-back'ом /etc) — это другие данные:
тогда не было empirical baseline стабильности конкретного 6.8.0-111,
а сейчас он есть (8 дней).

Цель: **подтвердить или опровергнуть гипотезу одним one-shot boot'ом**.
Если за 24+ часа на 6.8.0-111 не будет hang'а — corner подтверждён,
дальше думаем как пиннить kernel и подождать апстрим-фикс в 117+.

Параллельно: в `/boot/grub/grub.cfg` остался дангл-entry
**`Ubuntu Rollback 11.05.2026 (@new)`** (строка 298) — указывает на
btrfs subvolume `@new`, которого больше нет в `btrfs subvolume list`.
Если кто-то случайно выберет этот пункт — kernel panic «failed to
mount root». Чищу заодно.

## Подход (по выбору юзера)

### Шаг 1. Найти исходник дангл-entry и удалить его

`menuentry 'Ubuntu Rollback 11.05.2026 (@new)'` отсутствует в `40_custom`
(тот пустой). Значит он в `41_custom` (есть в `ls /etc/grub.d/`) или
в `40_custom.before-rollback-cleanup`. Сначала `cat` обоих, найти
источник, удалить relevant блок целиком.

Если entry в `41_custom` — сделать backup `41_custom.bak-2026-05-25` и
удалить блок `menuentry … @new … }`. Если в обоих или ещё где —
аналогично, без угадывания.

### Шаг 2. One-shot boot в 6.8.0-111 через `grub-reboot`

```bash
# Найти точный id submenu+entry
sudo grub-editenv list  # текущее saved_entry
# Команда задаёт следующий boot, после ребута возвращается на default
sudo grub-reboot "Advanced options for Ubuntu>Ubuntu, with Linux 6.8.0-111-generic"
```

Точный аргумент берётся из `grep "menuentry '" /boot/grub/grub.cfg`:
- Submenu: `gnulinux-advanced-6f61ae4a-55dd-4cce-95fa-045d7997eae5`
- Entry: `gnulinux-6.8.0-111-generic-advanced-6f61ae4a-55dd-4cce-95fa-045d7997eae5`

Безопаснее всего использовать **human-readable путь через `>`**, его
grub-reboot принимает: `"Advanced options for Ubuntu>Ubuntu, with Linux 6.8.0-111-generic"`.

Альтернатива (если path не сработает): по индексу — submenu
`1>2` (Advanced submenu = index 1, внутри: 0=117, 1=117 recovery,
**2=111**, 3=111 recovery). Команда: `sudo grub-reboot "1>2"`.

### Шаг 3. Ребут + проверка

```bash
sudo reboot
# после возвращения:
uname -r  # должен показать 6.8.0-111-generic
```

### Шаг 4. Наблюдение

Использовать машину как обычно 24-48 часов. Если **ни одного hang'а**
→ 6.8.0-117 подтверждённо регрессивный, делаем permanent default +
`apt-mark hold linux-image-6.8.0-117-generic` отдельным следующим
планом.

Если **hang повторится за этот период** → kernel не виноват, корень
глубже (NVIDIA driver, hardware, libinput). Тогда — следующий тест:
boot в iGPU-only через BIOS MUX switch (исключить NVIDIA).

## Critical files

- `/boot/grub/grub.cfg` — read-only (генерируется `update-grub`).
  Используется как источник правды для имён entry.
- `/etc/grub.d/41_custom` или `/etc/grub.d/40_custom.before-rollback-cleanup`
  — там лежит источник `menuentry 'Ubuntu Rollback … @new …'`. Один
  из них надо отредактировать (удалить блок), потом `update-grub`.
- `/boot/grub/grubenv` — `grub-editenv list` показывает `next_entry`
  после `grub-reboot`, ничего руками править не нужно.

## Команды (final, в порядке исполнения)

```bash
# 1. Найти источник дангл-entry
grep -l 'Ubuntu Rollback' /etc/grub.d/*

# 2. Backup + удалить блок (точный sed зависит от того где он лежит)
sudo cp /etc/grub.d/41_custom /etc/grub.d/41_custom.bak-2026-05-25
sudo $EDITOR /etc/grub.d/41_custom   # удалить весь menuentry-блок

# 3. Перегенерировать grub.cfg
sudo update-grub

# 4. Убедиться что entry пропал
grep -c 'Rollback' /boot/grub/grub.cfg   # должно быть 0

# 5. One-shot boot в 6.8.0-111
sudo grub-reboot "Advanced options for Ubuntu>Ubuntu, with Linux 6.8.0-111-generic"
sudo grub-editenv list   # должен показать next_entry=...

# 6. Reboot
sudo reboot

# (После ребута, в новой сессии:)
# 7. Проверить
uname -r    # → 6.8.0-111-generic
uptime
```

## Verification

- **Сразу после ребута**: `uname -r` возвращает `6.8.0-111-generic`.
- **Через 1-2 часа**: проверить что нет hang'ов (мышь кликает, можно
  открывать окна, перетаскивать, переключаться между приложениями).
- **Через 24 часа**: если ни одного hang'а — гипотеза подтверждена,
  переходим к pin'у kernel'а (отдельный план).
- **Если hang повторится** в течение 24 часов: kernel не виноват,
  возвращаемся в 117 (reboot сам по себе вернёт default = 117), и
  следующий тест — iGPU-only через BIOS MUX (исключить NVIDIA).

## Что НЕ делаю в этом плане

- Permanent default change `GRUB_DEFAULT` на 6.8.0-111 — только после
  подтверждения стабильности (отдельный план).
- `apt-mark hold linux-image-6.8.0-117-generic` — то же самое, отдельно.
- Удаление 6.8.0-117 из системы — не трогаем, оставляем как fallback.
- Включение или выключение NVIDIA driver — не делаем (это следующий
  тест, если kernel не виноват).
- Изменения в /etc/default/grub (timeout, GRUB_DEFAULT) — не нужны для
  one-shot теста.
