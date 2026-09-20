# background-tests-hardening — закрытие находок ревью change background-tests

## Why

Ревью `plans/reports/ak:code-reviewer-260920-1340-background-tests.md`
(вердикт needs-changes) оставило после коммита `5c41bc6` один major и ряд
minor: старый вердикт переживает старт нового прогона (ложный блок или пропуск
зависит от разбора `background_tasks`, форма записи которого живьём не
подтверждена), гейт ломается на нестроковом `status`, неизвестный статус
считается завершением, недокументированный дамп события, разный резолв
относительного `TEST_STATE_DIR`, нечисловой `TEST_TIMEOUT` → FAIL.

## What changes

- Обёртка пишет `status:"RUNNING"` до старта прогона; гейт на `RUNNING` молчит.
- Гейт больше не разбирает `background_tasks`: идущий прогон виден по
  `RUNNING`, а угадывание терминальных статусов (чёрный список молчал бы на
  `success`/`finished` — вечный пропуск) убрано по итогам ревью.
- Дамп события в `last-stop.json` — только при `TEST_GATE_DEBUG=1`.
- Относительный `TEST_STATE_DIR` — от корня репозитория в обёртке и гейте.
- Нечисловой или нулевой `TEST_TIMEOUT` → `TESTS REFUSED` rc=2, без вердикта.
- Сценарии для `flock` (второй запуск) и «rc обёртки = rc прогона».
- Сценарий «молчание» разбит: вывод называет упавший случай.
- `set -u` в обоих скриптах.

## Non-goals

- Замена `decision:"block"` на `additionalContext`; учёт `stop_hook_active`.
- Автозапуск тестов по событиям редактирования.

## Capabilities

- `background-tests` — MODIFIED REQ-background-tests-001, REQ-background-tests-002.

## Impact

`scripts/test-bg.sh`, `scripts/test-gate.sh`, `bdd/features/background-tests.feature`,
`openspec/specs/background-tests/spec.md` (после archive), `CLAUDE.md` (упоминание RUNNING).
