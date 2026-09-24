"""Unit tests for federation-проксирования ролей.

Покрытие:
* FederationRolesClient: группировка по domain, кэширование, обработка
  exception/timeout, local users пропускаются.
* UserRoleHandler.batch: смесь local + remote, only remote, only local,
  empty remote, federation timeout.
* UserRolesFederationServlet.on_GET: возвращает роли только локальных
  юзеров, чужие user_ids игнорируются; пустой/слишком большой user_ids - 400.
  X-Matrix auth не тестируем здесь - он сделан BaseFederationServlet._wrap
  до того как on_GET позвали. Тесты дёргают on_GET напрямую с уже
  валидированным origin.
"""

import asyncio
import unittest
from typing import Optional

from synapse_modules.user_roles._api import UserRoleHandler
from synapse_modules.user_roles._federation import FederationRolesClient
from synapse_modules.user_roles._roles import ACCOUNT_DATA_TYPE


def _run(coro):
    return asyncio.run(coro)


# --- Fakes -------------------------------------------------------------------


class _FakeCatalog:
    def __init__(self):
        self.rows = {
            "user": {"code": "user", "label": "Пользователь", "color": None},
            "ai": {"code": "ai", "label": "ИИ", "color": "#4CAF50"},
            "developer": {
                "code": "developer",
                "label": "Разработчик",
                "color": None,
            },
        }

    async def enrich(self, code):
        return self.rows.get(code)


class _FakeAccountDataManager:
    def __init__(self):
        self._store: dict[str, dict[str, dict]] = {}

    async def get_global(self, user_id: str, type_: str):
        from immutabledict import immutabledict

        raw = self._store.get(user_id, {}).get(type_)
        return None if raw is None else immutabledict(raw)

    async def put_global(self, user_id: str, type_: str, content: dict):
        self._store.setdefault(user_id, {})[type_] = content


class _FakeBroadcaster:
    def __init__(self):
        self.role_changes: list[str] = []

    async def broadcast_role_change(self, user_id: str):
        self.role_changes.append(user_id)


class _FakeFedHttp:
    """Имитирует MatrixFederationHttpClient.get_json.

    Захватывает все вызовы (destination, path, args) и возвращает
    предзаписанный ответ или поднимает заданное исключение.
    """

    def __init__(self):
        self.calls: list[tuple[str, str, dict]] = []
        self.responses: dict[str, dict] = {}  # destination -> {roles:{...}}
        self.exceptions: dict[str, Exception] = {}

    async def get_json(self, *, destination, path, args, timeout=None):
        self.calls.append((destination, path, dict(args or {})))
        if destination in self.exceptions:
            raise self.exceptions[destination]
        return self.responses.get(destination, {"roles": {}})


class _FakeHs:
    def __init__(self, hostname: str = "our_host"):
        self.hostname = hostname
        self._fed_http = _FakeFedHttp()

    def get_federation_http_client(self):
        return self._fed_http


# --- FederationRolesClient ---------------------------------------------------


