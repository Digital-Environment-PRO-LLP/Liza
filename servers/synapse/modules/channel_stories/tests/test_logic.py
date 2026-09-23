from synapse_modules.channel_stories._logic import (
    CHANNEL_STORIES_OF,
    STORIES_TAG,
    channel_stories_creation_content,
    is_channel_join,
    is_channel_leave,
)


def test_is_channel_join_true():
    assert is_channel_join("m.room.member", {"membership": "join"})


def test_is_channel_join_false_for_leave():
    assert not is_channel_join("m.room.member", {"membership": "leave"})


def test_is_channel_join_false_for_non_member():
    assert not is_channel_join("m.room.message", {})


def test_is_channel_leave_true_for_leave_and_ban():
    assert is_channel_leave("m.room.member", {"membership": "leave"})
    assert is_channel_leave("m.room.member", {"membership": "ban"})


def test_is_channel_leave_false_for_join():
    assert not is_channel_leave("m.room.member", {"membership": "join"})


def test_creation_content_has_markers():
    c = channel_stories_creation_content("!chan:h")
    assert c["com.liza.chat.type"] == "stories"
    assert c[STORIES_TAG] is True
    assert c[CHANNEL_STORIES_OF] == {"channel_id": "!chan:h"}
