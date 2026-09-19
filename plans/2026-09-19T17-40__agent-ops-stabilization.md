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

- Реестр остаётся курируемым, но получает **очередь обнаружения**:
  `agent-emit` при создании журнала дописывает проект в
  `~/.agent-ops/discovered.tsv`; отчёт бутстрапа и ночной прогон показывают
  «обнаружено, не в реестре: N — принять: …». Автоматически в `active=yes`
  никто не попадает — обход диска отвергнут, решение не пересматривается.
- Гейт SDD переводится на `openspec` напрямую (`tasks.md` — единственный
  носитель отметки), без слоя agentkit. Отвергнуто: держать `ak` как
  опциональный путь — снятый инструмент не должен оставаться в коде.
- `safe-auto` без docs (журнал + exclude) становится дефолтом SessionStart:
  оба действия бесплатны, обратимы и уже делаются post-commit'ом. docs по-
  прежнему только по явной команде — восемь файлов в чужом клоне мусор.

## Граф работ

```yaml
graph:
  # J. автоматика включения и самопроверка
  - {id: J1, needs: [],   parallel: "auto",  status: "[ ]", files: [~/.claude/hooks/session-start.sh, ~/.agent-ops/bootstrap/init-project.sh, ~/.agent-ops/tests/bootstrap-verify.sh]}
  - {id: J2, needs: [],   parallel: "auto",  status: "[ ]", files: [~/.agent-ops/bin/agent-emit, ~/.agent-ops/bin/agent-ops, ~/.agent-ops/bin/agent-nightly, ~/.agent-ops/discovered.tsv]}
  - {id: J3, needs: [],   parallel: "auto",  status: "[ ]", files: [~/.agent-ops/bin/agent-ops]}
  - {id: J4, needs: [J3], parallel: "",      status: "[ ]", files: [~/.agent-ops/bin/agent-nightly, ~/.config/systemd/user/agent-nightly.service]}
  # K. executable SDD
  - {id: K1, needs: [],   parallel: "sdd",   status: "[ ]", files: [~/.agent-ops/bin/agent-ops, ~/.agent-ops/tests/spec-check-verify.sh]}
  - {id: K2, needs: [K1], parallel: "",      status: "[ ]", files: [~/.agent-ops/sql/projections/req-status.sql]}
  - {id: K3, needs: [K1], parallel: "sdd",   status: "[!]", files: [~/.agent-ops/bootstrap/templates/openspec/**]}
  # L. событийный слой
  - {id: L1, needs: [],   parallel: "ev",    status: "[ ]", files: [~/.agent-ops/sql/events.ddl.sql, ~/.agent-ops/bin/agent-ops]}
  - {id: L2, needs: [],   parallel: "ev",    status: "[ ]", files: [~/.agent-ops/bin/agent-nightly]}
  - {id: L3, needs: [],   parallel: "ev",    status: "[ ]", files: [~/.agent-ops/sql/projections/compare-windows.sql]}
  # M. дерево документов
  - {id: M1, needs: [],   parallel: "docs",  status: "[ ]", files: [~/.agent-ops/bin/agent-ops]}
  - {id: M2, needs: [],   parallel: "docs",  status: "[ ]", files: [~/.agent-ops/bootstrap/templates/CLAUDE.md, ~/.agent-ops/bootstrap/init-project.sh]}
  # N. control center и соседи
  - {id: N1, needs: [],   parallel: "cc",    status: "[ ]", files: [~/.agent-ops/bin/agent-herdr-layout]}
  - {id: N2, needs: [J2], parallel: "",      status: "[ ]", files: [~/.agent-ops/bin/agent-ops, /mnt/82A23910A2390A65/.repowise-workspace.yaml]}
  - {id: N3, needs: [],   parallel: "cc",    status: "[ ]", files: [~/.agent-ops/bin/agent-nightly]}
  # O. полуавтоматическое пополнение
  - {id: O1, needs: [],   parallel: "",      status: "[ ]", files: [~/.agent-ops/bin/agent-harvest, ~/.agent-ops/bootstrap/templates/docs/_leaf-template.md]}
  - {id: O2, needs: [O1], parallel: "",      status: "[ ]", files: [~/.agent-ops/bin/agent-harvest]}
```

### Состояние исполнения

Статус — только в YAML. Свободны сразу: J1, J2, J3, K1, L1, L2, L3, M1, M2,
N1, N3, O1. Зоны J2/J3/K1/L1/M1/N2 пересекаются в `bin/agent-ops` —
вести последовательно или в worktree с записанным порядком влития.
K3 ждёт человека (см. узел).

---

## Узлы

### J1 `exclude-before-first-commit` — журнал не может попасть в коммит
- выход: SessionStart запускает `init-project.sh --mode safe-auto` с `BOOTSTRAP_SKIP_DOCS=1` (журнал + `.git/info/exclude`, без docs); `detect` остаётся для вызова руками.
- приёмка: в `bootstrap-verify` новый кейс — пустой репо, старт хука, `git add -A && git commit`, `git show --stat HEAD` не содержит `.agent/`. Время хука ≤50 мс (сейчас 18).
- заметки: отчёт хука должен описывать состояние ПОСЛЕ действий (дефект №6 прошлого плана — не повторять).

