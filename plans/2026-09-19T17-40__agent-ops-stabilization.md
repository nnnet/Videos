# Платформа `~/.agent-ops` — стабильность и автоматика: что доделать

Дата: 2026-09-19 17:40. Продолжение
`2026-09-19T00-10__claude-global-env-foundation.md` (39 узлов, все закрыты).
Гайд для человека: `~/.agent-ops/docs/getting-started.md`.

## Контекст и цель

Пять возможностей построены и приняты по одному разу — руками, в сессии. Цель
этого плана: чтобы каждая **включалась сама в новом репозитории**, **не
ломалась молча** и **не зависела от снятых инструментов**. Мерило одно —
пустой репозиторий + `claude` + коммит, без единой команды человека, даёт
журнал, защиту от утечки в коммит и видимость в общем обзоре.

## Что вскрылось при написании гайда (факты, не догадки)

1. **Гейт SDD мёртв.** `agent-ops spec-check` зовёт `ak change show/check`
   (agentkit), а agentkit снят пользователем. Требования и сценарии
   (`spec-coverage`) живы — сломана только отметка задачи.
2. **Окно утечки `.agent/` в коммит.** SessionStart-хук запускает бутстрап в
   `detect` (не пишет). Журнал создаёт `agent-emit` при первом действии, а
   `.git/info/exclude` появляется только при первом коммите (post-commit,
   т.е. ПОСЛЕ него) или ручным `safe-auto`. `git add -A` до этого — журнал
   в истории.
3. **Новый проект невидим в обзоре**, пока человек не допишет строку в
   `registry.tsv`: `agent-q`, ночной прогон и herdr читают только реестр.
   Намеренно (224 репозитория), но «руками» — значит забудут.
4. **Хуки не самопроверяются.** rtk-хук месяцами печатал warning на каждый
   вызов, и никто не узнал: `doctor` проверяет структуру `~/.agent-ops`, а
   не то, что `settings.json` ссылается на живые файлы.
5. **`harvest` только предлагает** — принять кандидата = переписать лист
   руками целиком. Половина «полуавтоматического» отсутствует.
6. **docs-check не ловит битые ссылки** — только листья без входящих.
   Разрез CLAUDE.md добавил пять ссылок из роутера; опечатка в любой из
   них пройдёт гейт.

## Решения

- **Пересмотрено 17:30 по слову пользователя** («при первом запуске клода
  всё должно инициализироваться автоматически»): дефолт SessionStart —
  `full-auto`. Первый запуск в любой папке/клоне ставит журнал, exclude,
  docs, openspec, bdd/, строку в реестре (`active=yes`), запись в
  workspace; pytest-bdd и `repowise init` — фоном (`slow-lane.sh`, flock,
  лог `.agent/slow-lane.log`, событие `bootstrap.slow-lane`). Отказ для
  конкретного проекта — `detect` в колонке mode реестра. Прежние варианты
  (очередь обнаружения, safe-auto-дефолт) сняты — группа P.
- Обход диска по-прежнему нет: в реестр попадает только то, где запускали
  `claude`. Это и есть «где реально работали».
- Гейт SDD переводится на `openspec` напрямую (`tasks.md` — единственный
  носитель отметки), без слоя agentkit. Отвергнуто: держать `ak` как
  опциональный путь — снятый инструмент не должен оставаться в коде.
- Индексация repowise автоматическая, но за index-guard'ом: каталог с
  тысячами файлов вне git не индексируется, в лог — команда для проверки.

## Граф работ

