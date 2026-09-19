# G3 `nightly-catchup` — отчёт исполнителя

Дата: 2026-09-19. Узел плана `2026-09-19T00-10__claude-global-env-foundation.md` → G3.

## Что создано

| Файл | Роль |
|---|---|
| `~/.agent-ops/bin/agent-nightly` | догоняющий прогон; по умолчанию — отчёт без трат |
| `~/.config/systemd/user/agent-nightly.service` | как запускать (режим отчёта зашит в ExecStart) |
| `~/.config/systemd/user/agent-nightly.timer` | когда запускать: 03:30, `Persistent=true`, разброс 15 мин |
| `~/.agent-ops/log/nightly-YYYYMMDD.log` | полный лог; `log/.gitignore` кладётся самим скриптом |

План плана трогал не я: файл плана и коммиты — за оркестратором.

## Расписание: systemd user timer (не CronCreate)

1. `Persistent=true` догоняет пропущенный запуск. Машина — ноутбук, ночью выключена или спит; cron-подобное расписание без догона означает, что «ночной» прогон не случится неделями.
2. `Linger=yes` у пользователя уже включён, `systemd --user` живой (рядом `headroom-default.service`) — новой инфраструктуры не заводится.
3. Расписание живёт в ОС и переживает перезапуск/обновление Claude Code. `CronCreate` привязывает ночную работу к харнессу агента — ночью его может не быть.
4. Юнит — обычный текстовый файл: видно и человеку, и в git, включение трат = одна правка строки.

Режим трат в расписание НЕ попал: `ExecStart=%h/.agent-ops/bin/agent-nightly` без `--apply`. Чтобы разрешить ночной догон — дописать ` --apply` и `systemctl --user daemon-reload`.

## Как защищено от трат

- **Умолчание — отчёт.** `--apply` только вручную; в юните его нет.
- **Только workspace.** Дорогие операции идут исключительно по `.repowise-workspace.yaml` (videos, viralmint, video-wizard). Реестр читается только чтобы показать, чего в workspace нет.
- **`repowise init` никогда не запускается сам.** Для непроиндексированных печатается готовая команда — решает человек.
- **`agent-ops index-guard` перед любой индексацией.** Красный — репозиторий пропускается целиком, событие `nightly.repo.skipped`.
- **Смета вместо траты.** `repowise update --dry-run` (граф влияния, без модели) + `docs_mode` из `.repowise/state.json` (`deterministic` → догон без LLM) + фактические траты из `repowise costs --all`.
- **`agent-harvest`** вызывается в обоих режимах: он только читает готовое, в модель не ходит.

## Не висит

`timeout -k` на каждом внешнем вызове (быстрые 60 с, `repowise update` 900 с), общий бюджет `NIGHTLY_MAX_SECONDS=3600` — каждый вызов урезается остатком бюджета; `flock -n` против наложения прогонов; `TimeoutStartSec=90min` в юните сверху. Выход всегда 0.

## Приёмка (реальные прогоны)

Отчёт по умолчанию, 5 с, ноль трат:

```
репозиторий коммит файлов решен цена что дальше
videos               5       1      0 без LLM предлагается update (догон нужен)
viralmint            9      16      0 LLM      предлагается update (догон нужен)
video-wizard         2       6      0 без LLM предлагается update (догон нужен)

в реестре, но не в workspace — init НЕ запускается автоматически,
это полная индексация с нуля; команду выполняет человек:
  agentkit       index-guard: зелёный
      cd /mnt/.../agentkit && repowise init --yes
  project2task   index-guard: зелёный
      cd /mnt/.../Project2Task && repowise init --yes

потрачено на LLM в этом workspace за всё время: $0.2051
сбор решений: пусто | SQL-плоскость: отвечает | прогон: 5 с
```

index-guard на синтетическом «складе данных» (5 файлов под git, 60 вне git и без игнора):

```
datadump             1       ?      ? —      index-guard КРАСНЫЙ — репозиторий пропущен
```
событие: `nightly.repo.skipped {"repo":"datadump","reason":"index-guard-red"}`.

Без repowise и duckdb (`env -i HOME=<tmp> PATH=/usr/bin:/bin`): `SQL-плоскость: недоступна (нет duckdb)`, `EXIT=0`.

Лок: второй прогон печатает «предыдущий прогон ещё идёт — отступаю», `exit 0`.

События в SQL-плоскости:

```
agent-q "select event_type, count(*) n, max(timestamp) as last_ts from all_events where aggregate_type='nightly' group by 1"
nightly.repo.checked   24 | nightly.repo.unindexed 20
nightly.run.started    10 | nightly.run.finished   10
```

Таймер: `NEXT Sun 2026-09-20 03:41:46 MSK, agent-nightly.timer → agent-nightly.service`; тестовый `systemctl --user start` отработал `status=0/SUCCESS`, отчёт лёг в journal.

## Осталось нерешённым

1. **Приёмка узла G3 формально не закрыта.** В плане: «за один ночной прогон непроиндексированный проект из registry получает вики и попадает в workspace». Автоматически это запрещено пользователем (состав workspace — три репозитория). Прогон доводит до одной команды и останавливается. Либо переформулировать приёмку, либо получить явное разрешение на `init` по белому списку.
2. **В юните нет `Environment=` для ключей провайдера.** В режиме отчёта не нужно; при включении `--apply` проверить, что repowise находит креды в окружении systemd (не из интерактивного профиля).
3. **`agent-q` при ATTACH печатает `Invalid Error: ... unable to open database file`** (существовало до меня, запрос при этом отрабатывает). Не мой узел, но `agent-ops doctor` из-за этого считает плоскость нерабочей.
4. **В журнале `videos` есть одно синтетическое событие** `nightly.repo.updated` (12:49:20Z) — от прогона `--apply` с подставным `repowise` для проверки ветки. Реального update не было, денег не потрачено; если событие мешает статистике — удалить из `Videos/.agent/events.db`.
5. `--apply` на живом repowise ни разу не выполнялся — по запрету на траты. Ветка проверена стабом.