class FederationRolesClientTestCase(unittest.TestCase):
    def setUp(self):
        self.hs = _FakeHs("our_host")
        self.catalog = _FakeCatalog()
        self.client = FederationRolesClient(self.hs, self.catalog, ttl_sec=60)

    def test_groups_by_domain(self):
        self.hs._fed_http.responses["host_a"] = {
            "roles": {
                "@a1:host_a": {"code": "ai", "label": "ИИ", "color": "#4CAF50"},
                "@a2:host_a": None,
            }
        }
        self.hs._fed_http.responses["host_b"] = {
            "roles": {
                "@b1:host_b": {
                    "code": "developer",
                    "label": "Разработчик",
                    "color": None,
                },
            }
        }
        result = _run(
            self.client.fetch_roles(
                ["@a1:host_a", "@a2:host_a", "@b1:host_b"]
            )
        )
        self.assertEqual(result["@a1:host_a"]["code"], "ai")
        self.assertIsNone(result["@a2:host_a"])
        self.assertEqual(result["@b1:host_b"]["code"], "developer")
        # Two domains -> two HTTP calls.
        destinations = {c[0] for c in self.hs._fed_http.calls}
        self.assertEqual(destinations, {"host_a", "host_b"})

    def test_skips_local_users(self):
        # Local user_ids must NOT trigger federation calls.
        result = _run(
            self.client.fetch_roles(["@alice:our_host", "@bob:our_host"])
        )
        self.assertEqual(result, {})
        self.assertEqual(self.hs._fed_http.calls, [])

    def test_ignores_invalid_user_ids(self):
        # Missing ":" or non-string entries are silently dropped.
        result = _run(self.client.fetch_roles(["not_a_user_id", "", ":host"]))
        self.assertEqual(result, {})
        self.assertEqual(self.hs._fed_http.calls, [])

    def test_caches_results(self):
        self.hs._fed_http.responses["host_a"] = {
            "roles": {
                "@a1:host_a": {"code": "ai", "label": "ИИ", "color": "#4CAF50"},
            }
        }
        _run(self.client.fetch_roles(["@a1:host_a"]))
        _run(self.client.fetch_roles(["@a1:host_a"]))
        # Second call must be served from cache - still one HTTP call.
        self.assertEqual(len(self.hs._fed_http.calls), 1)

    def test_cache_partial_hit(self):
        self.hs._fed_http.responses["host_a"] = {
            "roles": {
                "@a1:host_a": {"code": "ai", "label": "ИИ", "color": "#4CAF50"},
            }
        }
        _run(self.client.fetch_roles(["@a1:host_a"]))
        # Now request both; only @a2 should be fetched fresh.
        self.hs._fed_http.responses["host_a"] = {
            "roles": {
                "@a2:host_a": {
                    "code": "developer",
                    "label": "Разработчик",
                    "color": None,
                },
            }
        }
        result = _run(
            self.client.fetch_roles(["@a1:host_a", "@a2:host_a"])
        )
        self.assertEqual(result["@a1:host_a"]["code"], "ai")
        self.assertEqual(result["@a2:host_a"]["code"], "developer")
        # Two HTTP calls total; the second one carried only @a2.
        self.assertEqual(len(self.hs._fed_http.calls), 2)
        self.assertEqual(self.hs._fed_http.calls[1][2]["user_ids"], "@a2:host_a")

    def test_exception_returns_none(self):
        self.hs._fed_http.exceptions["host_a"] = RuntimeError("boom")
        result = _run(
            self.client.fetch_roles(["@a1:host_a", "@a2:host_a"])
        )
        self.assertIsNone(result["@a1:host_a"])
        self.assertIsNone(result["@a2:host_a"])

    def test_failure_negative_cached(self):
        # If fed call fails, we cache None to avoid hammering the remote.
        self.hs._fed_http.exceptions["host_a"] = RuntimeError("timeout")
        _run(self.client.fetch_roles(["@a1:host_a"]))
        _run(self.client.fetch_roles(["@a1:host_a"]))
        self.assertEqual(len(self.hs._fed_http.calls), 1)

    def test_missing_in_response_is_none(self):
        # Remote returns roles map without the requested uid -> None.
        self.hs._fed_http.responses["host_a"] = {"roles": {}}
        result = _run(self.client.fetch_roles(["@a1:host_a"]))
        self.assertIsNone(result["@a1:host_a"])

    def test_empty_user_ids_no_calls(self):
        result = _run(self.client.fetch_roles([]))
        self.assertEqual(result, {})
        self.assertEqual(self.hs._fed_http.calls, [])

    def test_uses_correct_path(self):
        self.hs._fed_http.responses["host_a"] = {"roles": {}}
        _run(self.client.fetch_roles(["@a1:host_a"]))
        self.assertEqual(
            self.hs._fed_http.calls[0][1],
            "/_matrix/federation/v1/com.liza/user_roles_batch",
        )


