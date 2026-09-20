#!/usr/bin/env bash
# Тесты под сторожевым таймером; вердикт в файл, код возврата сохраняется.
# Запускать через Bash с run_in_background: true — harness будит по завершении.
# Переопределения: TEST_CMD, TEST_TIMEOUT (с), TEST_STATE_DIR.
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
command -v jq >/dev/null || { echo "TESTS REFUSED: нужен jq для записи вердикта"; exit 2; }
ST="${TEST_STATE_DIR:-}"
if [ -z "$ST" ]; then
  # Под pytest без явного каталога прогон сценариев затёр бы настоящий вердикт.
  if [ -n "${PYTEST_CURRENT_TEST:-}" ]; then
    echo "TESTS REFUSED: под pytest задайте TEST_STATE_DIR"; exit 2
  fi
  ST="$ROOT/.claude/state"
fi
LIMIT="${TEST_TIMEOUT:-600}"
CMD="${TEST_CMD:-pytest -c bdd/pytest.ini bdd}"
mkdir -p "$ST"; ST=$(cd "$ST" && pwd)
exec 9>"$ST/test-bg.lock"
flock -n 9 || { echo "TESTS BUSY: прогон уже идёт"; exit 3; }
timeout --kill-after=10 "$LIMIT" bash -c "$CMD" >"$ST/test-result.log" 2>&1; rc=$?
case $rc in 0) s=PASS;; 124|137) s=HANG;; *) s=FAIL;; esac
jq -nc --arg s "$s" --argjson rc "$rc" --arg l "$ST/test-result.log" \
  --arg ts "$(date -Is)" --arg cwd "$ROOT" \
  '{status:$s, rc:$rc, log:$l, ts:$ts, cwd:$cwd, acked:false}' >"$ST/test-result.json.tmp" \
  && mv "$ST/test-result.json.tmp" "$ST/test-result.json" || { rm -f "$ST/test-result.json.tmp"; echo "TESTS REFUSED: вердикт не записан"; exit 2; }
echo "TESTS $s rc=$rc"; tail -n 40 "$ST/test-result.log"; exit $rc
