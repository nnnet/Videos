#!/usr/bin/env bash
# Тесты под сторожевым таймером; вердикт в файл, код возврата сохраняется.
# Запускать через Bash с run_in_background: true — harness будит по завершении.
# Переопределения: TEST_CMD, TEST_TIMEOUT (с), TEST_STATE_DIR (относительный —
# от корня репозитория).
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd) || exit 2
cd "$ROOT" || exit 2
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
case "$LIMIT" in ''|*[!0-9]*|0*) echo "TESTS REFUSED: TEST_TIMEOUT должен быть положительным целым числом секунд"; exit 2;; esac
CMD="${TEST_CMD:-pytest -c bdd/pytest.ini bdd}"
mkdir -p "$ST"; ST=$(cd "$ST" && pwd)
exec 9>"$ST/test-bg.lock"
flock -n 9 || { echo "TESTS BUSY: прогон уже идёт"; exit 3; }
# Атомарная запись вердикта: $1 — status, $2 — rc (JSON: число или null).
write_verdict() {
  jq -nc --arg s "$1" --argjson rc "$2" --arg l "$ST/test-result.log" \
    --arg ts "$(date -Is)" --arg cwd "$ROOT" \
    '{status:$s, rc:$rc, log:$l, ts:$ts, cwd:$cwd, acked:false}' >"$ST/test-result.json.tmp" \
    && mv "$ST/test-result.json.tmp" "$ST/test-result.json" \
    || { rm -f "$ST/test-result.json.tmp"; echo "TESTS REFUSED: вердикт не записан"; return 1; }
}
# Старый вердикт не должен пережить старт нового прогона.
write_verdict RUNNING null || exit 2
timeout --kill-after=10 "$LIMIT" bash -c "$CMD" >"$ST/test-result.log" 2>&1; rc=$?
case $rc in 0) s=PASS;; 124|137) s=HANG;; *) s=FAIL;; esac
write_verdict "$s" "$rc" || exit 2
echo "TESTS $s rc=$rc"; tail -n 40 "$ST/test-result.log"; exit $rc
