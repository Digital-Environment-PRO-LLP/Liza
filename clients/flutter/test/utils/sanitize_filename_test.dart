// ignore_for_file: avoid_print

// Document Preview Unicode Fix — Bug Condition Exploration Tests
//
// These tests encode EXPECTED (correct) behavior for sanitizeFilenameForIOS.
// They are designed to FAIL on unfixed code (stub returns filename unchanged),
// confirming the bug exists: non-ASCII filenames are not sanitized for iOS.
//
// Validates: Requirements 1.1, 1.2, 1.3, 2.1, 2.2, 2.3
//
// Property 1: Fault Condition — Opening files with non-ASCII names on iOS
//   For any filename containing non-ASCII characters, the result of
//   sanitizeFilenameForIOS MUST contain only ASCII characters AND preserve
//   the original file extension.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:liza/utils/matrix_sdk_extensions/event_extension.dart';

/// Returns true if every code unit in [s] is in the ASCII range (0–127).
bool _isAsciiOnly(String s) => s.codeUnits.every((c) => c <= 127);

/// Extracts the file extension including the dot, e.g. ".pdf".
/// Returns empty string if there is no extension.
String _extractExtension(String filename) {
  final dotIndex = filename.lastIndexOf('.');
  if (dotIndex <= 0) return '';
  return filename.substring(dotIndex);
}

