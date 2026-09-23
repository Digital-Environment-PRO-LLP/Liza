"""Тесты обхода иерархии пространства и сборки списка участников."""

import unittest

from synapse_modules.access_admin._space_members import (
    build_space_members,
    collect_space_room_ids,
)

ROOT = "!root:liza.example"


class CollectRoomIdsTestCase(unittest.TestCase):
    def test_root_included(self):
        self.assertEqual(collect_space_room_ids({}, ROOT), [ROOT])

    def test_direct_children_collected(self):
        edges = {ROOT: ["!a:liza.example", "!b:liza.example"]}
        result = collect_space_room_ids(edges, ROOT)
        self.assertEqual(
            sorted(result),
            sorted([ROOT, "!a:liza.example", "!b:liza.example"]),
        )

    def test_nested_subspace_collected(self):
        edges = {
            ROOT: ["!sub:liza.example"],
            "!sub:liza.example": ["!deep:liza.example"],
        }
        result = collect_space_room_ids(edges, ROOT)
        self.assertIn("!deep:liza.example", result)

    def test_cycle_does_not_hang(self):
        edges = {ROOT: ["!a:liza.example"], "!a:liza.example": [ROOT]}
        result = collect_space_room_ids(edges, ROOT)
        self.assertEqual(sorted(result), sorted([ROOT, "!a:liza.example"]))

    def test_depth_limit_respected(self):
        edges = {ROOT: ["!d1:x"], "!d1:x": ["!d2:x"], "!d2:x": ["!d3:x"]}
        result = collect_space_room_ids(edges, ROOT, max_depth=2)
        self.assertIn("!d2:x", result)
        self.assertNotIn("!d3:x", result)

    def test_no_duplicates(self):
        edges = {ROOT: ["!a:x", "!b:x"], "!a:x": ["!b:x"]}
        result = collect_space_room_ids(edges, ROOT)
        self.assertEqual(len(result), len(set(result)))

    def test_diamond_shape_no_duplicates(self):
        """R->A, R->B; A->C, B->C — C достижим ДВУМЯ путями В ОДНОМ слое.

        Дедуп по seen должен сработать даже когда дубль возникает не между
        слоями (как в test_no_duplicates), а внутри построения одного и
        того же фронта — иначе размер фронта растёт экспоненциально с
        шириной пространства (Critical, найдено ревью Task 6 round 1).
        """
        edges = {
            ROOT: ["!a:x", "!b:x"],
            "!a:x": ["!c:x"],
            "!b:x": ["!c:x"],
        }
        result = collect_space_room_ids(edges, ROOT)
        self.assertEqual(len(result), len(set(result)))
        self.assertEqual(result.count("!c:x"), 1)


class BuildMembersTestCase(unittest.TestCase):
    def _rows(self):
        # (room_id, user_id, power_level)
        return [
            (ROOT, "@ivan:liza.example", 100),
            ("!chat:liza.example", "@ivan:liza.example", 100),
            ("!chat:liza.example", "@petr:liza.example", 0),
        ]

    def _names(self):
        return {ROOT: "Компания", "!chat:liza.example": "Разработка"}

    def _groups(self):
        return {ROOT: "space", "!chat:liza.example": "chat"}

    def test_member_of_space_has_membership(self):
        members = build_space_members(
            self._rows(),
            root_id=ROOT,
            room_names=self._names(),
            room_groups=self._groups(),
        )
        ivan = next(m for m in members if m["user_id"] == "@ivan:liza.example")
        self.assertEqual(ivan["membership_in_space"], "join")

    def test_child_only_member_has_null_membership(self):
        members = build_space_members(
            self._rows(),
            root_id=ROOT,
            room_names=self._names(),
            room_groups=self._groups(),
        )
        petr = next(m for m in members if m["user_id"] == "@petr:liza.example")
        self.assertIsNone(petr["membership_in_space"])

    def test_child_only_member_is_present(self):
        members = build_space_members(
            self._rows(),
            root_id=ROOT,
            room_names=self._names(),
            room_groups=self._groups(),
        )
        self.assertIn(
            "@petr:liza.example", [m["user_id"] for m in members]
        )

    def test_max_power_level_across_subtree(self):
        members = build_space_members(
            [("!chat:liza.example", "@ivan:liza.example", 50)],
            root_id=ROOT,
            room_names=self._names(),
            room_groups=self._groups(),
        )
        self.assertEqual(members[0]["max_power_level"], 50)

    def test_elevated_rooms_lists_only_pl50_plus(self):
        rows = [
            ("!chat:liza.example", "@ivan:liza.example", 100),
            ("!other:liza.example", "@ivan:liza.example", 0),
        ]
        names = dict(self._names())
        names["!other:liza.example"] = "Обычный"
        groups = dict(self._groups())
        groups["!other:liza.example"] = "chat"
        members = build_space_members(
            rows, root_id=ROOT, room_names=names, room_groups=groups
        )
        elevated = members[0]["elevated_rooms"]
        self.assertEqual(len(elevated), 1)
        self.assertEqual(elevated[0]["name"], "Разработка")
        self.assertEqual(elevated[0]["group"], "chat")
