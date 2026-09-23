#!/usr/bin/env bash
# Проверка пуш-банера на iOS-симуляторе через simctl push.
# ⚠️ Это тест ОТОБРАЖЕНИЯ и тап-навигации: simctl push инжектит уведомление
# в обход APNs, NSE НЕ запускается (mutable-content игнорируется). Полный
# NSE-тест — только реальный APNs sandbox или TestFlight (см. tests/e2e.md).
# Предусловие: симулятор загружен, приложение установлено и один раз
# разрешило уведомления (диалог Allow — руками или через AXe).
set -euo pipefail
cd "$(dirname "$0")"

BUNDLE="com.prodamus.laba.liza"
OUT=/tmp/liza-e2e-push
mkdir -p "$OUT"

UDID="${LIZA_E2E_SIM_UDID:-$(xcrun simctl list devices booted --json \
  | python3 -c 'import json,sys; d=json.load(sys.stdin)["devices"]; print(next((x["udid"] for v in d.values() for x in v), ""))')}"
[ -n "$UDID" ] || { echo "Нет загруженного симулятора (сначала make e2e-ios)"; exit 1; }

echo "Шлём пуш в $UDID ($BUNDLE)"
xcrun simctl push "$UDID" "$BUNDLE" ios-push-payload.json

sleep 2
xcrun simctl io "$UDID" screenshot "$OUT/ios-banner.png"
echo "✓ Скриншот банера: $OUT/ios-banner.png (проверить глазами/vision)"
