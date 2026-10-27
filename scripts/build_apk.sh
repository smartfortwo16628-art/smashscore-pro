#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/bootstrap.sh
python3 scripts/prepare_pose_fixture.py
dart format lib test integration_test
flutter analyze
flutter test --reporter expanded
flutter build apk --release
if [ "${COACH_UNSIGNED_BUILD:-0}" = "1" ]; then
  python3 scripts/verify_apk.py build/app/outputs/flutter-apk/app-release.apk --unsigned
else
  python3 scripts/verify_apk.py build/app/outputs/flutter-apk/app-release.apk
fi
