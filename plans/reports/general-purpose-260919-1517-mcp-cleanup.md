# H1 `mcp-cleanup` — отчёт

Дата: 2026-09-19. Узел H1 плана
`plans/2026-09-19T00-10__claude-global-env-foundation.md`.

## Итог

Выполнено. В `~/.claude.json` → верхнеуровневый `mcpServers` было 9
серверов, стало **7**: удалены `playwright` и `browser-mcp`, оставлен
`agent-browser`. Конфиги удалённых сохранены и проверены на обратимость.

## 1. Проверка agent-browser (до удаления)

`agent_browser_doctor` — `success: true`, **10 pass / 0 fail / 0 warn**.
CLI 0.37.1, Chrome for Testing 153.0.8010.36, ffmpeg есть, CDN доступен.

Doctor сам по себе не доказывает работоспособность, поэтому — живой прогон:

| Шаг | Результат |
|---|---|
| `agent_browser_open https://example.com` | `browserLaunched: true`, `engine: chrome`, `title: "Example Domain"` |
| `agent_browser_get_text h1` | `"Example Domain"` — DOM реально прочитан |
| `agent_browser_close` | `closed: true` |

Реальный запуск Chrome, навигация, чтение со страницы. Сервер рабочий.

## 2. Бэкап

- Полный: `~/.agent-ops-backups/claude.json.20260919-152326.bak`
  — 326354 байт, распарсился как валидный JSON, права `600`.
- Поштучно: `~/.agent-ops-backups/mcp/playwright.json`,
  `~/.agent-ops-backups/mcp/browser-mcp.json`, права `600`.
- README с командами: `~/.agent-ops-backups/mcp/README.md`.

У обоих сохранённых конфигов `env` **пустой** — секретов в них нет.

## 3. Правка

Программно через `python3 json`, атомарная запись (`tempfile` +
`os.replace` в том же каталоге), отступ 2 пробела — как было, режим
файла `600` сохранён.

```
BEFORE top-level keys: 46      AFTER top-level keys: 46
BEFORE mcpServers: 9           AFTER mcpServers: 7
BEFORE projects: 14            AFTER projects: 14
top-level keys identical: True
projects list identical: True
per-project mcpServers identical: True   (2 проекта со своими mcpServers не тронуты)
removed exactly: ['browser-mcp', 'playwright']
added (must be empty): []
agent-browser present: True
```

## 4. Проверка восстановления

Команда прогнана **на одноразовой копии** (`HOME` подменён на temp),
живой конфиг не затронут:

```
Added stdio MCP server playwright to user config
Added stdio MCP server browser-mcp to user config
после: [agent-browser, browser-mcp, context7, headroom, keenable,
        playwright, process_triage, repowise, serena]
playwright identical: True
browser-mcp identical: True
живой конфиг после теста: 7 серверов — не изменился
```

Восстановление одной командой:

```bash
claude mcp add-json playwright "$(cat ~/.agent-ops-backups/mcp/playwright.json)" -s user
claude mcp add-json browser-mcp "$(cat ~/.agent-ops-backups/mcp/browser-mcp.json)" -s user
```

## Расхождение с формулировкой приёмки

В задании было «после правки в mcpServers осталось **шесть** серверов».
Фактически осталось **семь**: серверов было девять, удалено два, 9−2=7.
Шесть — арифметическая описка в постановке. Третий сервер удалять не
стал: это вышло бы за рамки решения пользователя (он назвал ровно
`playwright` и `browser-mcp` как дубли `agent-browser`).

## Что осталось нерешённым

- **`~/.claude.json` пишется живой сессией Claude Code.** Моя правка
  сделана атомарно, но если параллельно работающий процесс держал
  прочитанный снимок конфига и перезапишет его целиком, удалённые ключи
  могут вернуться. Проверить `mcpServers` после перезапуска сессии.
- Приёмка «сессия стартует без ошибок» проверяема только человеком при
  следующем запуске Claude Code — изнутри текущей сессии не проверить.
- `browser-mcp` — единственный из трёх, кто умеет живой Chrome
  пользователя с его логинами. `agent-browser` эту нишу не закрывает
  (поднимает отдельный Chrome for Testing, `2 Chrome profile(s)` в
  doctor — это профили, а не сессия пользователя). Зафиксировано в
  README; если всплывёт задача на залогиненный профиль — восстанавливать
  именно его.
- Файл плана и git-коммит не трогал — по заданию это на оркестраторе.
