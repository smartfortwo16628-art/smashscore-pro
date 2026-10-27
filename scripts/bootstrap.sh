#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
flutter --version
if [ ! -f android/gradlew ]; then
  flutter create --no-pub --platforms=android --project-name badminton_ai_coach --org hk.badminton --empty .generated_host
  python3 - <<'PY'
from pathlib import Path
import shutil
src=Path('.generated_host/android')
for f in src.rglob('*'):
    if f.is_file():
        target=Path('android')/f.relative_to(src)
        if not target.exists():
            target.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(f,target)
PY
fi
chmod +x android/gradlew
flutter pub get
