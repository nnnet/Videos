# tasks — background-tests-hardening

- [x] 1. `scripts/test-bg.sh`: `set -u`; `write_verdict()` (tmp+mv, при ошибке rm tmp → REFUSED rc=2); RUNNING до старта; валидация `TEST_TIMEOUT` (REQ-background-tests-001)
- [x] 2. `scripts/test-gate.sh`: `set -u`; `cd $ROOT`; `background_tasks` не разбирается (ревью: чёрный список статусов молчал бы навсегда); RUNNING → молчание; дамп под `TEST_GATE_DEBUG` (REQ-background-tests-002)
- [x] 3. `bdd/features/background-tests.feature`: сценарии дельты (RUNNING, BUSY, rc=7, TEST_TIMEOUT=abc, started/числовой статус, дамп); «молчание» печатает имя упавшего случая; синхронный `pytest -c bdd/pytest.ini bdd` зелёный (REQ-id не меняются — spec-coverage зелёный и до archive) (REQ-background-tests-001, REQ-background-tests-002)
- [x] 4. `CLAUDE.md`: упомянуть статус RUNNING и `TEST_GATE_DEBUG` (REQ-background-tests-002)
- [x] 5. `ak:code-reviewer` над diff → `openspec archive background-tests-hardening` → `agent-ops spec-coverage .` → коммит (REQ-background-tests-001, REQ-background-tests-002)
