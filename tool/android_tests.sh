#!/usr/bin/env bash
# Runs an integration test on a connected device/emulator and stores real
# `adb screencap` evidence whenever the test prints ADSPOCKET_SHOT=<name>.
#
#   tool/android_tests.sh integration_test/app_test.dart [device-id]
#   tool/android_tests.sh integration_test/live_meta_test.dart emulator-5554
set -u
target="${1:?usage: tool/android_tests.sh <integration_test/file.dart> [device]}"
device="${2:-emulator-5554}"
adb="${ADB:-adb}"
out="docs/screenshots"
log="build/$(basename "$target" .dart).log"
mkdir -p "$out" build
: > "$log"

flutter drive --driver=test_driver/integration_test.dart --target="$target" \
  -d "$device" > "$log" 2>&1 &
drive=$!

seen=0
while kill -0 "$drive" 2>/dev/null; do
  total=$(wc -l < "$log")
  if [ "$total" -gt "$seen" ]; then
    sed -n "$((seen + 1)),${total}p" "$log" |
      grep -oE 'ADSPOCKET_(SHOT=[a-z0-9-]+|TAP=[0-9]+,[0-9]+|TEXT=[A-Za-z0-9%]+|DEL=[0-9]+)' |
      while read -r marker; do
        case "$marker" in
          ADSPOCKET_SHOT=*)
            name="${marker#ADSPOCKET_SHOT=}"
            "$adb" -s "$device" exec-out screencap -p > "$out/$name.png"
            echo "screenshot: $out/$name.png" ;;
          ADSPOCKET_TAP=*)
            xy="${marker#ADSPOCKET_TAP=}"
            "$adb" -s "$device" shell input tap "${xy%,*}" "${xy#*,}"
            echo "tap: $xy" ;;
          ADSPOCKET_DEL=*)
            n="${marker#ADSPOCKET_DEL=}"
            "$adb" -s "$device" shell input keyevent KEYCODE_MOVE_END
            "$adb" -s "$device" shell input keyevent $(printf '67 %.0s' $(seq 1 "$n"))
            echo "delete: $n" ;;
          ADSPOCKET_TEXT=*)
            "$adb" -s "$device" shell input text "${marker#ADSPOCKET_TEXT=}"
            echo "text: ${marker#ADSPOCKET_TEXT=}" ;;
        esac
      done
    seen=$total
  fi
  sleep 1
done
wait "$drive"
status=$?
grep -E 'LIVE_|ADSPOCKET_|All tests passed|Some tests failed|Tempo esgotado|NÃO VERIFICADO|BLOQUEADO' "$log" |
  sed 's/^I\/flutter ([ 0-9]*): //'
echo "exit=$status log=$log"
exit "$status"
