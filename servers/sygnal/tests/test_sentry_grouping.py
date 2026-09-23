# -*- coding: utf-8 -*-
"""Страж группировки Sentry-событий Sygnal.

Прод-факт 2026-09-08: 1193 issue при 1193 событиях за 30 дней — каждая ошибка
APNs порождала новую issue со счётчиком 1, потому что в тексте сидел
идентификатор. Следствие: alert-правило «5 событий за 10 минут на issue»
недостижимо НИКОГДА, за всю историю проекта в чат не ушло ни одного
уведомления, и семичасовой сбой провайдер-токена APNs 2026-08-11 (1059 ошибок)
прошёл незамеченным.

ledger:RL-sygnal-sentry-issue-grouping
"""
import unittest

from sygnal.sentry_grouping import (
    before_breadcrumb,
    before_send,
    normalize_message,
    split_request_id,
)

UUID_A = "31051710-5e81-4eba-8801-80ed91b7db0f"
UUID_B = "d868272c-65bf-46aa-855e-48c088f6873f"


class NormalizeMessage(unittest.TestCase):
    def test_same_class_different_uuid_collapses(self):
        # AC:RL-sygnal-sentry-issue-grouping/1 — боевые заголовки, отличающиеся
        # ТОЛЬКО идентификатором, дают ОДИН класс. Это и есть корень 1193/1193.
        msgs = [f"Status of notification {u} is 400 (BadDeviceToken)"
                for u in (UUID_A, UUID_B)]
        self.assertEqual(len({normalize_message(m) for m in msgs}), 1)
        self.assertEqual(len(set(msgs)), 2, "исходные обязаны различаться")

    def test_different_reason_stays_separate(self):
        # AC:RL-sygnal-sentry-issue-grouping/2 — РАЗНЫЕ причины НЕ склеиваются,
        # иначе реальная авария (403) спрячется за штатной ротацией (400).
        self.assertNotEqual(
            normalize_message(f"Status of notification {UUID_A} is 403 (InvalidProviderToken)"),
            normalize_message(f"Status of notification {UUID_A} is 400 (BadDeviceToken)"),
        )

    def test_request_id_prefix_stripped(self):
        # AC:RL-sygnal-sentry-issue-grouping/3 — `[rid] ` от NotificationLoggerAdapter
        # не должен участвовать в группировке.
        self.assertEqual(split_request_id("[abc123] boom"), ("abc123", "boom"))
        self.assertEqual(split_request_id("boom"), (None, "boom"))
        self.assertEqual(normalize_message("[abc123] boom"), "boom")

    def test_long_hex_normalized(self):
        # AC:RL-sygnal-sentry-issue-grouping/4 — device-токены APNs (длинный hex).
        self.assertEqual(
            normalize_message("APNs token a1b2c3d4e5f60718293a4b5c6d7e8f90 was rejected"),
            "APNs token <hex> was rejected",
        )

    def test_plain_message_untouched(self):
        # AC:RL-sygnal-sentry-issue-grouping/5 — текст без энтропии не трогаем.
        for m in ("Failed to dispatch notification", "400 BadDeviceToken"):
            self.assertEqual(normalize_message(m), m)


class BeforeSend(unittest.TestCase):
    def _event(self, msg, logger_name="sygnal.apnspushkin"):
        return {"logentry": {"message": msg}, "logger": logger_name}

    def test_fingerprint_groups_by_class(self):
        # AC:RL-sygnal-sentry-issue-grouping/6 — два события, отличающиеся только
        # идентификатором, получают ОДИНАКОВЫЙ fingerprint (=> одна issue, честный
        # счётчик, достижимый порог alert-правила).
        a = before_send(self._event(f"[r1] Status of notification {UUID_A} is 400 (BadDeviceToken)"))
        b = before_send(self._event(f"[r2] Status of notification {UUID_B} is 400 (BadDeviceToken)"))
        self.assertEqual(a["fingerprint"], b["fingerprint"])

    def test_diagnostics_preserved(self):
        # AC:RL-sygnal-sentry-issue-grouping/7 — идентификатор НЕ теряется:
        # request_id уходит в теги, полный текст — в extra. Схлопывание не имеет
        # права стоить диагностики (по этим id ищут в логах и в поддержке Apple).
        ev = before_send(self._event(f"[req-9] Status of notification {UUID_A} is 400 (BadDeviceToken)"))
        self.assertEqual(ev["tags"]["request_id"], "req-9")
        self.assertIn(UUID_A, ev["extra"]["raw_message"])
        self.assertEqual(ev["logentry"]["message"],
                         "Status of notification <uuid> is 400 (BadDeviceToken)")

    def test_different_class_different_fingerprint(self):
        # AC:RL-sygnal-sentry-issue-grouping/8 — red-proof обратной стороны:
        # 403 и 400 обязаны остаться РАЗНЫМИ issue.
        a = before_send(self._event(f"[r1] Status of notification {UUID_A} is 403 (InvalidProviderToken)"))
        b = before_send(self._event(f"[r1] Status of notification {UUID_A} is 400 (BadDeviceToken)"))
        self.assertNotEqual(a["fingerprint"], b["fingerprint"])

    def test_event_without_message_survives(self):
        # AC:RL-sygnal-sentry-issue-grouping/9 — before_send стоит на горячем пути:
        # событие без текста не должно ронять отправку.
        ev = before_send({"exception": {"values": [{"type": "ValueError"}]}})
        self.assertNotIn("fingerprint", ev)

    def test_breadcrumb_normalized(self):
        # AC:RL-sygnal-sentry-issue-grouping/10
        crumb = before_breadcrumb({"message": f"[r1] notification {UUID_A} done"})
        self.assertEqual(crumb["message"], "notification <uuid> done")