# --- UserRoleHandler.batch (mixed local + remote) ----------------------------


class _FakeFederationClient:
    """Fake for FederationRolesClient with predetermined return values."""

    def __init__(self, mapping: Optional[dict] = None):
        self.mapping = mapping or {}
        self.calls: list[list[str]] = []

    async def fetch_roles(self, user_ids):
        self.calls.append(list(user_ids))
        return {uid: self.mapping.get(uid) for uid in user_ids}


class BatchWithFederationTestCase(unittest.TestCase):
    def setUp(self):
        self.catalog = _FakeCatalog()
        self.adm = _FakeAccountDataManager()
        self.adm._store["@alice:our_host"] = {
            ACCOUNT_DATA_TYPE: {"role": "ai"}
        }
        self.fed = _FakeFederationClient(
            mapping={
                "@bob:remote": {
                    "code": "developer",
                    "label": "Разработчик",
                    "color": None,
                },
                "@carol:remote": None,
            }
        )
        self.handler = UserRoleHandler(
            catalog=self.catalog,
            account_data=self.adm,
            broadcaster=_FakeBroadcaster(),
            check_user_exists=lambda uid: None,
            server_name="our_host",
            federation=self.fed,
        )

    def test_mixed_local_and_remote_v2(self):
        status, body = _run(
            self.handler.batch(
                ["@alice:our_host", "@bob:remote", "@carol:remote"], v2=True
            )
        )
        self.assertEqual(status, 200)
        self.assertEqual(body["roles"]["@alice:our_host"]["code"], "ai")
        self.assertEqual(body["roles"]["@bob:remote"]["code"], "developer")
        self.assertIsNone(body["roles"]["@carol:remote"])
        # Federation client received only remote ids.
        self.assertEqual(
            self.fed.calls, [["@bob:remote", "@carol:remote"]]
        )

    def test_only_remote_v2(self):
        status, body = _run(
            self.handler.batch(["@bob:remote", "@carol:remote"], v2=True)
        )
        self.assertEqual(body["roles"]["@bob:remote"]["label"], "Разработчик")
        self.assertIsNone(body["roles"]["@carol:remote"])

    def test_only_local_no_fed_call(self):
        _run(self.handler.batch(["@alice:our_host"], v2=True))
        self.assertEqual(self.fed.calls, [])

    def test_remote_v1_legacy_returns_default_string(self):
        # v1 не умеет объекты, поэтому remote отдаём как default string,
        # чтобы старый клиент не падал.
        status, body = _run(
            self.handler.batch(["@bob:remote"], v2=False)
        )
        self.assertEqual(body["roles"]["@bob:remote"], "user")
        # Federation call вообще не делался: v1 не идёт в fed.
        self.assertEqual(self.fed.calls, [])

    def test_federation_exception_returns_none(self):
        class _Boom:
            async def fetch_roles(self, _):
                raise RuntimeError("network down")

        handler = UserRoleHandler(
            catalog=self.catalog,
            account_data=self.adm,
            broadcaster=_FakeBroadcaster(),
            check_user_exists=lambda uid: None,
            server_name="our_host",
            federation=_Boom(),
        )
        # Should propagate exception (caller handles it / it's a server bug).
        with self.assertRaises(RuntimeError):
            _run(handler.batch(["@bob:remote"], v2=True))

    def test_no_federation_client_v2_returns_none(self):
        handler = UserRoleHandler(
            catalog=self.catalog,
            account_data=self.adm,
            broadcaster=_FakeBroadcaster(),
            check_user_exists=lambda uid: None,
            server_name="our_host",
            federation=None,
        )
        status, body = _run(
            handler.batch(["@bob:remote"], v2=True)
        )
        self.assertIsNone(body["roles"]["@bob:remote"])

    def test_legacy_handler_without_server_name(self):
        # Backwards-compat: handler без server_name считает всех локальными
        # (как до Task 9). Существующие тесты test_api_user_role.py зависят
        # от этого поведения.
        handler = UserRoleHandler(
            catalog=self.catalog,
            account_data=self.adm,
            broadcaster=_FakeBroadcaster(),
            check_user_exists=lambda uid: None,
        )
        status, body = _run(
            handler.batch(["@bob:remote"], v2=True)
        )
        # Bob трактуется как локальный -> default role enriched.
        self.assertEqual(body["roles"]["@bob:remote"]["code"], "user")


