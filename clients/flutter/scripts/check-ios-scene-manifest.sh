#!/usr/bin/env bash
# Гейт «SDK iOS ≥27 ⇒ scene-based жизненный цикл обязателен».
#
# С iOS 27 приложение, собранное свежим SDK без UIApplicationSceneManifest,
# UIKit не запускает вовсе — падение в
# _UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption до первого
# кадра. Так уехала сборка 3763 (заявка №34): собрана Xcode 27, на iOS 26
# работала, на iOS 27 не открывалась. Проверку зовёт build-ios.sh дважды: по
# исходному Info.plist до bump номера и по Info.plist собранного .app.
#
# Использование: check-ios-scene-manifest.sh <Info.plist> [версия SDK]
#   версия SDK по умолчанию — xcrun --sdk iphoneos --show-sdk-version.
# Выход: 0 — ок; 1 — манифеста нет при SDK ≥27; 2 — ошибка вызова.
set -euo pipefail

plist="${1:-}"
if [ -z "$plist" ] || [ ! -f "$plist" ]; then
  echo "check-ios-scene-manifest: нет файла Info.plist: '${plist}'" >&2
  exit 2
fi

sdk="${2:-$(xcrun --sdk iphoneos --show-sdk-version 2>/dev/null || echo 0)}"
sdk_major="${sdk%%.*}"
if ! [[ "$sdk_major" =~ ^[0-9]+$ ]]; then
  echo "check-ios-scene-manifest: не разобрал версию SDK '${sdk}'" >&2
  exit 2
fi

if [ "$sdk_major" -lt 27 ]; then
  echo "check-ios-scene-manifest: SDK ${sdk} < 27 — сцены не обязательны, пропуск"
  exit 0
fi

delegate="$(plutil -extract \
  UIApplicationSceneManifest.UISceneConfigurations.UIWindowSceneSessionRoleApplication.0.UISceneDelegateClassName \
  raw -o - "$plist" 2>/dev/null || true)"

if [ -z "$delegate" ]; then
  cat >&2 <<EOF
ERROR: сборка SDK iOS ${sdk} без scene-based жизненного цикла.
  В ${plist} нет UIApplicationSceneManifest с UISceneDelegateClassName.
  Такое приложение НЕ ЗАПУСТИТСЯ на iOS 27 (заявка №34, сборка 3763).
  См. docs/superpowers/specs/2026-09-21-ios-27-uiscene-lifecycle-design.md
EOF
  exit 1
fi

echo "check-ios-scene-manifest: ок (SDK ${sdk}, делегат сцены ${delegate})"
