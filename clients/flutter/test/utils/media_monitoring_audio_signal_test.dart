// Юнит-стражи клиентского аудио-сигнала мониторинга: стабильный PII-safe title
// `Monitoring.audioIssueTitle`, контракт префиксов `[audio-*]` с notifier,
// per-reason троттл, no-op при !isActive. Мультикейс ∀ по всем аудио-сбоям,
// которые видит пользователь (download / source / playback / autoplay / транскрибация)
// — один пример дал бы ложно-зелёный.
//
// Реальный сигнал на устройстве (нативная сборка, «Liza · Медиа») — device/manual
// (AC-6). Реестр: tests/registry/RL-media-monitoring-audio-signal.md
// Дизайн: docs/superpowers/specs/2026-08-31-media-monitoring-fleet-visibility-audio-coverage-design.md
//
// ledger:RL-media-monitoring-audio-signal

import 'package:flutter_test/flutter_test.dart';

import 'package:liza/utils/monitoring.dart';

void main() {
  // Все reason'ы, которые эмитит клиент (закрытое перечисление — НЕ e.toString()).
  // Транскрибация — по каждому TranscriptionErrorKind.name.
  const audioReasons = <String>[
    'download-fail',
    'source-error',
    'playback-error',
    'autoplay-next-fail',
    // Дедлайн сетевой фазы подготовки. ОТДЕЛЬНЫЙ reason, а не переиспользование
    // 'autoplay-next-fail'/'download-fail': троттл в Monitoring — per-reason,
    // и на общем бакете таймаут глотался бы предшествующей ошибкой скачивания
    // ([[RL-audio-prepare-no-dead-window]]).
    'prepare-timeout',
  ];
  const transcriptionReasons = <String>[
    'transcription-network',
    'transcription-timeout',
    'transcription-auth',
    'transcription-serviceBusy',
    'transcription-decrypt',
    'transcription-server',
    'transcription-parse',
    'transcription-unknown',
  ];

  group('Monitoring.audioIssueTitle — маркер + reason + host, стабилен', () {
    // AC:RL-media-monitoring-audio-signal/1
    test('AC-1: title = префикс + reason + host, префиксы-константы', () {
      expect(Monitoring.audioFailurePrefix, '[audio-fail]');
      expect(
        Monitoring.audioTranscriptionFailurePrefix,
        '[audio-transcription-fail]',
      );
      // host — КОРОТКОЙ формой (первые два лейбла): длинный съедал 36 из 99
      // символов бюджета GlitchTip и выталкивал весь диагностический хвост.
      expect(
        Monitoring.audioIssueTitle('[audio-fail]', 'source-error', 'synapse.liza.laba'),
        '[audio-fail] reason=source-error host=synapse.liza',
      );
      // host=null → 'unknown' (не пустая строка — дедуп notifier'а различает).
      expect(
        Monitoring.audioIssueTitle('[audio-fail]', 'download-fail', null),
        '[audio-fail] reason=download-fail host=unknown',
      );
    });

    // AC:RL-media-monitoring-audio-signal/2 — МУЛЬТИКЕЙС ∀ (не один пример)
    test('AC-2: ∀ аудио-кейсам {download/source/playback/autoplay + транскрибация×kind} '
        '→ корректный стабильный title', () {
      for (final reason in audioReasons) {
        expect(
          Monitoring.audioIssueTitle('[audio-fail]', reason, 'h'),
          '[audio-fail] reason=$reason host=h',
          reason: 'аудио-провал: $reason',
        );
      }
      for (final reason in transcriptionReasons) {
        expect(
          Monitoring.audioIssueTitle('[audio-transcription-fail]', reason, 'h'),
          '[audio-transcription-fail] reason=$reason host=h',
          reason: 'транскрибация: $reason',
        );
      }
    });

    // AC:RL-media-monitoring-audio-signal/3  AC:RL-mediadiag-no-secret/audio-fail
    test('AC-3: title НЕ несёт секретов/локаторов контента ∀ reason (red-proof)', () {
      // reason из закрытого перечня → ни mxc, ни пути temp-файла, ни токена.
      // Red-proof: если вызывающая сторона начнёт класть e.toString() (путь несёт
      // mxc media id из Uri.encodeComponent(pathSegments.last)) — этот тест
      // краснеет на подстроках ниже.
      const forbidden = [
        '@',
        ':synapse',
        'mxc://',
        '/var/',
        '/tmp/',
        'access_token=',
        'bearer ',
        'authorization',
        r'$',
      ];
      final hosts = ['synapse.liza.laba.prodamus.tech', 'liza.cyber-agro.ru', null];
      for (final reason in [...audioReasons, ...transcriptionReasons]) {
        for (final host in hosts) {
          final title = Monitoring.audioIssueTitle('[audio-fail]', reason, host);
          for (final bad in forbidden) {
            expect(
              title.toLowerCase(),
              isNot(contains(bad.toLowerCase())),
              reason: 'reason=$reason host=$host не должен нести "$bad"',
            );
          }
        }
      }
    });
  });

  group('Бюджет длины title (GlitchTip режет на 100) — AC-7..9', () {
    // Все реальные значения контекста, которые собирает `audioIssueContext`.
    const kinds = ['decrypt', 'http', 'network', 'timeout', 'sdk', 'other'];
    const mimes = [
      'audio/mp4',
      'audio/ogg',
      'audio/mpeg',
      'audio/wav',
      'audio/aac',
      'application/octet-stream',
    ];
    const sizes = ['unknown', '<1mb', '1-5mb', '5-20mb', '>20mb'];
    // ВЕСЬ парк server_name (servers/synapse/instances/*/config/homeserver.yaml)
    // + dev-домен: сокращение host'а не имеет права схлопнуть два инстанса в
    // один дедуп-ключ notifier'а `room|title`.
    const hosts = [
      'synapse.liza.laba.prodamus.tech',
      'liza.cyber-agro.ru',
      'user.liza.ru',
      'nadezhda.liza.ru',
      'bots.liza.ru',
      'd3n8it.liza.ru',
      'hello.liza.ru',
      'ppetipak.liza.ru',
      'pflb.liza.ru',
      'skharkov.liza.ru',
      'victoryeng.liza.ru',
      'liza.local',
      'dev.liza.laba.prodamus.tech',
      null,
    ];

    // AC:RL-media-monitoring-audio-signal/7 — RED-PROOF инцидента 2026-09-09.
    test('AC-7: ∀ (префикс × reason × host × kind × mime × size) title ≤ 99 — '
        'иначе GlitchTip обрежет хвост и контекст не доедет до дежурного', () {
      // Свидетель дефекта (то, что реально лежало в прод-БД GlitchTip обрубком
      // «… e2ee=t…»): ПРЕЖНЯЯ схема «длинный host + конкатенация контекста»
      // бюджет превышала — этот ассерт краснеет, если её вернут.
      const legacy =
          '[audio-transcription-fail] reason=transcription-decrypt '
          'host=synapse.liza.laba.prodamus.tech e2ee=true mime=audio/mp4 size=<1mb';
      expect(
        legacy.length,
        greaterThan(Monitoring.maxAlertTitleLength),
        reason: 'прежний формат обязан быть за бюджетом — иначе тест ничего не ловит',
      );

      final prefixes = [
        Monitoring.audioFailurePrefix,
        Monitoring.audioTranscriptionFailurePrefix,
      ];
      for (final prefix in prefixes) {
        for (final reason in [...audioReasons, ...transcriptionReasons]) {
          for (final host in hosts) {
            for (final kind in kinds) {
              for (final mime in mimes) {
                for (final size in sizes) {
                  final title = Monitoring.buildAlertTitle(
                    prefix: prefix,
                    reason: reason,
                    host: host,
                    context: {
                      'kind': kind,
                      'mime': mime,
                      'size': size,
                      'e2ee': 'true',
                    },
                  );
                  expect(
                    title.length,
                    lessThanOrEqualTo(Monitoring.maxAlertTitleLength),
                    reason:
                        'title длиннее бюджета GlitchTip: "$title" (${title.length})',
                  );
                }
              }
            }
          }
        }
      }
    });

    // AC:RL-media-monitoring-audio-signal/8
    test('AC-8: при нехватке бюджета отбрасывается ХВОСТ контекста целиком, '
        'а голова (маркер+reason+host) и самое ценное поле (kind) — никогда', () {
      final title = Monitoring.buildAlertTitle(
        prefix: Monitoring.audioTranscriptionFailurePrefix,
        reason: 'transcription-serviceBusy',
        host: 'synapse.liza.laba.prodamus.tech',
        context: {
          'kind': 'network',
          'mime': 'application/octet-stream',
          'size': '5-20mb',
          'e2ee': 'true',
        },
      );
      expect(title.length, lessThanOrEqualTo(Monitoring.maxAlertTitleLength));
      // Маркер роутинга notifier'а и ось дедупа — неприкосновенны.
      expect(title, startsWith('[audio-transcription-fail] '));
      expect(title, contains('reason=transcription-serviceBusy'));
      expect(title, contains('host=synapse.liza'));
      expect(title, contains('kind=network'));
      // Отброшен именно хвост, а не середина: обрубков вида `e2ee=t` нет.
      expect(title, isNot(contains('e2ee=t ')));
      expect(title.endsWith('…'), isFalse);
      for (final part in title.split(' ').skip(1)) {
        expect(part, contains('='), reason: 'обрубок в title: "$part"');
      }
    });

    // AC:RL-media-monitoring-audio-signal/9
    test('AC-9: shortHost различает ВЕСЬ парк инстансов (дедуп по хосту жив)', () {
      final shorts = hosts.map(Monitoring.shortHost).toList();
      expect(shorts.toSet().length, shorts.length, reason: 'коллизия: $shorts');
      expect(Monitoring.shortHost('synapse.liza.laba.prodamus.tech'), 'synapse.liza');
      expect(Monitoring.shortHost('liza.cyber-agro.ru'), 'liza.cyber-agro');
      expect(Monitoring.shortHost(null), 'unknown');
      expect(Monitoring.shortHost(''), 'unknown');
      expect(Monitoring.shortHost('localhost'), 'localhost');
    });
  });

  group('Троттл per-reason + инертность', () {
    // AC:RL-media-monitoring-audio-signal/4
    test('AC-4: audioIssueThrottleAllows — один эмит per-reason за окно 5м, '
        'разные reason независимы', () {
      Monitoring.resetAudioIssueThrottle();
      final t0 = DateTime(2026, 8, 31, 12, 0, 0);
      expect(Monitoring.audioIssueThrottleAllows('source-error', t0), isTrue);
      // обрыв сети рождает поток одинаковых ошибок по всем пузырям — подавлен
      expect(
        Monitoring.audioIssueThrottleAllows(
          'source-error',
          t0.add(const Duration(seconds: 3)),
        ),
        isFalse,
      );
      // за окном — снова можно
      expect(
        Monitoring.audioIssueThrottleAllows(
          'source-error',
          t0.add(const Duration(minutes: 6)),
        ),
        isTrue,
      );
      // другой reason в том же окне — независим (не подавляется чужим)
      expect(Monitoring.audioIssueThrottleAllows('download-fail', t0), isTrue);
    });

    // AC:RL-media-monitoring-audio-signal/5
    test('AC-5: reportAudioIssue при !isActive — no-op, не бросает', () {
      expect(Monitoring.isActive, isFalse);
      expect(
        () => Monitoring.reportAudioIssue(
          prefix: Monitoring.audioFailurePrefix,
          reason: 'source-error',
          host: 'h',
        ),
        returnsNormally,
      );
    });
  });
}
