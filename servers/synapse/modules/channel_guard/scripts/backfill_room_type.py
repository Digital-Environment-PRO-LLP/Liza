"""Одноразовый бэкфилл: проставляет room_stats_state.room_type каналам,
созданным ДО появления пометки в channel_guard (mark_channel_room_type).

Зачем: /publicRooms отдаёт room_type из room_stats_state (см.
storage/databases/main/room.py, get_room_with_stats_txn), а Liza-тип канала
живёт в m.room.create -> content['com.liza.chat.type']. Без пометки
публичный канал неотличим от публичного чата в каталоге, и клиент не может
развести их по разделам «Публичные чаты» / «Публичные каналы».

Почему правим room_stats_state, а НЕ m.room.create: create-событие в Matrix
неизменяемо (подписано, входит в auth chain). Пометить существующую комнату
можно только в производной таблице статистики — её Synapse и отдаёт наружу.

Запуск ВНУТРИ контейнера Synapse (там доступен Postgres по сети):

    docker exec matrix-synapse-nadezhda python -m \
        synapse_modules.channel_guard.scripts.backfill_room_type \
        --pg "host=postgres-nadezhda dbname=synapse_nadezhda user=... password=..." \
        [--dry-run]

Идемпотентен: комнаты с уже заданным room_type не трогает.
"""

import argparse
import logging
import sys

logger = logging.getLogger(__name__)

LIZA_CHANNEL_ROOM_TYPE = "com.liza.channel"

# Каналы без room_type. jsonb-извлечение, а не LIKE: формат JSON
# (пробелы после двоеточия) в event_json не гарантирован.
FIND_SQL = """
    SELECT cse.room_id
    FROM current_state_events cse
    JOIN event_json ej ON ej.event_id = cse.event_id
    LEFT JOIN room_stats_state rss ON rss.room_id = cse.room_id
    WHERE cse.type = 'm.room.create'
      AND cse.state_key = ''
      AND (ej.json::jsonb -> 'content' ->> 'com.liza.chat.type') = 'channel'
      AND (rss.room_type IS NULL OR rss.room_type = '')
"""

UPDATE_SQL = """
    UPDATE room_stats_state SET room_type = %s WHERE room_id = %s
"""


def find_channels_without_room_type(cursor) -> list[str]:
    cursor.execute(FIND_SQL)
    return [row[0] for row in cursor.fetchall()]


def backfill(cursor, room_ids: list[str], dry_run: bool) -> int:
    if dry_run:
        return 0
    updated = 0
    for room_id in room_ids:
        cursor.execute(UPDATE_SQL, (LIZA_CHANNEL_ROOM_TYPE, room_id))
        updated += cursor.rowcount
    return updated


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pg", required=True, help="строка подключения psycopg2")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="только показать, что было бы помечено",
    )
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(message)s")

    import psycopg2

    conn = psycopg2.connect(args.pg)
    try:
        with conn.cursor() as cursor:
            room_ids = find_channels_without_room_type(cursor)
            if not room_ids:
                logger.info("Каналов без room_type не найдено — бэкфилл не нужен.")
                return 0

            logger.info("Каналов без room_type: %d", len(room_ids))
            for room_id in room_ids:
                logger.info("  %s", room_id)

            if args.dry_run:
                logger.info("--dry-run: изменения НЕ применены.")
                return 0

            updated = backfill(cursor, room_ids, dry_run=False)
            conn.commit()
            logger.info("Помечено комнат: %d (room_type=%s)", updated, LIZA_CHANNEL_ROOM_TYPE)
    finally:
        conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
