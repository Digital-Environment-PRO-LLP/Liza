// Страж RL-push-rules-default-reset-client: клиент распознаёт выключенные
// дефолтные push-правила (инцидент 2026-09-14, у пользователя были выключены
// `.m.rule.message` и `.m.rule.suppress_edits`) и сбрасывает ТОЛЬКО их.
//
// ledger:RL-push-rules-default-reset-client

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/utils/push_rule_defaults.dart';

PushRule _rule(String id, bool enabled, {bool isDefault = true}) => PushRule(
  actions: const [],
  default$: isDefault,
  enabled: enabled,
  ruleId: id,
);

PushRuleSet _set({
  List<PushRule> override = const [],
  List<PushRule> underride = const [],
}) => PushRuleSet(override: override, underride: underride);

void main() {
  group('PushRuleDefaults.deviations', () {
    test(
      'AC:RL-push-rules-default-reset-client/1 — не загружено → null, не «всё выключено»',
      () {
        expect(PushRuleDefaults.deviations(null), isNull);
        expect(PushRuleDefaults.deviations(PushRuleSet()), isNull);
      },
    );

    test(
      'AC:RL-push-rules-default-reset-client/1 — дефолты и отсутствующие правила → пусто',
      () {
        final set = _set(
          override: [
            _rule('.m.rule.master', false),
            _rule('.m.rule.suppress_edits', true),
          ],
          underride: [_rule('.m.rule.message', true)],
        );
        expect(PushRuleDefaults.deviations(set), isEmpty);
      },
    );

    test('AC:RL-push-rules-default-reset-client/1 — состояние инцидента', () {
      final set = _set(
        override: [
          _rule('.m.rule.master', false),
          _rule('.m.rule.reaction', false),
          _rule('.m.rule.suppress_edits', false),
          _rule('!story:hs', false, isDefault: false),
        ],
        underride: [_rule('.m.rule.message', false)],
      );
      final ids = PushRuleDefaults.deviations(set)!.map((r) => r.ruleId);
      expect(ids, [
        '.m.rule.message',
        '.m.rule.suppress_edits',
        '.m.rule.reaction',
      ]);
      expect(
        PushRuleDefaults.anySilencing(PushRuleDefaults.deviations(set)!),
        isTrue,
      );
    });

    test(
      'AC:RL-push-rules-default-reset-client/2 — только шумовые отклонения не «немота»',
      () {
        final set = _set(override: [_rule('.m.rule.suppress_edits', false)]);
        final deviations = PushRuleDefaults.deviations(set)!;
        expect(deviations, hasLength(1));
        expect(PushRuleDefaults.anySilencing(deviations), isFalse);
      },
    );

    test(
      'AC:RL-push-rules-default-reset-client/2 — каждое правило немоты распознаётся',
      () {
        for (final rule in PushRuleDefaults.rules.where((r) => r.silences)) {
          final pushRule = _rule(rule.ruleId, false);
          final set = rule.kind == PushRuleKind.underride
              ? _set(underride: [pushRule])
              : _set(override: [pushRule]);
          final deviations = PushRuleDefaults.deviations(set)!;
          expect(
            PushRuleDefaults.anySilencing(deviations),
            isTrue,
            reason: rule.ruleId,
          );
        }
      },
    );
  });

  test(
    'AC:RL-push-rules-default-reset-client/3 — сброс трогает только отклонения, в дефолт',
    () async {
      final set = _set(
        override: [
          _rule('.m.rule.master', true),
          _rule('.m.rule.suppress_edits', false),
        ],
        underride: [_rule('.m.rule.message', false)],
      );
      final calls = <String>[];
      await PushRuleDefaults.resetToDefaults(
        PushRuleDefaults.deviations(set)!,
        (kind, ruleId, enabled) async =>
            calls.add('${kind.name}/$ruleId=$enabled'),
      );
      expect(calls, [
        'underride/.m.rule.message=true',
        'override/.m.rule.suppress_edits=true',
      ]);
    },
  );
}
