import argparse
import hashlib
import json
import shutil
import urllib.request
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--prepare-fonts', action='store_true')
parser.add_argument('--cache', type=Path)
args = parser.parse_args()
build = root / 'kindlespouse' / 'build'
build.mkdir(parents=True, exist_ok=True)
cache = args.cache or build / 'cache'
cache.mkdir(parents=True, exist_ok=True)
manifest = json.loads((root / 'kindlespouse' / 'fonts.json').read_text(encoding='utf-8'))
for asset in manifest['assets']:
    filename = cache / asset['filename']
    if not filename.exists() or hashlib.sha256(filename.read_bytes()).hexdigest() != asset['sha256']:
        request = urllib.request.Request(asset['url'], headers={'User-Agent': 'KindleSpouse/0.1'})
        with urllib.request.urlopen(request, timeout=120) as response:
            data = response.read(asset['bytes'] + 1)
        if len(data) != asset['bytes'] or hashlib.sha256(data).hexdigest() != asset['sha256']:
            raise ValueError('Font fingerprint mismatch: ' + asset['filename'])
        temporary = filename.with_name(filename.name + '.partial')
        temporary.write_bytes(data)
        temporary.replace(filename)
    if args.prepare_fonts and asset.get('style'):
        destination = root / 'resources' / 'fonts' / 'kindlespouse' / asset['filename']
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(filename, destination)
package = build / 'KindleSpouse-Scribe-Overlay.zip'
with zipfile.ZipFile(package, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
    for filename in sorted((root / 'plugins' / 'kindlespouse.koplugin').iterdir()):
        if filename.is_file():
            archive.write(filename, 'koreader/plugins/kindlespouse.koplugin/' + filename.name)
    for asset in manifest['assets']:
        archive.write(cache / asset['filename'], asset['target'])
    archive.write(root / 'kindlespouse' / 'fonts.json', 'kindlespouse/licenses/reader-fonts/manifest.json')
    archive.write(root / 'kindlespouse' / 'INSTALL.txt', 'KindleSpouse-INSTALL.txt')
digest = hashlib.sha256(package.read_bytes()).hexdigest()
package.with_suffix('.zip.sha256').write_text(digest + '\n', encoding='ascii')
print(json.dumps({'file': str(package), 'bytes': package.stat().st_size, 'sha256': digest, 'fonts': 4, 'containsCredentials': False}))
