"""Unit tests for catalog HTTP handler logic, bypassing Twisted Resource layer."""

import asyncio
import unittest

from synapse_modules.user_roles._api import CatalogHandler


def _run(coro):
    return asyncio.run(coro)


class _FakeCatalog:
    def __init__(self) -> None:
        # Pre-seeded with one role
        self.rows: dict[str, dict] = {
            "ai": {"code": "ai", "label": "ИИ", "color": "#4CAF50"},
        }
        # Track operations for assertions
        self.added: list[tuple[str, str, str | None]] = []
        self.patched: list[tuple[str, dict]] = []
        self.deleted: list[str] = []
        self._reload_called: bool = False
        # Hook used by reload tests: when set, _reload_cache transitions
        # ``rows`` to this dict, simulating a fresh DB load.
        self._reload_target: dict | None = None

    @staticmethod
    def is_valid_code(code) -> bool:
        return isinstance(code, str) and code.islower() and 1 <= len(code) <= 64

    @staticmethod
    def is_valid_color(color) -> bool:
        if color is None:
            return True
        return isinstance(color, str) and len(color) == 7 and color.startswith("#")

    async def enrich(self, code):
        return self.rows.get(code)

    async def add(self, code, display_name, color):
        if code in self.rows:
            raise Exception("UNIQUE constraint failed")
        self.rows[code] = {"code": code, "label": display_name, "color": color}
        self.added.append((code, display_name, color))

    async def patch(self, code, *, display_name=None, color=None, clear_color=False):
        if code not in self.rows:
            return False
        if display_name is not None:
            self.rows[code]["label"] = display_name
        if clear_color:
            self.rows[code]["color"] = None
        elif color is not None:
            self.rows[code]["color"] = color
        self.patched.append(
            (
                code,
                {
                    "display_name": display_name,
                    "color": color,
                    "clear_color": clear_color,
                },
            )
        )
        return True

    async def delete(self, code):
        if code not in self.rows:
            return False
        self.rows.pop(code)
        self.deleted.append(code)
        return True

    async def users_with_role(self, code):
        return []  # default: no users

    def snapshot(self) -> dict[str, dict]:
        return {code: dict(row) for code, row in self.rows.items()}

    async def reload(self) -> None:
        self._reload_called = True
        if self._reload_target is not None:
            self.rows = {
                code: dict(row) for code, row in self._reload_target.items()
            }


class _FakeBroadcaster:
    def __init__(self) -> None:
        self.patches: list[str] = []

    async def broadcast_catalog_patch(self, code: str) -> None:
        self.patches.append(code)


class CatalogPostTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.catalog = _FakeCatalog()
        self.broadcaster = _FakeBroadcaster()
        self.handler = CatalogHandler(self.catalog, self.broadcaster)

    def test_post_creates_role(self) -> None:
        status, body = _run(
            self.handler.create(
                {
                    "code": "cyber_agronom",
                    "display_name": "Кибер-Агроном",
                    "color": "#7CB342",
                }
            )
        )
        self.assertEqual(status, 201)
        self.assertEqual(
            body,
            {"code": "cyber_agronom", "label": "Кибер-Агроном", "color": "#7CB342"},
        )
        self.assertIn(
            ("cyber_agronom", "Кибер-Агроном", "#7CB342"), self.catalog.added
        )
        # Created role does not trigger broadcast
        self.assertEqual(self.broadcaster.patches, [])

    def test_post_creates_role_without_color(self) -> None:
        status, body = _run(
            self.handler.create(
                {
                    "code": "minimal",
                    "display_name": "Минимальный",
                }
            )
        )
        self.assertEqual(status, 201)
        self.assertIsNone(body["color"])

    def test_post_rejects_invalid_code(self) -> None:
        status, body = _run(
            self.handler.create(
                {
                    "code": "BadCode",
                    "display_name": "X",
                }
            )
        )
        self.assertEqual(status, 400)
        self.assertEqual(body["error"], "bad_request")

    def test_post_rejects_invalid_color(self) -> None:
        status, body = _run(
            self.handler.create(
                {
                    "code": "x",
                    "display_name": "X",
                    "color": "not-hex",
                }
            )
        )
        self.assertEqual(status, 400)

    def test_post_rejects_missing_display_name(self) -> None:
        status, body = _run(self.handler.create({"code": "x"}))
        self.assertEqual(status, 400)

    def test_post_rejects_empty_display_name(self) -> None:
        status, body = _run(
            self.handler.create({"code": "x", "display_name": "   "})
        )
        self.assertEqual(status, 400)

    def test_post_409_on_duplicate(self) -> None:
        # "ai" already exists
        status, body = _run(
            self.handler.create(
                {
                    "code": "ai",
                    "display_name": "Дубль",
                }
            )
        )
        self.assertEqual(status, 409)
        self.assertEqual(body["error"], "conflict")


class CatalogPatchTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.catalog = _FakeCatalog()
        self.broadcaster = _FakeBroadcaster()
        self.handler = CatalogHandler(self.catalog, self.broadcaster)

    def test_patch_display_name(self) -> None:
        status, body = _run(
            self.handler.update("ai", {"display_name": "Искусственный Интеллект"})
        )
        self.assertEqual(status, 200)
        self.assertEqual(body["label"], "Искусственный Интеллект")
        # Patch triggers broadcast
        self.assertEqual(self.broadcaster.patches, ["ai"])

    def test_patch_color(self) -> None:
        status, body = _run(self.handler.update("ai", {"color": "#000000"}))
        self.assertEqual(status, 200)
        self.assertEqual(body["color"], "#000000")

    def test_patch_clear_color(self) -> None:
        status, body = _run(self.handler.update("ai", {"color": None}))
        self.assertEqual(status, 200)
        self.assertIsNone(body["color"])

    def test_patch_unknown_returns_404(self) -> None:
        status, body = _run(
            self.handler.update("nonexistent", {"display_name": "X"})
        )
        self.assertEqual(status, 404)
        self.assertEqual(self.broadcaster.patches, [])

    def test_patch_invalid_color_returns_400(self) -> None:
        status, body = _run(self.handler.update("ai", {"color": "not-hex"}))
        self.assertEqual(status, 400)

    def test_patch_empty_display_name_returns_400(self) -> None:
        status, body = _run(self.handler.update("ai", {"display_name": "   "}))
        self.assertEqual(status, 400)


class CatalogDeleteTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.catalog = _FakeCatalog()
        self.broadcaster = _FakeBroadcaster()
        self.handler = CatalogHandler(self.catalog, self.broadcaster)

    def test_delete_role(self) -> None:
        # Add a temp role first
        _run(self.handler.create({"code": "temp", "display_name": "Временный"}))
        status, body = _run(self.handler.remove("temp"))
        self.assertEqual(status, 204)
        self.assertEqual(body, {})
        self.assertIn("temp", self.catalog.deleted)

    def test_delete_unknown_returns_404(self) -> None:
        status, body = _run(self.handler.remove("nonexistent"))
        self.assertEqual(status, 404)

    def test_delete_with_active_users_returns_409(self) -> None:
        # Override users_with_role to report a bearer
        async def fake_users(code):
            return ["@alice:test"] if code == "ai" else []

        self.catalog.users_with_role = fake_users
        status, body = _run(self.handler.remove("ai"))
        self.assertEqual(status, 409)
        self.assertNotIn("ai", self.catalog.deleted)


class CatalogReloadTestCase(unittest.TestCase):
    """POST /catalog/reload: snapshot diff -> broadcast changed codes."""

    def setUp(self) -> None:
        from synapse_modules.user_roles._api import CatalogReloadHandler

        self.catalog = _FakeCatalog()
        self.broadcaster = _FakeBroadcaster()
        self.handler = CatalogReloadHandler(self.catalog, self.broadcaster)

    def test_reload_returns_count_and_changed_list(self) -> None:
        # Before: только "ai". После reload: добавляется "cyber".
        self.catalog._reload_target = {
            "ai": {"code": "ai", "label": "ИИ", "color": "#4CAF50"},
            "cyber": {"code": "cyber", "label": "Кибер", "color": None},
        }
        status, body = _run(self.handler.reload())
        self.assertEqual(status, 200)
        self.assertTrue(body["reloaded"])
        self.assertEqual(body["count"], 2)
        self.assertEqual(body["changed"], ["cyber"])
        self.assertEqual(self.broadcaster.patches, ["cyber"])
        self.assertTrue(self.catalog._reload_called)

    def test_reload_with_modified_row_broadcasts(self) -> None:
        # Тот же код, но изменился label -> попадает в changed
        self.catalog._reload_target = {
            "ai": {"code": "ai", "label": "ИИ Renamed", "color": "#4CAF50"},
        }
        status, body = _run(self.handler.reload())
        self.assertEqual(status, 200)
        self.assertEqual(body["changed"], ["ai"])
        self.assertEqual(self.broadcaster.patches, ["ai"])

    def test_reload_no_changes_no_broadcast(self) -> None:
        # Reload не меняет состояние - changed пустой, broadcast не вызывается
        self.catalog._reload_target = {
            "ai": {"code": "ai", "label": "ИИ", "color": "#4CAF50"},
        }
        status, body = _run(self.handler.reload())
        self.assertEqual(status, 200)
        self.assertEqual(body["count"], 1)
        self.assertEqual(body["changed"], [])
        self.assertEqual(self.broadcaster.patches, [])

    def test_reload_broadcast_failure_does_not_abort(self) -> None:
        # Если broadcast упал на одном code, остальные всё равно вещаются и
        # эндпоинт возвращает 200 (logged-and-continue, как catalog PATCH).
        self.catalog._reload_target = {
            "ai": {"code": "ai", "label": "ИИ", "color": "#4CAF50"},
            "cyber": {"code": "cyber", "label": "Кибер", "color": None},
            "agro": {"code": "agro", "label": "Агро", "color": None},
        }
        call_log: list[str] = []

        async def flaky(code):
            call_log.append(code)
            if code == "cyber":
                raise RuntimeError("boom")

        self.broadcaster.broadcast_catalog_patch = flaky
        status, body = _run(self.handler.reload())
        self.assertEqual(status, 200)
        self.assertEqual(set(body["changed"]), {"cyber", "agro"})
        # Оба code были тронуты, несмотря на ошибку cyber
        self.assertEqual(set(call_log), {"cyber", "agro"})

    def test_reload_with_removed_code_not_in_changed(self) -> None:
        # Кейс: удалённый код (был в before, нет в after) не попадает в
        # changed - broadcast уже не нужен (роль исчезла, клиенты обновят
        # картинку при следующем GET /roles).
        self.catalog.rows = {
            "ai": {"code": "ai", "label": "ИИ", "color": "#4CAF50"},
            "stale": {"code": "stale", "label": "Удалить", "color": None},
        }
        self.catalog._reload_target = {
            "ai": {"code": "ai", "label": "ИИ", "color": "#4CAF50"},
        }
        status, body = _run(self.handler.reload())
        self.assertEqual(status, 200)
        self.assertEqual(body["count"], 1)
        self.assertEqual(body["changed"], [])
        self.assertEqual(self.broadcaster.patches, [])


if __name__ == "__main__":
    unittest.main()
