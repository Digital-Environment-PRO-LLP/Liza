"""Досье федеративного пользователя: account data чужого сервера недоступны.

Synapse AccountDataManager.get_global бросает ValueError для нелокального
MXID. До фикса это давало HTTP 500 на дочернем экране участников компании.

ledger:RL-company-members-access
AC:RL-company-members-access/13
"""

import asyncio
import json
import unittest

from synapse_modules.access_admin._dossier import DossierBuilder

SERVER = "liza.example"
LOCAL = "@local:liza.example"
REMOTE = "@remote:other.example"


def _run(coro):
    return asyncio.run(coro)


class _FakeDbPool:
    """runInteraction(name, fn) с заранее заданными строками членств."""

    def __init__(self, rows):
        self._rows = rows

    async def runInteraction(self, _name, fn):
        class _Txn:
            def __init__(self, rows):
                self._rows = rows

            def execute(self, _sql, _args):
                pass

            def fetchall(self):
                return self._rows

            def fetchone(self):
                return self._rows[0] if self._rows else None

        return fn(_Txn(self._rows))


class _FakeAccountData:
    """Зеркало поведения Synapse: для нелокального MXID — ValueError."""

    def __init__(self, server_name):
        self._server_name = server_name
        self.calls = []

    async def get_global(self, user_id, data_type):
        self.calls.append(user_id)
        if not user_id.endswith(":" + self._server_name):
            raise ValueError(
                f"{user_id} is not local to this homeserver; "
                "can't access account data for remote users."
            )
        return {}


def _row(room_id, name, room_type):
    return (
        room_id,
        name,
        None,
        room_type,
        json.dumps({"content": {"users": {}, "users_default": 0}}),
        json.dumps({"content": {}}),
        None,
        None,
    )


class FederatedDossierTestCase(unittest.TestCase):
    def _builder(self, account_data):
        return DossierBuilder(
            _FakeDbPool([_row("!c:liza.example", "Чат компании", None)]),
            account_data,
            SERVER,
        )

    def test_collect_for_remote_user_does_not_raise(self):
        account_data = _FakeAccountData(SERVER)
        groups = _run(self._builder(account_data).collect(REMOTE))
        self.assertEqual([e["room_id"] for e in groups["chats"]], ["!c:liza.example"])

    def test_collect_for_remote_user_skips_account_data(self):
        account_data = _FakeAccountData(SERVER)
        _run(self._builder(account_data).collect(REMOTE))
        self.assertEqual(account_data.calls, [])

    def test_collect_for_local_user_still_reads_account_data(self):
        account_data = _FakeAccountData(SERVER)
        _run(self._builder(account_data).collect(LOCAL))
        self.assertEqual(account_data.calls, [LOCAL, LOCAL])


if __name__ == "__main__":
    unittest.main()
