"""Tests for RoleBroadcaster using a fake store (no real HomeServer)."""

import asyncio
import unittest
from typing import Any
from unittest.mock import MagicMock

from synapse_modules.user_roles._broadcast import EVENT_TYPE, RoleBroadcaster


def _run(coro):
    return asyncio.run(coro)


class _FakeStore:
    """Stand-in for hs.get_datastores().main."""

    def __init__(self) -> None:
        # role storage: user_id -> {account_data_type: payload}
        self._account_data: dict[str, dict[str, Any]] = {}
        # room shares: user_id -> set[user_id]
        self._shared_rooms: dict[str, set[str]] = {}
        # captured to-device sends
        self.sent: list[dict] = []

    async def get_global_account_data_by_type_for_user(
        self, user_id: str, type_: str
    ) -> dict | None:
        return self._account_data.get(user_id, {}).get(type_)

    async def get_users_who_share_room_with_user(self, user_id: str) -> set[str]:
        return set(self._shared_rooms.get(user_id, set()))

    async def add_messages_to_device_inbox(
        self,
        local: dict[str, dict[str, Any]],
        remote: dict[str, Any],
    ) -> int:
        self.sent.append({"local": local, "remote": remote})
        return 1


class _FakeHomeServer:
    """module_api._hs surrogate with just get_datastores()."""

    def __init__(self, store: _FakeStore) -> None:
        self._store = store
        self.hostname = "test"

    def get_datastores(self) -> MagicMock:
        m = MagicMock()
        m.main = self._store
        return m

    def get_clock(self) -> MagicMock:
        m = MagicMock()
        m.time_msec.return_value = 1_000
        return m


class _FakeCatalog:
    """Minimal stand-in for RoleCatalog with the methods broadcaster needs."""

    def __init__(self, *, role_views: dict, role_bearers: dict[str, list[str]]) -> None:
        self._role_views = role_views
        self._role_bearers = role_bearers

    async def enrich(self, code):
        return self._role_views.get(code)

    async def users_with_role(self, code: str) -> list[str]:
        return list(self._role_bearers.get(code, []))


class BroadcastRoleChangeTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.store = _FakeStore()
        self.hs = _FakeHomeServer(self.store)
        self.catalog = _FakeCatalog(
            role_views={
                "ai": {"code": "ai", "label": "ИИ", "color": "#4CAF50"},
                "user": {"code": "user", "label": "Пользователь", "color": None},
            },
            role_bearers={},
        )
        self.broadcaster = RoleBroadcaster(self.hs, self.catalog)

    def test_broadcast_sends_to_self_and_room_peers(self) -> None:
        self.store._account_data["@alice:test"] = {
            "com.liza.user_role": {"role": "ai"}
        }
        self.store._shared_rooms["@alice:test"] = {"@bob:test", "@carol:test"}

        _run(self.broadcaster.broadcast_role_change("@alice:test"))

        self.assertEqual(len(self.store.sent), 1)
        sent = self.store.sent[0]
        recipients = set(sent["local"].keys())
        # Self + peers
        self.assertEqual(recipients, {"@alice:test", "@bob:test", "@carol:test"})
        # Each recipient gets wildcard device-id
        for uid in recipients:
            self.assertEqual(list(sent["local"][uid].keys()), ["*"])
            msg = sent["local"][uid]["*"]
            self.assertEqual(msg["type"], EVENT_TYPE)
            self.assertEqual(
                msg["content"],
                {
                    "user_id": "@alice:test",
                    "role": {"code": "ai", "label": "ИИ", "color": "#4CAF50"},
                },
            )
        self.assertEqual(sent["remote"], {})

    def test_broadcast_carries_extra_roles(self) -> None:
        # Иначе to-device владельцу затирал бы в клиенте доп. роль developer.
        self.store._account_data["@owner:test"] = {
            "com.liza.user_role": {"role": "ai", "extra_roles": ("user",)}
        }
        _run(self.broadcaster.broadcast_role_change("@owner:test"))
        msg = self.store.sent[0]["local"]["@owner:test"]["*"]
        self.assertEqual(msg["content"]["role"]["extra_roles"], ["user"])
        self.assertEqual(msg["content"]["role"]["code"], "ai")

    def test_broadcast_when_role_cleared(self) -> None:
        # account_data missing -> role: None
        self.store._shared_rooms["@alice:test"] = {"@bob:test"}
        _run(self.broadcaster.broadcast_role_change("@alice:test"))

        msg = self.store.sent[0]["local"]["@alice:test"]["*"]
        self.assertEqual(
            msg["content"],
            {"user_id": "@alice:test", "role": None},
        )

    def test_broadcast_with_no_peers_still_notifies_self(self) -> None:
        # No shared rooms; broadcast still goes to user's own devices.
        self.store._account_data["@solo:test"] = {
            "com.liza.user_role": {"role": "user"}
        }
        _run(self.broadcaster.broadcast_role_change("@solo:test"))
        self.assertEqual(set(self.store.sent[0]["local"].keys()), {"@solo:test"})


class BroadcastCatalogPatchTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.store = _FakeStore()
        self.hs = _FakeHomeServer(self.store)
        self.catalog = _FakeCatalog(
            role_views={
                "ai": {"code": "ai", "label": "ИИ Renamed", "color": "#00FF00"},
            },
            role_bearers={"ai": ["@bot1:test", "@bot2:test"]},
        )
        self.broadcaster = RoleBroadcaster(self.hs, self.catalog)

    def test_broadcast_catalog_patch_iterates_bearers(self) -> None:
        # Both bot1 and bot2 have the role; each lives in their own room with one peer.
        self.store._account_data["@bot1:test"] = {"com.liza.user_role": {"role": "ai"}}
        self.store._shared_rooms["@bot1:test"] = {"@user1:test"}
        self.store._account_data["@bot2:test"] = {"com.liza.user_role": {"role": "ai"}}
        self.store._shared_rooms["@bot2:test"] = {"@user2:test"}

        _run(self.broadcaster.broadcast_catalog_patch("ai"))

        self.assertEqual(len(self.store.sent), 2, "one broadcast per bearer")
        # Each broadcast should have the renamed label
        for sent in self.store.sent:
            for uid in sent["local"]:
                msg = sent["local"][uid]["*"]
                self.assertEqual(msg["content"]["role"]["label"], "ИИ Renamed")

    def test_broadcast_catalog_patch_no_bearers_is_noop(self) -> None:
        # No one has this role -> no sends
        self.catalog._role_bearers = {}
        _run(self.broadcaster.broadcast_catalog_patch("nonexistent"))
        self.assertEqual(self.store.sent, [])


if __name__ == "__main__":
    unittest.main()
