// ledger:RL-company-private-by-default
// AC:RL-company-private-by-default/11
//
// Страж дефолта видимости при СОЗДАНИИ компании/пространства. Раньше
// NewGroupController.initState форсил publicGroup=true для CreateGroupType.space
// → компания рождалась публичной (visibility:public в _createSpace) и утекала в
// федеративный поиск «Компании». Фикс — убрать форс: дефолт publicGroup=false
// (приват) для ВСЕХ типов; публичность — сознательный опт-ин через свитч
// «Публичная компания». Тест бьёт по РЕАЛЬНОМУ полю прод-контроллера
// (не реплика): красный, если вернуть `publicGroup = true` дефолтом.
// Полное поведение (свитч off, приватный хинт, приватное создание на живом
// стеке) покрывает device-flow iOS+Android (см. RL, guard.render:device).
// Спека 2026-08-25-companies-private-by-default-design.md.
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/pages/new_group/new_group.dart';

void main() {
  // AC:RL-company-private-by-default/11
  test(
    'AC-11: NewGroupController.publicGroup по умолчанию = false '
    '(компания/пространство создаётся приватной, публичность — опт-ин)',
    () {
      expect(
        NewGroupController().publicGroup,
        isFalse,
        reason: 'дефолт видимости при создании должен быть приватным; '
            'форс publicGroup=true для space утекал компании в поиск',
      );
      // groupCanBeFound (публикация в directory) тоже по умолчанию выключена.
      expect(NewGroupController().groupCanBeFound, isFalse);
    },
  );
}
