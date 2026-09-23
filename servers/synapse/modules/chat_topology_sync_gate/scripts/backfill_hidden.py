"""Одноразовый бэкфилл: проставляет com.liza.chat.topology {hidden: true}
на существующие сторис-комнаты (creation_content['com.liza.stories']==true
или creation_content['com.liza.chat.type']=='stories'), у которых ещё нет
этого state event. См. design doc, секция 5.

Запуск ВНУТРИ контейнера Synapse (там доступны и модуль, и localhost:8008,
и Postgres по сети), по образцу instances/dev-liza-laba/src/reset_password.py:

    docker exec matrix-synapse-dev-liza-laba python -m \
        synapse_modules.chat_topology_sync_gate.scripts.backfill_hidden \
        --server http://localhost:8008 \
        --pg "host=... dbname=synapse user=synapse password=..." \
        --admin-user @admin:<host> \
        [--admin-token syt_...] [--dry-run]

Комнаты ищутся прямым SQL к Postgres (find_legacy_stories_rooms — тот же
предикат, что HiddenRoomsLookup и клиентский isHiddenChat). Отправка state
идёт через Admin API make_room_admin (даёт админу PL в чужой комнате) +
обычный client PUT .../state/com.liza.chat.topology, плюс поднятие
m.room.power_levels events['com.liza.chat.topology']=100 (PL-гейт, чтобы
рядовой участник не снял hidden — design doc секция 1).
"""

import argparse
import asyncio
import json
import logging
import sys
from typing import Any, Awaitable, Callable, NamedTuple, Sequence
from urllib.parse import quote

logger = logging.getLogger(__name__)


class LegacyStoriesRoom(NamedTuple):
    room_id: str
    has_topology_state: bool


def needs_backfill(row: Any) -> bool:
    return not row.has_topology_state


async def find_legacy_stories_rooms(db_pool: Any) -> list[LegacyStoriesRoom]:
    """Комнаты с creation_content содержащим 'com.liza.stories': true,
    и факт наличия/отсутствия com.liza.chat.topology state event для
    каждой.

    Двухшаговый алгоритм (portable SQLite + Postgres, без LIKE по JSON):
    1. Найти m.room.create события, распарсить event_json.json на Python
       и проверить content['com.liza.stories'] - как в
       stories_membership/__init__.py:_find_expired_stories_txn (334-360),
       где явно задокументировано, что LIKE по JSON ненадёжен (форк
       Synapse сериализует событие компактно, separators=(",", ":"), без
       пробела после двоеточия - "com.liza.stories":true, а не
       "com.liza.stories": true - LIKE-паттерн с пробелом не матчит
       реальные данные).
    2. Для каждой найденной комнаты - EXISTS-проверка com.liza.chat.topology
       в current_state_events (это не JSON-поиск, обычный SQL, LIKE тут не
       нужен и не использовался)."""

    def _find(txn: Any) -> list[LegacyStoriesRoom]:
        txn.execute(
            """
            SELECT cs.room_id, ej.json
            FROM current_state_events cs
            JOIN event_json ej ON ej.event_id = cs.event_id
            WHERE cs.type = 'm.room.create' AND cs.state_key = ''
            """
        )
        stories_room_ids: list[str] = []
        for room_id, raw_json in txn.fetchall():
            try:
                event = json.loads(raw_json)
                content = event.get("content") or {}
            except (TypeError, ValueError):
                continue
            if content.get("com.liza.stories") or content.get(
                "com.liza.chat.type"
            ) == "stories":
                stories_room_ids.append(room_id)

        result: list[LegacyStoriesRoom] = []
        for room_id in stories_room_ids:
            txn.execute(
                """
                SELECT 1 FROM current_state_events
                WHERE room_id = ? AND type = 'com.liza.chat.topology' AND state_key = ''
                """,
                (room_id,),
            )
            has_topology_state = txn.fetchone() is not None
            result.append(LegacyStoriesRoom(room_id, has_topology_state))
        return result

    return await db_pool.runInteraction("chat_topology_backfill_find", _find)


async def run_backfill(
    rooms: Sequence[Any],
    send_topology_state: Callable[[str, str], Awaitable[None]],
    system_user_id: str,
    dry_run: bool,
) -> int:
    sent_count = 0
    for row in rooms:
        if not needs_backfill(row):
            continue
        logger.info(
            "backfill: room=%s dry_run=%s", row.room_id, dry_run
        )
        if not dry_run:
            await send_topology_state(row.room_id, system_user_id)
            sent_count += 1
    return sent_count


class _PsycopgDbPool:
    """Минимальный db_pool-адаптер поверх psycopg2 для find_legacy_stories_rooms.

    Даёт ровно то, что использует эта функция: engine.is_postgres и
    runInteraction(desc, fn, *args), где fn получает cursor с методами
    execute/fetchall/fetchone. Плейсхолдер '?' в SQL находки заменяем на
    '%s' (psycopg2 paramstyle) через обёртку курсора.
    """

    class _Engine:
        is_postgres = True

    def __init__(self, dsn: str) -> None:
        import psycopg2  # доступен в venv Synapse

        self.engine = self._Engine()
        self._conn = psycopg2.connect(dsn)

    async def runInteraction(self, _desc: str, fn: Callable, *args: Any) -> Any:
        cur = self._conn.cursor()

        class _Cur:
            def execute(self, sql: str, params: Sequence[Any] = ()) -> None:
                cur.execute(sql.replace("?", "%s"), params)

            def fetchall(self) -> list:
                return cur.fetchall()

            def fetchone(self) -> Any:
                return cur.fetchone()

        try:
            result = fn(_Cur(), *args)
            self._conn.commit()
            return result
        finally:
            cur.close()

    def close(self) -> None:
        self._conn.close()


