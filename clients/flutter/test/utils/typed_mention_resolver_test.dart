// Страж реестра регрессии: ledger:RL-typed-mention-highlight (см. tests/registry/).
//
// LABA-1897: набранный руками `@Имя` (без выбора подсказки) не попадал в
// m.mentions → у адресата счётчик чата был синий, а не красный. Резолвер
// переписывает однозначный `@токен` в пилюлю `@[Полное имя]`, чтобы SDK
// положил mxid в m.mentions и сервер поднял highlight.

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/utils/typed_mention_resolver.dart';
import 'test_client.dart';

void main() {
  group('TypedMentionResolver.resolve', () {
    const dmitrii = MentionCandidate(
      pill: '@[Дмитрий Луба]',
      tokens: {'дмитрий', 'луба', 'dmitrii.luba'},
    );
    const nadya = MentionCandidate(
      pill: '@[Надя Розенталь]',
      tokens: {'надя', 'розенталь', 'nadezhda.rozental'},
    );
    // Тёзка по имени — делает токен «дмитрий» неоднозначным.
    const dmitriiPetrov = MentionCandidate(
      pill: '@[Дмитрий Петров]',
      tokens: {'дмитрий', 'петров', 'dmitrii.petrov'},
    );

    test('однозначный @Имя → пилюля — ledger:RL-typed-mention-highlight '
        '(AC:RL-typed-mention-highlight/1)', () {
      expect(
        TypedMentionResolver.resolve('@Дмитрий глянь плиз', [dmitrii, nadya]),
        '@[Дмитрий Луба] глянь плиз',
      );
    });

    test('@Фамилия тоже резолвится — ledger:RL-typed-mention-highlight', () {
      expect(
        TypedMentionResolver.resolve('привет @Розенталь', [dmitrii, nadya]),
        'привет @[Надя Розенталь]',
      );
    });

    test('несколько @Имя в одном сообщении — оба резолвятся '
        '(AC:RL-typed-mention-highlight/2)', () {
      expect(
        TypedMentionResolver.resolve('@Дмитрий @Надя смотрите', [dmitrii, nadya]),
        '@[Дмитрий Луба] @[Надя Розенталь] смотрите',
      );
    });

    test('неоднозначный токен (два Дмитрия) — НЕ трогаем '
        '(AC:RL-typed-mention-highlight/3)', () {
      expect(
        TypedMentionResolver.resolve(
          '@Дмитрий привет',
          [dmitrii, dmitriiPetrov],
        ),
        '@Дмитрий привет',
      );
    });

    test('@room не трогаем — ledger:RL-typed-mention-highlight', () {
      expect(
        TypedMentionResolver.resolve('@room всем привет', [dmitrii]),
        '@room всем привет',
      );
    });

    test('готовую пилюлю @[...] не трогаем — ledger:RL-typed-mention-highlight',
        () {
      expect(
        TypedMentionResolver.resolve('@[Дмитрий Луба] ок', [dmitrii]),
        '@[Дмитрий Луба] ок',
      );
    });

    test('полный mxid @user:server отдаём SDK как есть '
        '— ledger:RL-typed-mention-highlight', () {
      expect(
        TypedMentionResolver.resolve(
          '@dmitrii.luba:server.tld ок',
          [dmitrii],
        ),
        '@dmitrii.luba:server.tld ок',
      );
    });

    test('незнакомый @токен не меняется — ledger:RL-typed-mention-highlight',
        () {
      expect(
        TypedMentionResolver.resolve('@Незнакомец ку', [dmitrii, nadya]),
        '@Незнакомец ку',
      );
    });

    test('email не считается упоминанием — ledger:RL-typed-mention-highlight',
        () {
      const text = 'пиши на me@Дмитрий.example';
      expect(TypedMentionResolver.resolve(text, [dmitrii]), text);
    });
  });

  group('TypedMentionResolver.candidatesFrom', () {
    test('строит пилюлю и токены из участника, себя исключает '
        '— ledger:RL-typed-mention-highlight', () async {
      final client = await prepareTestClient();
      final room = Room(id: '!r:server.tld', client: client);
      final me = User(
        '@me:server.tld',
        displayName: 'Я Сам',
        membership: 'join',
        room: room,
      );
      final dmitrii = User(
        '@dmitrii.luba:server.tld',
        displayName: 'Дмитрий Луба',
        membership: 'join',
        room: room,
      );

      final candidates =
          TypedMentionResolver.candidatesFrom([me, dmitrii], '@me:server.tld');

      expect(candidates.length, 1, reason: 'себя не включаем');
      final c = candidates.single;
      expect(c.pill, '@[Дмитрий Луба]');
      expect(c.tokens, containsAll(<String>['дмитрий', 'луба', 'dmitrii.luba']));

      // Сквозной эффект: @Имя из чужого участника → пилюля.
      expect(
        TypedMentionResolver.resolve('@Дмитрий тут?', candidates),
        '@[Дмитрий Луба] тут?',
      );

      await client.dispose();
    });
  });
}
