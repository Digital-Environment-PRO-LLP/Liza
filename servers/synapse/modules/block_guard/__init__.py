"""Synapse-модуль: реальная блокировка пользователя (LABA-2545).

Заблокированный (тот, кого держат в m.ignored_user_list) не может:
- создать ЛИЧНЫЙ чат с блокирующим (on_create_room — отказ ДО создания комнаты,
  поэтому комнат-сирот не остаётся);
- пригласить его в личный чат и писать ему в существующем личном чате
  (check_event_allowed).

Отказ — 403 со СВОИМ errcode и русским текстом: третьи-party-rules колбэки
единственные, где апстрим явно разрешает пробрасывать SynapseError
(third_party_event_rules_callbacks.py:294-306 «relied upon by some modules»),
поэтому текст доезжает до пользователя даже на уже установленной сборке.

Чего модуль НЕ делает (осознанно, см. спеку):
- не регистрирует user_may_join_room — иначе сломается force-join публичного
  канала liza_news (RL-liza-news-forcejoin-dedup);
- не регистрирует spam-checker: check_event_for_spam на входящей федеративной
  PDU делает prune_event + soft-fail, т.е. НЕОБРАТИМО срезает содержимое у
  получателя при любом ложном срабатывании (federation_base.py:182-197);
- не трогает группы, каналы, пространства, сторис и служебные аккаунты;
- не блокирует обратное направление (блокирующий писать может).

Ограничение (честное): энфорс работает, когда обе стороны на ОДНОМ хоумсервере.
На федерации third-party rules для входящих сообщений и инвайтов не вызываются
вовсе (federation_event.py:451-461 — только knock). Пуш-«призрак» при этом
закрыт отдельно, в push/bulk_push_rule_evaluator.py (см. _logic.should_notify_invite).

Конфигурация в homeserver.yaml:

    modules:
      - module: synapse_modules.block_guard.BlockGuardModule
        config:
          enabled: true                       # рубильник отката без снятия модуля
          service_localparts: [liza, support] # переопределяет дефолт из _logic
"""

import logging
from typing import Any

from ._logic import (
    BLOCKED_ERRCODE,
    BLOCKED_MESSAGE,
    CREATE_EVENT_TYPE,
    CHAT_TYPE_KEY,
    DEFAULT_SERVICE_LOCALPARTS,
    DIRECT_ACCOUNT_DATA,
    IGNORED_USER_LIST,
    LEGACY_STORIES_KEY,
    MEMBER_EVENT_TYPE,
    TOPOLOGY_STATE_TYPE,
    USER_ROLE_ACCOUNT_DATA,
    blocked_invitees,
    dm_counterpart,
    ignores,
    is_blockable_event_type,
    is_exempt_room,
    is_service_localpart,
    room_is_direct_for,
)

logger = logging.getLogger(__name__)


def _blocked_error() -> Exception:
    """Отказ 403 с нашим errcode и русским текстом.

    `SynapseError` импортируется ЛЕНИВО, чтобы пакет оставался импортируемым без
    установленного Synapse — тогда тесты модуля гоняются локально (тот же приём,
    что делает knock_notify синапс-независимым; тесты channel_guard, который
    импортирует synapse на уровне файла, локально не собираются вовсе).
    В контейнере (`/editable-src`) импорт всегда доступен.
    """
    from synapse.api.errors import SynapseError

    return SynapseError(403, BLOCKED_MESSAGE, BLOCKED_ERRCODE)