### J2 `discovered-queue` — новый проект виден без правки реестра
- выход: `agent-emit` при создании `.agent/events.db` дописывает `путь\tимя` в `~/.agent-ops/discovered.tsv` (если пути нет ни в реестре, ни в очереди); `agent-ops registry --discovered` печатает очередь; отчёт бутстрапа и ночной прогон показывают «обнаружено, не в реестре: N — принять: agent-ops registry accept <путь>»; `accept` переносит строку в `registry.tsv` как `safe-auto\tyes`.
- приёмка: temp-репо + одно событие → путь в `discovered.tsv`; `accept` → в `agent-q --sources`; повторное событие строку не дублирует.
- заметки: очередь — не реестр: `agent-q` её не читает. Клоны чужих репозиториев попадут в очередь — это нормально, принимает человек.

### J3 `doctor-hooks` — самопроверка подключений
- выход: `agent-ops doctor` дополнительно: каждый `command` из `~/.claude/settings.json` (`hooks.*`) существует и исполняем; `core.hooksPath` указывает на наш диспетчер; таймер `agent-nightly.timer` активен; каждая БД реестра открывается и имеет таблицу `events`; `~/.claude/CLAUDE.md` ссылается на существующие листы.
- приёмка: подложить в settings.json хук на несуществующий файл → `doctor` красный с именем файла; убрать → зелёный.
- заметки: ровно этот класс дефекта (rtk) жил незамеченным; проверка стоит секунду.

### J4 `nightly-selfcheck` — платформа проверяет себя ночью
- выход: `agent-nightly` в начале прогона зовёт `doctor` и `bootstrap-verify`; результат — событие `nightly.selfcheck` (`ok`/`fail`, список красных) в журнал Videos (первичный проект); красный selfcheck прерывает `--apply`.
- приёмка: журнал systemd за ночь содержит selfcheck; `agent-q -p gate-failures` показывает подложенный провал.
- заметки: `bootstrap-verify` вне песочницы уже зелёный (исправлен подсчёт `.git/ai`).

### K1 `spec-check-without-ak` — гейт SDD без agentkit
- выход: `agent-ops spec-check <change> <номер>` читает и отмечает задачу в `openspec/changes/<change>/tasks.md` сам (номер = порядковый `- [ ]`), `ak` из кода удалён; событие `gate.passed/gate.failed` с REQ-id пишется, как и сейчас; код pytest 5 — отдельная ветвь «нечего запускать».
- приёмка: `tests/spec-check-verify.sh`: temp-проект с одним REQ, одним `.feature`, одной задачей — зелёный прогон ставит `[x]`, красный не ставит и пишет `gate.failed`; `command -v ak` не требуется.
- заметки: openspec CLI (`openspec status --change`) — предпочтительный источник номера, если установлен; иначе разбор `tasks.md` по порядку строк `- [ ]`/`- [x]`. Приёмка на ViralMint запрещена — только temp.

### K2 `req-status-projection` — SQL по требованиям
- выход: проекция `req-status`: для каждого REQ-id — последний результат гейта, дата, число провалов за 7 дней; «REQ без единого прогона» отдельной строкой.
- приёмка: `agent-q -p req-status` на temp-проекте из K1 показывает REQ с `passed`, затем `failed` после сломанного сценария.
- заметки: события есть (`gate.*`), проекции нет — вопрос «что у нас с требованиями» сейчас не задать одной командой.

### K3 `prd-to-req` — требование рождается с id и сценарием
- исполнитель: **человек** `[!]` решает формат
- выход: шаблон `openspec/specs/<cap>/spec.md` и `.feature` в бутстрапе `full-auto`, где каждое требование из PRD (`bmad-create-prd` возвращён узлом F4) сразу получает `REQ-<id>` и пустой сценарий с тегом.
- приёмка: `spec-coverage` на свежем `full-auto` проекте зелёный с нулём требований и зелёный после добавления одного по шаблону.
- заметки: **ждёт человека** — формат PRD (bmad vs `ouroboros:pm`) и правило нумерации REQ — ваш выбор; агент шаблон без этого не напишет.

### L1 `events-schema-version` — схема версионирована
- выход: `PRAGMA user_version` в `events.ddl.sql`; `agent-emit`/`agent-event` при расхождении применяют миграции `sql/migrations/NNN.sql` (только `ALTER ADD`/`CREATE` — append-only распространяется и на схему); `doctor` показывает версию каждой БД реестра.
- приёмка: БД версии 0 + событие → версия N, старые строки на месте, `agent-q` читает.
- заметки: без этого первое же новое поле = ручной обход всех `.agent/events.db`.

