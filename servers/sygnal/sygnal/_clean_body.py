# -*- coding: utf-8 -*-
# Liza-specific: чистка m.room.message.body перед отправкой в push-payload.
# Сервис уведомлений (iOS NSE, macOS AppDelegate, Android pushHelper) кладёт
# этот текст напрямую в banner — без markdown-рендера и без знания о Matrix
# меншнах. Без чистки в push прилетают сырые reply-quote ("> <@user:server> ...")
# и mention-форматы (@[Имя] / @user:server).

import re
from typing import Any, Dict, Optional

_REPLY_LINE_RE = re.compile(r"^>\s.*(?:\r?\n|$)")
_MENTION_PILL_RE = re.compile(r"@\[([^\]]+)\]")
_MXID_RE = re.compile(r"@([a-zA-Z0-9._=/\-]+):[a-zA-Z0-9.\-]+")

# LABA-2238: у медиа `content.body` == имя файла (`recording…ogg`). Системные
# баннеры (iOS NSE, macOS AppDelegate, Android Doze-гибрид) кладут body напрямую
# в текст уведомления → показывали имя файла вместо «Голосовое сообщение».
_VOICE_KEY = "org.matrix.msc3245.voice"
_MEDIA_MSGTYPES = frozenset(
    {"m.image", "m.audio", "m.video", "m.file", "m.sticker"}
)

# LABA-1970: сторис публикуется как m.room.message с объектом com.liza.story в
# content. Пуш на публикацию показывает имя автора + «опубликовал историю»
# (муж. род без «(а)» — правило локализации проекта), а НЕ имя файла/room_name
# ("Stories - ivan"). Детект здесь — обычный Python-доступ к dict (ограничение
# rust-эвалюатора push-rules на матч по объекту тут не действует).
STORY_CONTENT_KEY = "com.liza.story"
STORY_PUBLISHED_BODY = "опубликовал историю"


def clean_message_body(body: str) -> str:
    """Прибирает m.room.message.body для отображения в push-уведомлении.

    Делает:
    - вырезает ведущий reply-fallback блок (строки, начинающиеся с "> "),
      плюс одну пустую строку-разделитель после него (MSC2781 fallback);
    - заменяет mention pill "@[Имя Фамилия]" на "Имя Фамилия";
    - заменяет MXID "@localpart:server" на "localpart" (без display name —
      Sygnal не имеет доступа к Matrix store, лучшее что мы можем).

    Возвращает исходную строку без изменений, если в ней нет ничего из
    перечисленного.
    """
    if not body:
        return body

    cleaned = body
    while True:
        match = _REPLY_LINE_RE.match(cleaned)
        if not match:
            break
        cleaned = cleaned[match.end():]
    # После блока quote обычно идёт пустая строка-разделитель — съедаем.
    if cleaned.startswith("\n"):
        cleaned = cleaned[1:]
    elif cleaned.startswith("\r\n"):
        cleaned = cleaned[2:]

    cleaned = _MENTION_PILL_RE.sub(lambda m: m.group(1), cleaned)
    cleaned = _MXID_RE.sub(lambda m: m.group(1), cleaned)

    return cleaned


def is_media_msgtype(content: Dict[str, Any]) -> bool:
    """Событие — медиа (image/audio/video/file/sticker)?"""
    return content.get("msgtype") in _MEDIA_MSGTYPES


def is_story(content: Any) -> bool:
    """Событие — публикация сторис (LABA-1970)? Маркер — объект com.liza.story."""
    return isinstance(content, dict) and isinstance(
        content.get(STORY_CONTENT_KEY), dict
    )


def media_caption(content: Dict[str, Any]) -> Optional[str]:
    """Реальная подпись медиа или None (если body == имя файла).

    Повторяет клиентскую логику `Event.fileDescription` (LABA-2238): у медиа
    `body` — это имя файла-фолбэк; реальная подпись есть, только если очищенный
    от reply-fallback `body` отличается от `filename`. При отсутствии поля
    `filename` (внешний/старый клиент) body трактуем как подпись — как и клиент.

    Ограничение: снятие reply-fallback опирается на `clean_message_body`, чей
    `_REPLY_LINE_RE` требует пробел после `>` (`> цитата`) — так строит Matrix
    Dart SDK (`room.dart`). Внешний клиент, приславший цитату БЕЗ пробела
    (`>цитата`), здесь не распознается → у медиа-ответа без подписи в Doze-баннер
    может попасть обрывок цитаты вместо строки-по-типу. Для нашего клиента не
    воспроизводится; ослаблять общий `_REPLY_LINE_RE` (его зовёт и текстовый путь)
    ради этого края не станем — иначе риск обрезать легитимный `>`-текст.
    """
    body = content.get("body")
    if not isinstance(body, str):
        return None
    cleaned = clean_message_body(body)
    if not cleaned:
        return None
    filename = content.get("filename")
    if isinstance(filename, str) and cleaned == filename:
        return None
    return cleaned


def media_type_label(content: Dict[str, Any]) -> str:
    """RU строка-по-типу для системного баннера (Android Doze-гибрид).

    iOS/macOS локализуют по `msgtype` нативно (NSE/AppDelegate + xcstrings);
    здесь — только для серверного Android-Doze-fallback, где текст рисует Sygnal
    (согласовано с уже хардкоженным «Новое сообщение» там же).
    """
    msgtype = content.get("msgtype")
    if msgtype == "m.image":
        return "🖼 Фото"
    if msgtype == "m.video":
        return "🎬 Видео"
    if msgtype == "m.file":
        return "📎 Файл"
    if msgtype == "m.sticker":
        return "Стикер"
    if msgtype == "m.audio":
        return "🎤 Голосовое сообщение" if _VOICE_KEY in content else "🎤 Аудио"
    return "Новое сообщение"


def has_voice_marker(content: Dict[str, Any]) -> bool:
    """В content есть маркер голосового (MSC3245) — iOS NSE «Голосовое» vs «Аудио»."""
    return _VOICE_KEY in content
