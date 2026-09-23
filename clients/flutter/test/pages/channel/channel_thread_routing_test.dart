import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Спек 2026-07-30, Этап 2: у треда собственный роут; кнопка под постом ведёт
// в тред, а не в привязанный чат целиком.
//
// Структурный тест: полноценный widget-тест экрана треда требует поднятого
// Matrix-клиента с каналом и привязанным чатом — несоразмерно проверяемому
// факту (что роут объявлен и точка навигации переключена).
void main() {
  test('роут треда объявлен', () {
    final routes = File('lib/config/routes.dart').readAsStringSync();
    expect(
      routes.contains('post/:postid/comments'),
      isTrue,
      reason: 'роут треда не найден в routes.dart',
    );
    expect(routes.contains('ChannelThreadPage'), isTrue);
  });

  test('кнопка под постом больше не уходит в /rooms/<чат>', () {
    final code = File(
      'lib/pages/chat/events/channel_post_comments.dart',
    ).readAsStringSync();
    expect(
      code.contains('/post/'),
      isTrue,
      reason: 'переход должен вести в тред поста',
    );
  });

  test('шапка треда показывает НАСТОЯЩУЮ статистику поста', () {
    // Было захардкожено `reactions: null, viewCount: 0` — пост с 40 реакциями
    // и 5000 просмотров показывал в треде пустоту и «0 просмотров». Считаем
    // тем же способом, что лента (message.dart → ChannelPostFooter).
    final page = File(
      'lib/pages/channel_thread/channel_thread_page.dart',
    ).readAsStringSync();
    final ids = _dartIdentifiers(page);
    expect(
      ids.contains('MessageReactions'),
      isTrue,
      reason: 'реакции в шапке треда — тот же виджет, что в ленте',
    );
    expect(
      ids.contains('getReadReceiptsPerMessage'),
      isTrue,
      reason: 'просмотры — квитанции прочтения, как считает лента',
    );
    // Комментарии срезаем (в них прежняя заглушка описана как «что было»),
    // пробелы схлопываем — форматтер разносит аргументы по строкам.
    final flat = _stripComments(page).replaceAll(RegExp(r'\s+'), ' ');
    expect(
      flat.contains('reactions: null') || flat.contains('viewCount: 0,'),
      isFalse,
      reason: 'статистика поста в треде не имеет права быть заглушкой',
    );
  });

  test('плашка под постом и тред считают одно и то же', () {
    // Плашка звала countReplies (только ПРЯМЫЕ ответы), а тред строится на
    // threadEvents (прямые + ответы на них) — пост с одним комментарием и
    // пятью ответами обещал «1 комментарий», а открывался с шестью.
    final bar = _dartIdentifiers(
      File('lib/pages/chat/events/channel_post_comments.dart').readAsStringSync(),
    );
    expect(
      bar.contains('countThreadComments'),
      isTrue,
      reason: 'счётчик плашки обязан считать весь тред, а не прямые ответы',
    );
    expect(
      bar.contains('countReplies'),
      isFalse,
      reason:
          'countReplies считает только прямые ответы — с содержимым треда '
          'этот счётчик расходится',
    );
    final page = _dartIdentifiers(
      File('lib/pages/channel_thread/channel_thread_page.dart')
          .readAsStringSync(),
    );
    expect(
      page.contains('threadEvents'),
      isTrue,
      reason: 'тред обязан строиться на threadEvents — на нём же счётчик',
    );
  });

  test('в треде не раскрывается привязанный чат в списке чатов', () {
    final page = File(
      'lib/pages/channel_thread/channel_thread_page.dart',
    ).readAsStringSync();
    // Ищем ГОЛОЕ имя идентификатора в КОДЕ (комментарии срезаны), а не
    // подстроку «revealChatForMe(»: поиск с открывающей скобкой пропускал
    // рабочие формы вызова — tear-off (`final f = x.revealChatForMe; f();`),
    // вызов с пробелом (`revealChatForMe ()`) и каскад
    // (`..revealChatForMe()`). Комментарии срезаем, чтобы сам инвариант
    // можно было документировать рядом с отправкой.
    expect(
      _dartIdentifiers(page).contains('revealChatForMe'),
      isFalse,
      reason:
          'режим «комментирую, не вступая»: тред не имеет права раскрывать '
          'чат обсуждения в списке чатов — осознанный вход только через '
          'кнопку «Обсуждение» в деталях канала',
    );
  });
}

/// Исходник без комментариев (`//…`, `/*…*/`, dartdoc).
///
/// Стражам инвариантов «такого в этом файле быть не должно» комментарии
/// мешают: в них инвариант как раз и документируется («сюда нельзя звать
/// revealChatForMe», «раньше тут стояла заглушка reactions: null») — поиск по
/// сырому тексту давал бы ложное срабатывание на самой документации.
String _stripComments(String source) => source
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), ' ')
    .replaceAll(RegExp(r'//[^\n]*'), ' ');

/// Множество идентификаторов, встречающихся в КОДЕ файла: комментарии
/// (`//…`, `/*…*/`, dartdoc) и содержимое строковых литералов срезаны.
///
/// Нужно стражам инвариантов «такой-то вызов в этом файле запрещён»: искать
/// подстроку по сырому исходнику бесполезно (комментарий с упоминанием даёт
/// ложное срабатывание, а tear-off без скобок — ложное молчание).
Set<String> _dartIdentifiers(String source) {
  final code = _stripComments(source)
      .replaceAll(RegExp("'''.*?'''", dotAll: true), " '' ")
      .replaceAll(RegExp('""".*?"""', dotAll: true), ' "" ')
      .replaceAll(RegExp(r"'(?:[^'\\\n]|\\.)*'"), " '' ")
      .replaceAll(RegExp(r'"(?:[^"\\\n]|\\.)*"'), ' "" ');
  return RegExp(
    r'[A-Za-z_$][A-Za-z0-9_$]*',
  ).allMatches(code).map((m) => m[0]!).toSet();
}
