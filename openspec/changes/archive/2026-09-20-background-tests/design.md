# design — background-tests

## Поток

```
главный агент решает прогнать тесты
  └─ Bash{command:"scripts/test-bg.sh", run_in_background:true}  → ход продолжается
       └─ flock → timeout --kill-after=10 $TEST_TIMEOUT bash -c "$TEST_CMD" > test-result.log
            └─ rc → PASS(0) | HANG(124|137) | FAIL(прочее) → test-result.json (tmp + mv)
       └─ процесс завершился → harness будит агента (task-notification) → агент читает статус
агент заканчивает ход → Stop → scripts/test-gate.sh (параллельно с глобальными Stop-хуками)
  ├─ маркер AUTO-COMPACT в last_assistant_message → exit 0
  ├─ бегущая scripts/test-bg.sh в background_tasks → exit 0 (побудка придёт от harness)
  ├─ нет файла / битый / PASS / acked / старше TTL → exit 0
  └─ FAIL|HANG и не acked → {"decision":"block","reason":…}  (harness снимает после 8 подряд)
```

Источник побудки: описание инструмента Bash в Claude Code 2.1.267
(«`run_in_background` … re-invokes you when it exits»). В `hooks.md`/`tools.md`
явной формулировки нет — задача 0 проверяет это живой сессией до кода.

## Решения (после аудита 2026-09-20)

| Вопрос | Решение | Почему |
|---|---|---|
| Где watchdog | в обёртке (`timeout`) | `timeout` инструмента Bash зависание не ловит — уводит команду в фон |
| Корень проекта | от `BASH_SOURCE` скрипта | `CLAUDE_PROJECT_DIR` есть только у хуков, у Bash-инструмента нет; в worktree cwd ≠ корень |
| Где скрипты | `scripts/` (новый каталог) | корень занят 20+ доменными скриптами пайплайна; это инструментарий агента, не пайплайн. `.claude/hooks` — deny-mount песочницы |
| Ответ гейта | `decision:"block"` | защиты от петли у `block` и `additionalContext` одинаковые (`stop_hook_active`, 8 подряд); `block` виден пользователю как hook error — это и нужно |
| `stop_hook_active` | не учитывается | блок повторяется намеренно, пока не PASS/acked; потолок 8 — документированный |
| Бегущая задача | `type==shell` ∧ `command ~ scripts/test-bg\.sh` ∧ `status ∈ {running,pending,queued,in_progress,∅}` | завершённые задачи могут оставаться в массиве; голая подстрока `test-bg` ловила `chmod`/`git add` |
| Авто-компакт | маркер `AUTO-COMPACT-READY` в `last_assistant_message` → exit 0 | глобальный `stop-detect-compact.sh` ждёт конца хода с маркером; гейт не должен его срывать |
| Устаревший вердикт | TTL `TEST_RESULT_TTL_MIN` (240) по mtime + поля `ts`, `cwd` | вердикт другой сессии/каталога не должен блокировать; поля делают расхождение диагностируемым |
| Запись вердикта | `tmp` + `mv`; `flock -n` на запуск | Stop посреди записи читал бы обрезанный JSON и молчал ровно на FAIL; два прогона не перетирают друг друга |
| Ошибки в хуке | fail-open: всегда exit 0, никогда exit 2; на stdout строго один объект (`jq -c`) | битый инструмент не должен ловить сессию в петлю; посторонняя строка = parse failure |
| Подмена в сценариях | `TEST_CMD`, `TEST_STATE_DIR`; под `PYTEST_CURRENT_TEST` без `TEST_STATE_DIR` — отказ | без этого прогон сценариев писал бы FAIL в настоящий вердикт и запирал агента |
| Квитирование | точная команда в `reason`: `jq '.acked=true' F > F.tmp && mv F.tmp F` | агент не должен редактировать JSON вручную внутри цикла блокировки |
| rc=137 | HANG, но в reason: «таймаут или внешний kill -9» | 137 — не только `--kill-after` |
| Опечатка в `TEST_CMD` → FAIL | оставлено как есть | сломанная команда тестов тоже требует действия агента; лог показывает причину |
| Субагенты, `claude -p` | правило в CLAUDE.md: в фоне запускает только главный агент | harness убивает фон по финальному ответу субагента / `-p` |
| `.claude/settings.json` | агент, `dangerouslyDisableSandbox` (разрешено пользователем), точечный `jq`-merge ключа `hooks`, файл не печатать | файл в deny-листе песочницы и содержит секрет в `env` |
| Состояние | `.claude/state/` + `.git/info/exclude` | локальный артефакт; локальные ignore — не в `.gitignore` |
| Автозапуск на Edit | нет | отвергнут пользователем |
| bdd-шаги | добавить `команда завершается с ошибкой`, `файл "{rel}" содержит "{text}"` в `bdd/steps/repo_steps.py` | без них сценарии REQ-001/003 невыразимы |

## Скрипты (эскиз)

