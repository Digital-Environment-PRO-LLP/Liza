"""Pure-предикаты channel_sync: без импорта synapse, тестируются напрямую."""

CHANNEL_DISCUSSION_STATE = "com.liza.channel.discussion"
CHANNEL_PARENT_STATE = "com.liza.channel.parent"
POST_REF_KEY = "com.liza.channel.post_ref"
DISCUSSION_CHAT_TYPE = "channel_discussion"
# Ключ в content com.liza.channel.discussion, которым клиент помечает удаление
# КАНАЛА (а не выключение комментариев). Пишется РЯДОМ с room_id, не вместо
# него. См. channel_deleted_of.
CHANNEL_DELETED_KEY = "deleted"

JOIN_RULES_STATE = "m.room.join_rules"
HISTORY_VISIBILITY_STATE = "m.room.history_visibility"
TOPOLOGY_STATE = "com.liza.chat.topology"

_RELATES = "m.relates_to"


def is_root_post(event_type: str, content: dict) -> bool:
    """Корневой пост канала: m.room.message без relation (не reply/edit)."""
    if event_type != "m.room.message":
        return False
    return _RELATES not in content


def is_edit(content: dict) -> bool:
    rel = content.get(_RELATES) or {}
    return rel.get("rel_type") == "m.replace"


def edited_event_id(content: dict) -> str | None:
    rel = content.get(_RELATES) or {}
    if rel.get("rel_type") != "m.replace":
        return None
    return rel.get("event_id")


def discussion_room_of(create_content: dict, discussion_state_content: dict | None) -> str | None:
    """room_id привязанного чата из state com.liza.channel.discussion, или None.

    Маркер удаления (deleted:true) здесь НАМЕРЕННО не учитывается: маркер
    пишется вместе с room_id и обязан оставлять чат находимым. На нём держится
    кик подписчиков из чата обсуждения при удалении канала — см.
    ChannelSyncModule._on_channel_leave и channel_deleted_of.
    """
    if not discussion_state_content:
        return None
    return discussion_state_content.get("room_id")


def channel_deleted_of(discussion_state_content: dict | None) -> bool:
    """Маркер «канал удалён» в content com.liza.channel.discussion.

    В Matrix нет события «комната удалена»: удаление канала — это кик
    участников + leave + forget, сервер видит ровно те же события, что и при
    обычной отписке. Поэтому удаление помечается ЯВНО: клиент перед уходом
    пишет в привязку {"room_id": <чат>, "deleted": true}. Выводить удаление из
    простой отвязки нельзя — это и был баг, из-за которого выключение
    комментариев стирало связь постов с комментариями безвозвратно.

    room_id в маркере ОБЯЗАТЕЛЕН и держит инвариант порядка: кик каждого
    подписчика из канала обрабатывается фоново (run_as_background_process), и
    к моменту, когда фоновый процесс дочитает привязку, маркер уже может быть
    записан. Пустой content на этом месте (как было в первой версии) означал
    бы «комментариев нет» → часть подписчиков осталась бы членами чата
    обсуждения. С room_id ответ не зависит от того, что успело приземлиться
    раньше.

    Признаём только литеральный True: маркер запускает необратимое удаление
    строк, и «правдоподобное» значение (строка "true", 1) от чужого клиента
    не должно к нему приводить.
    """
    if not discussion_state_content:
        return False
    return discussion_state_content.get(CHANNEL_DELETED_KEY) is True


def should_cleanup_mappings(
    *,
    prev_room: str | None,
    new_room: str | None,
    channel_deleted: bool,
) -> bool:
    """Нужно ли удалять маппинги пост→зеркало отвязанного чата.

    Отвязка чата (выключение комментариев) маппинги СОХРАНЯЕТ: чат остаётся
    целым, и при повторном включении комментарии возвращаются — так же, как
    при повторном включении. Раньше здесь чистилось всё подряд, и старые треды
    восстановить было уже нельзя.

    Чистим в двух случаях: канал удалён либо привязка переехала на ДРУГОЙ
    чат (маппинги старого больше никому не нужны).
    """
    if not prev_room:
        return False
    if channel_deleted:
        return True
    return new_room is not None and new_room != prev_room