def _make_send_topology_state(
    server_url: str, admin_token: str
) -> Callable[[str, str], Awaitable[None]]:
    """send_topology_state(room_id, sender): даёт админу PL в чужой
    (invite-only) комнате через Admin make_room_admin (который сам инвайтит
    его, если не в комнате — rooms.py:757-785), затем обычным client join
    принимает инвайт, поднимает PL-гейт на topology-событие и шлёт сам
    com.liza.chat.topology {hidden: true}.

    Все client-события идут ОТ ИМЕНИ АДМИНА (masquerade ?user_id= недоступен
    обычному admin-токену — только для application service). Поэтому sender
    здесь и есть admin-user.

    Найдено на реальном прогоне на dev: Admin join (JoinRoomAliasServlet)
    сам по себе НЕ годится — он шлёт invite от лица requester-а, а если
    requester ещё не в комнате, инвайт падает 403 "not in room" (тот же
    источник прав, что и на message send). make_room_admin — единственный
    admin-примитив, который может добавить постороннего в приватную комнату
    (он подписывает invite от лица уже состоящего владельца), но сам
    оставляет админа в статусе invite, не join (rooms.py:778-783: action=
    INVITE, не JOIN) — отсюда обязательный client join вторым шагом."""
    import requests

    headers = {"Authorization": f"Bearer {admin_token}"}

    async def _send(room_id: str, sender: str) -> None:
        rid = quote(room_id, safe="")

        # 1. make_room_admin — даёт админу PL 100 и инвайтит его в комнату,
        # если он там ещё не состоит (идемпотентно: повторный вызов, когда
        # он уже join/invite с нужным PL, безвреден).
        r = requests.post(
            f"{server_url}/_synapse/admin/v1/rooms/{rid}/make_room_admin",
            headers=headers,
            json={},
            timeout=30,
        )
        if r.status_code not in (200, 400):
            # 400 бывает, когда админ уже в комнате с нужным PL — не ошибка.
            r.raise_for_status()

        # 2. Обычный client join — принимает инвайт от шага 1. Если админ
        # уже join (повторный прогон), Synapse отдаёt 200 идемпотентно.
        requests.post(
            f"{server_url}/_matrix/client/v3/join/{rid}",
            headers=headers,
            json={},
            timeout=30,
        ).raise_for_status()

        # 3. PL-гейт: events['com.liza.chat.topology']=100. Читаем текущий
        # m.room.power_levels, мержим, пишем обратно (не затираем прочие PL).
        pl_get = requests.get(
            f"{server_url}/_matrix/client/v3/rooms/{rid}"
            f"/state/m.room.power_levels/",
            headers=headers,
            timeout=30,
        )
        pl = pl_get.json() if pl_get.status_code == 200 else {}
        events = dict(pl.get("events") or {})
        if events.get("com.liza.chat.topology") != 100:
            events["com.liza.chat.topology"] = 100
            pl["events"] = events
            requests.put(
                f"{server_url}/_matrix/client/v3/rooms/{rid}"
                f"/state/m.room.power_levels/",
                headers=headers,
                json=pl,
                timeout=30,
            ).raise_for_status()

        # 4. Сам topology state event (state_key="").
        requests.put(
            f"{server_url}/_matrix/client/v3/rooms/{rid}"
            f"/state/com.liza.chat.topology/",
            headers=headers,
            json={"hidden": True},
            timeout=30,
        ).raise_for_status()

    return _send


def _load_admin_token(explicit: str | None) -> str:
    if explicit:
        return explicit
    # По умолчанию — тот же admin.json, что и остальные скрипты (см.
    # server-access.md / user_roles/README.md).
    path = "/data/admin.json"
    try:
        with open(path) as f:
            return json.load(f)["access_token"]
    except (OSError, KeyError, ValueError) as e:
        raise SystemExit(
            f"не удалось прочитать admin token из {path}: {e}; "
            "передай --admin-token явно"
        )


async def _run(args: argparse.Namespace) -> int:
    db_pool = _PsycopgDbPool(args.pg)
    try:
        rooms = await find_legacy_stories_rooms(db_pool)
    finally:
        db_pool.close()

    to_do = [r for r in rooms if needs_backfill(r)]
    logger.info(
        "backfill: всего сторис-комнат=%d, без topology-state=%d, dry_run=%s",
        len(rooms), len(to_do), args.dry_run,
    )

    send = _make_send_topology_state(args.server, _load_admin_token(args.admin_token))
    sent = await run_backfill(
        rooms=rooms,
        send_topology_state=send,
        system_user_id=args.admin_user,
        dry_run=args.dry_run,
    )
    logger.info("backfill завершён: отправлено topology-событий=%d", sent)
    return sent


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(prog="backfill_hidden")
    parser.add_argument(
        "--server", default="http://localhost:8008",
        help="базовый URL Synapse (внутри контейнера — localhost:8008)",
    )
    parser.add_argument(
        "--pg", required=True,
        help="psycopg2 DSN до БД Synapse, например "
        "'host=matrix-postgres dbname=synapse user=synapse password=...'",
    )
    parser.add_argument(
        "--admin-user", required=True,
        help="Matrix ID админ-аккаунта, чей токен используется (@admin:<host>); "
        "от его имени make_room_admin наделяет PL и шлёт topology-события",
    )
    parser.add_argument(
        "--admin-token", default=None,
        help="access_token админа; по умолчанию — из /data/admin.json",
    )
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.INFO)
    sys.exit(0 if asyncio.run(_run(args)) >= 0 else 1)


if __name__ == "__main__":
    main()
