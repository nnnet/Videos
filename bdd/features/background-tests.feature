# language: ru
# Требования из openspec/specs/background-tests/spec.md (change background-tests,
# hardening). Сценарии всегда задают TEST_STATE_DIR внутри .claude/state/bdd/ —
# иначе прогон затёр бы настоящий вердикт и Stop-гейт заблокировал бы агента.
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
    Когда я выполняю команду "d=.claude/state/bdd/fail; TEST_STATE_DIR=$d TEST_CMD='exit 7' scripts/test-bg.sh; rc=$?; echo wrapper-rc=$rc verdict=$(jq -r .status $d/test-result.json); exit $rc"
    Тогда команда завершается с ошибкой
    И вывод содержит "TESTS FAIL rc=7"
    И вывод содержит "wrapper-rc=7 verdict=FAIL"

  @REQ-background-tests-001
  Сценарий: Превышение таймера даёт HANG
    Дано репозиторий проекта
    Когда я выполняю команду "d=.claude/state/bdd/hang; TEST_STATE_DIR=$d TEST_TIMEOUT=1 TEST_CMD='sleep 5' scripts/test-bg.sh; rc=$?; echo verdict=$(jq -r .status $d/test-result.json); exit $rc"
    Тогда команда завершается с ошибкой
    И вывод содержит "TESTS HANG rc=124"
    И вывод содержит "verdict=HANG"

  @REQ-background-tests-001
  Сценарий: До старта прогона вердикт RUNNING
    Дано репозиторий проекта
    Когда я выполняю команду "d=.claude/state/bdd/running; TEST_STATE_DIR=$d TEST_CMD='echo during=$(jq -r .status .claude/state/bdd/running/test-result.json)' scripts/test-bg.sh && echo after=$(jq -r .status $d/test-result.json)"
    Тогда команда завершается успешно
    И вывод содержит "during=RUNNING"
    И вывод содержит "after=PASS"

  @REQ-background-tests-001
  Сценарий: Второй одновременный запуск отказывается
    Дано репозиторий проекта
    Когда я выполняю команду "d=.claude/state/bdd/busy; TEST_STATE_DIR=$d TEST_CMD='sleep 3' scripts/test-bg.sh >/dev/null & sleep 1; TEST_STATE_DIR=$d TEST_CMD=true scripts/test-bg.sh; echo second-rc=$?; wait"
    Тогда вывод содержит "TESTS BUSY"
    И вывод содержит "second-rc=3"

  @REQ-background-tests-001
  Сценарий: Нечисловой TEST_TIMEOUT — отказ без вердикта
    Дано репозиторий проекта
    Когда я выполняю команду "d=.claude/state/bdd/bad-timeout; rm -f $d/test-result.json $d/test-result.json.tmp; TEST_STATE_DIR=$d TEST_TIMEOUT=abc TEST_CMD=true scripts/test-bg.sh; rc=$?; TEST_STATE_DIR=$d TEST_TIMEOUT=0 TEST_CMD=true scripts/test-bg.sh; echo zero-rc=$?; echo verdict-files=$(ls $d/test-result.json* 2>/dev/null | wc -l); exit $rc"
    Тогда команда завершается с ошибкой
    И вывод содержит "TESTS REFUSED"
    И вывод содержит "zero-rc=2"
    И вывод содержит "verdict-files=0"

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
    Когда я выполняю команду "d=.claude/state/bdd/gate-run; TEST_STATE_DIR=$d TEST_CMD=false scripts/test-bg.sh >/dev/null; TEST_STATE_DIR=$d TEST_CMD='sleep 3' scripts/test-bg.sh >/dev/null & sleep 1; out=$(echo '{}' | TEST_STATE_DIR=$d scripts/test-gate.sh); echo rc=$? len=${#out}; wait"
    Тогда вывод содержит "rc=0 len=0"

  @REQ-background-tests-002
  Сценарий: Вердикт RUNNING — хук молчит
    Дано репозиторий проекта
    Когда я выполняю команду "d=.claude/state/bdd/gate-running; mkdir -p $d; jq -nc --arg s RUNNING '{status:$s,rc:null,acked:false}' > $d/test-result.json; out=$(echo '{}' | TEST_STATE_DIR=$d scripts/test-gate.sh); echo rc=$? len=${#out}"
    Тогда вывод содержит "rc=0 len=0"

  @REQ-background-tests-002
  Сценарий: Завершённая задача в списке не глушит гейт
    Дано репозиторий проекта
    Когда я выполняю команду "d=.claude/state/bdd/gate-done; TEST_STATE_DIR=$d TEST_CMD=false scripts/test-bg.sh >/dev/null; n=0; for s in completed running success 1; do r=$(jq -nc --arg t shell --arg c scripts/test-bg.sh --arg s $s '{background_tasks:[{type:$t,command:$c,status:($s|tonumber? // $s)}]}' | TEST_STATE_DIR=$d scripts/test-gate.sh | jq -r .decision); if [ block = $r ]; then n=$((n+1)); else echo fail-case=$s; fi; done; echo block=$n/4"
    Тогда вывод содержит "block=4/4"

  @REQ-background-tests-002
  Сценарий: PASS, квитированный, устаревший или отсутствующий вердикт — хук молчит
    Дано репозиторий проекта
    Когда я выполняю команду "d=.claude/state/bdd/gate-silent; n=0; g() { out=$(printf %s $2 | TEST_STATE_DIR=$d scripts/test-gate.sh); if [ $? -eq 0 ] && [ ${#out} -eq 0 ]; then n=$((n+1)); else echo fail-case=$1; fi; }; TEST_STATE_DIR=$d TEST_CMD=true scripts/test-bg.sh >/dev/null; g pass '{}'; TEST_STATE_DIR=$d TEST_CMD=false scripts/test-bg.sh >/dev/null; jq '.acked=true' $d/test-result.json > $d/t && mv $d/t $d/test-result.json; g acked '{}'; TEST_STATE_DIR=$d TEST_CMD=false scripts/test-bg.sh >/dev/null; touch -d '-5 hours' $d/test-result.json; g ttl '{}'; TEST_STATE_DIR=$d TEST_CMD=false scripts/test-bg.sh >/dev/null; g empty-stdin ''; rm -f $d/test-result.json; g no-file '{}'; echo silent=$n/5"
    Тогда вывод содержит "silent=5/5"

  @REQ-background-tests-002
  Сценарий: Маркер авто-компакта — хук молчит
    Дано репозиторий проекта
    Когда я выполняю команду "d=.claude/state/bdd/gate-compact; TEST_STATE_DIR=$d TEST_CMD=false scripts/test-bg.sh >/dev/null; out=$(jq -nc --arg m 'x <<<AUTO-COMPACT-READY-vK7q>>> y' '{last_assistant_message:$m}' | TEST_STATE_DIR=$d scripts/test-gate.sh); echo rc=$? len=${#out}"
    Тогда вывод содержит "rc=0 len=0"

  @REQ-background-tests-002
  Сценарий: Дамп события только в отладке
    Дано репозиторий проекта
    Когда я выполняю команду "d=.claude/state/bdd/gate-dump; TEST_STATE_DIR=$d TEST_CMD=true scripts/test-bg.sh >/dev/null; rm -f $d/last-stop.json; echo '{}' | TEST_STATE_DIR=$d scripts/test-gate.sh; echo dump=$(ls $d/last-stop.json 2>/dev/null | wc -l); echo '{}' | TEST_STATE_DIR=$d TEST_GATE_DEBUG=1 scripts/test-gate.sh; echo dump=$(ls $d/last-stop.json 2>/dev/null | wc -l)"
    Тогда вывод содержит "dump=0"
    И вывод содержит "dump=1"

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
    И файл "CLAUDE.md" содержит "RUNNING"
    И файл "CLAUDE.md" содержит "TEST_GATE_DEBUG"
