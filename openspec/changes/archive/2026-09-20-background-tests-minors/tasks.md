# tasks — background-tests-minors

- [x] 1. `scripts/test-bg.sh`: при провале финальной `write_verdict` — повтор с `FAIL 2`, затем `TESTS REFUSED` rc=2 с явным «RUNNING остался» (REQ-background-tests-001)
- [x] 2. `bdd/features/background-tests.feature`: сценарии «Нет jq», «Каталог недоступен» (skip под root через `[ $(id -u) = 0 ]` → печатать ожидаемые строки), «Провал финальной записи», «Относительный TEST_STATE_DIR», BUSY с `cmp`; `TEST_CMD` с `chmod` обязан вернуть права в конце (REQ-background-tests-001)
- [x] 3. фоновый `scripts/test-bg.sh` зелёный → `ak:code-reviewer` → `openspec archive background-tests-minors --yes` → `agent-ops spec-coverage .` → коммит, push (REQ-background-tests-001)
