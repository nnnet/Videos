#!/usr/bin/env bash
# ШАГ 1 — самый мягкий: только GNOME settings, без root, полностью обратимо.
# Включает tap-to-click и сбрасывает click-method на default.
# Если не помогло — переходи на fix_touchpad_2_driver.sh

set +e

NS="org.gnome.desktop.peripherals.touchpad"

echo "=== ДО ==="
echo "  tap-to-click       = $(gsettings get $NS tap-to-click)"
echo "  click-method       = $(gsettings get $NS click-method)"
echo "  tap-and-drag       = $(gsettings get $NS tap-and-drag)"
echo "  send-events        = $(gsettings get $NS send-events)"
echo "  two-finger-scroll  = $(gsettings get $NS two-finger-scrolling-enabled)"
echo "  natural-scroll     = $(gsettings get $NS natural-scroll)"
echo "  disable-while-type = $(gsettings get $NS disable-while-typing)"

echo
echo "=== Применяю ==="
gsettings set $NS send-events 'enabled'           && echo "  ok send-events = enabled"
gsettings set $NS tap-to-click true               && echo "  ok tap-to-click = true"
gsettings set $NS click-method 'default'          && echo "  ok click-method = default"
gsettings set $NS two-finger-scrolling-enabled true && echo "  ok two-finger-scrolling-enabled = true"

echo
echo "=== ПОСЛЕ ==="
echo "  tap-to-click       = $(gsettings get $NS tap-to-click)"
echo "  click-method       = $(gsettings get $NS click-method)"
echo "  send-events        = $(gsettings get $NS send-events)"

cat <<'TAIL'

=== ТЕСТ ===
Сейчас попробуй:
  1) одиночный тап одним пальцем  → должен быть левый клик
  2) тап двумя пальцами одновременно → правый клик
  3) проведи двумя пальцами по тачпаду → скролл

Если ВСЁ работает — на этом всё, перезагружать драйвер не нужно.
Если тап всё ещё не кликает (но курсор двигается) — запускай:
        ./fix_touchpad_2_driver.sh

=== ОТКАТ если что-то стало хуже ===
gsettings reset org.gnome.desktop.peripherals.touchpad tap-to-click
gsettings reset org.gnome.desktop.peripherals.touchpad click-method
gsettings reset org.gnome.desktop.peripherals.touchpad two-finger-scrolling-enabled
gsettings reset org.gnome.desktop.peripherals.touchpad send-events
TAIL
