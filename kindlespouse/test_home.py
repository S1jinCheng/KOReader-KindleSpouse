import argparse
import hashlib
import json
import os
import subprocess
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--runtime', type=Path, required=True)
parser.add_argument('--fonts', type=Path)
args = parser.parse_args()
runtime = args.runtime.resolve()
fonts = (args.fonts or root / 'kindlespouse' / 'build' / 'cache').resolve()
test = root / 'kindlespouse' / 'build' / 'test'
books = test / 'books'
output = root / 'kindlespouse' / 'build' / 'artifacts'
(books / 'nested').mkdir(parents=True, exist_ok=True)
(books / '.notebooks').mkdir(parents=True, exist_ok=True)
(books / '.notebooks' / 'private.txt').write_text('Excluded fixture', encoding='utf-8')
output.mkdir(parents=True, exist_ok=True)
(test / 'patches').mkdir(parents=True, exist_ok=True)
manifest = json.loads((root / 'kindlespouse' / 'fonts.json').read_text(encoding='utf-8'))
for asset in manifest['assets']:
    data = (fonts / asset['filename']).read_bytes()
    assert len(data) == asset['bytes'] and hashlib.sha256(data).hexdigest() == asset['sha256'], asset['filename']
    if asset.get('style'):
        count = int.from_bytes(data[4:6], 'big')
        tables = [data[12 + index * 16:16 + index * 16] for index in range(count)]
        assert b'cmap' in tables and b'fvar' not in tables, asset['filename'] + ' must be a static font'
titles = ['山间来信', '一日三餐', '阅读的四季', '慢慢走', '生活的形状', '一间自己的书房', '寻常故事', '昨日书简']
for index, title in enumerate(titles):
    filename = books / ('nested' if index > 3 else '') / (str(index + 1) + '.epub')
    with zipfile.ZipFile(filename, 'w') as archive:
        archive.writestr('mimetype', 'application/epub+zip')
        archive.writestr('META-INF/container.xml', '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="book.opf" media-type="application/oebps-package+xml"/></rootfiles></container>')
        archive.writestr('book.opf', f'<package version="2.0" xmlns="http://www.idpf.org/2007/opf" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">kindlespouse-test-{index}</dc:identifier><dc:title>{title}</dc:title><dc:creator>KindleSpouse</dc:creator><dc:language>zh-CN</dc:language><meta name="cover" content="cover"/></metadata><manifest><item id="text" href="text.xhtml" media-type="application/xhtml+xml"/><item id="cover" href="cover.svg" media-type="image/svg+xml"/><item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/></manifest><spine toc="ncx"><itemref idref="text"/></spine></package>')
        archive.writestr('text.xhtml', f'<html xmlns="http://www.w3.org/1999/xhtml"><head><title>{title}</title></head><body><h1>{title}</h1><p>测试中文图书与封面书架。</p></body></html>')
        archive.writestr('toc.ncx', f'<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1"><head><meta name="dtb:uid" content="kindlespouse-test-{index}"/></head><docTitle><text>{title}</text></docTitle><navMap><navPoint id="one" playOrder="1"><navLabel><text>{title}</text></navLabel><content src="text.xhtml"/></navPoint></navMap></ncx>')
        shade = [225, 180, 80, 210, 140, 55, 195, 110][index]
        ink = 'white' if shade < 150 else 'black'
        archive.writestr('cover.svg', f'<svg xmlns="http://www.w3.org/2000/svg" width="400" height="600"><rect width="400" height="600" fill="rgb({shade},{shade},{shade})"/><rect x="30" y="30" width="340" height="540" fill="none" stroke="{ink}" stroke-width="2"/><text x="200" y="260" fill="{ink}" font-size="32" text-anchor="middle">BOOK {index + 1}</text><text x="200" y="510" fill="{ink}" font-size="18" text-anchor="middle">KindleSpouse</text></svg>')
disabled = ','.join('[' + json.dumps(path.name.removesuffix('.koplugin')) + ']=true' for path in (runtime / 'plugins').iterdir() if path.name.endswith('.koplugin') and path.name != 'coverbrowser.koplugin')
settings = f'return {{language="en", last_migration_date=20260701, quickstart_shown_version=99999999, home_dir={json.dumps(str(books))}, start_with="filemanager", disable_network_connection=true, auto_suspend_timeout_seconds=0, plugins_disabled={{{disabled}}}}}'
(test / 'settings.reader.lua').write_text(settings, encoding='utf-8')
(test / 'patches' / '2-home-test.lua').write_text((root / 'kindlespouse' / 'test_home.lua').read_text(encoding='utf-8'), encoding='utf-8')
environment = dict(os.environ, SDL_VIDEODRIVER='dummy', SDL_AUDIODRIVER='dummy', KO_HOME=str(test), KINDLESPOUSE_TEST_ROOT=str(root), KINDLESPOUSE_TEST_FONTS=str(fonts), KINDLESPOUSE_TEST_OUTPUT=str(output), EMULATE_READER_W='1860', EMULATE_READER_H='2480', EMULATE_READER_DPI='300', LD_LIBRARY_PATH='libs')
for filename in (root / 'plugins' / 'kindlespouse.koplugin').glob('*.lua'):
    result = subprocess.run([str(runtime / 'luajit'), '-e', f'assert(loadfile({json.dumps(str(filename))}))'], cwd=runtime, env=environment, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
result = subprocess.run([str(runtime / 'luajit'), 'reader.lua', str(books)], cwd=runtime, env=environment, capture_output=True, text=True, timeout=180)
(test / 'runtime.log').write_text(result.stdout + result.stderr, encoding='utf-8')
assert result.returncode == 0 and 'KindleSpouse home acceptance passed' in result.stdout, (result.stdout + result.stderr)[-6000:]
for name in ['library', 'notebook', 'landscape']:
    assert (output / ('koreader-home-' + name + '.png')).stat().st_size > 1000
print('Passed: native cover grid, nested books, two tabs, original menus, four static Chinese fonts, portrait, landscape, native exit and reversible settings.')