def build_mirror_content(post_content: dict, channel_id: str, post_event_id: str) -> dict:
    """Копия content поста + маркер обратной ссылки на оригинал."""
    mirror = dict(post_content)
    mirror[POST_REF_KEY] = {
        "channel_id": channel_id,
        "post_event_id": post_event_id,
    }
    return mirror


def join_rule_of(content: dict | None) -> str | None:
    """join_rule из content события m.room.join_rules, или None."""
    if not content:
        return None
    return content.get("join_rule")


def is_public_channel(join_rule: str | None) -> bool:
    return join_rule == "public"


def is_membership_leave(event_type: str, content: dict) -> bool:
    """Событие членства, лишающее доступа: отписка (leave) или бан (ban).

    Бан здесь равен уходу: забаненный в канале не должен оставаться в
    привязанном чате обсуждения. Копия семантики
    channel_stories._logic.is_channel_leave.
    """
    return event_type == "m.room.member" and content.get("membership") in (
        "leave",
        "ban",
    )


def discussion_settings_for(channel_join_rule: str | None) -> dict:
    """Настройки привязанного чата под приватность канала.

    Открытый канал: чат public + world_readable — комментарии видны без
    членства (peek), войти можно самому при первой отправке. Закрытый:
    invite + shared, членство раздаёт авто-инвайт при join в канал.

    Любое НЕизвестное правило (knock/restricted/None) трактуем как закрытый
    канал: ошибка в сторону приватности не раскрывает чужие комментарии.
    """
    if is_public_channel(channel_join_rule):
        return {"join_rule": "public", "history_visibility": "world_readable"}
    return {"join_rule": "invite", "history_visibility": "shared"}


def plan_discussion_migration(snapshot: dict) -> dict:
    """Что надо изменить в привязанном чате канала, чтобы он соответствовал
    целевой модели (см. docs/superpowers/specs/2026-07-24-channels-fixes-design.md,
    «Миграция существующих каналов»).

    Чистая функция: снимок состояния собирает вызывающий (модуль читает его из
    Synapse), решение принимается здесь и тестируется без Synapse.

    Ключи снимка: channel_join_rule, discussion_join_rule,
    discussion_history_visibility, discussion_hidden, channel_members,
    discussion_members (join + invite привязанного чата).

    Возвращает {"set_join_rule", "set_history_visibility", "set_hidden",
    "invite"}; уже правильное — None/False/[], поэтому повторный прогон не
    порождает записей (идемпотентность считается ЗДЕСЬ, а не в вызывающем).
    """
    wanted = discussion_settings_for(snapshot.get("channel_join_rule"))

    set_join_rule = (
        wanted["join_rule"]
        if snapshot.get("discussion_join_rule") != wanted["join_rule"]
        else None
    )
    set_history = (
        wanted["history_visibility"]
        if snapshot.get("discussion_history_visibility")
        != wanted["history_visibility"]
        else None
    )

    # Чаты, созданные до этой ветки, топологию не несут вовсе: без неё
    # isHiddenChat=False, и обсуждение вылезает отдельной строкой в списке
    # чатов у каждого, кого доинвайтили. hidden:true — «скрыто у всех по
    # умолчанию»; персональное раскрытие живёт в room account data и этой
    # простановкой не затрагивается.
    set_hidden = snapshot.get("discussion_hidden") is not True

    # Инвайты нужны только ЗАКРЫТОМУ каналу: у открытого чат public и
    # подписчик войдёт сам при первой отправке комментария.
    invite: list[str] = []
    if not is_public_channel(snapshot.get("channel_join_rule")):
        # discussion_members включает и join, и invite: приглашённого, но ещё
        # не принявшего инвайт повторно звать нельзя — Synapse дубликат не
        # отклоняет, а переиздаёт m.room.member, и живой человек получает
        # второе уведомление при каждом рестарте Synapse.
        already = set(snapshot.get("discussion_members") or ())
        invite = [m for m in (snapshot.get("channel_members") or ()) if m not in already]

    return {
        "set_join_rule": set_join_rule,
        "set_history_visibility": set_history,
        "set_hidden": set_hidden,
        "invite": invite,
    }


def plan_is_noop(plan: dict) -> bool:
    """True, если по плану делать нечего — канал уже мигрирован."""
    return (
        plan["set_join_rule"] is None
        and plan["set_history_visibility"] is None
        and not plan["set_hidden"]
        and not plan["invite"]
    )
