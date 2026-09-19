"""Шаги с SQL: утверждение о событиях проверяется запросом, а не рассказом.

Два источника, одни и те же шаги над обоими:

* ``событийный слой проекта`` — живой лог всех активных проектов; запрос
  идёт через ``agent-q``, который собирает ATTACH-преамбулу из реестра.
  Дублировать эту сборку здесь нельзя: разъедется на первом же новом
  проекте.
* ``событийный слой из файла "<path>"`` — конкретный sqlite-файл. Нужен
  ровно затем, чтобы можно было подсунуть заведомо испорченные данные и
  убедиться, что сценарий краснеет. Сценарий, который не умеет падать,
  ничего не доказывает.

Модуль ``duckdb`` в venv не нужен: оба пути ходят через CLI.
"""
import json
import os
import shutil
import subprocess

from pytest_bdd import given, parsers, then, when

AGENT_Q = os.path.expanduser("~/.agent-ops/bin/agent-q")
DUCKDB = shutil.which("duckdb") or os.path.expanduser("~/.local/bin/duckdb")

# Та же нормализация времени, что в agent-q: в ouroboros метки вида
# "2026-09-19 01:02:03.456", у нас ISO с "T"/"Z". Как строки они
# несравнимы, и любая хронология молча перемешала бы источники.
_TS = (
    "try_cast(replace(replace(timestamp,'T',' '),'Z','') AS TIMESTAMP) AS ts"
)


def _run(argv, stdin=None):
    proc = subprocess.run(
        argv, input=stdin, capture_output=True, text=True, timeout=120
    )
    assert proc.returncode == 0, (
        f"{argv[0]} вернул {proc.returncode}: {proc.stderr.strip()[:400]}"
    )
    out = proc.stdout.strip()
    return json.loads(out) if out else []


@given("событийный слой проекта", target_fixture="sql_source")
def _source_live():
    return {"kind": "agent-q"}


@given(
    parsers.parse('событийный слой из файла "{path}"'),
    target_fixture="sql_source",
)
def _source_file(repo, path):
    db = (repo / path) if not os.path.isabs(path) else path
    assert os.path.exists(db), f"нет файла событий: {db}"
    return {"kind": "file", "path": str(db)}


@when(parsers.parse('я выполняю запрос "{sql}"'))
def _run_query(sql_source, context, sql):
    if sql_source["kind"] == "agent-q":
        context["rows"] = _run([AGENT_Q, "--json", sql])
    else:
        script = (
            f"ATTACH '{sql_source['path']}' AS src (TYPE SQLITE, READ_ONLY);\n"
            f"CREATE VIEW all_events AS select *, {_TS} from src.events;\n"
            f"{sql.rstrip(';')};\n"
        )
        context["rows"] = _run(
            [DUCKDB, "-json", "-init", "/dev/null", ":memory:"], stdin=script
        )


@then("ответ не пуст")
def _not_empty(context):
    assert context["rows"], "запрос вернул ноль строк"


@then(parsers.parse("строк в ответе: {n:d}"))
def _row_count(context, n):
    got = len(context["rows"])
    assert got == n, f"строк {got}, ожидалось {n}"


@then(parsers.parse('значение "{col}" равно {value:d}'))
def _value_eq(context, col, value):
    rows = context["rows"]
    assert rows, "запрос вернул ноль строк — сравнивать нечего"
    got = rows[0][col]
    assert got == value, f"{col} = {got}, ожидалось {value}"


@then(parsers.parse('значение "{col}" больше {value:d}'))
def _value_gt(context, col, value):
    rows = context["rows"]
    assert rows, "запрос вернул ноль строк — сравнивать нечего"
    got = rows[0][col]
    assert got > value, f"{col} = {got}, ожидалось больше {value}"
