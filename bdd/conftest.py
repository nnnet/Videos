"""Общие фикстуры слоя сценариев проекта videos.

Развёрнуто бутстрапом agent-ops (2026-09-19). Каталог bdd/ — свой, вне
апстримового tests/: там conftest.py правит апстрим, и наш код дал бы
конфликт при слиянии.
"""
from pathlib import Path

import pytest

# bdd/conftest.py → на уровень вверх корень репозитория.
REPO_ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture
def repo() -> Path:
    """Корень репозитория — точка отсчёта для всех путей в сценариях."""
    return REPO_ROOT


@pytest.fixture
def context() -> dict:
    """Ящик для передачи состояния между шагами одного сценария.

    pytest-bdd не даёт шагам общего объекта, а возвращаемое значение шага
    видно только через ``target_fixture``. Явный словарь дешевле и не
    прячет поток данных.
    """
    return {}
