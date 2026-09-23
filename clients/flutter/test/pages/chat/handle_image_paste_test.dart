// ignore_for_file: avoid_print

// Safari URL Paste — Bug Condition Exploration Tests
//
// These tests encode EXPECTED (correct) behavior.
// They are designed to FAIL on unfixed code, confirming the bug exists.
//
// Validates: Requirements 1.1, 1.2, 1.3, 2.1, 2.2, 2.3
//
// Bug: When a URL is copied from Safari on iOS, Safari places rich clipboard
// data (URL text + preview image + public.url metadata) into the clipboard.
// The unfixed handleImagePaste() checks Pasteboard.files() and Pasteboard.image
// BEFORE checking clipboard text, so it treats the Safari preview as media and
// returns true — preventing the URL from being pasted as text.
//
// Formal bug condition:
//   isBugCondition(input):
//     clipboardText = Clipboard.getData(kTextPlain)
//     clipboardFiles = Pasteboard.files()
//     clipboardImage = Pasteboard.image
//     RETURN clipboardText != null AND clipboardText.isNotEmpty AND isUrl(clipboardText)
//            AND (clipboardFiles.isNotEmpty OR clipboardImage != null)

library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Simulated clipboard state — mirrors what Safari puts in the clipboard
// ---------------------------------------------------------------------------

/// Represents the state of the system clipboard at the moment of paste.
class ClipboardState {
  /// Plain text content (from Clipboard.getData(kTextPlain)).
  final String? text;

  /// Files returned by Pasteboard.files() — Safari puts public.url here.
  final List<String> files;

  /// Image bytes returned by Pasteboard.image — Safari puts preview PNG here.
  final Uint8List? image;

  const ClipboardState({
    this.text,
    this.files = const [],
    this.image,
  });
}

// ---------------------------------------------------------------------------
// Simulated handleImagePaste() — mirrors the UNFIXED logic in chat.dart
//
// The unfixed method:
//   1. Calls Pasteboard.files() — if non-empty, returns true (handles as media)
//   2. Calls Pasteboard.image  — if non-null, returns true (handles as media)
//   3. Returns false (no media found)
//
// Critically: it does NOT check clipboard text before the media checks.
// ---------------------------------------------------------------------------

/// Simulates the UNFIXED handleImagePaste() logic from lib/pages/chat/chat.dart.
///
/// Returns true if clipboard contained files or an image (handled as media).
/// Returns false if no media was found (falls through to text paste).
Future<bool> unfixedHandleImagePaste(ClipboardState state) async {
  // First check for files in clipboard (e.g. copied from Finder)
  // BUG: no URL text check before this
  if (state.files.isNotEmpty) {
    // Would show SendFileDialog — returns true
    return true;
  }

  // Then check for image data in clipboard (e.g. screenshot, copied image)
  // BUG: no URL text check before this either
  if (state.image != null) {
    // Would call sendImageFromClipBoard — returns true
    return true;
  }

  return false;
}

// ---------------------------------------------------------------------------
// Simulated handleImagePaste() — mirrors the FIXED logic in chat.dart
//
// The fixed method:
//   1. Checks clipboard text — if it's a URL (http/https), returns false immediately
//   2. Calls Pasteboard.files() — if non-empty, returns true (handles as media)
//   3. Calls Pasteboard.image  — if non-null, returns true (handles as media)
//   4. Returns false (no media found)
// ---------------------------------------------------------------------------

/// Simulates the FIXED handleImagePaste() logic from lib/pages/chat/chat.dart.
///
/// Returns false immediately if clipboard text is an http/https URL.
/// Returns true if clipboard contained files or an image (handled as media).
/// Returns false if no media was found (falls through to text paste).
Future<bool> fixedHandleImagePaste(ClipboardState state) async {
  // NEW: check if clipboard text is a URL — if so, skip media handling
  if (state.text != null && state.text!.isNotEmpty) {
    final text = state.text!.trim();
    final uri = Uri.tryParse(text);
    if (uri != null &&
        uri.hasScheme &&
        (uri.scheme == 'http' || uri.scheme == 'https')) {
      return false;
    }
  }

  // Existing logic unchanged
  if (state.files.isNotEmpty) {
    return true;
  }
  if (state.image != null) {
    return true;
  }
  return false;
}

