"""Build a test-only still-person video from Google's public MediaPipe test asset.

This is an inference smoke test, NOT badminton validation data. Nothing is added
to the release APK. Pin the upstream content so test evidence is reproducible.
"""
import base64
import hashlib
from pathlib import Path
import subprocess
import urllib.request

root = Path(__file__).resolve().parents[1]
scratch = root / 'build' / 'pose-fixture'
scratch.mkdir(parents=True, exist_ok=True)
url = 'https://storage.googleapis.com/mediapipe-assets/pose.jpg?generation=1678737494661975'
with urllib.request.urlopen(url, timeout=45) as response:
    image = response.read()
assert hashlib.sha256(image).hexdigest() == 'c8a830ed683c0276d713dd5aeda28f415f10cd6291972084a40d0d8b934ed62b'
source = scratch / 'pose.jpg'
source.write_bytes(image)
clip = scratch / 'pose.mp4'
subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-loop', '1', '-i', str(source),
                '-t', '3', '-r', '8', '-vf', 'scale=960:640', '-c:v', 'libx264',
                '-pix_fmt', 'yuv420p', '-movflags', '+faststart', str(clip)], check=True)
encoded = base64.b64encode(clip.read_bytes()).decode('ascii')
(root / 'integration_test' / 'pose_clip.dart').write_text(
    '// Generated test fixture; never bundled in the release application.\n'
    f"const poseClipBase64 = '{encoded}';\n")
print('Prepared pinned MediaPipe still-person inference test clip.')
