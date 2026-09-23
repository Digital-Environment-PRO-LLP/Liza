# -*- coding: utf-8 -*-
# Тесты для sygnal._clean_body.clean_message_body — чистка m.room.message.body
# перед отправкой в push-payload (iOS NSE / macOS AppDelegate читают этот текст
# напрямую и не умеют сами вырезать reply-quote и Matrix-меншны).

from unittest import TestCase

from sygnal._clean_body import (
    STORY_PUBLISHED_BODY,
    clean_message_body,
    has_voice_marker,
    is_media_msgtype,
    is_story,
    media_caption,
    media_type_label,
)


class CleanMessageBodyTestCase(TestCase):
    def test_empty_string(self) -> None:
        self.assertEqual(clean_message_body(""), "")

    def test_plain_text_untouched(self) -> None:
        self.assertEqual(
            clean_message_body("Привет, как дела?"),
            "Привет, как дела?",
        )

    def test_mention_pill_replaced_with_display_name(self) -> None:
        self.assertEqual(
            clean_message_body("@[Иван Петров], глянь"),
            "Иван Петров, глянь",
        )

    def test_multiple_mention_pills(self) -> None:
        self.assertEqual(
            clean_message_body("@[Иван] и @[Мария Сидорова] зайдите"),
            "Иван и Мария Сидорова зайдите",
        )

    def test_mxid_replaced_with_localpart(self) -> None:
        self.assertEqual(
            clean_message_body("@roman:liza.prodamus.tech, привет"),
            "roman, привет",
        )

    def test_mxid_with_special_chars(self) -> None:
        # Локальные части MXID допускают '.', '_', '=', '/', '-'.
        self.assertEqual(
            clean_message_body("@user.name_test:server.example.com"),
            "user.name_test",
        )

    def test_reply_quote_stripped(self) -> None:
        body = (
            "> <@alice:server.com> Изначальное сообщение\n"
            "\n"
            "Ответ Боба"
        )
        self.assertEqual(clean_message_body(body), "Ответ Боба")

    def test_multiline_reply_quote_stripped(self) -> None:
        body = (
            "> <@alice:server.com> Первая строка цитаты\n"
            "> вторая строка цитаты\n"
            "> третья\n"
            "\n"
            "Сам ответ"
        )
        self.assertEqual(clean_message_body(body), "Сам ответ")

    def test_reply_quote_with_crlf(self) -> None:
        body = (
            "> <@alice:server.com> цитата\r\n"
            "\r\n"
            "ответ"
        )
        self.assertEqual(clean_message_body(body), "ответ")

    def test_reply_quote_plus_mention_in_reply(self) -> None:
        body = (
            "> <@alice:server.com> исходник\n"
            "\n"
            "@[Алиса], подтверждаю"
        )
        self.assertEqual(clean_message_body(body), "Алиса, подтверждаю")

    def test_no_double_strip_of_mention_in_reply_quote(self) -> None:
        # Reply-quote сам содержит MXID отвечающего — мы режем quote целиком,
        # так что MXID внутри quote не должен попадать в результат.
        body = (
            "> <@alice:server.com> @[Боб] видел?\n"
            "\n"
            "Да, видел"
        )
        self.assertEqual(clean_message_body(body), "Да, видел")

    def test_mention_pill_without_brackets_in_body_kept(self) -> None:
        # Квадратные скобки без префикса @ не должны трогаться.
        self.assertEqual(
            clean_message_body("[важное] обновление"),
            "[важное] обновление",
        )

    def test_email_in_body_kept(self) -> None:
        # Email — не MXID, regex требует ведущий '@', email его не имеет.
        self.assertEqual(
            clean_message_body("Пиши на user@example.com"),
            "Пиши на user@example.com",
        )

    def test_only_reply_quote_returns_empty(self) -> None:
        # Edge case: сообщение состоит только из reply-quote (странно,
        # но не должно падать).
        body = "> <@alice:server.com> цитата\n\n"
        self.assertEqual(clean_message_body(body), "")


