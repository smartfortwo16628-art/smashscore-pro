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
assert "package: name='hk.badminton.coach.autoanalysis'" in badging
assert "versionCode='5'" in badging
assert "versionName='1.2.1'" in badging
assert "application-label:'羽毛球 AI 自動分析'" in badging
assert 'hk.badminton.coach.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION' not in badging
assert "sdkVersion:'28'" in badging
assert "targetSdkVersion:'35'" in badging
assert 'application-debuggable' not in badging
for denied in ('INTERNET', 'ACCESS_NETWORK_STATE', 'RECEIVE_BOOT_COMPLETED', 'FOREGROUND_SERVICE', 'CAMERA', 'RECORD_AUDIO', 'READ_EXTERNAL_STORAGE', 'WRITE_EXTERNAL_STORAGE', 'MANAGE_EXTERNAL_STORAGE', 'READ_MEDIA_VIDEO'):
    assert f"android.permission.{denied}" not in badging, denied
if '--unsigned' in sys.argv:
    result = subprocess.run([str(build_tools / 'apksigner'), 'verify', str(apk)], capture_output=True)
    assert result.returncode != 0, 'Unsigned staging artifact must not carry an unexpected signer'
    signature = 'SIGNATURE PENDING: unsigned staging artifact; do not install or distribute.'
else:
    signature = run(build_tools / 'apksigner', 'verify', '--verbose', '--print-certs', apk)
    expected_certificate = Path('android/signing-certificate-sha256.txt').read_text().strip()
    assert f'Signer #1 certificate SHA-256 digest: {expected_certificate}' in signature
report = badging + '\n' + signature + '\nSHA256: ' + hashlib.sha256(apk.read_bytes()).hexdigest() + '\n'
Path('build/apk-verification.txt').write_text(report)
print(report)