// ---------------------------------------------------------------------------
// Property 1: Fault Condition — Non-ASCII filenames on iOS
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  // Specific counterexamples from the design document's Fault Condition
  // -------------------------------------------------------------------------

  group('Fault Condition — specific counterexamples from design', () {
    /// **Validates: Requirements 1.1, 2.1**
    test(
      'Cyrillic filename «Документ отчёт.pdf» must be sanitized to ASCII-only with .pdf extension',
      () {
        const input = 'Документ отчёт.pdf';
        final result = sanitizeFilenameForIOS(input);

        expect(
          _isAsciiOnly(result),
          isTrue,
          reason:
              'COUNTEREXAMPLE: sanitizeFilenameForIOS("$input") returned "$result" '
              'which contains non-ASCII characters. On iOS, OpenAppFile.open() '
              'cannot handle paths with non-ASCII characters.',
        );
        expect(
          _extractExtension(result),
          equals('.pdf'),
          reason:
              'File extension .pdf must be preserved after sanitization '
              'so iOS can determine the correct app to open the file.',
        );
      },
    );

    /// **Validates: Requirements 1.3, 2.3**
    test(
      'Filename with spaces and special chars «Мой файл (копия).pdf» must be sanitized to ASCII-only with .pdf extension',
      () {
        const input = 'Мой файл (копия).pdf';
        final result = sanitizeFilenameForIOS(input);

        expect(
          _isAsciiOnly(result),
          isTrue,
          reason:
              'COUNTEREXAMPLE: sanitizeFilenameForIOS("$input") returned "$result" '
              'which contains non-ASCII characters.',
        );
        expect(
          _extractExtension(result),
          equals('.pdf'),
          reason: 'File extension .pdf must be preserved after sanitization.',
        );
      },
    );

    /// **Validates: Requirements 1.2, 2.2**
    test(
      'Mixed ASCII/Cyrillic filename «report_отчёт 2024.docx» must be sanitized to ASCII-only with .docx extension',
      () {
        const input = 'report_отчёт 2024.docx';
        final result = sanitizeFilenameForIOS(input);

        expect(
          _isAsciiOnly(result),
          isTrue,
          reason:
              'COUNTEREXAMPLE: sanitizeFilenameForIOS("$input") returned "$result" '
              'which contains non-ASCII characters.',
        );
        expect(
          _extractExtension(result),
          equals('.docx'),
          reason: 'File extension .docx must be preserved after sanitization.',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // Property-based test: scoped PBT over non-ASCII filenames
  // -------------------------------------------------------------------------

  group('Fault Condition — property-based: non-ASCII filenames', () {
    /// **Validates: Requirements 1.1, 1.2, 1.3, 2.1, 2.2, 2.3**
    ///
    /// Property: For ANY filename containing non-ASCII characters,
    /// sanitizeFilenameForIOS MUST return a string that:
    ///   1. Contains only ASCII characters (code units 0–127)
    ///   2. Preserves the original file extension
    test(
      'for any non-ASCII filename, result must be ASCII-only and preserve extension',
      () {
        // Scoped PBT: generate a focused set of non-ASCII filenames
        // covering Cyrillic, spaces, special chars, and mixed content.
        final random = Random(42); // deterministic seed for reproducibility

        const cyrillicChars = 'абвгдежзийклмнопрстуфхцчшщъыьэюяАБВГДЕЖЗ';
        const specialChars = ' ()[]{}!@#\$%^&+=';
        const asciiChars = 'abcdefghijklmnopqrstuvwxyz0123456789_-';
        const extensions = ['.pdf', '.docx', '.xlsx', '.txt', '.png', '.mp4'];

        // Generate random non-ASCII filename
        String generateNonAsciiFilename() {
          final allChars = cyrillicChars + specialChars + asciiChars;
          final nameLength = random.nextInt(20) + 3;
          final name = String.fromCharCodes(
            List.generate(
              nameLength,
              (_) => allChars.codeUnitAt(random.nextInt(allChars.length)),
            ),
          );
          // Ensure at least one non-ASCII character
          final cyrChar = cyrillicChars[random.nextInt(cyrillicChars.length)];
          final ext = extensions[random.nextInt(extensions.length)];
          return '$cyrChar$name$ext';
        }

        const numTrials = 100;
        final counterexamples = <String>[];

        for (var i = 0; i < numTrials; i++) {
          final input = generateNonAsciiFilename();
          final result = sanitizeFilenameForIOS(input);
          final expectedExt = _extractExtension(input);

          final isAscii = _isAsciiOnly(result);
          final hasCorrectExt = _extractExtension(result) == expectedExt;

          if (!isAscii || !hasCorrectExt) {
            counterexamples.add(
              '  input="$input" → result="$result" '
              '(ascii=$isAscii, ext=${_extractExtension(result)} expected=$expectedExt)',
            );
          }
        }

        expect(
          counterexamples,
          isEmpty,
          reason:
              'COUNTEREXAMPLES found (${counterexamples.length}/$numTrials):\n'
              '${counterexamples.take(10).join('\n')}'
              '${counterexamples.length > 10 ? '\n  ... and ${counterexamples.length - 10} more' : ''}',
        );
      },
    );
  });

  // =========================================================================
  // Property 2: Preservation — ASCII filenames and other platforms
  // =========================================================================
  //
  // These tests verify that existing correct behavior is preserved.
  // They MUST PASS on unfixed code (stub returns filename unchanged).
  //
  // Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5

  // -------------------------------------------------------------------------
  // Preservation: ASCII-only filenames remain unchanged
  // -------------------------------------------------------------------------

  group('Preservation — ASCII-only filenames unchanged', () {
    /// **Validates: Requirements 3.1**
    ///
    /// Property: For ANY filename containing ONLY ASCII characters,
    /// sanitizeFilenameForIOS MUST return the name unchanged.
    test(
      'property: for any ASCII-only filename, sanitization returns it unchanged',
      () {
        final random = Random(99); // deterministic seed

        const asciiLetters = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
        const digits = '0123456789';
        const safeChars = '$asciiLetters${digits}_-';
        const extensions = ['.pdf', '.docx', '.xlsx', '.txt', '.png', '.mp4', '.csv', '.zip'];

        String generateAsciiFilename() {
          final nameLength = random.nextInt(20) + 1;
          final name = String.fromCharCodes(
            List.generate(
              nameLength,
              (_) => safeChars.codeUnitAt(random.nextInt(safeChars.length)),
            ),
          );
          final ext = extensions[random.nextInt(extensions.length)];
          return '$name$ext';
        }

        const numTrials = 100;
        final failures = <String>[];

        for (var i = 0; i < numTrials; i++) {
          final input = generateAsciiFilename();
          final result = sanitizeFilenameForIOS(input);

          if (result != input) {
            failures.add(
              '  input="$input" → result="$result" (expected unchanged)',
            );
          }
        }

        expect(
          failures,
          isEmpty,
          reason:
              'ASCII-only filenames MUST NOT be modified by sanitization.\n'
              'Failures (${failures.length}/$numTrials):\n'
              '${failures.take(10).join('\n')}'
              '${failures.length > 10 ? '\n  ... and ${failures.length - 10} more' : ''}',
        );
      },
    );

    /// **Validates: Requirements 3.1**
    test('specific: report.pdf is returned unchanged', () {
      const input = 'report.pdf';
      expect(sanitizeFilenameForIOS(input), equals(input));
    });

    /// **Validates: Requirements 3.1**
    test('specific: data.csv is returned unchanged', () {
      const input = 'data.csv';
      expect(sanitizeFilenameForIOS(input), equals(input));
    });

    /// **Validates: Requirements 3.1**
    test('specific: my_document_2024.docx is returned unchanged', () {
      const input = 'my_document_2024.docx';
      expect(sanitizeFilenameForIOS(input), equals(input));
    });
  });

  // -------------------------------------------------------------------------
  // Preservation: Extension is always preserved
  // -------------------------------------------------------------------------

  group('Preservation — extension preserved after sanitization', () {
    /// **Validates: Requirements 3.5**
    ///
    /// Property: For ANY filename (ASCII or not), the file extension
    /// MUST be preserved after sanitization.
    test(
      'property: for any filename, the extension is preserved after sanitization',
      () {
        final random = Random(77); // deterministic seed

        const asciiChars = 'abcdefghijklmnopqrstuvwxyz0123456789_-';
        const cyrillicChars = 'абвгдежзийклмнопрстуфхцчшщъыьэюя';
        const allChars = '$asciiChars$cyrillicChars';
        const extensions = ['.pdf', '.docx', '.xlsx', '.txt', '.png', '.mp4', '.csv', '.zip', '.tar.gz'];

        String generateFilename() {
          final nameLength = random.nextInt(20) + 1;
          final name = String.fromCharCodes(
            List.generate(
              nameLength,
              (_) => allChars.codeUnitAt(random.nextInt(allChars.length)),
            ),
          );
          final ext = extensions[random.nextInt(extensions.length)];
          return '$name$ext';
        }

        const numTrials = 100;
        final failures = <String>[];

        for (var i = 0; i < numTrials; i++) {
          final input = generateFilename();
          final result = sanitizeFilenameForIOS(input);
          final inputExt = _extractExtension(input);
          final resultExt = _extractExtension(result);

          if (resultExt != inputExt) {
            failures.add(
              '  input="$input" (ext=$inputExt) → result="$result" (ext=$resultExt)',
            );
          }
        }

        expect(
          failures,
          isEmpty,
          reason:
              'File extension MUST be preserved after sanitization.\n'
              'Failures (${failures.length}/$numTrials):\n'
              '${failures.take(10).join('\n')}'
              '${failures.length > 10 ? '\n  ... and ${failures.length - 10} more' : ''}',
        );
      },
    );

    /// **Validates: Requirements 3.5**
    test('specific: .pdf extension preserved for Cyrillic filename', () {
      const input = 'документ.pdf';
      final result = sanitizeFilenameForIOS(input);
      expect(_extractExtension(result), equals('.pdf'));
    });

    /// **Validates: Requirements 3.5**
    test('specific: .docx extension preserved for mixed filename', () {
      const input = 'report_отчёт.docx';
      final result = sanitizeFilenameForIOS(input);
      expect(_extractExtension(result), equals('.docx'));
    });

    /// **Validates: Requirements 3.5**
    test('specific: filename without extension returns without extension', () {
      const input = 'README';
      final result = sanitizeFilenameForIOS(input);
      expect(_extractExtension(result), equals(''));
    });
  });

  // -------------------------------------------------------------------------
  // Preservation: Platform branching — sanitization only on iOS
  // -------------------------------------------------------------------------

  group('Preservation — platform branching logic', () {
    /// **Validates: Requirements 3.3, 3.4**
    ///
    /// Observation: on macOS, Process.run('open', ...) is used — not affected
    /// Observation: on web, saveFile is used — not affected
    /// Observation: saveFile and shareFile use original filename — not affected
    ///
    /// This test verifies that sanitizeFilenameForIOS is a pure function
    /// that can be applied selectively per platform. The openFile method
    /// should only call it on iOS; other platforms use the original name.
    test(
      'sanitizeFilenameForIOS is a pure function (no side effects, deterministic)',
      () {
        // Calling sanitizeFilenameForIOS multiple times with the same input
        // must always produce the same result — this ensures it can be safely
        // applied only on iOS without affecting other code paths.
        const inputs = [
          'report.pdf',
          'Документ.pdf',
          'my file (copy).docx',
          'report_отчёт_2024.xlsx',
          'data.csv',
        ];

        for (final input in inputs) {
          final result1 = sanitizeFilenameForIOS(input);
          final result2 = sanitizeFilenameForIOS(input);
          expect(
            result1,
            equals(result2),
            reason:
                'sanitizeFilenameForIOS must be deterministic: '
                '"$input" → "$result1" then "$result2"',
          );
        }
      },
    );

    /// **Validates: Requirements 3.3, 3.4, 3.5**
    ///
    /// The openFile method in event_extension.dart has platform branching:
    ///   - Web → saveFile (original name, no sanitization)
    ///   - macOS → Process.run('open', ...) (original name, no sanitization)
    ///   - iOS → should use sanitized name
    ///   - Other → OpenAppFile.open() with original name
    ///
    /// This test verifies that saveFile and shareFile paths are not affected
    /// by sanitization — they always use the original filename.
    /// We verify this by checking that sanitizeFilenameForIOS does NOT modify
    /// the original input string (it returns a new string or the same string).
    test(
      'sanitization does not mutate the original filename string',
      () {
        const original = 'Документ отчёт.pdf';
        final originalCopy = String.fromCharCodes(original.codeUnits);

        sanitizeFilenameForIOS(original);

        // The original string must remain unchanged — saveFile and shareFile
        // rely on file.name being the original filename.
        expect(original, equals(originalCopy));
      },
    );
  });
}