```yaml
graph:
  # P. полная автоматика первого запуска (решение пользователя 17:30)
  - {id: P1, needs: [],   parallel: "",      status: "[x]", files: [~/.agent-ops/bootstrap/init-project.sh, ~/.agent-ops/config.sh, ~/.claude/hooks/session-start.sh, ~/.agent-ops/registry.tsv]}
  - {id: P2, needs: [],   parallel: "",      status: "[x]", files: [~/.agent-ops/bootstrap/templates/bdd/**, ~/.agent-ops/bin/agent-ops]}
  - {id: P3, needs: [P1], parallel: "",      status: "[x]", files: [~/.agent-ops/bootstrap/slow-lane.sh, ~/.agent-ops/bin/agent-nightly]}
  - {id: P4, needs: [P1, P2, P3], parallel: "", status: "[x]", files: [~/.agent-ops/tests/bootstrap-verify.sh, ~/.agent-ops/docs/getting-started.md]}
  # J. автоматика включения и самопроверка
  - {id: J1, needs: [],   parallel: "",      status: "[-]", files: []}
  - {id: J2, needs: [],   parallel: "",      status: "[-]", files: []}
  - {id: J3, needs: [],   parallel: "auto",  status: "[x]", files: [~/.agent-ops/bin/agent-ops]}
  - {id: J4, needs: [J3], parallel: "",      status: "[x]", files: [~/.agent-ops/bin/agent-nightly, ~/.config/systemd/user/agent-nightly.service]}
  # K. executable SDD
  - {id: K1, needs: [],   parallel: "sdd",   status: "[x]", files: [~/.agent-ops/bin/agent-ops, ~/.agent-ops/tests/spec-check-verify.sh]}
  - {id: K2, needs: [K1], parallel: "",      status: "[x]", files: [~/.agent-ops/sql/projections/req-status.sql]}
  - {id: K3, needs: [], parallel: "sdd",   status: "[x]", files: [~/.agent-ops/bootstrap/templates/openspec/**]}
  # L. событийный слой
  - {id: L1, needs: [],   parallel: "ev",    status: "[x]", files: [~/.agent-ops/sql/events.ddl.sql, ~/.agent-ops/bin/agent-ops]}
  - {id: L2, needs: [],   parallel: "ev",    status: "[x]", files: [~/.agent-ops/bin/agent-nightly]}
  - {id: L3, needs: [],   parallel: "ev",    status: "[x]", files: [~/.agent-ops/sql/projections/compare-windows.sql]}
  # M. дерево документов
  - {id: M1, needs: [],   parallel: "docs",  status: "[x]", files: [~/.agent-ops/bin/agent-ops]}
  - {id: M2, needs: [],   parallel: "docs",  status: "[x]", files: [~/.agent-ops/bootstrap/templates/CLAUDE.md, ~/.agent-ops/bootstrap/init-project.sh]}
  # N. control center и соседи
  - {id: N1, needs: [],   parallel: "cc",    status: "[x]", files: [~/.agent-ops/bin/agent-herdr-layout]}
  - {id: N2, needs: [P1], parallel: "",      status: "[x]", files: [~/.agent-ops/bin/agent-ops, /mnt/82A23910A2390A65/.repowise-workspace.yaml]}
  - {id: N3, needs: [],   parallel: "cc",    status: "[x]", files: [~/.agent-ops/bin/agent-nightly]}
  # O. полуавтоматическое пополнение
  - {id: O1, needs: [],   parallel: "",      status: "[x]", files: [~/.agent-ops/bin/agent-harvest, ~/.agent-ops/bootstrap/templates/docs/_leaf-template.md]}
  - {id: O2, needs: [O1], parallel: "",      status: "[x]", files: [~/.agent-ops/bin/agent-harvest]}
  # Q. резервирование (заказ пользователя 22:00)
  - {id: Q1, needs: [],   parallel: "",      status: "[x]", files: [~/.agent-ops/bin/agent-backup, ~/.agent-ops/systemd/**, ~/.agent-ops/tests/backup-verify.sh, ~/.agent-ops/bin/agent-ops, ~/.agent-ops/docs/backup.md, bdd/features/project-baseline.feature]}
  - {id: Q2, needs: [],   parallel: "",      status: "[x]", files: [~/.agent-ops/git-hooks/dispatcher, ~/.agent-ops/bootstrap/templates/CLAUDE.md, ~/.agent-ops/tests/precommit-gate-verify.sh, CLAUDE.md]}
```

### Состояние исполнения

**19:50 — план закрыт.** 17 узлов `[x]`, J1/J2 `[-]`. Коммит `~/.agent-ops` `14b247a`. Финал: bootstrap 35/35, doctor 15/15, schema 19/19, spec-check 23/23, docs-check 15/15, workspace-sync 30/30; docs-check обоих деревьев зелёный; живой doctor — ок 44, проблем 0.

Статус — только в YAML. P1–P4 закрыты 17:30–17:45 (коммит `5dcbe17`).
J1/J2 отменены — их цель закрыта группой P. K3 разблокирован решением
пользователя 17:50 (openspec напрямую, `REQ-<cap>-NNN`, шаблон при
бутстрапе; bmad/ouroboros снимаются). Партия 1 (17:55, параллельно,
зоны не пересекаются): J3, L2, L3, N1, O1, M2+K3 (один агент — оба правят
`init-project.sh`). Партия 2 после неё: K1 → L1 → M1 (все в `bin/agent-ops`,
строго по одному), N3 (после L2), J4 (после J3+N3), K2 (после K1), O2
(после O1), N2.

---

## Узлы

