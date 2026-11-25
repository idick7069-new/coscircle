"""Verify upload dimensions, encoding and size without altering images."""
from pathlib import Path
from PIL import Image
import json
root = Path(__file__).resolve().parents[2] / 'output/google-play/2026-11-19'
checks = [('app-icon-512.png', (512, 512), 1024 * 1024), ('feature-graphic-1024x500.png', (1024, 500), 8 * 1024 * 1024)]
checks += [(str(p.relative_to(root)), (1080, 1920), 8 * 1024 * 1024) for p in sorted((root / 'phone-screenshots').glob('*.png'))]
assert len(checks) == 8
report = []
for name, size, limit in checks:
    p = root / name
    with Image.open(p) as im:
        assert im.format == 'PNG' and im.size == size, name
        assert p.stat().st_size <= limit, name
        if name.startswith('feature'):
            assert im.mode == 'RGB', name
        if 'A' in im.getbands():
            assert im.getchannel('A').getextrema() == (255, 255), name
        report.append(dict(file=name, width=im.width, height=im.height, mode=im.mode, bytes=p.stat().st_size, passed=True))
(root / 'validation.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
print('PASS: all 8 Google Play upload images have correct dimensions, opaque pixels, and file sizes.')
