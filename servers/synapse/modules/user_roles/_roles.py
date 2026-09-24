"""Role constants. Note: legitimate roles live in user_roles_catalog table."""

from collections.abc import Mapping

DEFAULT_ROLE = "user"
ACCOUNT_DATA_TYPE = "com.liza.user_role"
ADMIN_ROLE = "admin"

# Персональные дополнительные роли поверх основной (напр. владельцу — admin +
# developer). Поле есть только у тех, кому его явно выставили PUT-ом; у всех
# остальных записи и ответы API не меняются. Видно всем, кто читает роль
# (GET/batch/to-device/федерация), — как и основная роль, это не секрет.
EXTRA_ROLES_KEY = "extra_roles"


def stored_extra_roles(data) -> list[str]:
    """extra_roles из account_data; Synapse отдаёт списки замороженными в tuple."""
    raw = data.get(EXTRA_ROLES_KEY) if isinstance(data, Mapping) else None
    if not isinstance(raw, (list, tuple)):
        return []
    return [r for r in raw if isinstance(r, str) and r]


def with_extra_roles(view, extras: list[str]):
    """Catalog view + extra_roles; без доп. ролей — view как есть (прежний контракт)."""
    if not isinstance(view, Mapping) or not extras:
        return view
    return {**view, EXTRA_ROLES_KEY: list(extras)}