### L2 `wal-checkpoint` — журнал не растёт бесконечно
- выход: ночной прогон делает `PRAGMA wal_checkpoint(TRUNCATE)` по БД реестра; размер `-wal` в отчёте.
- приёмка: подложить 10 МБ событий без чекпойнта → после прогона `-wal` = 0 байт, строки на месте.
- заметки: сейчас `-wal` в Videos 0 байт только потому, что писатели закрываются; долгий `watch` в herdr это изменит.

### L3 `compare-windows` — эксперимент одним запросом
- выход: проекция `compare-windows`: два интервала времени (аргументы) → по проектам: события, провалы гейтов, инструментальные ошибки, коммиты — рядом, с разницей.
- приёмка: `agent-q -p compare-windows '2026-09-18' '2026-09-19'` на Videos даёт таблицу с двумя колонками чисел и дельтой.
- заметки: «упрощает эксперименты» без этого — обещание: сравнить «до/после» сейчас можно только двумя запросами и глазами.

### M1 `docs-check-links` — битые ссылки не проходят гейт
- выход: `docs-check` разбирает `[..](path)` в каждом файле дерева и падает на ссылке в несуществующий файл (относительно файла); внешние `http` пропускает.
- приёмка: опечатка в ссылке роутера/README → красный с именем файла и строкой.
- заметки: после C2 роутер держится на пяти ссылках; сейчас гейт их не видит.

### M2 `project-claude-md-router` — проектный CLAUDE.md по тому же принципу
- выход: `safe-auto` кладёт `CLAUDE.md` ≤30 строк только если файла нет: указатели на `docs/README.md`, где планы, как проверить (`docs-check`, `spec-coverage`); существующий файл не трогается никогда.
- приёмка: `bootstrap-verify`: новый репо → файл ≤30 строк; репо с готовым CLAUDE.md → байт в байт прежний.
- заметки: Videos-CLAUDE.md сейчас описывает скрипты, а не платформу — не заменять, это проектный файл; шаблон только для пустых.

### N1 `herdr-layout-idempotent` — повторный вызов не плодит workspace
- выход: `herdr-layout` ищет workspace с той же меткой и cwd; найден — фокусирует его, не создаёт второй; `--new` принуждает.
- приёмка: два вызова подряд → в `herdr workspace list` один workspace на проект.
- заметки: сегодня проверка оставила лишний workspace — закрывать руками.

### N2 `workspace-from-registry` — один источник правды для repowise
- выход: `agent-ops workspace-sync` генерирует `.repowise-workspace.yaml` из реестра (колонка `index=yes`, добавляется в `registry.tsv`); файл руками не правится, шапка «сгенерировано».
- приёмка: изменить колонку → `workspace-sync` → `repowise` видит новый набор; `git diff` файла показывает только ожидаемую строку.
- заметки: сейчас два списка проектов (реестр и yaml) расходятся молча.

### N3 `borrow-recheck-nightly` — заимствования следят за источником
- выход: ночной прогон вызывает `borrow recheck` по всем распискам активных проектов; изменившийся источник — событие `borrow.source_changed` и строка в отчёте.
- приёмка: изменить файл-источник в temp-репо → утром событие с id расписки.
- заметки: `recheck` есть, но его надо помнить — то же, что с `git ls-files`.

### O1 `harvest-apply` — принять кандидата одной командой
- выход: `agent-harvest --apply KEY [--to docs/<раздел>/<имя>.md]`: пишет лист по `_leaf-template.md` (заголовок, источник, дата, цитата), добавляет ссылку в `index.md` раздела, пишет событие `docs.harvested`; `docs-check` после — зелёный или откат.
- приёмка: кандидат из repowise на temp-проекте → `--apply` → лист существует, ссылка есть, событие есть, `docs-check` зелёный.
- заметки: сейчас «полуавтоматически» = машина предлагает, человек делает всё; должно быть — машина предлагает, человек говорит «да».

### O2 `harvest-from-events` — кандидаты из собственного журнала
- выход: источники `harvest` расширены: повторяющиеся `gate.failed` по одному REQ (≥3 за неделю), инструментальные ошибки одного вида (≥5), решения из `commit.created` с `subject` вида `decision:` — предлагаются как кандидаты с готовым текстом.
- приёмка: подложить 3 `gate.failed` → `agent-harvest --show` предлагает лист «REQ-X падает третий раз».
- заметки: сейчас все источники — чужие инструменты; свой журнал платформа не читает для пополнения дерева.

---

## Порядок, если делать по одному

J1 → J3 → K1 → J2 → M1 → O1 → остальное. Первые три закрывают дыры
(утечка в коммит, слепые хуки, мёртвый гейт); дальше — автоматика.

## Что не входит

- Индексация repowise новых проектов автоматически — нет, минуты и деньги.
- ViralMint как полигон — нет, запрет остаётся.
- Возврат agentkit/headroom/rtk в любом виде — нет.