# --- UserRolesFederationServlet.on_GET ---------------------------------------


class UserRolesFederationServletTestCase(unittest.TestCase):
    """Тестируем on_GET напрямую: X-Matrix auth и ratelimit обеспечиваются
    BaseFederationServlet._wrap до того как on_GET зовётся, поэтому в
    тестах эту обвязку обходим.

    Конструируем servlet вручную минуя BaseFederationServlet.__init__
    (он требует Authenticator/FederationRateLimiter из реального HS,
    которые в тесте недоступны).
    """

    def _make_servlet(self, hostname: str = "our_host"):
        from synapse_modules.user_roles import _federation_servlet as fs

        catalog = _FakeCatalog()
        adm = _FakeAccountDataManager()
        adm._store["@alice:our_host"] = {ACCOUNT_DATA_TYPE: {"role": "ai"}}
        adm._store["@bob:our_host"] = {
            ACCOUNT_DATA_TYPE: {"role": "developer"}
        }
        fs._servlet_deps["catalog"] = catalog
        fs._servlet_deps["account_data"] = adm
        fs._servlet_deps["server_name"] = hostname

        servlet = fs.UserRolesFederationServlet.__new__(
            fs.UserRolesFederationServlet
        )
        return servlet

    def test_returns_only_local_users(self):
        servlet = self._make_servlet()
        status, body = _run(
            servlet.on_GET(
                origin="remote.example",
                content=None,
                query={
                    b"user_ids": [
                        b"@alice:our_host,@bob:our_host,@stranger:remote"
                    ]
                },
            )
        )
        self.assertEqual(status, 200)
        roles = body["roles"]
        self.assertIn("@alice:our_host", roles)
        self.assertIn("@bob:our_host", roles)
        # Remote user_ids дропаются - анти-loop защита.
        self.assertNotIn("@stranger:remote", roles)
        self.assertEqual(roles["@alice:our_host"]["code"], "ai")

    def test_extra_roles_only_where_stored(self):
        """Бот liza_news на своём HS получает роль владельца через этот servlet.
        AC:RL-developer-gates-strict/13"""
        from synapse_modules.user_roles import _federation_servlet as fs

        servlet = self._make_servlet()
        fs._servlet_deps["account_data"]._store["@owner:our_host"] = {
            ACCOUNT_DATA_TYPE: {
                "role": "ai",
                "extra_roles": ("developer",),
            }
        }
        status, body = _run(
            servlet.on_GET(
                origin="remote.example",
                content=None,
                query={b"user_ids": [b"@owner:our_host,@bob:our_host"]},
            )
        )
        self.assertEqual(status, 200)
        self.assertEqual(
            body["roles"]["@owner:our_host"],
            {
                "code": "ai",
                "label": "ИИ",
                "color": "#4CAF50",
                "extra_roles": ["developer"],
            },
        )
        # Без доп. ролей — ответ ровно прежний, без ключа.
        self.assertEqual(
            body["roles"]["@bob:our_host"],
            {"code": "developer", "label": "Разработчик", "color": None},
        )

    def test_missing_user_ids_returns_400(self):
        servlet = self._make_servlet()
        status, body = _run(
            servlet.on_GET(origin="remote.example", content=None, query={})
        )
        self.assertEqual(status, 400)
        self.assertEqual(body["errcode"], "M_MISSING_PARAM")

    def test_too_many_user_ids_returns_400(self):
        servlet = self._make_servlet()
        too_many = ",".join(f"@u{i}:our_host" for i in range(101))
        status, body = _run(
            servlet.on_GET(
                origin="remote.example",
                content=None,
                query={b"user_ids": [too_many.encode()]},
            )
        )
        self.assertEqual(status, 400)
        self.assertEqual(body["errcode"], "M_INVALID_PARAM")

    def test_unknown_local_user_returns_default(self):
        servlet = self._make_servlet()
        status, body = _run(
            servlet.on_GET(
                origin="remote.example",
                content=None,
                query={b"user_ids": [b"@unknown:our_host"]},
            )
        )
        self.assertEqual(status, 200)
        # default role "user" из каталога.
        self.assertEqual(
            body["roles"]["@unknown:our_host"]["code"], "user"
        )