### P1 `full-auto-default` — первый запуск поднимает всё сам
- выход: `BOOTSTRAP_MODE=full-auto` в `config.sh` (v2); `init-project.sh`: шаги `ensure_registry` (имя = папка → `[a-z0-9_]`, суффикс при коллизии, `full-auto\tyes`), `ensure_workspace` (`repowise workspace add --no-index --alias`), `ensure_repowise_ignore`, `ensure_slow_lane`; `detect` в колонке mode реестра = отказ (CLI `--mode` сильнее); хук — `timeout 20`; отчёт до 8 строк шагов; тесты подменяют `OPS_REGISTRY`/`WORKSPACE_FILE`, фон отключают `BOOTSTRAP_SKIP_SLOW=1`.
- приёмка: `bootstrap-verify` §7 — 14 проверок, все зелёные; хук 1.4 с; повтор «изменений нет»; `git add -A` без `.agent/`/`.repowise/`; Videos поднят живьём (`openspec/`, `bdd/`, 2 passed).
- заметки: имя из реестра важнее имени папки — `ensure_registry` идёт до `ensure_bdd`, чтобы шаблон получил то же имя. `WORKSPACE_FILE` выведен в `config.sh` (файл лежит на уровень выше `WORKSPACE_ROOT`), nightly его читает.

### P2 `bdd-template` — слой сценариев из коробки
- выход: `bootstrap/templates/bdd/`: `pytest.ini` (rootdir = bdd), `conftest.py` (`repo`, `context`), `steps/repo_steps.py` (каталог/файл существует, команда, вывод), `steps/sql_steps.py` (запрос к `agent-q` и к файлу событий через duckdb), `test_features.py` (`scenarios()` абсолютным путём — относительный складывался с `bdd_features_base_dir`), первый `.feature` без REQ-тегов; `spec-check` ищет `bdd/` и `host-local/bdd/`; `doctor` помечает `bdd`.
- приёмка: на пустом репо `pytest -c bdd/pytest.ini bdd` → 2 passed (второй сценарий — SQL к `.agent/events.db`); `spec-coverage` 0/0/0.
- заметки: пример тега в комментарии feature-файла (`@REQ-001`) гейт принимал за настоящий — в шаблоне остался только `@REQ-<id>`.

### P3 `slow-lane` — минутное в фоне, один экземпляр на проект
- выход: `bootstrap/slow-lane.sh`: `flock` на `.agent/slow-lane.lock`; pytest-bdd в `.venv` проекта либо `--user --break-system-packages` (PEP 668, только `~/.local`); `repowise init --yes` за `index-guard`, `timeout 1800`, лог `.agent/repowise-init.log`; событие `bootstrap.slow-lane {status, done, failed}`.
- приёмка: на temp-репо: pip первый раз упал (PEP 668) → флаг → ok; repowise 36 с; событие в журнале; повторный запуск — «вики уже есть».
- заметки: хук запускает через `setsid nohup … &`, сам возвращается сразу; `have_wiki` в следующей сессии — признак завершения. **Дефект, найденный при приёмке (17:35):** `repowise init` ставит post-commit через `git rev-parse --git-path hooks` и при глобальном `core.hooksPath` дописал блок в наш `git-hooks/dispatcher` (та же ловушка, что при G6). Исправлено: на время `init` ставится локальный `core.hooksPath=<repo>/.git/hooks` и снимается после; плюс страховка — блок в диспетчере вырезается с бэкапом и событием `failed: repowise:global-hook`. Проверено на temp-репо: блок в `<repo>/.git/hooks/post-commit`, диспетчер чист. Кандидат в J3: `doctor` должен красить `repowise-hook-start` в диспетчере.

### P4 `verify-and-guide` — приёмка и гайд
- выход: `bootstrap-verify.sh` §7 (хук end-to-end, идемпотентность, утечка в индекс git, реестр-отказ, pytest, spec-coverage); `docs/getting-started.md` переписан: «git init → claude → всё», таблица «само за секунду» / «в фоне за минуты» / «руками — ничего обязательного».
- приёмка: 29/29 зелёных вне песочницы; `docs-check` зелёный.
- заметки: —

### J1 `exclude-before-first-commit` — отменён
- заметки: цель закрыта P1: full-auto ставит exclude на старте сессии, приёмка «`git add -A` без `.agent/`» — в §7 verify.

### J2 `discovered-queue` — отменён
- заметки: пользователь выбрал прямую запись в реестр при первом запуске (P1); очередь обнаружения не нужна.

