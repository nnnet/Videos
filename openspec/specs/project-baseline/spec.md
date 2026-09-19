# project-baseline Specification

## Purpose
Площадка проекта videos: каталоги и журнал, без которых агент не может
работать по требованиям. Развёрнуто бутстрапом 2026-09-19.

Эта capability — образец нумерации. Id требования: `REQ-<capability>-NNN`,
capability = имя каталога в `openspec/specs/`, NNN — сквозной номер внутри
неё. Id живёт в заголовке `### Requirement:`; сценарий в `bdd/features/`
помечается тем же id как тегом. Гейт `agent-ops spec-coverage .` сводит
одно с другим и падает на разнице в любую сторону — требование без
сценария и тег без требования одинаково красные.

## Requirements

### Requirement: REQ-project-baseline-001 Требования живут рядом со сценариями
Репозиторий SHALL хранить требования в `openspec/specs/<capability>/spec.md`
и исполняемые сценарии в `bdd/features/`, так что у каждого требования есть
сценарий с его id.

#### Scenario: Требование пронумеровано и имеет сценарий
- **WHEN** агент открывает репозиторий
- **THEN** файл `openspec/specs/project-baseline/spec.md` существует
- **AND** каталог `bdd/features` существует
