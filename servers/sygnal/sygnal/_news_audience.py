# -*- coding: utf-8 -*-
# Liza-specific: адресная рассылка Liza News по платформам устройства.
# Спека — docs/superpowers/specs/2026-09-21-liza-news-platform-audience-design.md.
#
# Пост канала несёт content["com.liza.news.audience"] = {"platforms": [...]}.
# Sygnal видит платформу КАЖДОГО устройства (pusher'а) и не шлёт пуш туда, где её
# нет в списке. Решение «не слать» ОБЯЗАНО оставаться вне `rejected`: pushkey в
# rejected Synapse понимает как «pusher мёртв» и удаляет его — устройство
# онемеет навсегда (класс pusher_rechurn).
#
# Политика — fail-open: пуш режется ТОЛЬКО когда платформа устройства определена
# и её явно нет в аудитории. Всё неопознанное (легаси-pusher без client_name,
# второй аккаунт «Liza-<ms>», битая метка) — доставляется.

from typing import Any, Dict, FrozenSet, Optional

from sygnal.notifications import Device, Notification

AUDIENCE_KEY = "com.liza.news.audience"
PLATFORMS = frozenset({"ios", "macos", "android"})
# Apple-устройство, у которого iOS от macOS не отличить: легаси app_id
# com.prodamus.laba.liza (один APNs topic на обе ОС) без client_name.
APPLE_UNKNOWN = "apple"

# Метку честим только от бота Liza News: иначе любой участник чата мог бы
# приложить её к своему сообщению и заглушить собеседникам пуши на iPhone.
NEWS_SENDERS = frozenset({"@liza-news:bots.liza.ru"})


def audience_platforms(n: Notification) -> Optional[FrozenSet[str]]:
    """Платформы из метки поста; None — метки нет или она невалидна (= всем)."""
    if n.sender not in NEWS_SENDERS or not isinstance(n.content, dict):
        return None
    audience = n.content.get(AUDIENCE_KEY)
    if not isinstance(audience, dict):
        return None
    raw = audience.get("platforms")
    if not isinstance(raw, list):
        return None
    platforms = frozenset(
        p.lower() for p in raw if isinstance(p, str) and p.lower() in PLATFORMS
    )
    # Пустой/сплошь неизвестный список — скорее ошибка разметки, чем «никому».
    return platforms or None


def _platform_from_client_name(client_name: Any) -> Optional[str]:
    # PlatformInfos.clientName: «Liza ios», «Liza macosDebug». Второй аккаунт на
    # устройстве называется «Liza-<ms>» — платформы там нет.
    if not isinstance(client_name, str):
        return None
    parts = client_name.split(" ")
    if len(parts) != 2:
        return None
    os_name = parts[1].lower()
    if os_name.endswith("debug"):
        os_name = os_name[: -len("debug")]
    return os_name if os_name in PLATFORMS else None


def device_platform(device: Device) -> Optional[str]:
    """ios | macos | android | apple (iOS или macOS) | None (неизвестно)."""
    data: Dict[str, Any] = device.data or {}
    payload = data.get("default_payload")
    payload = payload if isinstance(payload, dict) else {}

    explicit = payload.get("platform")
    if isinstance(explicit, str) and explicit.lower() in PLATFORMS:
        return explicit.lower()

    if device.app_id.endswith(".data_message") or data.get("data_message") == "android":
        return "android"

    from_name = _platform_from_client_name(payload.get("client_name"))
    if from_name is not None:
        return from_name

    if data.get("data_message") == "ios":
        return APPLE_UNKNOWN
    return None


def should_skip(n: Notification, device: Device) -> Optional[str]:
    """Платформа устройства, если пуш ему по аудитории НЕ положен; иначе None."""
    audience = audience_platforms(n)
    if audience is None:
        return None
    platform = device_platform(device)
    if platform is None:
        return None
    if platform == APPLE_UNKNOWN:
        return None if audience & {"ios", "macos"} else platform
    return None if platform in audience else platform
