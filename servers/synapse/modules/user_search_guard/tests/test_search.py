"""Pure-logic тесты предикатов user_search_guard (без HomeServer)."""

import importlib.util
from pathlib import Path

# Грузим _search.py напрямую по пути, без триггера пакетного __init__
# (тот импортирует synapse.module_api, недоступный без живого HS).
_search_path = Path(__file__).resolve().parent.parent / "_search.py"
_spec = importlib.util.spec_from_file_location("usg_search", _search_path)
search = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(search)


class TestMatchesPrefix:
    def test_совпадение_с_начала_имени(self):
        assert search.matches_prefix("Иван Петров", "@ivan:s", "Ив") is True

    def test_совпадение_со_второго_слова(self):
        """Ищем по фамилии, не только по первому слову."""
        assert search.matches_prefix("Иван Петров", "@ivan:s", "Пет") is True

    def test_совпадение_по_localpart(self):
        assert search.matches_prefix(None, "@petrov:s", "petr") is True

    def test_регистр_игнорируется(self):
        assert search.matches_prefix("ИВАН", "@i:s", "ив") is True

    def test_середина_слова_не_совпадает(self):
        """Префиксный поиск: 'ван' не должно находить 'Иван'."""
        assert search.matches_prefix("Иван", "@i:s", "ван") is False

    def test_пустой_запрос_не_совпадает(self):
        assert search.matches_prefix("Иван", "@i:s", "") is False


class TestBelongsToDomain:
    def test_свой_домен(self):
        assert search.belongs_to_domain("@u:nadezhda.liza.ru", "nadezhda.liza.ru") is True

    def test_чужой_домен_отбрасывается(self):
        """Анти-spoofing: сосед не может выдать себя за пользователя другого домена."""
        assert search.belongs_to_domain("@u:prod.example", "nadezhda.liza.ru") is False

    def test_подстрока_домена_не_проходит(self):
        assert search.belongs_to_domain("@u:evil-nadezhda.liza.ru", "nadezhda.liza.ru") is False

    def test_мусор_не_проходит(self):
        assert search.belongs_to_domain("не-mxid", "nadezhda.liza.ru") is False


class TestDeduplicateUsers:
    def test_дубли_по_user_id_схлопываются(self):
        users = [
            {"user_id": "@a:s", "display_name": "A"},
            {"user_id": "@b:s", "display_name": "B"},
            {"user_id": "@a:s", "display_name": "A дубль"},
        ]
        result = search.deduplicate_users(users)
        assert [u["user_id"] for u in result] == ["@a:s", "@b:s"]

    def test_первый_выигрывает(self):
        users = [
            {"user_id": "@a:s", "display_name": "Первый"},
            {"user_id": "@a:s", "display_name": "Второй"},
        ]
        assert search.deduplicate_users(users)[0]["display_name"] == "Первый"

    def test_запись_без_user_id_отбрасывается(self):
        assert search.deduplicate_users([{"display_name": "нет id"}]) == []


class TestIsOwnDomain:
    def test_свой(self):
        assert search.is_own_domain("@u:my.server", "my.server") is True

    def test_чужой(self):
        assert search.is_own_domain("@u:other.server", "my.server") is False
