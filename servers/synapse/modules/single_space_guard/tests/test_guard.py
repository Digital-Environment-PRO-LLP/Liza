"""Pure-logic tests for single_space_guard predicates (no HomeServer)."""

import importlib.util
from pathlib import Path

# Загружаем _guard.py напрямую по пути, без триггера package __init__
# (тот импортирует synapse.module_api, недоступный без живого HS).
_guard_path = Path(__file__).resolve().parent.parent / "_guard.py"
_spec = importlib.util.spec_from_file_location("ssg_guard", _guard_path)
guard = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(guard)


class TestIsRootSpaceCreation:
    def test_space_without_parent_is_root(self):
        config = {"creation_content": {"type": "m.space"}}
        assert guard.is_root_space_creation(config) is True

    def test_plain_room_is_not_root(self):
        config = {"creation_content": {}}
        assert guard.is_root_space_creation(config) is False

    def test_space_with_parent_in_initial_state_is_not_root(self):
        config = {
            "creation_content": {"type": "m.space"},
            "initial_state": [
                {"type": "m.space.parent", "state_key": "!parent:hs", "content": {}}
            ],
        }
        assert guard.is_root_space_creation(config) is False

    def test_missing_creation_content_is_not_root(self):
        assert guard.is_root_space_creation({}) is False

    # Контракт с клиентом (LABA-2532). Тела ниже — литералы того, что реально
    # шлёт Flutter-клиент; их зеркало — clients/flutter/test/utils/
    # create_subspace_test.dart (AC-1/2) и new_group.dart::_createSpace.
    # Расходятся клиент и предикат — краснеет одна из двух сторон.
    # ledger:RL-subspace-create-with-parent

    def test_client_subspace_body_is_not_root(self):
        # AC:RL-subspace-create-with-parent/6 — тело createSubspace():
        # подпространство с родителем в initial_state гард пропускает.
        config = {
            "name": "Отдел",
            "visibility": "private",
            "creation_content": {"type": "m.space"},
            "power_level_content_override": {"events_default": 100},
            "initial_state": [
                {
                    "type": "m.space.parent",
                    "state_key": "!company:example.invalid",
                    "content": {"via": ["example.invalid"]},
                }
            ],
        }
        assert guard.is_root_space_creation(config) is False

    def test_client_company_body_is_root(self):
        # AC:RL-subspace-create-with-parent/4 — тело _createSpace() экрана
        # «Создать компанию» (/rooms/newspace): initial_state без
        # m.space.parent → это root-space, и второй такой гард обязан резать.
        # Если сюда когда-нибудь попадёт m.space.parent — гард ослепнет.
        config = {
            "preset": "private_chat",
            "creation_content": {"type": "m.space"},
            "visibility": "private",
            "name": "Компания 1",
            "power_level_content_override": {"events_default": 100},
            "initial_state": [
                {"type": "m.room.avatar", "content": {"url": "mxc://hs/avatar"}},
                {"type": "m.room.join_rules", "content": {"join_rule": "invite"}},
            ],
        }
        assert guard.is_root_space_creation(config) is True


class TestIsMainSpaceLeave:
    def test_leave_of_main_space_matches(self):
        assert guard.is_protected_membership_change(
            event_type="m.room.member",
            membership="leave",
            room_id="!main:hs",
            main_root_space_id="!main:hs",
        ) is True

    def test_ban_of_main_space_matches(self):
        assert guard.is_protected_membership_change(
            event_type="m.room.member",
            membership="ban",
            room_id="!main:hs",
            main_root_space_id="!main:hs",
        ) is True

    def test_leave_of_other_space_does_not_match(self):
        assert guard.is_protected_membership_change(
            event_type="m.room.member",
            membership="leave",
            room_id="!other:hs",
            main_root_space_id="!main:hs",
        ) is False

    def test_join_of_main_space_does_not_match(self):
        assert guard.is_protected_membership_change(
            event_type="m.room.member",
            membership="join",
            room_id="!main:hs",
            main_root_space_id="!main:hs",
        ) is False

    def test_non_member_event_does_not_match(self):
        assert guard.is_protected_membership_change(
            event_type="m.room.message",
            membership=None,
            room_id="!main:hs",
            main_root_space_id="!main:hs",
        ) is False

    def test_no_main_space_yet_does_not_match(self):
        assert guard.is_protected_membership_change(
            event_type="m.room.member",
            membership="leave",
            room_id="!main:hs",
            main_root_space_id=None,
        ) is False