class BareRoleAiFederationTestCase(unittest.TestCase):
    """ledger:RL-user-role-federation-ai-foreign

    Инвариант фикса «кнопки Liza News на Windows/Android»
    (docs/superpowers/specs/2026-09-02-liza-news-buttons-server-role-ai-design.md):
    роль бота `@liza-news` проставлена ОДНИМ own-token account_data-write
    `{"role":"ai"}` БЕЗ поля `role_v2` (стандартный C-S account_data endpoint не
    пишет role_v2). Читатель-редактор на ДРУГОМ инстансе резолвит роль по
    федерации через этот servlet. Servlet ОБЯЗАН обогатить bare-роль из каталога
    и вернуть `code=="ai"` — иначе клиент-редактор (даже непересобранный, Windows
    3720) не увидит кнопки карточки. Red-proof — AC-2: без account_data роль
    деградирует в `user` (fail-safe: чужой бот не получает `ai` по умолчанию).
    """

    def _servlet_with(self, store):
        from synapse_modules.user_roles import _federation_servlet as fs

        catalog = _FakeCatalog()
        adm = _FakeAccountDataManager()
        for uid, content in store.items():
            adm._store[uid] = {ACCOUNT_DATA_TYPE: content}
        fs._servlet_deps["catalog"] = catalog
        fs._servlet_deps["account_data"] = adm
        fs._servlet_deps["server_name"] = "bots.liza.ru"
        return fs.UserRolesFederationServlet.__new__(
            fs.UserRolesFederationServlet
        )

    def test_bare_role_ai_without_role_v2_enriches_to_ai(self):
        # AC:RL-user-role-federation-ai-foreign/1 — own-token bare-write путь.
        servlet = self._servlet_with(
            {"@liza-news:bots.liza.ru": {"role": "ai"}}
        )
        status, body = _run(
            servlet.on_GET(
                origin="synapse.liza.laba.prodamus.tech",
                content=None,
                query={b"user_ids": [b"@liza-news:bots.liza.ru"]},
            )
        )
        self.assertEqual(status, 200)
        view = body["roles"]["@liza-news:bots.liza.ru"]
        self.assertIsNotNone(view)
        self.assertEqual(view["code"], "ai")
        self.assertEqual(view["label"], "ИИ")

    def test_no_account_data_falls_back_to_user_not_ai(self):
        # AC:RL-user-role-federation-ai-foreign/2 — red-proof / fail-safe.
        servlet = self._servlet_with({})
        status, body = _run(
            servlet.on_GET(
                origin="synapse.liza.laba.prodamus.tech",
                content=None,
                query={b"user_ids": [b"@liza-news:bots.liza.ru"]},
            )
        )
        self.assertEqual(status, 200)
        self.assertEqual(
            body["roles"]["@liza-news:bots.liza.ru"]["code"], "user"
        )


if __name__ == "__main__":
    unittest.main()
