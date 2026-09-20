# language: ru
# Требования из openspec/specs/background-tests/spec.md (change background-tests).
# Сценарии всегда задают TEST_STATE_DIR внутри .claude/state/bdd/ — иначе
# прогон затёр бы настоящий вердикт и Stop-гейт заблокировал бы агента.
Функция: Фоновый прогон тестов с вердиктом и Stop-гейтом

  @REQ-background-tests-001
  Сценарий: Зелёный прогон даёт PASS
    Дано репозиторий проекта
    Когда я выполняю команду "d=.claude/state/bdd/pass; TEST_STATE_DIR=$d TEST_CMD=true scripts/test-bg.sh && echo verdict=$(jq -r --arg s : '.status+$s+(.acked|tostring)' $d/test-result.json)"
    Тогда команда завершается успешно
    И вывод содержит "TESTS PASS rc=0"
    И вывод содержит "verdict=PASS:false"

  @REQ-background-tests-001
  Сценарий: Красный прогон даёт FAIL
    Дано репозиторий проекта
    Когда я выполняю команду "d=.claude/state/bdd/fail; TEST_STATE_DIR=$d TEST_CMD=false scripts/test-bg.sh; rc=$?; echo verdict=$(jq -r .status $d/test-result.json); exit $rc"
    Тогда команда завершается с ошибкой
    И вывод содержит "TESTS FAIL rc=1"
    И вывод содержит "verdict=FAIL"

  @REQ-background-tests-001
  Сценарий: Превышение таймера даёт HANG
    Дано репозиторий проекта
    Когда я выполняю команду "d=.claude/state/bdd/hang; TEST_STATE_DIR=$d TEST_TIMEOUT=1 TEST_CMD='sleep 5' scripts/test-bg.sh; rc=$?; echo verdict=$(jq -r .status $d/test-result.json); exit $rc"
    Тогда команда завершается с ошибкой
    И вывод содержит "TESTS HANG rc=124"
    И вывод содержит "verdict=HANG"

  @REQ-background-tests-001
  Сценарий: Под pytest без TEST_STATE_DIR обёртка отказывается писать
    Дано репозиторий проекта
    Когда я выполняю команду "TEST_CMD=true scripts/test-bg.sh"
    Тогда команда завершается с ошибкой
    И вывод содержит "TEST_STATE_DIR"

  @REQ-background-tests-002
  Сценарий: Необработанный FAIL блокирует завершение хода
    Дано репозиторий проекта
    Когда я выполняю команду "d=.claude/state/bdd/gate-fail; TEST_STATE_DIR=$d TEST_CMD=false scripts/test-bg.sh >/dev/null; echo '{}' | TEST_STATE_DIR=$d scripts/test-gate.sh | jq -r '.decision,.reason'"
    Тогда команда завершается успешно
    И вывод содержит "block"
    И вывод содержит "FAIL"
    И вывод содержит "test-result.log"

  @REQ-background-tests-002
  Сценарий: Тесты ещё бегут — хук молчит
    Дано репозиторий проекта
    Когда я выполняю команду "d=.claude/state/bdd/gate-run; TEST_STATE_DIR=$d TEST_CMD=false scripts/test-bg.sh >/dev/null; out=$(jq -nc --arg t shell --arg c 'scripts/test-bg.sh' --arg s running '{background_tasks:[{type:$t,status:$s,command:$c}]}' | TEST_STATE_DIR=$d scripts/test-gate.sh); echo rc=$? len=${#out}"
    Тогда вывод содержит "rc=0 len=0"

  @REQ-background-tests-002
  Сценарий: Завершённая задача в списке не глушит гейт
    Дано репозиторий проекта
    Когда я выполняю команду "d=.claude/state/bdd/gate-done; TEST_STATE_DIR=$d TEST_CMD=false scripts/test-bg.sh >/dev/null; jq -nc --arg t shell --arg c 'scripts/test-bg.sh' --arg s completed '{background_tasks:[{type:$t,status:$s,command:$c}]}' | TEST_STATE_DIR=$d scripts/test-gate.sh | jq -r .decision"
    Тогда вывод содержит "block"

  @REQ-background-tests-002
  Сценарий: PASS, квитированный, устаревший или отсутствующий вердикт — хук молчит
    Дано репозиторий проекта
    Когда я выполняю команду "d=.claude/state/bdd/gate-silent; n=0; g() { out=$(printf %s $1 | TEST_STATE_DIR=$d scripts/test-gate.sh); [ $? -eq 0 ] && [ ${#out} -eq 0 ] && n=$((n+1)); }; TEST_STATE_DIR=$d TEST_CMD=true scripts/test-bg.sh >/dev/null; g '{}'; TEST_STATE_DIR=$d TEST_CMD=false scripts/test-bg.sh >/dev/null; jq '.acked=true' $d/test-result.json > $d/t && mv $d/t $d/test-result.json; g '{}'; TEST_STATE_DIR=$d TEST_CMD=false scripts/test-bg.sh >/dev/null; touch -d '-5 hours' $d/test-result.json; g '{}'; TEST_STATE_DIR=$d TEST_CMD=false scripts/test-bg.sh >/dev/null; g ''; rm -f $d/test-result.json; g '{}'; echo silent=$n/5"
    Тогда вывод содержит "silent=5/5"

  @REQ-background-tests-002
  Сценарий: Маркер авто-компакта — хук молчит
    Дано репозиторий проекта
    Когда я выполняю команду "d=.claude/state/bdd/gate-compact; TEST_STATE_DIR=$d TEST_CMD=false scripts/test-bg.sh >/dev/null; out=$(jq -nc --arg m 'x <<<AUTO-COMPACT-READY-vK7q>>> y' '{last_assistant_message:$m}' | TEST_STATE_DIR=$d scripts/test-gate.sh); echo rc=$? len=${#out}"
    Тогда вывод содержит "rc=0 len=0"

  @REQ-background-tests-003
  Сценарий: Гейт зарегистрирован, автозапуска нет
    Дано репозиторий проекта
    Когда я выполняю команду "jq -r '.hooks.Stop[]?.hooks[]?.command' .claude/settings.json; echo autorun=$(jq -r '.hooks.PostToolUse[]?.hooks[]?.command' .claude/settings.json | grep -c test-bg)"
    Тогда команда завершается успешно
    И вывод содержит "scripts/test-gate.sh"
    И вывод содержит "autorun=0"

  @REQ-background-tests-003
  Сценарий: Правило записано в CLAUDE.md
    Дано репозиторий проекта
    Тогда файл "CLAUDE.md" содержит "scripts/test-bg.sh"
    И файл "CLAUDE.md" содержит "run_in_background"
