from synapse_modules.channel_guard.scripts.backfill_room_type import (
    LIZA_CHANNEL_ROOM_TYPE,
    backfill,
    find_channels_without_room_type,
)


class _FakeCursor:
    """Курсор-заглушка: отдаёт заданные строки и пишет выполненные UPDATE."""

    def __init__(self, rows=()):
        self._rows = list(rows)
        self.executed = []
        self.rowcount = 1

    def execute(self, sql, params=None):
        self.executed.append((sql, params))

    def fetchall(self):
        return [(room_id,) for room_id in self._rows]


def test_find_returns_room_ids():
    cursor = _FakeCursor(["!a:test", "!b:test"])
    assert find_channels_without_room_type(cursor) == ["!a:test", "!b:test"]


def test_find_returns_empty_when_nothing_to_do():
    cursor = _FakeCursor([])
    assert find_channels_without_room_type(cursor) == []


def test_backfill_updates_each_room_with_channel_type():
    cursor = _FakeCursor()
    updated = backfill(cursor, ["!a:test", "!b:test"], dry_run=False)

    assert updated == 2
    params = [p for _, p in cursor.executed]
    assert params == [
        (LIZA_CHANNEL_ROOM_TYPE, "!a:test"),
        (LIZA_CHANNEL_ROOM_TYPE, "!b:test"),
    ]


def test_backfill_dry_run_executes_nothing():
    cursor = _FakeCursor()
    updated = backfill(cursor, ["!a:test"], dry_run=True)

    assert updated == 0
    assert cursor.executed == []


def test_backfill_empty_list_is_noop():
    cursor = _FakeCursor()
    assert backfill(cursor, [], dry_run=False) == 0
    assert cursor.executed == []