class TestDeduplicateCompanies:
    def test_no_duplicates_unchanged(self):
        companies = [
            {"room_id": "!a:hs", "name": "Acme"},
            {"room_id": "!b:hs", "name": "Beta"},
        ]
        result = guard.deduplicate_companies(companies)
        assert [c["room_id"] for c in result] == ["!a:hs", "!b:hs"]

    def test_duplicate_removed_first_kept(self):
        companies = [
            {"room_id": "!a:hs", "name": "Acme"},
            {"room_id": "!b:hs", "name": "Beta"},
            {"room_id": "!a:hs", "name": "Acme duplicate"},
        ]
        result = guard.deduplicate_companies(companies)
        assert len(result) == 2
        assert result[0]["name"] == "Acme"
        assert result[1]["room_id"] == "!b:hs"

    def test_empty_list(self):
        assert guard.deduplicate_companies([]) == []

    def test_skips_entries_without_room_id(self):
        companies = [{"name": "No ID"}, {"room_id": "!a:hs", "name": "Valid"}]
        result = guard.deduplicate_companies(companies)
        assert len(result) == 1
        assert result[0]["room_id"] == "!a:hs"


class TestIsSpaceChunk:
    def test_space_chunk_is_space(self):
        chunk = {"room_type": "m.space", "room_id": "!a:hs", "name": "Acme"}
        assert guard.is_space_chunk(chunk) is True

    def test_plain_room_chunk_is_not_space(self):
        chunk = {"room_id": "!b:hs", "name": "General"}
        assert guard.is_space_chunk(chunk) is False

    def test_matches_query_case_insensitive(self):
        assert guard.matches_query("Cyber Agro", "agro") is True
        assert guard.matches_query("Cyber Agro", "AGRO") is True
        assert guard.matches_query("Cyber Agro", "xyz") is False

    def test_empty_query_matches_all(self):
        assert guard.matches_query("Anything", "") is True
        assert guard.matches_query("Anything", None) is True

    def test_matches_query_handles_none_name(self):
        assert guard.matches_query(None, "agro") is False
        assert guard.matches_query(None, "") is True

    def test_matches_query_normalizes_dashes(self):
        # длинное тире (U+2013) в имени vs обычный дефис в запросе
        assert guard.matches_query("Кибер–Агро", "Кибер-Агро") is True
        assert guard.matches_query("Кибер-Агро", "Кибер–Агро") is True
        # em dash (U+2014) и minus (U+2212)
        assert guard.matches_query("Кибер—Агро", "кибер-агро") is True
        assert guard.matches_query("A−B", "a-b") is True

    def test_matches_query_cyrillic_case_insensitive(self):
        assert guard.matches_query("Кибер-Агро", "КИБЕР") is True
        assert guard.matches_query("ОБЩЕСТВО", "общество") is True

    def test_matches_query_collapses_whitespace(self):
        assert guard.matches_query("Cyber   Agro", "cyber agro") is True


class TestIsAutoAddCandidate:
    def test_plain_local_group_is_candidate(self):
        assert guard.is_auto_add_candidate(
            room_type=None,
            is_direct=False,
            has_space_parent=False,
            is_local=True,
        ) is True

    def test_space_is_not_candidate(self):
        assert guard.is_auto_add_candidate(
            room_type="m.space",
            is_direct=False,
            has_space_parent=False,
            is_local=True,
        ) is False

    def test_dm_is_not_candidate(self):
        assert guard.is_auto_add_candidate(
            room_type=None,
            is_direct=True,
            has_space_parent=False,
            is_local=True,
        ) is False

    def test_room_already_in_space_is_not_candidate(self):
        assert guard.is_auto_add_candidate(
            room_type=None,
            is_direct=False,
            has_space_parent=True,
            is_local=True,
        ) is False

    def test_remote_room_is_not_candidate(self):
        assert guard.is_auto_add_candidate(
            room_type=None,
            is_direct=False,
            has_space_parent=False,
            is_local=False,
        ) is False


class TestIsDmCreation:
    def test_is_direct_true(self):
        assert guard.is_dm_creation({"is_direct": True}) is True

    def test_is_direct_false(self):
        assert guard.is_dm_creation({"is_direct": False}) is False

    def test_is_direct_absent(self):
        assert guard.is_dm_creation({}) is False

    def test_is_direct_truthy_nonbool_coerced(self):
        assert guard.is_dm_creation({"is_direct": 1}) is True
        assert guard.is_dm_creation({"is_direct": 0}) is False


class TestIsLocalRoom:
    def test_local_room_matches_server_name(self):
        assert guard.is_local_room("!abc:liza.cyber-agro.ru", "liza.cyber-agro.ru") is True

    def test_remote_room_does_not_match(self):
        assert guard.is_local_room("!abc:synapse.liza.laba.prodamus.tech", "liza.cyber-agro.ru") is False

    def test_empty_room_id_is_not_local(self):
        assert guard.is_local_room("", "liza.cyber-agro.ru") is False

    def test_server_name_as_substring_does_not_falsely_match(self):
        # ведущий ":" защищает от ложного совпадения по суффиксу домена
        assert guard.is_local_room("!abc:evil-liza.cyber-agro.ru", "liza.cyber-agro.ru") is False

    def test_server_name_present_but_not_at_end(self):
        assert guard.is_local_room("!liza.cyber-agro.ru:other.tld", "liza.cyber-agro.ru") is False
