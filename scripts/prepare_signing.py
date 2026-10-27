"""Restore a private signing key only from an explicitly configured CI secret."""
import base64
import json
import os
from pathlib import Path

raw = os.environ.get('COACH_ANDROID_SIGNING', '')
if not raw:
    print('No signing secret: build an unsigned APK for private local signing.')
else:
    data = json.loads(raw)
    password = data['password']
    alias = data['alias']
    assert password and all(c.isalnum() or c in '-_' for c in password)
    assert alias and all(c.isalnum() or c in '-_' for c in alias)
    private = Path(os.environ.get('RUNNER_TEMP', 'build/signing')).resolve()
    private.mkdir(parents=True, exist_ok=True)
    key = private / 'coach-auto.p12'
    key.write_bytes(base64.b64decode(data['keystore_base64'], validate=True))
    key.chmod(0o600)
    properties = Path('android/key.properties')
    properties.write_text(f'storeFile={key.as_posix()}\nstorePassword={password}\nkeyAlias={alias}\nkeyPassword={password}\n')
    properties.chmod(0o600)
    print('Private signing configuration restored; no key material is logged.')