class LazyLogentry(unittest.TestCase):
    """Боевая форма события: `%`-ленивое логирование.

    Прод-факт 2026-09-08: эмитент — НЕ наш код, а `aioapns/client.py`:
    `logger.warning("Status of notification %s is %s (%s)", nid, status, reason)`.
    `sentry_sdk.integrations.logging` кладёт в `logentry` ШАБЛОН + `params`
    отдельно, БЕЗ ключа `formatted`. Прежние фикстуры подавали уже
    отформатированную строку — форму, которой боевой путь не производит никогда,
    поэтому тесты были зелёными при неработающей нормализации.
    """

    def _event(self, template, params, logger_name="aioapns.client"):
        return {"logentry": {"message": template, "params": params},
                "logger": logger_name}

    TEMPLATE = "Status of notification %s is %s (%s)"

    def test_lazy_params_rendered_and_normalized(self):
        # AC:RL-sygnal-sentry-issue-grouping/11 — RED-PROOF: до фикса `raw` был
        # шаблоном без uuid, нормализация вырождалась в no-op, а title в GlitchTip
        # всё равно нёс идентификатор (GlitchTip сам рендерит message % params).
        ev = before_send(self._event(self.TEMPLATE, (UUID_A, "400", "BadDeviceToken")))
        self.assertEqual(ev["logentry"]["message"],
                         "Status of notification <uuid> is 400 (BadDeviceToken)")
        # params обязаны быть погашены: иначе рендер на стороне GlitchTip вернёт
        # идентификатор в заголовок и кардинальность взорвётся снова.
        self.assertFalse(ev["logentry"].get("params"))
        self.assertIn(UUID_A, ev["extra"]["raw_message"])

    def test_lazy_different_reason_different_fingerprint(self):
        # AC:RL-sygnal-sentry-issue-grouping/12 — RED-PROOF главного вреда: на
        # ленивой форме fingerprint строился из ОДНОГО шаблона, поэтому 400/403/410
        # слипались в одну issue. Реальная авария (403 InvalidProviderToken,
        # 7 часов молчания 2026-08-11) пряталась бы за штатной ротацией токенов.
        codes = [("400", "BadDeviceToken"),
                 ("403", "InvalidProviderToken"),
                 ("410", "Unregistered")]
        prints = {
            tuple(before_send(self._event(self.TEMPLATE, (UUID_A, code, reason)))["fingerprint"])
            for code, reason in codes
        }
        self.assertEqual(len(prints), 3, "400/403/410 обязаны остаться РАЗНЫМИ issue")

    def test_lazy_same_reason_collapses(self):
        # AC:RL-sygnal-sentry-issue-grouping/13 — обратная сторона: одна причина с
        # разными uuid — ОДНА issue (честный счётчик, достижимый порог алёрта).
        a = before_send(self._event(self.TEMPLATE, (UUID_A, "400", "BadDeviceToken")))
        b = before_send(self._event(self.TEMPLATE, (UUID_B, "400", "BadDeviceToken")))
        self.assertEqual(a["fingerprint"], b["fingerprint"])

    def test_dict_params_supported(self):
        # AC:RL-sygnal-sentry-issue-grouping/14 — `logger.warning("%(a)s", {"a": …})`.
        ev = before_send(self._event("notification %(nid)s failed", {"nid": UUID_A}))
        self.assertEqual(ev["logentry"]["message"], "notification <uuid> failed")

    def test_broken_params_do_not_raise(self):
        # AC:RL-sygnal-sentry-issue-grouping/15 — before_send на горячем пути:
        # рассогласованные шаблон/аргументы не имеют права ронять отправку.
        ev = before_send(self._event("only one slot %s", ("a", "b", "c")))
        self.assertIn("fingerprint", ev)
        ev2 = before_send(self._event("literal 100% done", ()))
        self.assertIn("fingerprint", ev2)