### J3 `doctor-hooks` — самопроверка подключений
- выход: `agent-ops doctor` дополнительно: каждый `command` из `~/.claude/settings.json` (`hooks.*`) существует и исполняем; `core.hooksPath` указывает на наш диспетчер; таймер `agent-nightly.timer` активен; каждая БД реестра открывается и имеет таблицу `events`; `~/.claude/CLAUDE.md` ссылается на существующие листы.
- приёмка: подложить в settings.json хук на несуществующий файл → `doctor` красный с именем файла; убрать → зелёный.
- заметки: ровно этот класс дефекта (rtk) жил незамеченным; проверка стоит секунду. **Сделано 18:15:** 5 секций в `cmd_doctor` (хуки claude по `$CLAUDE_SETTINGS`, `core.hooksPath` + диспетчер без `repowise-hook-start`, таймер, БД реестра read-only со снапшотом как в `agent-q`, ссылки `~/.claude/CLAUDE.md` → `docs/claude/`); `tests/doctor-verify.sh` 15/15; живой doctor 45/45. Эвристика: листом считается только `[a-z0-9-]+\.md` в бэктиках (иначе `HANDOFF.md` красил бы). `CLAUDE_SETTINGS`/`CLAUDE_MD` — дефолты внутри `cmd_doctor`, в `config.sh` не вынесены.

### Q1 `backup-4h` — remote для платформы и бэкап каждые 4 часа
- выход: приватный `github.com/nnnet/.agent-ops` (origin `~/.agent-ops`, ветка `master`); `bin/agent-backup [--no-push]`: копия `.repowise-workspace.yaml` → `backups/`, `.dump` `events.db` активных проектов → `backups/<name>/events.sql`, `repowise decision list --format json` → `decisions.json`, коммит+пуш `~/.agent-ops`, коммит+пуш `~/.claude` (rebase при расхождении, `exit 0` всегда); `systemd/agent-backup.{service,timer}` (`00/4:00`, Persistent) + копия в `~/.config/systemd/user/`; `doctor`: обе таймера, remote платформы, итог последнего прогона; `docs/backup.md`.
- приёмка: `tests/backup-verify.sh` 14/14; первый боевой прогон — 4 проекта + workspace в origin; `git rev-list origin/master..master` = 0, `git -C ~/.claude rev-list origin/main..main` = 0; `systemctl --user list-timers` показывает `agent-backup.timer`.
- заметки: шаблон бутстрапа править не пришлось — `project-baseline.feature` с тегом там уже был, Videos бутстрапился раньше; файл добавлен в Videos руками (не закоммичен). Событие о бэкапе в журнал не пишется намеренно (иначе каждый снимок отличался бы от предыдущего). Первый пуш `~/.claude` (12 МБ пак, 3 неотправленных коммита с 24.08 — хук на `/clear` не пушил) упёрся в таймаут 120 с и «Connection closed» от GitHub; ручной повтор — 11 с; таймаут поднят до 300 с. wiki.db не бэкапится.

### Q2 `spec-gate-precommit` — спеки по умолчанию
- выход: блок 1б в `git-hooks/dispatcher`: pre-commit в репозитории с `openspec/` и `bdd/features/`, если в индексе есть файлы `openspec/specs/` или `bdd/features/`, зовёт `agent-ops spec-coverage`; код 1 → коммит остановлен с причиной; timeout/код 2 → пропуск; обход `AGENT_OPS_SKIP_GATE=1`. Правило «сначала требование и сценарий» — в шаблоне CLAUDE.md и в CLAUDE.md Videos (у него свой файл, шаблон не применялся).
- приёмка: `tests/precommit-gate-verify.sh` 7/7 (сходятся / без сценария остановлен / чужой файл в индексе проходит / обход / сценарий добавлен / без bdd).
- заметки: ViralMint не задет — там openspec без `bdd/`. Гейт смотрит рабочее дерево, не индекс.

### J4 `nightly-selfcheck` — платформа проверяет себя ночью
- выход: `agent-nightly` в начале прогона зовёт `doctor` и `bootstrap-verify`; результат — событие `nightly.selfcheck` (`ok`/`fail`, список красных) в журнал Videos (первичный проект); красный selfcheck прерывает `--apply`.
- приёмка: журнал systemd за ночь содержит selfcheck; `agent-q -p gate-failures` показывает подложенный провал.
- заметки: `bootstrap-verify` вне песочницы уже зелёный (исправлен подсчёт `.git/ai`). **Сделано 19:05:** секция в `agent-nightly` сразу после `nightly.run.started`: `doctor` + `bootstrap-verify` под `cap`/бюджетом; событие `nightly.selfcheck {status,doctor,verify,seconds,red[≤10]}` в `NIGHTLY_PRIMARY` (дефолт Videos); красный при `--apply` → понижение до report (`apply_aborted:1`), `repowise update` не запускается, отчёт цельный; строка «самопроверка:» в отчёте, поля `selfcheck`/`apply_aborted` в `nightly.run.finished`. Приёмка на temp: зелёный (35/0), красный через подменный `CLAUDE_SETTINGS`, обрезка по `--max-seconds 1` → `rc=124`. systemd не тронут (90 мин > бюджета). Нюанс: `doctor_db_ok` кладёт/удаляет пробный файл в `.agent/` каждого активного проекта — теперь еженощно, в т.ч. ViralMint; verify §6 делает detect на Videos ежедневно (ничего не пишет).

