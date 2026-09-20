"""Шаги общего назначения: файлы репозитория и команды.

Импортируются тестовым модулем (``from steps.repo_steps import *``) —
pytest-bdd собирает шаги из пространства имён тестового модуля.
"""
import subprocess

from pytest_bdd import given, parsers, then, when


@given("репозиторий проекта", target_fixture="repo_root")
def _repo_root(repo):
    return repo


# Голая строка в декораторе сравнивается буквально — плейсхолдер требует
# явного parsers.parse, иначе шаг просто не находится.
@then(parsers.parse('каталог "{rel}" существует'))
def _dir_exists(repo_root, rel):
    path = repo_root / rel
    assert path.is_dir(), f"нет каталога {path}"


@then(parsers.parse('файл "{rel}" существует'))
def _file_exists(repo_root, rel):
    path = repo_root / rel
    assert path.is_file(), f"нет файла {path}"


@when(parsers.parse('я выполняю команду "{cmd}"'))
def _run_cmd(repo_root, context, cmd):
    context["proc"] = subprocess.run(
        cmd, shell=True, cwd=repo_root, capture_output=True, text=True, timeout=120
    )


@then("команда завершается успешно")
def _cmd_ok(context):
    proc = context["proc"]
    assert proc.returncode == 0, (
        f"код {proc.returncode}: {proc.stderr.strip()[:300]}"
    )


@then(parsers.parse('вывод содержит "{text}"'))
def _out_contains(context, text):
    out = context["proc"].stdout
    assert text in out, f"в выводе нет «{text}»: {out[:300]}"


@then("команда завершается с ошибкой")
def _cmd_fails(context):
    proc = context["proc"]
    assert proc.returncode != 0, f"команда неожиданно завершилась успешно: {proc.stdout[:300]}"


@then(parsers.parse('файл "{rel}" содержит "{text}"'))
def _file_contains(repo_root, rel, text):
    path = repo_root / rel
    assert path.is_file(), f"нет файла {path}"
    body = path.read_text()
    assert text in body, f"в {rel} нет «{text}»"