# Страж реестра регрессии: ledger:RL-push-media-type-preview (см.
# tests/registry/). LABA-2238: системные пуш-баннеры (iOS NSE, macOS AppDelegate,
# Android Doze-гибрид) кладут body напрямую в текст — у медиа это имя файла.
# `media_caption`/`media_type_label` зеркалят клиентский `Event.fileDescription`:
# подпись есть, только если очищенный body != filename.
#
# Критерии приёмки (LABA-2238): «имя файла НЕ показывать никогда» — ∀ по типам
# (voice/audio/image/video/file), reply и не-reply, с подписью и без.
class MediaPreviewTestCase(TestCase):
    def _voice(self, body: str, filename: str) -> dict:
        return {
            "msgtype": "m.audio",
            "body": body,
            "filename": filename,
            "org.matrix.msc3245.voice": {},
            "info": {"duration": 3000},
        }

    # AC-1: reply-голосовое (главный кейс) — подписи нет, тип «Голосовое».
    # AC:RL-push-media-type-preview/1
    def test_reply_voice_no_caption(self) -> None:
        content = self._voice(
            body="> <@peer:s> привет\n\nrecording1785329047882163.ogg",
            filename="recording1785329047882163.ogg",
        )
        self.assertIsNone(media_caption(content))
        self.assertEqual(media_type_label(content), "🎤 Голосовое сообщение")
        self.assertTrue(has_voice_marker(content))

    # AC-2: не-reply голосовое (контроль) — тоже без подписи.
    # AC:RL-push-media-type-preview/2
    def test_plain_voice_no_caption(self) -> None:
        content = self._voice(
            body="recording1785329047882163.ogg",
            filename="recording1785329047882163.ogg",
        )
        self.assertIsNone(media_caption(content))
        self.assertEqual(media_type_label(content), "🎤 Голосовое сообщение")

    # AC-3: аудио БЕЗ voice-маркера → «Аудио», не имя файла.
    # AC:RL-push-media-type-preview/3
    def test_plain_audio_label(self) -> None:
        content = {
            "msgtype": "m.audio",
            "body": "song.mp3",
            "filename": "song.mp3",
        }
        self.assertIsNone(media_caption(content))
        self.assertEqual(media_type_label(content), "🎤 Аудио")
        self.assertFalse(has_voice_marker(content))

    # AC-4: медиа с РЕАЛЬНОЙ подписью (reply) — подпись сохранена, без цитаты и
    # без имени файла.
    # AC:RL-push-media-type-preview/4
    def test_reply_image_with_caption(self) -> None:
        content = {
            "msgtype": "m.image",
            "body": "> <@peer:s> привет\n\nсмотри сюда",
            "filename": "photo.jpg",
        }
        self.assertEqual(media_caption(content), "смотри сюда")

    # AC-5: типы image/video/file.
    # AC:RL-push-media-type-preview/5
    def test_type_labels(self) -> None:
        self.assertEqual(media_type_label({"msgtype": "m.image"}), "🖼 Фото")
        self.assertEqual(media_type_label({"msgtype": "m.video"}), "🎬 Видео")
        self.assertEqual(media_type_label({"msgtype": "m.file"}), "📎 Файл")
        self.assertEqual(media_type_label({"msgtype": "m.sticker"}), "Стикер")

    # Край: медиа без поля filename (внешний/старый клиент) — body трактуем как
    # подпись (как клиент), не падаем.
    def test_media_without_filename_treated_as_caption(self) -> None:
        content = {"msgtype": "m.image", "body": "подпись без filename"}
        self.assertEqual(media_caption(content), "подпись без filename")

    def test_is_media_msgtype(self) -> None:
        for mt in ("m.image", "m.audio", "m.video", "m.file", "m.sticker"):
            self.assertTrue(is_media_msgtype({"msgtype": mt}))
        self.assertFalse(is_media_msgtype({"msgtype": "m.text"}))
        self.assertFalse(is_media_msgtype({}))

    def test_media_caption_non_str_body(self) -> None:
        self.assertIsNone(media_caption({"msgtype": "m.image"}))

    # LABA-1970: детект публикации сторис (маркер-объект com.liza.story).
    def test_is_story_positive(self) -> None:
        self.assertTrue(is_story({"com.liza.story": {"expires_ts": 1}}))

    def test_is_story_plain_message(self) -> None:
        self.assertFalse(is_story({"msgtype": "m.text", "body": "привет"}))

    def test_is_story_marker_not_object(self) -> None:
        # Маркер обязан быть объектом (dict), не строкой/флагом.
        self.assertFalse(is_story({"com.liza.story": "1"}))

    def test_is_story_non_dict_content(self) -> None:
        self.assertFalse(is_story(None))
        self.assertFalse(is_story("nope"))

    def test_story_published_body_masculine_no_paren(self) -> None:
        # Правило локализации проекта: муж. род без скобочной «(а)».
        self.assertEqual(STORY_PUBLISHED_BODY, "опубликовал историю")
        self.assertNotIn("(а)", STORY_PUBLISHED_BODY)