### K1 `spec-check-without-ak` — гейт SDD без agentkit
- выход: `agent-ops spec-check <change> <номер>` читает и отмечает задачу в `openspec/changes/<change>/tasks.md` сам (номер = порядковый `- [ ]`), `ak` из кода удалён; событие `gate.passed/gate.failed` с REQ-id пишется, как и сейчас; код pytest 5 — отдельная ветвь «нечего запускать».
- приёмка: `tests/spec-check-verify.sh`: temp-проект с одним REQ, одним `.feature`, одной задачей — зелёный прогон ставит `[x]`, красный не ставит и пишет `gate.failed`; `command -v ak` не требуется.
- заметки: openspec CLI (`openspec status --change`) — предпочтительный источник номера, если установлен; иначе разбор `tasks.md` по порядку строк `- [ ]`/`- [x]`. Приёмка на ViralMint запрещена — только temp. **Сделано 18:55:** `ak` удалён; `spec_tasks`/`spec_task_mark` — собственный разбор тем же regex, что у openspec (`status` задач не выдаёт, `instructions apply --json` даёт — нумерация сверена, совпала); pytest 5 → `gate.uncovered` (было `gate.no-scenarios`), задача не отмечается; попутно дефект: `gate_event` писал в журнал `$PWD`, а не проекта — исправлено (`gate_dir`). `tests/spec-check-verify.sh` 23/23, bootstrap-verify 35/35. Осталось: `cmd_doctor` всё ещё упоминает `ak` в списке необязательных инструментов — снять при M1.

### K2 `req-status-projection` — SQL по требованиям
- выход: проекция `req-status`: для каждого REQ-id — последний результат гейта, дата, число провалов за 7 дней; «REQ без единого прогона» отдельной строкой.
- приёмка: `agent-q -p req-status` на temp-проекте из K1 показывает REQ с `passed`, затем `failed` после сломанного сценария.
- заметки: события есть (`gate.*`), проекции нет — вопрос «что у нас с требованиями» сейчас не задать одной командой. **Сделано 19:15:** `sql/projections/req-status.sql`, `agent-q -p req-status [проект]`: project, req (`aggregate_id`), last_result (passed/failed/uncovered), last_run (UTC), failed_7d, runs; `gate.untied`/`unnumbered` (`aggregate_id='-'`) и `orphan-tag` отсечены; сортировка failed → uncovered → passed. Граница 7 дней — `now() at time zone 'UTC'` (в `session-timeline` окно сдвинуто на +3 ч — косметика, не правлено). Приёмка на temp: пусто rc=0 → 2 passed → failed/uncovered/passed после поломки; фильтр по проекту. «REQ без прогона» из событий невозможен: REQ живёт только в `spec.md`; предложение — событие `spec.registered` из `spec-coverage`/бутстрапа + left join (не реализовано). Payload gate.* — только `reason`: change/task/число сценариев проекциям недоступны.

### K3 `prd-to-req` — требование рождается с id и сценарием
- выход: шаблон `templates/openspec/specs/project-baseline/spec.md` (формат openspec, требование `REQ-project-baseline-001`) и `templates/bdd/features/project-baseline.feature` с тегом; `ensure_openspec_spec` в full-auto копирует шаблон только в пустой `openspec/specs/`.
- приёмка: свежий full-auto проект → `spec-coverage` зелёный (1 требование, 1 тег), `pytest bdd` 3 passed; verify зелёный.
- заметки: решение пользователя 2026-09-19 17:50 — PRD-слоя нет, требования прямо в openspec (bmad/ouroboros будут удалены); нумерация `REQ-<cap>-NNN`, `cap` = каталог в `openspec/specs/`; шаблон ставится сразу при бутстрапе. `needs: [K1]` снят — гейт отметки задачи к шаблону не относится. **Сделано 18:45:** формат spec.md — из `openspec-sync-specs/SKILL.md` (openspec 1.11.0), `openspec validate --specs` зелёный; `ensure_openspec_spec` только в пустой `openspec/specs/`; feature с тегом на шагах `repo_steps.py`; pytest 3 passed, spec-coverage 1/1/0; чужой проект со своими спеками — байт в байт. Без openspec CLI спека не ставится, а CLAUDE.md всё равно ссылается на `openspec/specs/` — мелочь, отмечено.

