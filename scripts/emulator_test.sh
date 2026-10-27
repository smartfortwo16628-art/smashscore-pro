#!/usr/bin/env bash
set -euo pipefail
# VM service remains reachable over adb; the emulator has no mobile/Wi-Fi data.
adb shell svc wifi disable
adb shell svc data disable
flutter test integration_test/app_test.dart -d emulator-5554 --reporter expanded
