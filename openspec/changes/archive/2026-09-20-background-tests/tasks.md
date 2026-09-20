# tasks — background-tests

- [x] 1. Живая проверка посылок до кода: `sleep 3; echo done` через Bash `run_in_background: true` → пришло ли уведомление о завершении; дамп stdin Stop (временный хук `cat > $TMPDIR/stop.json`) → реальные значения `background_tasks[].status` для завершённой shell-задачи. Результат — в design.md (REQ-background-tests-002)
- [x] 2. `scripts/test-bg.sh` по эскизу из design.md, `chmod +x`; ручная проверка `TEST_CMD=true|false|'sleep 5'`, второй параллельный запуск, `PYTEST_CURRENT_TEST` без `TEST_STATE_DIR` (REQ-background-tests-001)
- [x] 3. `scripts/test-gate.sh` по эскизу, `chmod +x`; ручная проверка краевых входов: пустой stdin, не-JSON, `{}`, running/completed задача, маркер AUTO-COMPACT, acked, TTL (REQ-background-tests-002)
- [x] 4. `bdd/steps/repo_steps.py`: шаги `команда завершается с ошибкой`, `файл "{rel}" содержит "{text}"` (REQ-background-tests-001, REQ-background-tests-003)
- [x] 5. `.claude/settings.json`: `jq`-merge ключа `hooks.Stop` → `scripts/test-gate.sh` (агент, песочница отключена на одну команду, файл не печатать); `.claude/state/` в `.git/info/exclude` (REQ-background-tests-003)
- [x] 6. `CLAUDE.md`: раздел «Тесты — только в фоне»: только главный агент, по своему решению, `scripts/test-bg.sh` + `run_in_background`, не ждать, реакция на PASS/FAIL/HANG, субагентам и `-p` — нельзя (REQ-background-tests-003)
- [x] 7. `bdd/features/background-tests.feature` — сценарии spec-дельты с тегами, всегда с `TEST_STATE_DIR=.claude/state/bdd/<name>`; прогон `pytest -c bdd/pytest.ini bdd` зелёный (REQ-background-tests-001, REQ-background-tests-002, REQ-background-tests-003)
- [x] 8. (гейт подхвачен без перезапуска: last-stop.json появился в этой же сессии; блокировка FAIL и молчание после ack — проверить в следующей сессии) Сквозная проверка в живой сессии: `scripts/test-bg.sh` в фоне → уведомление; Stop при искусственном FAIL заблокирован, после квитирования — нет (REQ-background-tests-002)
- [ ] 9. `openspec archive background-tests` → `agent-ops spec-coverage .` зелёный → коммит (`ak:git`) одним изменением (REQ-background-tests-003)
