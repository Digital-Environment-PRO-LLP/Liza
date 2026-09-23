"""Тесты мягкой деактивации/реактивации.

Ключевой инвариант: членства, пароль и account data НЕ трогаются —
проверяем, что вызываются ровно нужные методы и никакие лишние.
"""

import asyncio
import unittest

from synapse.types import UserID
from synapse_modules.access_admin._accounts import AccountManager


def _run(coro):
    return asyncio.run(coro)


class _FakeStore:
    def __init__(self, deactivated: bool = False):
        self.deactivated_flags: list[tuple[str, bool]] = []
        self._state = deactivated
        self.profile_calls: list[str] = []

    async def set_user_deactivated_status(self, user_id: str, value: bool):
        self.deactivated_flags.append((user_id, value))
        self._state = value

    async def get_user_deactivated_status(self, user_id: str) -> bool:
        return self._state

    async def get_profileinfo(self, user_id):
        # Проверяем, что user_id имеет метод to_string() — требует UserID, не строку
        user_string = user_id.to_string()
        self.profile_calls.append(user_string)
        return {"display_name": "Иван", "avatar_url": None}


class _FakeAuthHandler:
    def __init__(self):
        self.token_deletions: list[str] = []

    async def delete_access_tokens_for_user(self, user_id: str):
        self.token_deletions.append(user_id)


class _FakeUserDirectory:
    def __init__(self):
        self.deactivated: list[str] = []
        self.profile_changes: list[str] = []

    async def handle_local_user_deactivated(self, user_id: str):
        self.deactivated.append(user_id)

    async def handle_local_profile_change(self, user_id: str, profile):
        self.profile_changes.append(user_id)


def _manager(deactivated: bool = False):
    store = _FakeStore(deactivated)
    auth = _FakeAuthHandler()
    directory = _FakeUserDirectory()
    return AccountManager(store, auth, directory), store, auth, directory


class DeactivateTestCase(unittest.TestCase):
    def test_sets_flag(self):
        mgr, store, _, _ = _manager()
        _run(mgr.deactivate("@u:srv"))
        self.assertEqual(store.deactivated_flags, [("@u:srv", True)])

    def test_revokes_tokens(self):
        mgr, _, auth, _ = _manager()
        _run(mgr.deactivate("@u:srv"))
        self.assertEqual(auth.token_deletions, ["@u:srv"])

    def test_removes_from_user_directory(self):
        mgr, _, _, directory = _manager()
        _run(mgr.deactivate("@u:srv"))
        self.assertEqual(directory.deactivated, ["@u:srv"])

    def test_returns_state(self):
        mgr, _, _, _ = _manager()
        result = _run(mgr.deactivate("@u:srv"))
        self.assertEqual(result, {"user_id": "@u:srv", "deactivated": True})

    def test_idempotent_on_already_deactivated(self):
        mgr, store, _, _ = _manager(deactivated=True)
        result = _run(mgr.deactivate("@u:srv"))
        self.assertEqual(result, {"user_id": "@u:srv", "deactivated": True})
        self.assertEqual(store.deactivated_flags, [])


class ReactivateTestCase(unittest.TestCase):
    def test_clears_flag(self):
        mgr, store, _, _ = _manager(deactivated=True)
        _run(mgr.reactivate("@u:srv"))
        self.assertEqual(store.deactivated_flags, [("@u:srv", False)])

    def test_returns_to_user_directory(self):
        mgr, _, _, directory = _manager(deactivated=True)
        _run(mgr.reactivate("@u:srv"))
        self.assertEqual(directory.profile_changes, ["@u:srv"])

    def test_does_not_revoke_tokens(self):
        mgr, _, auth, _ = _manager(deactivated=True)
        _run(mgr.reactivate("@u:srv"))
        self.assertEqual(auth.token_deletions, [])

    def test_returns_state(self):
        mgr, _, _, _ = _manager(deactivated=True)
        result = _run(mgr.reactivate("@u:srv"))
        self.assertEqual(result, {"user_id": "@u:srv", "deactivated": False})

    def test_idempotent_on_active_account(self):
        mgr, store, _, _ = _manager(deactivated=False)
        result = _run(mgr.reactivate("@u:srv"))
        self.assertEqual(result, {"user_id": "@u:srv", "deactivated": False})
        self.assertEqual(store.deactivated_flags, [])

    def test_passes_userid_to_profileinfo(self):
        """get_profileinfo получает UserID объект, а не строку."""
        mgr, store, _, _ = _manager(deactivated=True)
        _run(mgr.reactivate("@u:srv"))
        # profile_calls содержит результат to_string(), значит был объект UserID
        self.assertEqual(store.profile_calls, ["@u:srv"])


if __name__ == "__main__":
    unittest.main()
