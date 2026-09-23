#!/bin/bash
# Живой прогон жизненного цикла iOS-клиента на симуляторе (RL-ios-uiscene-lifecycle
# AC-14/AC-15): 3 сворачивания, блокировка, холодный старт по liza:// и ShareMedia-URL,
# «Поделиться» из Фото → Liza Share → «Опубликовать». После каждого шага процесс
# обязан остаться тем же (PID).
#
#   bash scripts/e2e/ios-lifecycle/run.sh <UDID-симулятора> <Runner.app> [тест ...]
#
# Runner.app — `flutter build ios --simulator --debug --dart-define=APP_ENV=local`.
# Нужен xcodegen (brew install xcodegen). Симулятор перезагружается (стартует
# разблокированным) и гасится в конце, если его поднял этот скрипт.
set -u
U=${1:?UDID}; APP=${2:?Runner.app}; shift 2
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d /tmp/liza-lifecycle.XXXX)
PIDFILE=/tmp/liza-lifecycle-pid
LOG=$WORK/xcodebuild.log

was_booted=$(xcrun simctl list devices | grep "$U" | grep -c Booted)
poller=""
xb=""
cleanup() {
  [ -n "$poller" ] && kill "$poller" 2>/dev/null
  [ -n "$xb" ] && kill "$xb" 2>/dev/null
  [ "$was_booted" = 0 ] && xcrun simctl shutdown "$U" 2>/dev/null
  rm -f "$PIDFILE"
}
trap cleanup EXIT INT TERM

cp -R "$HERE/project.yml" "$HERE/Host" "$HERE/UITests" "$WORK/"
(cd "$WORK" && xcodegen generate >/dev/null) || exit 1

xcrun simctl shutdown "$U" 2>/dev/null
xcrun simctl boot "$U" && xcrun simctl bootstatus "$U" >/dev/null 2>&1
xcrun simctl install "$U" "$APP" || exit 1
sleep 3

( while true; do
    p=$(xcrun simctl spawn "$U" launchctl list 2>/dev/null |
      awk '$3 ~ /UIKitApplication:ru\.prodamus\.liza\[/ && $1 != "-" {print $1}' | head -1)
    echo "${p:-0}" > "$PIDFILE.tmp" && mv "$PIDFILE.tmp" "$PIDFILE"
    sleep 0.5
  done ) &
poller=$!

ONLY=()
for t in "$@"; do ONLY+=("-only-testing:UITests/LizaLifecycleTests/$t"); done
expect=${#ONLY[@]}; [ "$expect" = 0 ] && expect=5
(cd "$WORK" && xcodebuild test -project LizaUI.xcodeproj -scheme UITests \
  -destination "id=$U" -derivedDataPath "$WORK/dd" ${ONLY[@]+"${ONLY[@]}"} > "$LOG" 2>&1) &
xb=$!
# xcodebuild после последнего теста висит минутами — ждём итогов и гасим сами.
for _ in $(seq 1 240); do
  [ "$(grep -cE "Test Case .*(passed|failed) \(" "$LOG")" -ge "$expect" ] && break
  kill -0 "$xb" 2>/dev/null || break
  sleep 5
done
grep -E "LIZA-AC:|Test Case .*(passed|failed) \(|error:" "$LOG" | cut -c1-220
failed=$(grep -cE "Test Case .*failed \(" "$LOG")
passed=$(grep -cE "Test Case .*passed \(" "$LOG")
echo "итог: passed=$passed failed=$failed (лог: $LOG)"
[ "$failed" = 0 ] && [ "$passed" -ge "$expect" ]
