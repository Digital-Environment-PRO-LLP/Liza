"""Тесты сборки досье из строк БД."""

import json
import unittest

from synapse_modules.access_admin._dossier import build_dossier_groups

SERVER = "liza.example"
TARGET = "@u:liza.example"


def _power_json(users: dict, default: int = 0) -> str:
    return json.dumps({"content": {"users": users, "users_default": default}})


def _create_json(chat_type: str | None = None) -> str:
    content = {}
    if chat_type is not None:
        content["com.liza.chat.type"] = chat_type
    return json.dumps({"content": content})


def _legacy_create_json() -> str:
    return json.dumps({"content": {"com.liza.stories": True}})


def _topology_json(hidden: bool) -> str:
    return json.dumps({"content": {"hidden": hidden}})


def _row(
    room_id,
    name,
    room_type,
    power_json=None,
    create_json=None,
    avatar=None,
    topology_json=None,
    tombstone=None,
):
    return (
        room_id,
        name,
        avatar,
        room_type,
        power_json if power_json is not None else _power_json({}),
        create_json if create_json is not None else _create_json(),
        topology_json,
        tombstone,
    )


def _build(rows, dm_room_ids=frozenset(), bot_dm_room_ids=frozenset()):
    return build_dossier_groups(
        rows,
        target_id=TARGET,
        server_name=SERVER,
        dm_room_ids=dm_room_ids,
        bot_dm_room_ids=bot_dm_room_ids,
    )


class GroupingTestCase(unittest.TestCase):
    def test_space_goes_to_spaces(self):
        rows = [_row("!s:liza.example", "Компания", "m.space")]
        result = _build(rows)
        self.assertEqual(len(result["spaces"]), 1)
        self.assertEqual(result["spaces"][0]["name"], "Компания")

    def test_channel_goes_to_channels(self):
        rows = [_row("!c:liza.example", "Канал", "com.liza.channel")]
        self.assertEqual(len(_build(rows)["channels"]), 1)

    def test_plain_room_goes_to_chats(self):
        rows = [_row("!r:liza.example", "Чат", None)]
        self.assertEqual(len(_build(rows)["chats"]), 1)

    def test_all_groups_present_even_when_empty(self):
        result = _build([])
        self.assertEqual(
            result, {"spaces": [], "channels": [], "chats": [], "bots": []}
        )


class ExclusionTestCase(unittest.TestCase):
    def test_dm_excluded(self):
        rows = [_row("!dm:liza.example", "Иван", None)]
        result = _build(rows, dm_room_ids={"!dm:liza.example"})
        self.assertEqual(result["chats"], [])

    def test_stories_room_excluded(self):
        rows = [
            _row("!st:liza.example", "Сторисы", None,
                 create_json=_create_json("stories"))
        ]
        self.assertEqual(_build(rows)["chats"], [])

    def test_channel_discussion_excluded(self):
        rows = [
            _row("!d:liza.example", "Обсуждение", None,
                 create_json=_create_json("channel_discussion"))
        ]
        self.assertEqual(_build(rows)["chats"], [])

    def test_federated_room_included(self):
        # Комнаты чужих серверов больше не отсекаются: досье показывает
        # всё, что известно нашему серверу (спека §5.2 п.3).
        rows = [_row("!f:other.example", "Чужая", None)]
        self.assertEqual(len(_build(rows)["chats"]), 1)

    def test_federated_space_also_included(self):
        rows = [_row("!f:other.example", "Чужая компания", "m.space")]
        self.assertEqual(len(_build(rows)["spaces"]), 1)