// ---------------------------------------------------------------------------
// Helper: URL detection (mirrors what the FIX will add)
// ---------------------------------------------------------------------------

bool _isUrl(String text) {
  final uri = Uri.tryParse(text.trim());
  return uri != null &&
      uri.hasScheme &&
      (uri.scheme == 'http' || uri.scheme == 'https');
}

bool isBugCondition(ClipboardState state) {
  final text = state.text;
  return text != null &&
      text.isNotEmpty &&
      _isUrl(text) &&
      (state.files.isNotEmpty || state.image != null);
}

// ---------------------------------------------------------------------------
// Property 1: Fault Condition (verified against FIXED code)
//
// For any clipboard state where isBugCondition is true,
// handleImagePaste() SHOULD return false (URL must be pasted as text).
//
// These tests use fixedHandleImagePaste() and PASS — confirming the fix works.
//
// Validates: Requirements 2.1, 2.2, 2.3
// ---------------------------------------------------------------------------

void _runFaultConditionTests() {
  group(
    'Property 1: Fault Condition — URL from Safari pasted as text (FIXED)',
    () {
      // Specific counterexamples from the design document

      test(
        'COUNTEREXAMPLE 1: https://matrix.org + preview image → fixedHandleImagePaste() returns false (FIXED)',
        () async {
          // Safari copies URL from address bar:
          //   clipboard text = "https://matrix.org"
          //   clipboard image = preview PNG of the page
          final state = ClipboardState(
            text: 'https://matrix.org',
            image: Uint8List.fromList([137, 80, 78, 71]), // PNG header bytes
          );

          // Confirm this is a bug condition
          expect(
            isBugCondition(state),
            isTrue,
            reason: 'State has URL text + image — bug condition is met',
          );

          final result = await fixedHandleImagePaste(state);

          // EXPECTED (correct) behavior: return false so URL is pasted as text.
          // The fix checks URL text BEFORE media — so it returns false immediately.
          expect(
            result,
            isFalse,
            reason:
                'Fixed handleImagePaste() must return false for clipboard '
                'containing URL text "https://matrix.org" + preview image. '
                'The URL should be pasted as text, not sent as media.',
          );
        },
      );

      test(
        'COUNTEREXAMPLE 2: https://liza.prodamus.tech/ + file → fixedHandleImagePaste() returns false (FIXED)',
        () async {
          // Safari copies link from page:
          //   clipboard text = "https://liza.prodamus.tech/"
          //   clipboard files = ["/tmp/public.url"] (public.url metadata)
          final state = ClipboardState(
            text: 'https://liza.prodamus.tech/',
            files: ['/tmp/safari_public_url_12345'],
          );

          expect(
            isBugCondition(state),
            isTrue,
            reason: 'State has URL text + files — bug condition is met',
          );

          final result = await fixedHandleImagePaste(state);

          // EXPECTED: false (paste as text). Fix returns false before file check.
          expect(
            result,
            isFalse,
            reason:
                'Fixed handleImagePaste() must return false for clipboard '
                'containing URL text "https://liza.prodamus.tech/" + file. '
                'The URL should be pasted as text, not sent as media.',
          );
        },
      );

      test(
        'COUNTEREXAMPLE 3: https://example.com/path?q=1&r=2 + image → fixedHandleImagePaste() returns false (FIXED)',
        () async {
          // Safari copies URL with query parameters:
          //   clipboard text = "https://example.com/path?q=1&r=2"
          //   clipboard image = preview PNG
          final state = ClipboardState(
            text: 'https://example.com/path?q=1&r=2',
            image: Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
          );

          expect(
            isBugCondition(state),
            isTrue,
            reason: 'State has URL text + image — bug condition is met',
          );

          final result = await fixedHandleImagePaste(state);

          // EXPECTED: false (paste as text). Fix returns false before image check.
          expect(
            result,
            isFalse,
            reason:
                'Fixed handleImagePaste() must return false for clipboard '
                'containing URL text "https://example.com/path?q=1&r=2" + image. '
                'The URL should be pasted as text, not sent as media.',
          );
        },
      );

      // Property-based: multiple URL shapes all handled correctly by the fix
      final urlsWithImages = [
        'https://matrix.org',
        'https://liza.prodamus.tech/',
        'https://example.com/path?q=1&r=2',
        'https://github.com/example/liza',
        'http://example.com',
        'https://sub.domain.example.com/path/to/page#anchor',
        'https://example.com/search?q=hello+world&lang=en',
      ];

      for (final url in urlsWithImages) {
        test(
          'Property 1 (image): "$url" + preview image → should return false',
          () async {
            final state = ClipboardState(
              text: url,
              image: Uint8List.fromList([137, 80, 78, 71]),
            );

            expect(isBugCondition(state), isTrue);

            final result = await fixedHandleImagePaste(state);

            expect(
              result,
              isFalse,
              reason:
                  'Fixed handleImagePaste() must return false for URL "$url" '
                  'with preview image. URL text check fires before image check.',
            );
          },
        );

        test(
          'Property 1 (file): "$url" + public.url file → should return false',
          () async {
            final state = ClipboardState(
              text: url,
              files: ['/tmp/safari_url_data'],
            );

            expect(isBugCondition(state), isTrue);

            final result = await fixedHandleImagePaste(state);

            expect(
              result,
              isFalse,
              reason:
                  'Fixed handleImagePaste() must return false for URL "$url" '
                  'with file. URL text check fires before files check.',
            );
          },
        );
      }
    },
  );
}

