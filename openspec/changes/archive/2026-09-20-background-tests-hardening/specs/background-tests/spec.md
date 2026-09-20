# background-tests — дельта (hardening)

## MODIFIED Requirements

### Requirement: REQ-background-tests-001 Обёртка фиксирует вердикт прогона
Обёртка `scripts/test-bg.sh` SHALL запускать набор тестов проекта под
сторожевым таймером (`TEST_TIMEOUT`, по умолчанию 600 с) и по завершении
атомарно записывать вердикт в `<state>/test-result.json` с полями `status`
(`PASS` | `FAIL` | `HANG`), `rc`, `log`, `ts`, `cwd`, `acked: false`, полный
вывод — в `<state>/test-result.log`, а в stdout печатать строку
`TESTS <status> rc=<n>` и хвост лога. **До старта прогона** обёртка SHALL
атомарно записать вердикт `status:"RUNNING"`, `rc: null`, чтобы предыдущий
вердикт не пережил старт нового прогона. Код возврата обёртки SHALL
равняться коду прогона. `<state>` по умолчанию — `.claude/state` в корне
репозитория, вычисленном от расположения скрипта; относительный
`TEST_STATE_DIR` SHALL резолвиться от того же корня. Команда и каталог
переопределяются `TEST_CMD`, `TEST_STATE_DIR`. Нечисловой или нулевой `TEST_TIMEOUT`,
отсутствие `jq` или ошибка записи вердикта → `TESTS REFUSED`, код 2, вердикт
не тронут (временный файл удалён). Второй одновременный запуск SHALL
завершаться сразу с `TESTS BUSY`, код 3, не трогая вердикт. Под pytest
(`PYTEST_CURRENT_TEST` задан) без `TEST_STATE_DIR` обёртка SHALL отказываться
писать в каталог по умолчанию.

#### Scenario: Зелёный прогон даёт PASS
- **WHEN** обёртка запущена с `TEST_STATE_DIR` во временный каталог и `TEST_CMD=true`
- **THEN** команда завершается успешно
- **AND** вывод содержит `TESTS PASS rc=0`
- **AND** файл вердикта содержит `"status":"PASS"` и `"acked":false`

#### Scenario: Красный прогон даёт FAIL
- **WHEN** обёртка запущена с `TEST_CMD='exit 7'`
- **THEN** команда завершается с ошибкой
- **AND** вывод содержит `TESTS FAIL rc=7` и `wrapper-rc=7`

#### Scenario: Превышение таймера даёт HANG
- **WHEN** обёртка запущена с `TEST_TIMEOUT=1`, `TEST_CMD='sleep 5'`
- **THEN** вывод содержит `TESTS HANG rc=124`
- **AND** файл вердикта содержит `"status":"HANG"`

#### Scenario: До старта прогона вердикт RUNNING
- **WHEN** обёртка запущена с `TEST_CMD`, печатающим `status` из файла вердикта
- **THEN** вывод содержит `RUNNING`
- **AND** после завершения файл вердикта содержит `"status":"PASS"`

#### Scenario: Второй одновременный запуск отказывается
- **WHEN** обёртка запущена дважды параллельно в один `TEST_STATE_DIR`
- **THEN** вывод содержит `TESTS BUSY` и `second-rc=3`

#### Scenario: Нечисловой TEST_TIMEOUT — отказ без вердикта
- **WHEN** обёртка запущена с `TEST_TIMEOUT=abc` в каталог без вердикта
- **THEN** команда завершается с ошибкой
- **AND** вывод содержит `TESTS REFUSED` и `verdict-files=0`

#### Scenario: Под pytest без TEST_STATE_DIR обёртка отказывается писать
- **WHEN** обёртка запущена из-под pytest без `TEST_STATE_DIR`
- **THEN** команда завершается с ошибкой
- **AND** вывод содержит `TEST_STATE_DIR`

### Requirement: REQ-background-tests-002 Stop-гейт не даёт закончить ход с необработанным провалом
Хук `scripts/test-gate.sh` на событии `Stop` SHALL читать JSON события из
stdin и вердикт из `<state>/test-result.json` (тот же `<state>`, что у
обёртки; относительный `TEST_STATE_DIR` — от корня репозитория). Он SHALL
вывести ровно один JSON-объект `{"decision":"block","reason":…}` — reason
содержит статус, код, путь к логу и инструкцию (FAIL → найти причину,
исправить, перезапустить обёртку в фоне; HANG → найти зависший шаг по логу,
таймер молча не поднимать, rc=137 может быть внешним kill; если исправить
нельзя — квитировать точной командой из reason и объяснить пользователю) —
тогда и только тогда, когда одновременно (`background_tasks` события
SHALL NOT влиять на решение — идущий прогон виден по вердикту `RUNNING`):
- вердикт есть, читается и не старше `TEST_RESULT_TTL_MIN` (по умолчанию 240 мин);
- `status` ∈ {`FAIL`, `HANG`} и `acked` = `false` (`RUNNING`, `PASS` → молчать);
- `last_assistant_message` не содержит маркера `AUTO-COMPACT-READY`.

Во всех остальных случаях и при любой внутренней ошибке хук SHALL
завершиться кодом 0 без вывода; SHALL NOT завершаться кодом 2. Сырой JSON
события SHALL записываться в `<state>/last-stop.json` только при
`TEST_GATE_DEBUG=1`.

#### Scenario: Необработанный FAIL блокирует завершение хода
- **WHEN** вердикт `FAIL`, `acked` = `false`, в событии Stop нет фоновых задач
- **THEN** вывод содержит `"decision":"block"`, `FAIL` и путь к логу

#### Scenario: Тесты ещё бегут — хук молчит
- **WHEN** предыдущий вердикт `FAIL`, обёртка запущена в фоне с долгим
  `TEST_CMD`, гейт вызван во время прогона
- **THEN** вывод содержит `rc=0 len=0`

#### Scenario: Вердикт RUNNING — хук молчит
- **WHEN** файл вердикта содержит `"status":"RUNNING"`
- **THEN** вывод содержит `rc=0 len=0`

#### Scenario: Завершённая задача в списке не глушит гейт
- **WHEN** вердикт `FAIL`, а в `background_tasks` задача `shell` с командой
  `scripts/test-bg.sh` и `status` по очереди `completed`, `running`, `success`, числовой `1`
- **THEN** вывод содержит `block=4/4` — список задач не влияет на решение

#### Scenario: PASS, квитированный, устаревший или отсутствующий вердикт — хук молчит
- **WHEN** по очереди: вердикт `PASS`; `acked` = `true`; mtime старше TTL; пустой stdin; файла нет
- **THEN** вывод содержит `silent=5/5`, а при провале — имя случая

#### Scenario: Маркер авто-компакта — хук молчит
- **WHEN** вердикт `FAIL`, а `last_assistant_message` содержит `AUTO-COMPACT-READY`
- **THEN** вывод содержит `rc=0 len=0`

#### Scenario: Дамп события только в отладке
- **WHEN** гейт вызван без `TEST_GATE_DEBUG`, затем с `TEST_GATE_DEBUG=1`
- **THEN** вывод содержит `dump=0` затем `dump=1`
