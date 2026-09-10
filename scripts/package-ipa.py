#!/usr/bin/env python3
"""Package the signed Theos application without touching older VK builds."""
from pathlib import Path
import plistlib
import zipfile

root = Path(__file__).resolve().parents[1]
app = root / '.theos' / '_' / 'Applications' / 'OpenVK.app'
if not (app / 'OpenVK').is_file():
    raise SystemExit('Run make package FINALPACKAGE=1 first')
info = plistlib.loads((app / 'Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'org.openvk.ios6'
assert info['CFBundleExecutable'] == 'OpenVK'
output = root / 'build' / 'OpenVK.ipa'
output.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
    for source in sorted(app.rglob('*')):
        if source.is_file():
            archive.write(source, str(Path('Payload/OpenVK.app') / source.relative_to(app)))
with zipfile.ZipFile(output) as archive:
    assert archive.testzip() is None
    binary = archive.read('Payload/OpenVK.app/OpenVK')
    assert b'api.openvk.org' in binary
    assert b'oauth.vk.com' not in binary
    assert b'api.vk.com' not in binary
print(output)