### L1 `events-schema-version` — схема версионирована
- выход: `PRAGMA user_version` в `events.ddl.sql`; `agent-emit`/`agent-event` при расхождении применяют миграции `sql/migrations/NNN.sql` (только `ALTER ADD`/`CREATE` — append-only распространяется и на схему); `doctor` показывает версию каждой БД реестра.
- приёмка: БД версии 0 + событие → версия N, старые строки на месте, `agent-q` читает.
- заметки: без этого первое же новое поле = ручной обход всех `.agent/events.db`. **Сделано 19:20:** `PRAGMA user_version = 1` в DDL (единственный источник номера, парсится `lib/schema.sh` без fork); `sql/migrations/001.sql` (шапка-правила + штамп); `schema_ensure <db>` в `lib/schema.sh`, зовётся `agent-emit`/`agent-event` только для существующей БД: +1 вызов sqlite3 на событие, миграции — раз в жизни БД, провал → stderr, INSERT идёт. doctor: «схема vN» (✔ равна DDL, `•` отстаёт — применится при первом событии, ✘ новее DDL/не открывается); `ak` убран из списка инструментов; `doctor_db_ok` больше не пишет пробный файл — всегда снапшот в mktemp + `sqlite3 -readonly`. Тесты: schema-verify 19/19 (новый), doctor 15/15, spec-check 23/23, bootstrap 35/35. Реальные БД уже v1 (доведены штатно первым событием). Нюансы: `-wal/-shm` рядом с БД проектов оставляет `agent-q` внутри doctor (duckdb ATTACH READ_ONLY) — свойство SQLite WAL, не запись данных; `schema_ensure` без `busy_timeout` — как и INSERT'ы писателей, при «locked» повторится на следующем событии.

### L2 `wal-checkpoint` — журнал не растёт бесконечно
- выход: ночной прогон делает `PRAGMA wal_checkpoint(TRUNCATE)` по БД реестра; размер `-wal` в отчёте.
- приёмка: подложить 10 МБ событий без чекпойнта → после прогона `-wal` = 0 байт, строки на месте.
- заметки: сейчас `-wal` в Videos 0 байт только потому, что писатели закрываются; долгий `watch` в herdr это изменит. **Сделано 18:05:** секция в `agent-nightly` (после обхода реестра, до harvest), обоих режимах — чекпойнт бесплатен; `busy_timeout=5000`; без `-w` — «пропущен»; событие `nightly.wal.checkpoint {repo,before,after,result}`, поля `wal`/`wal_skipped` в `nightly.run.finished`. Приёмка: 11.9 МБ `-wal` → 0, count тот же, integrity ok; read-only → пропуск, rc=0. Нюанс теста: `wal_autocheckpoint=0` мало — CLI чекпойнтит при закрытии, нужен второй держатель соединения.

### L3 `compare-windows` — эксперимент одним запросом
- выход: проекция `compare-windows`: два интервала времени (аргументы) → по проектам: события, провалы гейтов, инструментальные ошибки, коммиты — рядом, с разницей.
- приёмка: `agent-q -p compare-windows '2026-09-18' '2026-09-19'` на Videos даёт таблицу с двумя колонками чисел и дельтой.
- заметки: «упрощает эксперименты» без этого — обещание: сравнить «до/после» сейчас можно только двумя запросами и глазами. **Сделано 18:20:** `sql/projections/compare-windows.sql`; попутно дефект `agent-q`: аргументы после `-p` не доходили до SQL вовсе — теперь `SET VARIABLE argN`, проекции читают `getvariable('argN')`. Окно = префикс времени (`2026-09-18` сутки, `2026-09-19 12` час), без аргументов вчера/сегодня; шкала UTC как у остальных проекций. Приёмка на Videos: 4 проекта, дельты, пустое окно → нули, exit 0. Открыто: `gate.failed` в данных нет (есть `gate.uncovered`) — колонка пока всегда 0; при K1/K2 решить семантику `gate.%`. **Решено 19:15 (по K2):** `cmd_spec_check`/`spec-coverage` пишут passed/failed/uncovered/untied/orphan-tag/unnumbered, всё кроме passed — rc≠0; `gates_*` теперь считает `gate.%` кроме `gate.passed` (Videos: 0 → 1). Бэкап `compare-windows.sql.*.bak-gates`.

