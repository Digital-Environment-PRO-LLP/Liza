#!/usr/bin/env bash
# Проверка FCM-пуша при убитом приложении (полный e2e: локальный Synapse →
# прод-Sygnal → FCM → эмулятор). Предусловие: на эмуляторе выполнен
# make e2e-android (приложение установлено и залогинено под testuser,
# adb reverse активен). Запуск: make e2e-push-android. См. tests/e2e.md.
set -euo pipefail

PKG="com.prodamus.laba.liza.android"
HS="http://localhost:8008"
ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
ADB="$ANDROID_HOME/platform-tools/adb"
SERIAL=$("$ADB" devices | awk '/^emulator-/{print $1; exit}')
[ -n "$SERIAL" ] || { echo "Эмулятор не запущен (сначала make e2e-android)"; exit 1; }
ADB="$ADB -s $SERIAL"

OUT=/tmp/liza-e2e-push
mkdir -p "$OUT"

login() { # user pass → access_token
  curl -fsS -X POST "$HS/_matrix/client/v3/login" -H 'Content-Type: application/json' \
    -d "{\"type\":\"m.login.password\",
         \"identifier\":{\"type\":\"m.id.user\",\"user\":\"$1\"},
         \"password\":\"$2\",
         \"initial_device_display_name\":\"Liza E2E push $1\"}" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])'
}

echo "1/5 Разрешение на уведомления + убиваем приложение (am kill, НЕ force-stop:"
echo "    force-stop переводит в stopped state и FCM не доставляется)"
$ADB shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS || true
$ADB shell am kill "$PKG" || true

echo "2/5 Логиним акторов и готовим комнату"
TOK_A=$(login testuser testpass)
TOK_B=$(login testuser2 testpass2)
UID_A=$(curl -fsS "$HS/_matrix/client/v3/account/whoami" -H "Authorization: Bearer $TOK_A" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["user_id"])')
ROOM=$(curl -fsS -X POST "$HS/_matrix/client/v3/createRoom" -H "Authorization: Bearer $TOK_B" \
  -d "{\"invite\":[\"$UID_A\"],\"is_direct\":true,\"preset\":\"trusted_private_chat\"}" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["room_id"])')
curl -fsS -X POST "$HS/_matrix/client/v3/join/$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1],safe=''))" "$ROOM")" \
  -H "Authorization: Bearer $TOK_A" -d '{}' >/dev/null

echo "3/5 B пишет сообщение (это должно породить пуш на убитое приложение)"
MARKER="e2e push $(date +%s)"
curl -fsS -X PUT "$HS/_matrix/client/v3/rooms/$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1],safe=''))" "$ROOM")/send/m.room.message/e2e$(date +%s)" \
  -H "Authorization: Bearer $TOK_B" \
  -d "{\"msgtype\":\"m.text\",\"body\":\"$MARKER\"}" >/dev/null

echo "4/5 Ждём банер (poll dumpsys notification --noredact, до 90с)"
DEADLINE=$(( $(date +%s) + 90 ))
while true; do
  if $ADB shell dumpsys notification --noredact 2>/dev/null | grep -q "$PKG"; then
    echo "✓ Уведомление от $PKG в шторке"
    $ADB shell dumpsys notification --noredact | grep -B2 -A15 "$PKG" \
      > "$OUT/dumpsys-notification.txt" || true
    break
  fi
  if [ "$(date +%s)" -ge "$DEADLINE" ]; then
    echo "✗ Пуш не пришёл за 90с. Диагностика:"
    echo "  - логи FCM:      adb logcat -d -s FirebaseMessaging FcmPushService GCM"
    echo "  - pusher на месте? curl $HS/_matrix/client/v3/pushers -H 'Authorization: Bearer <A>'"
    echo "  - Sygnal (прод): недоступен без VPN — смотреть event_push_actions локально"
    exit 1
  fi
  sleep 3
done

echo "5/5 Скриншот шторки → $OUT"
$ADB shell cmd statusbar expand-notifications
sleep 1
$ADB exec-out screencap -p > "$OUT/notification-shade.png"
$ADB shell cmd statusbar collapse
echo "✓ Готово: $OUT/notification-shade.png, $OUT/dumpsys-notification.txt"
