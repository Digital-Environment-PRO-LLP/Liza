# Changelog

## Liza

### Latest

- feat(chat): mention pills, pin @liza chat, auto-create Liza DM
- fix(push): resolve duplicate notifications, missing loc-keys, and message truncation
- fix(stability): only hard-restart on startup failures, not runtime errors
- fix(windows): ignore non-fatal zone errors (temp file deletion, zone mismatch)
- fix(auth): redirect desktop auth callback to auth proxy /done page
- fix(windows): resolve libsqlcipher.dll not found and auto-recovery crashes
- feat(windows): add local notification support via sync events
- fix(windows): remove broken placeholder client fallback on native init failure
- fix(ux): seamless auto-recovery on init errors instead of dead-end screens
- fix(ios): restore notification sound after Communication Notification wrapping
- fix(platform): resolve App Store/Play Store warnings and missing permissions
- fix(client): surface initialization error instead of empty list crash
- fix(windows): support ARM64 cross-compilation and update version format
- fix(android): add namespace and compileSdk compat for AGP 8+
- fix(input): disable smart punctuation in chat input
- feat(audio): add voice message transcription with LRU cache
- feat(macos): add native APNs push plugin with thread-safe token handling
- feat(ios): add Communication Notifications with sender avatar
- feat(auth): rewrite auth proxy login with multi-platform support
- fix: refresh HTTP connections on resume + handle read marker errors
- fix: strip reply fallback from plain text message body
- fix: force-disable HTML rendering in messages
- fix: translate fallback error screen to Russian
- fix(ios): prevent grey screen on Keychain lock + improve error recovery
- feat: Android improvements + rebrand localizations
- fix: macOS window size, push notification content, disable markdown formatting
