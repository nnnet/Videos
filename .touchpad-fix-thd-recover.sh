#!/usr/bin/env bash
# Pointer recovery — root-level wrapper for triggerhappy.
# Triggered by Scroll Lock (kernel-level, bypasses all X11 grabs).
set +e

GUI_PID=$(pgrep -u uadmin gnome-shell | head -1)
if [[ -z "$GUI_PID" ]]; then
    logger -t pointer-recover-root "no gnome-shell"
    exit 1
fi

DISPLAY_VAL=$(tr '\0' '\n' < /proc/$GUI_PID/environ | grep '^DISPLAY=' | cut -d= -f2)
XAUTH_VAL=$(tr '\0' '\n' < /proc/$GUI_PID/environ | grep '^XAUTHORITY=' | cut -d= -f2)
[[ -z "$DISPLAY_VAL" ]] && DISPLAY_VAL=":0"
[[ -z "$XAUTH_VAL" ]] && XAUTH_VAL=$(find /run/user/1000 -maxdepth 2 -name '*authority*' 2>/dev/null | head -1)

logger -t pointer-recover-root "triggered: DISPLAY=$DISPLAY_VAL XAUTHORITY=$XAUTH_VAL"

SLAVES=$(sudo -u uadmin DISPLAY="$DISPLAY_VAL" XAUTHORITY="$XAUTH_VAL" xinput --list --id-only 2>/dev/null | while read id; do
    info=$(sudo -u uadmin DISPLAY="$DISPLAY_VAL" XAUTHORITY="$XAUTH_VAL" xinput --list "$id" 2>/dev/null)
    case "$info" in
        *"slave  pointer"*) echo "$id" ;;
    esac
done)

[[ -z "$SLAVES" ]] && { logger -t pointer-recover-root "no slaves"; exit 1; }

for id in $SLAVES; do
    sudo -u uadmin DISPLAY="$DISPLAY_VAL" XAUTHORITY="$XAUTH_VAL" xinput disable "$id" 2>/dev/null
done
sleep 0.3
for id in $SLAVES; do
    sudo -u uadmin DISPLAY="$DISPLAY_VAL" XAUTHORITY="$XAUTH_VAL" xinput enable "$id" 2>/dev/null
done

sleep 0.1
for btn in 1 2 3; do
    sudo -u uadmin DISPLAY="$DISPLAY_VAL" XAUTHORITY="$XAUTH_VAL" xdotool mouseup $btn 2>/dev/null
done

sudo -u uadmin DISPLAY="$DISPLAY_VAL" XAUTHORITY="$XAUTH_VAL" notify-send -t 2000 "Pointer recovered" "Scroll Lock" 2>/dev/null
logger -t pointer-recover-root "done"