`scripts/test-bg.sh`
```bash
#!/usr/bin/env bash
# Тесты под сторожевым таймером; вердикт в файл, код возврата сохраняется.
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ST="${TEST_STATE_DIR:-}"
if [ -z "$ST" ]; then
  [ -n "${PYTEST_CURRENT_TEST:-}" ] && { echo "под pytest задайте TEST_STATE_DIR" >&2; exit 2; }
  ST="$ROOT/.claude/state"
fi
LIMIT="${TEST_TIMEOUT:-600}"; CMD="${TEST_CMD:-pytest -c bdd/pytest.ini bdd}"
mkdir -p "$ST"
exec 9>"$ST/test-bg.lock"; flock -n 9 || { echo "TESTS BUSY: прогон уже идёт" >&2; exit 3; }
cd "$ROOT"
timeout --kill-after=10 "$LIMIT" bash -c "$CMD" >"$ST/test-result.log" 2>&1; rc=$?
case $rc in 0) s=PASS;; 124|137) s=HANG;; *) s=FAIL;; esac
jq -nc --arg s "$s" --argjson rc "$rc" --arg l "$ST/test-result.log" --arg ts "$(date -Is)" --arg cwd "$ROOT" \
  '{status:$s, rc:$rc, log:$l, ts:$ts, cwd:$cwd, acked:false}' >"$ST/test-result.json.tmp" \
  && mv "$ST/test-result.json.tmp" "$ST/test-result.json"
echo "TESTS $s rc=$rc"; tail -n 40 "$ST/test-result.log"; exit $rc
```

`scripts/test-gate.sh`
```bash
#!/usr/bin/env bash
# Stop-хук: блокирует завершение хода при необработанном FAIL/HANG. Fail-open, никогда exit 2.
command -v jq >/dev/null || exit 0
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
f="${TEST_STATE_DIR:-$ROOT/.claude/state}/test-result.json"
[ -f "$f" ] || exit 0
[ -n "$(find "$f" -mmin +"${TEST_RESULT_TTL_MIN:-240}" 2>/dev/null)" ] && exit 0
in=$(cat)
printf '%s' "$in" | jq -e '(.last_assistant_message // "") | test("AUTO-COMPACT-READY")' >/dev/null 2>&1 && exit 0
printf '%s' "$in" | jq -e '(.background_tasks // [])[] | select(.type=="shell"
  and ((.command // "") | test("scripts/test-bg\\.sh"))
  and ((.status // "running") | ascii_downcase | test("run|pend|queue|progress")))' >/dev/null 2>&1 && exit 0
s=$(jq -r '.status // empty' "$f" 2>/dev/null); a=$(jq -r '.acked // false' "$f" 2>/dev/null)
case "$s" in FAIL|HANG) ;; *) exit 0;; esac
[ "$a" = true ] && exit 0
jq -nc --arg s "$s" --arg rc "$(jq -r .rc "$f")" --arg l "$(jq -r .log "$f")" --arg f "$f" '{decision:"block",
 reason:("Тесты: "+$s+" rc="+$rc+". Прочитай лог "+$l+". FAIL → найди причину (ak:debug), исправь, перезапусти scripts/test-bg.sh в фоне (run_in_background). HANG → найди зависший шаг по логу; таймаут молча не поднимай; rc=137 может быть внешним kill. Если исправить нельзя — квитируй: jq '.acked=true' "+$f+" > "+$f+".tmp && mv "+$f+".tmp "+$f+" — и объясни пользователю.")}' 2>/dev/null
exit 0
```

`.claude/settings.json` — точечное добавление (`jq '.hooks.Stop += [...]'` во временный файл, затем `mv`):
```json
"hooks": { "Stop": [ { "hooks": [
  { "type": "command", "command": "\"${CLAUDE_PROJECT_DIR}\"/scripts/test-gate.sh", "timeout": 10 }
] } ] }
```

## Порядок с гейтом spec-coverage

`agent-ops spec-coverage` читает требования только из `openspec/specs/`;
дельта в change не считается. Поэтому `.feature` с тегами `@REQ-background-tests-*`
делает pre-commit красным до архивации change. Порядок: реализовать →
прогнать `pytest -c bdd/pytest.ini bdd` → `openspec archive background-tests`
(дельта ложится в `openspec/specs/background-tests/spec.md`) →
`agent-ops spec-coverage .` зелёный → коммит одним изменением.

## Результат живой проверки (задача 1, 2026-09-20)

- `scripts/test-bg.sh` через Bash `run_in_background: true` → harness прислал
  task-notification (`status: completed`, exit 0) без ожидания агентом;
  вердикт `.claude/state/test-result.json` = `PASS rc=0 acked=false`.
  Побудка подтверждена.
- `flock`: второй параллельный запуск → `TESTS BUSY`, rc=3. Подтверждено.
- Stop-хук из `.claude/settings.json` в текущей сессии ещё не срабатывал
  (`last-stop.json` отсутствует): hooks.md не описывает горячую перезагрузку
  project-хуков → живой тест блокировки (задача 8) — в новой сессии.
