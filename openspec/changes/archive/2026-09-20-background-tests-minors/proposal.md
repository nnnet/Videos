# background-tests-minors — остаток minor'ов ревью hardening

## Why

Ревью `plans/reports/ak:code-reviewer-260920-1641-background-tests-hardening.md`
(коммит `29856b5`) оставило два minor без сценариев/фикса:
- провал финальной записи вердикта оставляет `RUNNING` навсегда — гейт на нём
  молчит, необработанный провал теряется;
- четыре утверждения прозы REQ-001 без WHEN/THEN: нет `jq`; ошибка записи
  вердикта; «BUSY не трогая вердикт»; относительный `TEST_STATE_DIR` от корня.

## What changes

- `scripts/test-bg.sh`: при провале финальной записи — попытка вернуть вердикт
  в `FAIL rc=2` тем же `write_verdict`; если и это не удалось — `TESTS REFUSED`,
  rc=2 (файл `RUNNING` остаётся, но об этом сказано в stdout).
- Сценарии-регрессии: `jq` недоступен (`PATH` без jq) → `REFUSED` rc=2, вердикт
  нетронут; каталог `<state>` только для чтения → `REFUSED` rc=2, вердикт
  нетронут (`chmod`, пропускать под root); BUSY не меняет байты вердикта
  (`cmp`); обёртка и гейт из подкаталога с относительным `TEST_STATE_DIR`
  видят один файл.

## Non-goals

`stop_hook_active`, `additionalContext`, автозапуск — как раньше.
