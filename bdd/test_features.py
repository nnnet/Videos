"""Привязка .feature к шагам.

Файл существует только ради ``scenarios()``: pytest собирает тесты из
``test_*.py``, а сам Gherkin лежит в ``features/``. Новый .feature подхва-
тывается без правок здесь — ``scenarios`` обходит каталог целиком.
"""
from pathlib import Path

from pytest_bdd import scenarios

from steps.repo_steps import *  # noqa: F401,F403 — шаги регистрируются импортом
from steps.sql_steps import *  # noqa: F401,F403

# Абсолютный путь: относительный складывается с bdd_features_base_dir из
# pytest.ini и превращается в features/features.
scenarios(str(Path(__file__).parent / "features"))
