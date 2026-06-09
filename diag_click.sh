#!/usr/bin/env bash
# Тест "тачпад двигает но не кликает", без libinput/evtest — через python и /dev/input.

set +e

if ! sudo -n true 2>/dev/null; then
    echo "Нужен sudo. Введи пароль:"
    sudo -v || { echo "sudo не дал прав"; exit 1; }
fi

cat <<'INTRO'
=== Сейчас 10 секунд слушаем сырые input-events с двух устройств ===
  event5 — "04F3:31FD Mouse"    (PS2-эмуляция: BTN_LEFT/RIGHT/MIDDLE)
  event7 — "04F3:31FD Touchpad" (мультитач: BTN_TOUCH, BTN_TOOL_*, ABS)

В эти 10 секунд: подвигай пальцем, тапни, нажми физическую левую кнопку.
Если кнопок две — нажми обе. Если есть внешняя мышь — кликни и ей.
INTRO

sleep 1

sudo timeout 10 python3 - <<'PY' /dev/input/event5 /dev/input/event7
import os, struct, select, sys, time

EV_FMT = "llHHi"            # struct input_event на 64-bit: 2*long + 2*ushort + int = 24 bytes
SZ = struct.calcsize(EV_FMT)
EV_TYPE = {0:"SYN",1:"KEY",2:"REL",3:"ABS",4:"MSC"}
KEY_CODES = {  # частичный декод
    272:"BTN_LEFT", 273:"BTN_RIGHT", 274:"BTN_MIDDLE",
    275:"BTN_SIDE", 276:"BTN_EXTRA",
    320:"BTN_TOOL_PEN",
    325:"BTN_TOOL_FINGER", 333:"BTN_TOOL_DOUBLETAP",
    334:"BTN_TOOL_TRIPLETAP", 335:"BTN_TOOL_QUADTAP",
    330:"BTN_TOUCH",
}
REL_CODES = {0:"REL_X",1:"REL_Y",8:"REL_WHEEL",11:"REL_WHEEL_HI_RES"}

paths = sys.argv[1:]
fds = []
labels = {}
for p in paths:
    try:
        fd = os.open(p, os.O_RDONLY | os.O_NONBLOCK)
        fds.append(fd)
        labels[fd] = p.split("/")[-1]
        print(f"opened {p}")
    except OSError as e:
        print(f"FAIL open {p}: {e}")

if not fds:
    sys.exit(2)

n_motion = {p.split("/")[-1]:0 for p in paths}
n_button = {p.split("/")[-1]:0 for p in paths}

end = time.time() + 9.5
poller = select.poll()
for fd in fds: poller.register(fd, select.POLLIN)

while time.time() < end:
    for fd, _ in poller.poll(500):
        try:
            data = os.read(fd, SZ * 64)
        except BlockingIOError:
            continue
        for i in range(0, len(data), SZ):
            sec, usec, ev_type, code, value = struct.unpack(EV_FMT, data[i:i+SZ])
            lbl = labels[fd]
            t = EV_TYPE.get(ev_type, str(ev_type))
            if t == "SYN":
                continue
            if t == "KEY":
                name = KEY_CODES.get(code, f"KEY_{code}")
                action = "PRESS" if value else "RELEASE"
                n_button[lbl] += 1
                print(f"  {lbl}  KEY    {name:20s} {action}")
            elif t == "REL":
                n_motion[lbl] += 1
                # не печатаем каждое движение, слишком шумно
            elif t == "ABS":
                # ABS_X/Y/MT_* — координаты тачпада
                if code in (0,1):    # ABS_X, ABS_Y
                    n_motion[lbl] += 1
            elif t == "MSC":
                pass

print()
print("=== ИТОГ за 10 секунд ===")
for lbl in n_motion:
    print(f"  {lbl}:  motion-events={n_motion[lbl]:5d}   button-events={n_button[lbl]:3d}")
PY

cat <<'TAIL'

=== Как читать ИТОГ ===
  motion > 0, button > 0          → железо/драйвер в норме, виноват compositor.
                                    Лечение: переключиться в TTY (Ctrl+Alt+F3)
                                    и обратно (Ctrl+Alt+F2), либо перелогиниться.
  motion > 0, button = 0          → тачпад не отдаёт BTN_LEFT — фильтрует контроллер.
                                    Лечение:
        sudo modprobe -r hid_multitouch i2c_hid_acpi i2c_hid && \
        sudo modprobe i2c_hid_acpi
                                    Или в Settings → Mouse&Touchpad — переключить
                                    Tap-to-click off/on.
  motion = 0, button = 0          → события вообще не идут (или ты не успел
                                    потрогать) — запусти ещё раз и активнее тапай.
TAIL