### M1 `docs-check-links` — битые ссылки не проходят гейт
- выход: `docs-check` разбирает `[..](path)` в каждом файле дерева и падает на ссылке в несуществующий файл (относительно файла); внешние `http` пропускает.
- приёмка: опечатка в ссылке роутера/README → красный с именем файла и строкой.
- заметки: после C2 роутер держится на пяти ссылках; сейчас гейт их не видит. **Сделано 19:30:** хелпер `docs_links_of` (awk): `[..](цель)`, `![..](..)`, `[..]: цель`; срезаются `<…>`, title, `#фрагмент`, `?query`; пропуск `схема://`, `mailto:`, якорей; fenced и inline-код вырезаются до разбора; `~/` → HOME, `/` как есть, остальное от каталога файла. Итог `…, битых ссылок B`, exit 1 при B>0; префикс и старые поля не тронуты (harvest/verify/doctor совместимы). `tests/docs-check-verify.sh` 15/15; bootstrap 35/35 (один флейк «≤3 с» 3.7 с), doctor 15/15, schema 19/19, spec-check 23/23. Реальные деревья: `~/.agent-ops/docs` зелёный; Videos — одна битая: `docs/_leaf-template.md:24 → ./other-leaf.md` (старая версия шаблона, наш коммит 0e9f0cd) — заменён на платформенный шаблон с `{{RELATED}}`, бэкап в `~/.agent-ops-backups/`, зелёный. HTML-комментарии не игнорируются — в деревьях их нет.

### M2 `project-claude-md-router` — проектный CLAUDE.md по тому же принципу
- выход: `safe-auto` кладёт `CLAUDE.md` ≤30 строк только если файла нет: указатели на `docs/README.md`, где планы, как проверить (`docs-check`, `spec-coverage`); существующий файл не трогается никогда.
- приёмка: `bootstrap-verify`: новый репо → файл ≤30 строк; репо с готовым CLAUDE.md → байт в байт прежний.
- заметки: Videos-CLAUDE.md сейчас описывает скрипты, а не платформу — не заменять, это проектный файл; шаблон только для пустых. **Сделано 18:45:** `templates/CLAUDE.md` 26 строк; `ensure_claude_md` (только при отсутствии файла); общий копир `seed_templates`; `amend` склеивает пары строк отчёта (реестр+workspace, openspec+спека) — полный full-auto = 7 строк; пары должны идти подряд (комментарий в блоке). verify 35/35 ×3; один ранний прогон 34/35 — вероятно, тайминг «хук ≤3 с» на холодном node (2.3 с) — флейк, поднять порог при повторе.

### N1 `herdr-layout-idempotent` — повторный вызов не плодит workspace
- выход: `herdr-layout` ищет workspace с той же меткой и cwd; найден — фокусирует его, не создаёт второй; `--new` принуждает.
- приёмка: два вызова подряд → в `herdr workspace list` один workspace на проект.
- заметки: сегодня проверка оставила лишний workspace — закрывать руками. **Сделано 18:25:** флаги `--new`, `--dry-run`; поиск = `workspace list` (label) + `pane list` (cwd панели, у workspace cwd нет; herdr 0.8.2, protocol 20); найден → `workspace focus`. Приёмка живьём: два вызова → один «Videos», `--new` → второй, убран, фокус возвращён. Открыто: `wK Videos` (1 панель, в ней работает пользователь) — не наш трёхпанельный, не закрыт; «дособрать панели в найденном» — отдельный узел, если нужен. cwd панели живой (уезжает за `cd`) — если во всех панелях ушли из проекта, создастся новый.

### N2 `workspace-from-registry` — один источник правды для repowise
- выход: `agent-ops workspace-sync` генерирует `.repowise-workspace.yaml` из реестра (колонка `index=yes`, добавляется в `registry.tsv`); файл руками не правится, шапка «сгенерировано».
- приёмка: изменить колонку → `workspace-sync` → `repowise` видит новый набор; `git diff` файла показывает только ожидаемую строку.
- заметки: сейчас два списка проектов (реестр и yaml) расходятся молча. **Сделано 19:40:** колонка `index` (yes|no) в `registry.tsv` (5-я, парсеры `$1..$4` не задеты; строка без колонки = yes); `agent-ops workspace-sync [--dry-run] [--check]`: `registry_indexed`, `workspace_parse`/`workspace_render`; сохраняет `version`, `default_repo`, `is_primary`, alias старых записей (`video-wizard` ≠ `video_wizard`) и `last_commit_at_index`; шапка «сгенерировано … не править руками»; атомарная запись, без изменений — файл не трогается; пустой набор → exit 1. `--check` сравнивает без комментариев: `repowise workspace add` при бутстрапе снимает шапку, красный из-за неё был бы ложным. `ensure_registry` пишет 5-е поле; регэксп в `bootstrap-verify.sh` §7 подправлен. Тесты: workspace-sync 30/30 (новый), bootstrap 35/35, doctor 15/15, schema 19/19, spec-check 23/23, docs-check 15/15. Реальный yaml: diff — только шапка, 3 репо/алиасы/sha на месте, `repowise workspace list` rc=0. В doctor/ночной прогон не подключён.

