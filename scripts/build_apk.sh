#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/bootstrap.sh
flutter analyze
flutter test --reporter expanded
flutter build apk --release
python3 scripts/verify_apk.py build/app/outputs/flutter-apk/app-release.apk
