// LABA-1970: контракт имени override-правила пуша на сторис между клиентом и
// сервером. Клиент шлёт `setPushRuleEnabled(override, <name>)`, сервер создаёт
// правило с `global/override/<name>`. Формат ОБЯЗАН совпадать с серверным
// stories_membership/_logic.py:story_notify_rule_name — иначе тумблер не найдёт
// правило (M_NOT_FOUND) и настройка не применится.
//
// ledger:RL-stories-publish-push AC:RL-stories-publish-push/5 (toggle-rule-name)

import 'package:flutter_test/flutter_test.dart';
import 'package:liza/utils/stories/stories_extension.dart';

void main() {
  group('storyNotifyRuleName', () {
    test('формат — com.liza.story_notify.{roomId} (совпадает с сервером)', () {
      expect(
        storyNotifyRuleName('!abc:server.tld'),
        'com.liza.story_notify.!abc:server.tld',
      );
    });

    test('сегмент без "/" — иначе URL push-rule распадётся', () {
      // room_id может нести ":", "!", ".", но НЕ "/". Имя правила обязано быть
      // одним path-сегментом (см. setPushRuleEnabled URL).
      expect(storyNotifyRuleName('!x:matrix.org').contains('/'), isFalse);
      expect(
        storyNotifyRuleName('!weird.id:sub.domain.example').contains('/'),
        isFalse,
      );
    });

    test('room_id с точками в домене не ломает формат', () {
      expect(
        storyNotifyRuleName('!room:liza.laba.prodamus.tech'),
        'com.liza.story_notify.!room:liza.laba.prodamus.tech',
      );
    });
  });
}
