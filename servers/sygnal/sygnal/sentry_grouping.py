"""Группировка Sentry-событий Sygnal по КЛАССУ ошибки, а не по идентификатору.

⚠ Зачем (прод-факт 2026-09-08). В GlitchTip у проекта `sygnal` за 30 дней
накопилось **1193 issue при 1193 событиях** — то есть каждая ошибка порождала
НОВУЮ issue со счётчиком 1. Причина в высокоэнтропийном идентификаторе внутри
самого текста сообщения:

* `NotificationLoggerAdapter.process` (`utils.py`) клеит `[{request_id}] ` в
  начало КАЖДОЙ строки лога;
* строки вида `Status of notification <uuid> is 400 (BadDeviceToken)` несут наш
  `notification_id` (см. `apnspushkin.py`, `NotificationRequest(...)`).

Последствия были не косметические:

1. **alert-правило GlitchTip недостижимо в принципе.** Порог «5 событий за 10
   минут НА ISSUE» не может сработать, если каждая issue живёт со счётчиком 1 —
   поэтому за всю историю проекта в чат не ушло ни одного уведомления. Реальный
   ~7-часовой сбой провайдер-токена APNs 2026-08-11 (1059 ошибок) прошёл
   незамеченным именно так.
2. **Темп не виден.** «BadDeviceToken случился 121 раз» не отображалось нигде:
   вместо счётчика были 121 отдельная issue.
3. **Дедуп notifier'а расклеивался.** Ключ `room|title` уникален на каждое
   событие, поэтому антифлуд не схлопывал ничего.

Лечим У ИСТОЧНИКА, а не порогом ниже по течению: идентификатор уходит в ТЕГИ
(диагностика сохраняется — по нему ищут в логах и в поддержке Apple), а в тексте
остаётся стабильный класс. Это ровно то, чего не хватало дефолтному
`sentry_sdk.init(dsn)` — он шёл без `before_send` и без `fingerprint`.
"""
import re
from typing import Any, Dict, Optional, Tuple

# `[abc123] сообщение` — префикс NotificationLoggerAdapter.
_REQUEST_ID_PREFIX_RE = re.compile(r"^\[([^\]]{1,64})\]\s*")
_UUID_RE = re.compile(
    r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
)
# Длинные hex-строки (device-токены APNs, идентификаторы) — тоже энтропия.
_LONG_HEX_RE = re.compile(r"\b[0-9a-fA-F]{16,}\b")


def split_request_id(message: str) -> Tuple[Optional[str], str]:
    """`[rid] текст` → `("rid", "текст")`. Без префикса → `(None, текст)`."""
    match = _REQUEST_ID_PREFIX_RE.match(message or "")
    if not match:
        return None, message or ""
    return match.group(1), message[match.end():]


def normalize_message(message: str) -> str:
    """Текст, приведённый к КЛАССУ: идентификаторы → плейсхолдеры.

    Консервативно: трогаем только заведомо-энтропийные формы. Осмысленные части
    (код статуса, причина APNs, имя pushkin'а) обязаны остаться — по ним
    и различаются классы, ради которых всё делается.
    """
    _, body = split_request_id(message or "")
    body = _UUID_RE.sub("<uuid>", body)
    return _LONG_HEX_RE.sub("<hex>", body)


def render_logentry(logentry: Dict[str, Any]) -> str:
    """Текст события как его увидит GlitchTip: `message % params`.

    ⚠ Боевой эмитент логирует ЛЕНИВО (`logger.warning("… %s …", nid, status)`),
    и `sentry_sdk.integrations.logging` кладёт в `logentry` ШАБЛОН плюс отдельный
    `params`, БЕЗ ключа `formatted`. Без рендера нормализация видит шаблон, в
    котором идентификаторов нет вовсе: она вырождается в no-op, а весь класс
    ошибок схлопывается в ОДИН fingerprint (400/403/410 неразличимы), тогда как
    заголовок в GlitchTip всё равно несёт uuid — тот сам подставляет `params`.
    Рассогласованный шаблон не имеет права ронять отправку: before_send стоит на
    горячем пути, поэтому при любой ошибке форматирования возвращаем шаблон.
    """
    message = logentry.get("message")
    if not isinstance(message, str):
        return ""
    params = logentry.get("params")
    if not params:
        return message
    try:
        return message % (params if isinstance(params, dict) else tuple(params))
    except (TypeError, ValueError, KeyError):
        return message


def before_send(event: Dict[str, Any], hint: Any = None) -> Dict[str, Any]:
    """Схлопнуть событие к классу, сохранив идентификатор в тегах."""
    logentry = event.get("logentry")
    raw = ""
    if isinstance(logentry, dict):
        raw = render_logentry(logentry)
    elif isinstance(event.get("message"), str):
        raw = event["message"]

    if raw:
        request_id, _ = split_request_id(raw)
        normalized = normalize_message(raw)
        if request_id:
            event.setdefault("tags", {}).setdefault("request_id", request_id)
        if normalized != raw:
            # Идентификатор не теряем: полный текст остаётся в extra.
            event.setdefault("extra", {}).setdefault("raw_message", raw)
        if isinstance(logentry, dict):
            logentry["message"] = normalized
            # Аргументы гасим: они уже вклеены в `normalized`, а оставленный
            # `params` заставил бы GlitchTip отрендерить шаблон повторно и вернуть
            # идентификатор в ЗАГОЛОВОК issue — то есть воскресить кардинальность.
            if logentry.get("params"):
                logentry["params"] = []
            if isinstance(logentry.get("formatted"), str):
                logentry["formatted"] = normalize_message(logentry["formatted"])
        else:
            event["message"] = normalized

    # Явный fingerprint: группировка по классу, а не по тексту с идентификатором.
    fingerprint_source = normalize_message(raw) if raw else ""
    if fingerprint_source:
        event["fingerprint"] = ["sygnal", event.get("logger") or "", fingerprint_source]
    return event


def before_breadcrumb(crumb: Dict[str, Any], hint: Any = None) -> Dict[str, Any]:
    """Крошки уезжают прицепом к событию — нормализуем и их (в т.ч. device-токены,
    которые `apnspushkin` печатает на INFO при реджекте)."""
    if isinstance(crumb.get("message"), str):
        crumb["message"] = normalize_message(crumb["message"])
    return crumb
