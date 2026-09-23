"""Pure-предикаты channel_stories: без импорта synapse."""

CHANNEL_STORIES_OF = "com.liza.channel.stories_of"
CHANNEL_STORIES_STATE = "com.liza.channel.stories"
STORIES_TAG = "com.liza.stories"
CHAT_TYPE_KEY = "com.liza.chat.type"


def is_channel_join(event_type: str, content: dict) -> bool:
    return event_type == "m.room.member" and content.get("membership") == "join"


def is_channel_leave(event_type: str, content: dict) -> bool:
    return event_type == "m.room.member" and content.get("membership") in (
        "leave",
        "ban",
    )


def channel_stories_creation_content(channel_id: str) -> dict:
    return {
        CHAT_TYPE_KEY: "stories",
        STORIES_TAG: True,
        CHANNEL_STORIES_OF: {"channel_id": channel_id},
    }