### N3 `borrow-recheck-nightly` — заимствования следят за источником
- выход: ночной прогон вызывает `borrow recheck` по всем распискам активных проектов; изменившийся источник — событие `borrow.source_changed` и строка в отчёте.
- приёмка: изменить файл-источник в temp-репо → утром событие с id расписки.
- заметки: `recheck` есть, но его надо помнить — то же, что с `git ls-files`. **Сделано 18:50:** секция в `agent-nightly` после WAL; расписки читаются из `.repowise/wiki.db` (`decision_records`, тег borrowed, строка `recheck: git -C <донор> log <sha>..HEAD -- <файл>`) — строка не исполняется, разбирается regex, затем `git rev-list --count`; >0 → `borrow.source_changed {decision, repo, source, file, since, commits}` + строка отчёта; поломанные расписки — строка, счётчик `borrow_broken`. Приёмка на temp: тишина без изменений, событие после коммита в доноре, мусорный recheck не исполнен. Без дедупа «уже сообщали» — сознательно.

### O1 `harvest-apply` — принять кандидата одной командой
- выход: `agent-harvest --apply KEY [--to docs/<раздел>/<имя>.md]`: пишет лист по `_leaf-template.md` (заголовок, источник, дата, цитата), добавляет ссылку в `index.md` раздела, пишет событие `docs.harvested`; `docs-check` после — зелёный или откат.
- приёмка: кандидат из repowise на temp-проекте → `--apply` → лист существует, ссылка есть, событие есть, `docs-check` зелёный.
- заметки: сейчас «полуавтоматически» = машина предлагает, человек делает всё; должно быть — машина предлагает, человек говорит «да». **Сделано 18:35:** `agent-harvest --apply KEY [--to …]`; раздел без `--to`: `d:` → `docs/decisions/NNNN-<slug>.md` (статус «предложено»), `c:`/`g:` → `docs/operations/`, `architecture/` только явно; slug — транслит. Порядок перевёрнут сознательно: docs-check → событие `docs.harvested` + тумбстоун; красный → откат листа и index, ни события, ни тумбстоуна. Шаблон `_leaf-template.md` — машинные плейсхолдеры `{{TITLE}}…`. Приёмка на temp (фикстуры через `HARVEST_REPOWISE`/`HARVEST_AGENT_Q`): три `--apply`, повтор → «уже в тумбстоунах», docs-check 11 файлов зелёный, 3 события; откат проверен.

### O2 `harvest-from-events` — кандидаты из собственного журнала
- выход: источники `harvest` расширены: повторяющиеся `gate.failed` по одному REQ (≥3 за неделю), инструментальные ошибки одного вида (≥5), решения из `commit.created` с `subject` вида `decision:` — предлагаются как кандидаты с готовым текстом.
- приёмка: подложить 3 `gate.failed` → `agent-harvest --show` предлагает лист «REQ-X падает третий раз».
- заметки: сейчас все источники — чужие инструменты; свой журнал платформа не читает для пополнения дерева. **Сделано 19:10:** 4-й источник `ev` в `agent-harvest`: `.agent/events.db` читается напрямую (`sqlite3 -readonly -json`, снапшот при каталоге без прав), не через `agent-q` — safe-auto реестр не пишет. Пороги env: `HARVEST_EVENTS_DAYS=7`, `HARVEST_GATE_MIN=3`, `HARVEST_TOOL_MIN=5`. Ключи: `g:` по (проект, REQ) — только `gate.failed`, созревший вытесняет строку проекции `gate-failures`; `c:` по (tool, вид ошибки без чисел/путей); `d:` по subject коммита `decision:` (без окна). `--apply` для `src: events` строит лист из самих событий; `--dismiss d:` с 6 hex — свой тумбстоун. Приёмка на temp: три кандидата, порог REQ-9 (2<3) не созрел, `--apply g:/c:/d:` зелёные, brief 5 строк, снапшот-ветка без следов в `.agent`. Открыто: `gate.failed` несёт только `reason` (change/task появятся, когда `gate_event` их запишет); `commit.created` без `body`; отклонённый через старый ключ REQ всплывёт раз под новым.

---

## Порядок, если делать по одному

J3 → K1 → M1 → O1 → остальное. Первые два закрывают дыры (слепые хуки,
мёртвый гейт); утечка в коммит закрыта группой P.

## Что не входит

- Ручной шаг при первом запуске — нет: всё, включая `repowise init`, само
  (P1–P3); индексация только за index-guard'ом.
- ViralMint как полигон — нет, запрет остаётся.
- Возврат agentkit/headroom/rtk в любом виде — нет.