class LevelTestCase(unittest.TestCase):
    def test_admin_level(self):
        rows = [
            _row("!s:liza.example", "К", "m.space",
                 power_json=_power_json({TARGET: 100}))
        ]
        self.assertEqual(_build(rows)["spaces"][0]["level"], "admin")

    def test_moderator_level(self):
        rows = [
            _row("!s:liza.example", "К", "m.space",
                 power_json=_power_json({TARGET: 50}))
        ]
        self.assertEqual(_build(rows)["spaces"][0]["level"], "moderator")

    def test_user_level_from_default(self):
        rows = [
            _row("!s:liza.example", "К", "m.space",
                 power_json=_power_json({}, default=0))
        ]
        self.assertEqual(_build(rows)["spaces"][0]["level"], "user")

    def test_missing_power_levels_event_is_user(self):
        rows = [_row("!s:liza.example", "К", "m.space", power_json=None)]
        self.assertEqual(_build(rows)["spaces"][0]["level"], "user")

    def test_broken_json_does_not_crash(self):
        rows = [_row("!s:liza.example", "К", "m.space", power_json="{не json")]
        self.assertEqual(_build(rows)["spaces"][0]["level"], "user")


class SortingTestCase(unittest.TestCase):
    def test_sorted_by_level_then_name(self):
        rows = [
            _row("!a:liza.example", "Яна", None, _power_json({TARGET: 0})),
            _row("!b:liza.example", "Борис", None, _power_json({TARGET: 100})),
            _row("!c:liza.example", "Анна", None, _power_json({TARGET: 100})),
        ]
        names = [c["name"] for c in _build(rows)["chats"]]
        self.assertEqual(names, ["Анна", "Борис", "Яна"])


class LegacyStoriesRowTestCase(unittest.TestCase):
    def test_legacy_stories_room_excluded(self):
        rows = [
            _row("!s:liza.example", "Сторис", None,
                 create_json=_legacy_create_json())
        ]
        result = _build(rows)
        self.assertEqual(result["chats"], [])


class UnnamedRoomTestCase(unittest.TestCase):
    def test_room_without_name_has_null_name(self):
        rows = [_row("!x:liza.example", None, None)]
        result = _build(rows)
        self.assertIsNone(result["chats"][0]["name"])


class HiddenRoomsTestCase(unittest.TestCase):
    def test_topology_hidden_excluded(self):
        rows = [_row("!h:liza.example", "Скрытый", None,
                      topology_json=_topology_json(True))]
        self.assertEqual(_build(rows)["chats"], [])

    def test_topology_hidden_false_included(self):
        rows = [_row("!v:liza.example", "Видимый", None,
                      topology_json=_topology_json(False))]
        self.assertEqual(len(_build(rows)["chats"]), 1)

    def test_topology_state_wins_over_legacy_stories(self):
        # Есть topology-стейт → легаси-ключ не смотрим (зеркало isHiddenChat).
        rows = [_row("!l:liza.example", "Комната", None,
                      create_json=_legacy_create_json(),
                      topology_json=_topology_json(False))]
        self.assertEqual(len(_build(rows)["chats"]), 1)


class TombstoneTestCase(unittest.TestCase):
    def test_tombstoned_room_excluded(self):
        rows = [_row("!t:liza.example", "Апгрейженный", None,
                      tombstone="$evt:liza.example")]
        self.assertEqual(_build(rows)["chats"], [])


class BotGroupTestCase(unittest.TestCase):
    def test_dm_with_bot_goes_to_bots(self):
        rows = [_row("!b:liza.example", "Лиза", None)]
        result = build_dossier_groups(
            rows,
            target_id=TARGET,
            server_name=SERVER,
            dm_room_ids={"!b:liza.example"},
            bot_dm_room_ids={"!b:liza.example"},
        )
        self.assertEqual(len(result["bots"]), 1)
        self.assertEqual(result["chats"], [])

    def test_dm_with_human_still_excluded(self):
        rows = [_row("!d:liza.example", "Пётр", None)]
        result = build_dossier_groups(
            rows,
            target_id=TARGET,
            server_name=SERVER,
            dm_room_ids={"!d:liza.example"},
            bot_dm_room_ids=frozenset(),
        )
        self.assertEqual(result["bots"], [])
        self.assertEqual(result["chats"], [])

    def test_bots_group_always_present(self):
        self.assertEqual(
            _build([]),
            {"spaces": [], "channels": [], "chats": [], "bots": []},
        )


if __name__ == "__main__":
    unittest.main()
