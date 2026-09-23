from synapse_modules.stories_membership._logic import (
    STORIES_ROOM_NAME_PREFIX,
    dm_pairs_from_direct,
    is_direct_membership_join,
    is_hidden_room,
    is_local_room,
    is_local_user,
    is_reachable_server,
    localpart_of,
    server_name_of,
    stories_room_name,
    story_is_expired,
)


def test_is_direct_membership_join_true():
    assert is_direct_membership_join(
        "m.room.member", {"membership": "join"}, True
    )


def test_is_direct_membership_join_false_not_direct():
    assert not is_direct_membership_join(
        "m.room.member", {"membership": "join"}, False
    )


def test_is_direct_membership_join_false_on_leave():
    assert not is_direct_membership_join(
        "m.room.member", {"membership": "leave"}, True
    )


def test_is_direct_membership_join_false_wrong_type():
    assert not is_direct_membership_join(
        "m.room.message", {"membership": "join"}, True
    )


def test_server_name_of():
    assert server_name_of("@bob:other.example") == "other.example"


def test_localpart_of():
    assert localpart_of("@bob:other.example") == "bob"


def test_is_local_user_true():
    assert is_local_user("@alice:local.test", "local.test")


def test_is_local_user_false_remote():
    assert not is_local_user("@bob:remote.example", "local.test")


def test_is_local_user_no_colon():
    assert not is_local_user("invalid", "local.test")


def test_stories_room_name():
    assert stories_room_name("@ivan.petrov:local.test") == "Stories - ivan.petrov"


def test_stories_room_name_uses_shared_prefix_constant():
    assert stories_room_name("@bob:x").startswith(STORIES_ROOM_NAME_PREFIX)


def test_story_is_expired_true():
    assert story_is_expired(
        {"com.liza.story": {"expires_ts": 1000}}, 2000
    )


def test_story_is_expired_false_future():
    assert not story_is_expired(
        {"com.liza.story": {"expires_ts": 5000}}, 2000
    )


def test_story_is_expired_false_no_story_field():
    assert not story_is_expired({"msgtype": "m.image"}, 2000)


# --- is_local_room ---

def test_is_local_room_true():
    assert is_local_room("!abc:local.test", "local.test")


def test_is_local_room_false_other_server():
    assert not is_local_room("!abc:other.example", "local.test")


def test_is_local_room_false_no_colon():
    assert not is_local_room("invalid", "local.test")


def test_is_local_room_subdomain():
    # "local.test" не совпадает с "sub.local.test"
    assert not is_local_room("!abc:sub.local.test", "local.test")


# --- dm_pairs_from_direct ---

def test_dm_pairs_from_direct_basic():
    """Для owner с двумя DM-контрагентами возвращает две пары."""
    content = {
        "@bob:x": ["!r1:x"],
        "@carol:x": ["!r2:x"],
    }
    pairs = dm_pairs_from_direct("@alice:x", content)
    # Пары нормализованы (sorted), уникальны
    assert ("@alice:x", "@bob:x") in pairs or ("@bob:x", "@alice:x") in pairs
    assert ("@alice:x", "@carol:x") in pairs or ("@carol:x", "@alice:x") in pairs
    assert len(pairs) == 2


def test_dm_pairs_from_direct_empty_content():
    assert dm_pairs_from_direct("@alice:x", {}) == []


def test_dm_pairs_from_direct_empty_rooms_list():
    """other_user с пустым списком комнат - пара всё равно возвращается."""
    content = {"@bob:x": []}
    pairs = dm_pairs_from_direct("@alice:x", content)
    assert len(pairs) == 1


def test_dm_pairs_from_direct_dedup():
    """Несколько комнат с одним контрагентом - пара одна."""
    content = {"@bob:x": ["!r1:x", "!r2:x"]}
    pairs = dm_pairs_from_direct("@alice:x", content)
    assert len(pairs) == 1


def test_dm_pairs_from_direct_normalizes_order():
    """(a, b) и (b, a) дают одну и ту же нормализованную пару."""
    pairs_a = dm_pairs_from_direct("@alice:x", {"@bob:x": ["!r:x"]})
    pairs_b = dm_pairs_from_direct("@bob:x", {"@alice:x": ["!r:x"]})
    assert set(map(tuple, pairs_a)) == set(map(tuple, pairs_b))


# --- is_hidden_room (обобщение под /remember: не только "stories") ---


def test_is_hidden_room_explicit_hidden_true():
    assert is_hidden_room(None, {"hidden": True})


def test_is_hidden_room_explicit_hidden_false():
    """Явный hidden=false побеждает даже если create_content выглядит как stories."""
    assert not is_hidden_room({"com.liza.stories": True}, {"hidden": False})


def test_is_hidden_room_legacy_com_liza_stories():
    assert is_hidden_room({"com.liza.stories": True}, None)


def test_is_hidden_room_legacy_chat_type_stories():
    assert is_hidden_room({"com.liza.chat.type": "stories"}, None)


def test_is_hidden_room_legacy_chat_type_other_value_not_hidden():
    """com.liza.chat.type - будущая категория, не 'stories' - НЕ hidden по
    legacy-дефолту (только явный topology.hidden решает для новых типов)."""
    assert not is_hidden_room({"com.liza.chat.type": "system"}, None)


def test_is_hidden_room_ordinary_room():
    assert not is_hidden_room({}, None)


def test_is_hidden_room_no_create_content_no_topology():
    assert not is_hidden_room(None, None)


def test_is_hidden_room_topology_content_empty_dict_is_not_hidden():
    """Пустой content у topology state (hidden отсутствует) - не hidden,
    и НЕ падает на legacy-дефолт (явный state event уже есть, приоритет ему)."""
    assert not is_hidden_room({"com.liza.stories": True}, {})


# --- is_reachable_server: не ходим на погашенные серверы ---

def test_reachable_own_server_always():
    """Свой сервер достижим, даже если whitelist его не перечисляет."""
    assert is_reachable_server("@a:local.test", "local.test", {"other.test": True})


def test_reachable_remote_in_whitelist():
    assert is_reachable_server("@a:other.test", "local.test", {"other.test": True})


def test_unreachable_remote_not_in_whitelist():
    """Погашенный сервер, убранный из whitelist, больше не дёргается."""
    assert not is_reachable_server(
        "@a:dev.dead.example", "local.test", {"other.test": True}
    )


def test_reachable_when_whitelist_not_configured():
    """whitelist=None (не настроен) - поведение Synapse по умолчанию: все достижимы."""
    assert is_reachable_server("@a:any.example", "local.test", None)


def test_unreachable_when_whitelist_empty():
    """Пустой whitelist (федерация закрыта) - чужие недостижимы, свой доступен."""
    assert not is_reachable_server("@a:other.test", "local.test", {})
    assert is_reachable_server("@a:local.test", "local.test", {})


def test_malformed_user_id_is_unreachable():
    """Кривой Matrix ID без домена не роняет проход, считается недостижимым."""
    assert not is_reachable_server("@nocolon", "local.test", {"x": True})