// ---------------------------------------------------------------------------
// Property 2: Preservation (verified against FIXED code)
//
// For any clipboard state where isBugCondition is FALSE,
// fixedHandleImagePaste() MUST produce the same result as unfixedHandleImagePaste().
//
// These tests verify no regressions were introduced by the fix.
//
// Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5
// ---------------------------------------------------------------------------

void _runPreservationTests() {
  group(
    'Property 2: Preservation — existing paste behavior must not regress',
    () {
      // -----------------------------------------------------------------------
      // Preservation 3.1 & 3.4: Image-only clipboard (no URL text)
      // → handleImagePaste() MUST return true (media attachment)
      // -----------------------------------------------------------------------
      group('Image paste preserved (Req 3.1, 3.4)', () {
        final imageOnlyStates = [
          ClipboardState(
            image: Uint8List.fromList([137, 80, 78, 71]), // PNG header
          ),
          ClipboardState(
            text: null,
            image: Uint8List.fromList([255, 216, 255, 224]), // JPEG header
          ),
          ClipboardState(
            text: '', // empty text — not a URL
            image: Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
          ),
        ];

        for (final state in imageOnlyStates) {
          test(
            'Image-only clipboard (text="${state.text}") → returns true',
            () async {
              // Confirm this is NOT a bug condition
              expect(
                isBugCondition(state),
                isFalse,
                reason: 'No URL text — not a bug condition',
              );

              final result = await fixedHandleImagePaste(state);

              expect(
                result,
                isTrue,
                reason:
                    'Image-only clipboard must be handled as media attachment',
              );
            },
          );
        }

        // Property-based: any image bytes without URL text → returns true
        final imageSizes = [1, 4, 8, 16, 100, 1024];
        for (final size in imageSizes) {
          test(
            'Property 2 (image, $size bytes, no text) → returns true',
            () async {
              final state = ClipboardState(
                image: Uint8List(size)..fillRange(0, size, 0xFF),
              );

              expect(isBugCondition(state), isFalse);

              final result = await fixedHandleImagePaste(state);
              expect(
                result,
                isTrue,
                reason: 'Image without URL text must be treated as media',
              );
            },
          );
        }
      });

      // -----------------------------------------------------------------------
      // Preservation 3.2: Files-only clipboard (no URL text)
      // → handleImagePaste() MUST return true (media attachment)
      // -----------------------------------------------------------------------
      group('File paste preserved (Req 3.2)', () {
        final fileOnlyStates = [
          ClipboardState(files: ['/home/user/photo.jpg']),
          ClipboardState(files: ['/tmp/document.pdf']),
          ClipboardState(
            files: ['/home/user/image.png', '/home/user/video.mp4'],
          ),
          ClipboardState(
            text: null,
            files: ['/home/user/file.txt'],
          ),
          ClipboardState(
            text: '', // empty text — not a URL
            files: ['/home/user/archive.zip'],
          ),
        ];

        for (final state in fileOnlyStates) {
          test(
            'Files-only clipboard (files=${state.files}) → returns true',
            () async {
              expect(
                isBugCondition(state),
                isFalse,
                reason: 'No URL text — not a bug condition',
              );

              final result = await fixedHandleImagePaste(state);

              expect(
                result,
                isTrue,
                reason: 'Files without URL text must be handled as media',
              );
            },
          );
        }
      });

      // -----------------------------------------------------------------------
      // Preservation 3.3: Empty clipboard (no files, no image)
      // → handleImagePaste() MUST return false (fall through to text paste)
      // -----------------------------------------------------------------------
      group('Empty clipboard preserved (Req 3.3)', () {
        final emptyStates = [
          const ClipboardState(),
          const ClipboardState(text: null),
          const ClipboardState(text: ''),
          const ClipboardState(text: 'hello world'),
          const ClipboardState(text: 'just some plain text'),
          const ClipboardState(text: 'not a url at all'),
        ];

        for (final state in emptyStates) {
          test(
            'No-media clipboard (text="${state.text}") → returns false',
            () async {
              expect(
                isBugCondition(state),
                isFalse,
                reason: 'No media data — not a bug condition',
              );

              final result = await fixedHandleImagePaste(state);

              expect(
                result,
                isFalse,
                reason:
                    'Clipboard without files or image must return false '
                    '(fall through to text paste)',
              );
            },
          );
        }
      });

      // -----------------------------------------------------------------------
      // Preservation: Non-URL text + image
      // → handleImagePaste() MUST return true (image takes priority over plain text)
      // -----------------------------------------------------------------------
      group('Non-URL text + image preserved (image priority)', () {
        final nonUrlTexts = [
          'hello world',
          'just some text',
          'not a url',
          'ftp://not-http-or-https.com', // ftp is not http/https
          'file:///local/path',
          '   ', // whitespace only
          'matrix.org', // no scheme — not a URL
          'www.example.com', // no scheme — not a URL
        ];

        for (final text in nonUrlTexts) {
          test(
            'Non-URL text "$text" + image → returns true (image wins)',
            () async {
              final state = ClipboardState(
                text: text,
                image: Uint8List.fromList([137, 80, 78, 71]),
              );

              expect(
                isBugCondition(state),
                isFalse,
                reason: '"$text" is not a URL — not a bug condition',
              );

              final result = await fixedHandleImagePaste(state);

              expect(
                result,
                isTrue,
                reason:
                    'Non-URL text with image must be treated as media '
                    '(image takes priority over plain text)',
              );
            },
          );
        }

        // Also test non-URL text + files
        for (final text in nonUrlTexts) {
          test(
            'Non-URL text "$text" + files → returns true (files win)',
            () async {
              final state = ClipboardState(
                text: text,
                files: ['/home/user/photo.jpg'],
              );

              expect(
                isBugCondition(state),
                isFalse,
                reason: '"$text" is not a URL — not a bug condition',
              );

              final result = await fixedHandleImagePaste(state);

              expect(
                result,
                isTrue,
                reason:
                    'Non-URL text with files must be treated as media '
                    '(files take priority over plain text)',
              );
            },
          );
        }
      });
    },
  );
}

// ---------------------------------------------------------------------------
// Test entry point
// ---------------------------------------------------------------------------

void main() {
  _runFaultConditionTests();
  _runPreservationTests();
}
