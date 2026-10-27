"""Disposable emulator regression: old app data survives side-by-side install.

Unsigned CI builds receive a temporary validation signature only for this test.
That temporary APK/key is never included in a distribution artifact.
"""
import os
from pathlib import Path
import subprocess
import tempfile

sdk = Path(os.environ.get('ANDROID_SDK_ROOT') or os.environ['ANDROID_HOME'])
bt = sdk / 'build-tools/35.0.0'
new_id = 'hk.badminton.coach.autoanalysis'
old_id = 'hk.badminton.coach'

def run(*args):
    result = subprocess.run([str(x) for x in args], text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(f'{args[0]} failed: {result.stdout} {result.stderr}')
    return result.stdout

with tempfile.TemporaryDirectory(prefix='coach-install-') as directory:
    root = Path(directory)
    manifest = root / 'AndroidManifest.xml'
    manifest.write_text(f'''<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="{old_id}" android:versionCode="1" android:versionName="fixture">
    <uses-sdk android:minSdkVersion="28" android:targetSdkVersion="35"/>
    <permission android:name="{old_id}.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION" android:protectionLevel="signature"/>
    <uses-permission android:name="{old_id}.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION"/>
    <application android:label="Disposable legacy install fixture" android:debuggable="true"/>
    </manifest>''')
    legacy = root / 'legacy.apk'
    run(bt / 'aapt', 'package', '-f', '-M', manifest, '-I', sdk / 'platforms/android-36/android.jar', '-F', legacy)
    def temporary_signer(name):
        key = root / f'{name}.p12'
        run('keytool', '-genkeypair', '-keystore', key, '-storetype', 'PKCS12', '-storepass', 'android', '-keypass', 'android', '-alias', 'validation', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '2', '-dname', f'CN={name}', '-noprompt')
        return key
    def sign(key, source, dest):
        run(bt / 'apksigner', 'sign', '--ks', key, '--ks-pass', 'pass:android', '--out', dest, source)
    signed_legacy = root / 'legacy-signed.apk'
    sign(temporary_signer('old-fixture'), legacy, signed_legacy)
    release = Path('build/app/outputs/flutter-apk/app-release.apk')
    if os.environ.get('COACH_UNSIGNED_BUILD') == '1':
        validated = root / 'release-validation-only.apk'
        sign(temporary_signer('new-fixture'), release, validated)
        release = validated
    run('adb', 'install', '-r', signed_legacy)
    run('adb', 'shell', 'run-as', old_id, 'sh', '-c', '"echo legacy-record-kept > legacy-marker"')
    run('adb', 'install', '-r', release)
    packages = run('adb', 'shell', 'pm', 'list', 'packages')
    assert f'package:{old_id}\n' in packages and f'package:{new_id}\n' in packages
    assert 'legacy-record-kept' in run('adb', 'shell', 'run-as', old_id, 'cat', 'legacy-marker')
    launch = run('adb', 'shell', 'am', 'start', '-W', '-n', f'{new_id}/hk.badminton.coach.MainActivity')
    assert 'Status: ok' in launch, launch
    assert run('adb', 'shell', 'pidof', new_id).strip()
    run('adb', 'install', '-r', release)
    assert 'legacy-record-kept' in run('adb', 'shell', 'run-as', old_id, 'cat', 'legacy-marker')
    report = 'PASS: distinct signing certificates, side-by-side install, legacy sandbox marker retained, release launch, same-signer reinstall.\n'
    if os.environ.get('COACH_UNSIGNED_BUILD') == '1':
        report += 'CI uses a temporary test signature. Distribution signature must be verified after private local signing.\n'
    Path('build/install-compatibility.txt').write_text(report)
    print(report)
