#!/usr/bin/env bash
# Stop-хук Claude Code: не даёт закончить ход при необработанном FAIL/HANG от
# scripts/test-bg.sh. Fail-open: любая ошибка → exit 0; никогда exit 2.
# На stdout — строго один JSON-объект или ничего. TEST_GATE_DEBUG=1 — дамп
# события в <state>/last-stop.json.
set -u
command -v jq >/dev/null || exit 0
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd) || exit 0
cd "$ROOT" || exit 0
ST="${TEST_STATE_DIR:-$ROOT/.claude/state}"
ST=$(cd "$ST" 2>/dev/null && pwd) || exit 0
f="$ST/test-result.json"
in=$(cat)
[ "${TEST_GATE_DEBUG:-0}" != 0 ] && printf '%s' "$in" >"$ST/last-stop.json" 2>/dev/null
[ -n "$in" ] || exit 0
printf '%s' "$in" | jq -e . >/dev/null 2>&1 || exit 0
[ -f "$f" ] || exit 0
[ -n "$(find "$f" -mmin +"${TEST_RESULT_TTL_MIN:-240}" 2>/dev/null)" ] && exit 0
# Идёт авто-компакт — глобальный Stop-хук ждёт конца хода с маркером.
printf '%s' "$in" | jq -e '(.last_assistant_message // "") | test("AUTO-COMPACT-READY")' >/dev/null 2>&1 && exit 0
# Пока прогон идёт, обёртка держит вердикт RUNNING — гейт молчит по нему;
# background_tasks события не разбирается (форма статусов не гарантирована).
s=$(jq -r '.status // empty' "$f" 2>/dev/null); a=$(jq -r '.acked // false' "$f" 2>/dev/null)
case "$s" in FAIL|HANG) ;; *) exit 0;; esac
[ "$a" = true ] && exit 0
jq -nc --arg s "$s" --arg rc "$(jq -r .rc "$f")" --arg l "$(jq -r .log "$f")" --arg f "$f" \
  '{decision:"block", reason:("Тесты: "+$s+" rc="+$rc+". Прочитай лог "+$l+". FAIL → найди причину (ak:debug), исправь, перезапусти scripts/test-bg.sh в фоне (run_in_background). HANG → найди зависший шаг по логу; таймаут молча не поднимай; rc=137 может быть внешним kill. Если исправить нельзя — квитируй: jq '"'"'.acked=true'"'"' "+$f+" > "+$f+".tmp && mv "+$f+".tmp "+$f+" — и объясни пользователю.")}' 2>/dev/null
exit 0
