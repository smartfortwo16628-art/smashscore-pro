"""Check the actual signed artifact, not only source manifest claims."""
import hashlib
import os
from pathlib import Path
import subprocess
import sys

apk = Path(sys.argv[1])
sdk = Path(os.environ.get('ANDROID_SDK_ROOT') or os.environ['ANDROID_HOME'])
build_tools = sdk / 'build-tools' / '35.0.0'
def run(*args):
    return subprocess.check_output([str(x) for x in args], text=True)
badging = run(build_tools / 'aapt', 'dump', 'badging', apk)
assert "package: name='hk.badminton.coach'" in badging
assert "sdkVersion:'28'" in badging
assert "targetSdkVersion:'35'" in badging
assert 'application-debuggable' not in badging
for denied in ('INTERNET', 'ACCESS_NETWORK_STATE', 'RECEIVE_BOOT_COMPLETED', 'FOREGROUND_SERVICE', 'CAMERA', 'RECORD_AUDIO', 'READ_EXTERNAL_STORAGE', 'WRITE_EXTERNAL_STORAGE', 'MANAGE_EXTERNAL_STORAGE', 'READ_MEDIA_VIDEO'):
    assert f"android.permission.{denied}" not in badging, denied
signature = run(build_tools / 'apksigner', 'verify', '--verbose', '--print-certs', apk)
report = badging + '\n' + signature + '\nSHA256: ' + hashlib.sha256(apk.read_bytes()).hexdigest() + '\n'
Path('build/apk-verification.txt').write_text(report)
print(report)
