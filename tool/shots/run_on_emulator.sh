#!/usr/bin/env bash
# Runs inside reactivecircus/android-emulator-runner (emulator booted, adb connected).
set -uo pipefail
SERVER="${EDUX_SHOTS_SERVER:-http://10.0.2.2:8000}"
adb wait-for-device
adb shell settings put global window_animation_scale 0 || true
adb shell settings put global transition_animation_scale 0 || true
adb shell settings put global animator_duration_scale 0 || true
# Clean status bar (System UI demo mode): fixed clock, full battery and signal, no notifications.
adb shell settings put global sysui_demo_allowed 1 || true
adb shell am broadcast -a com.android.systemui.demo -e command enter || true
adb shell am broadcast -a com.android.systemui.demo -e command clock -e hhmm 0941 || true
adb shell am broadcast -a com.android.systemui.demo -e command battery -e level 100 -e plugged false || true
adb shell am broadcast -a com.android.systemui.demo -e command network -e wifi show -e level 4 || true
adb shell am broadcast -a com.android.systemui.demo -e command network -e mobile show -e datatype none -e level 4 || true
adb shell am broadcast -a com.android.systemui.demo -e command notifications -e visible false || true
adb shell wm size
adb shell wm density
flutter test integration_test/shots_test.dart -d emulator-5554 --reporter expanded \
  --dart-define=EDUX_SERVER="$SERVER" 2>&1 | tee test.log
status=${PIPESTATUS[0]}
echo "flutter test exit code: $status"
exit 0