class BlockGuardModule:
    def __init__(self, config: dict[str, Any], api: Any) -> None:
        self._api = api
        self._enabled = bool(config.get("enabled", True))
        self._service_localparts = tuple(
            config.get("service_localparts", DEFAULT_SERVICE_LOCALPARTS)
        )

        api.register_third_party_rules_callbacks(
            on_create_room=self._on_create_room,
            check_event_allowed=self._check_event_allowed,
        )

        logger.info(
            "BlockGuardModule loaded (enabled=%s, service_localparts=%s)",
            self._enabled,
            ",".join(self._service_localparts),
        )

    # ── чтение account data ────────────────────────────────────────────────

    async def _get_global(self, user_id: str, data_type: str) -> Any:
        """Публичный ModuleApi (под @cached в store). Ошибку глушим в None:
        отсутствие данных должно вести к fail-open, а не к отказу отправки."""
        try:
            return await self._api.account_data_manager.get_global(user_id, data_type)
        except Exception:
            logger.warning(
                "block_guard: не прочитал %s у %s", data_type, user_id, exc_info=True
            )
            return None

    async def _ignores(self, owner: str, candidate: str) -> bool:
        """Держит ли owner пользователя candidate в своём чёрном списке.

        Реверс-лукап («кто игнорирует отправителя») не нужен: адресат в личном
        чате ровно один, поэтому хватает публичного чтения ЕГО списка. Для
        удалённого owner список недоступен — его сторону обслуживает его сервер.
        """
        if not self._api.is_mine(owner):
            return False
        return ignores(await self._get_global(owner, IGNORED_USER_LIST), candidate)

    async def _is_service_account(self, user_id: str) -> bool:
        """Служебный аккаунт: известный localpart либо роль ai в user_roles.

        Зеркало stories_membership._is_ai_user. Без этого блокировка @liza
        оставила бы пользователя без ассистента, а @support — без заявок.
        """
        if is_service_localpart(user_id, self._service_localparts):
            return True
        if not self._api.is_mine(user_id):
            return False
        data = await self._get_global(user_id, USER_ROLE_ACCOUNT_DATA)
        return bool(data) and data.get("role") == "ai"

    # ── колбэки ────────────────────────────────────────────────────────────

    async def _on_create_room(
        self, requester: Any, config: dict, is_requester_admin: bool
    ) -> None:
        """Отказ на создание ЛИЧНОГО чата с тем, кто тебя заблокировал.

        Вызывается на handlers/room.py:1112 — ДО _send_events_for_new_room,
        поэтому при отказе комната не создаётся (инвайты рассылаются позже, на
        room.py:1332-1350, и отказ там оставил бы комнату-сироту).

        is_requester_admin намеренно НЕ даёт байпаса: блокировка — решение
        пользователя, а не вопрос прав администратора сервера.
        """
        if not self._enabled or not config.get("is_direct"):
            return
        creator = requester.user.to_string()
        if await self._is_service_account(creator):
            return

        invites = config.get("invite")
        if not isinstance(invites, list):
            return
        lookup = {
            invitee: await self._ignores(invitee, creator)
            for invitee in invites
            if isinstance(invitee, str)
        }
        blocked = blocked_invitees(config, lookup)
        if not blocked:
            return

        logger.info(
            "block_guard: создание личного чата %s -> %s отклонено (блокировка)",
            creator,
            ",".join(blocked),
        )
        raise _blocked_error()

    async def _check_event_allowed(
        self, event: Any, state_events: Any
    ) -> tuple[bool, dict | None]:
        """Отказ на личный инвайт и на сообщения заблокированному.

        Порядок проверок — от бесплатного к дорогому (тип события → is_mine →
        топология комнаты → служебный аккаунт → парность → чёрный список →
        m.direct). Колбэк исполняется на КАЖДОМ локально создаваемом событии
        (handlers/message.py:1386, create_new_client_event), поэтому ранние
        выходы обязательны. Событие не мутируется: во всех allow-ветках
        возвращаем (True, None).
        """
        if not self._enabled:
            return True, None
        if not is_blockable_event_type(event.type, event.content):
            return True, None
        if not self._api.is_mine(event.sender):
            return True, None
        if self._is_exempt_room(state_events):
            return True, None
        if await self._is_service_account(event.sender):
            return True, None

        if event.type == MEMBER_EVENT_TYPE:
            target = event.state_key
            if not target or await self._is_service_account(target):
                return True, None
            if not await self._ignores(target, event.sender):
                return True, None
            logger.info(
                "block_guard: личный инвайт %s -> %s отклонён (блокировка)",
                event.sender,
                target,
            )
            raise _blocked_error()

        counterpart = dm_counterpart(self._members(state_events), event.sender)
        if counterpart is None or await self._is_service_account(counterpart):
            return True, None
        if not await self._ignores(counterpart, event.sender):
            return True, None
        if not await self._is_direct_room(event.room_id, event.sender, counterpart):
            # Парная комната, не числящаяся личным чатом ни у одной стороны
            # (схлопнувшаяся группа, комната заявки) — fail-open: рвать чужую
            # переписку хуже, чем пропустить редкий краевой случай.
            return True, None

        logger.info(
            "block_guard: сообщение %s -> %s отклонено (блокировка)",
            event.sender,
            counterpart,
        )
        raise _blocked_error()

    # ── помощники по состоянию комнаты ─────────────────────────────────────

    @staticmethod
    def _members(state_events: Any) -> list[tuple[str, str]]:
        """[(user_id, membership)] из state_events колбэка."""
        members: list[tuple[str, str]] = []
        if not state_events:
            return members
        for key, ev in state_events.items():
            if not isinstance(key, tuple) or key[0] != MEMBER_EVENT_TYPE:
                continue
            content = getattr(ev, "content", None) or {}
            membership = content.get("membership")
            if isinstance(key[1], str) and isinstance(membership, str):
                members.append((key[1], membership))
        return members

    def _is_exempt_room(self, state_events: Any) -> bool:
        """Пространство / канал / сторис / скрытая комната — вне энфорса."""
        create = self._state(state_events, CREATE_EVENT_TYPE)
        topology = self._state(state_events, TOPOLOGY_STATE_TYPE)
        create_content = getattr(create, "content", None) or {}
        return is_exempt_room(
            create_content.get("type"),
            create_content.get(CHAT_TYPE_KEY),
            getattr(topology, "content", None),
            legacy_stories=bool(create_content.get(LEGACY_STORIES_KEY)),
        )

    @staticmethod
    def _state(state_events: Any, event_type: str) -> Any:
        if not state_events:
            return None
        return state_events.get((event_type, ""))

    async def _is_direct_room(
        self, room_id: str, sender: str, counterpart: str
    ) -> bool:
        """Личный чат по m.direct ЛЮБОЙ из сторон.

        Достаточно одной записи: отправитель почти наверняка держит комнату в
        своём m.direct, даже если получатель её туда не добавил.
        """
        for user_id in (counterpart, sender):
            if not self._api.is_mine(user_id):
                continue
            direct = await self._get_global(user_id, DIRECT_ACCOUNT_DATA)
            if room_is_direct_for(direct, room_id):
                return True
        return False
