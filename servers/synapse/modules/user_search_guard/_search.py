"""Чистые предикаты поиска пользователей.

Без импортов synapse — модуль грузится в тестах напрямую по пути,
без живого HomeServer.
"""

# Федеративный веер запускаем от 2 символов: на 1 символ ответ слишком
# шумный, а соседей пришлось бы дёргать на каждую букву.
MIN_FEDERATED_QUERY_LEN = 2


def normalize(text: str) -> str:
    """casefold + схлопывание пробелов. Для сравнения имён."""
    return " ".join(text.split()).casefold()


def matches_prefix(display_name: str | None, user_id: str, query: str) -> bool:
    """True, если query — префикс любого слова имени или localpart.

    Именно префикс, а не подстрока: поиск «с первых символов» не должен
    выдавать всех, у кого запрос встретился в середине слова.
    """
    if not query:
        return False
    q = normalize(query)

    if display_name:
        for word in normalize(display_name).split():
            if word.startswith(q):
                return True

    localpart = user_id[1:].split(":", 1)[0] if user_id.startswith("@") else user_id
    return normalize(localpart).startswith(q)


def is_own_domain(user_id: str, server_name: str) -> bool:
    """Принадлежит ли MXID нашему серверу."""
    return bool(user_id) and user_id.endswith(":" + server_name)


def belongs_to_domain(user_id: str, destination: str) -> bool:
    """Анти-spoofing: сосед вправе отдавать только своих пользователей.

    Без этой проверки чужой инстанс мог бы вернуть @admin:наш.домен и
    подменить собой локального пользователя в выдаче.
    """
    return bool(user_id) and user_id.startswith("@") and user_id.endswith(":" + destination)


def deduplicate_users(users: list[dict]) -> list[dict]:
    """Дедупликация по user_id, порядок сохраняется (первый выигрывает)."""
    seen: set[str] = set()
    result: list[dict] = []
    for u in users:
        uid = u.get("user_id")
        if not uid or uid in seen:
            continue
        seen.add(uid)
        result.append(u)
    return result
