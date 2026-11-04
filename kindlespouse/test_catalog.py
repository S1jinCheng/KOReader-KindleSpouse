import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument('--runtime', type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
runtime = args.runtime.resolve()
output = root / 'kindlespouse' / 'build' / 'catalog-tests'
output.mkdir(parents=True, exist_ok=True)
fixture = Path(tempfile.mkdtemp(prefix='run-', dir=output))
books = fixture / 'books'
start = fixture / 'start'
start.mkdir()
files = []
for index in range(500):
    directory = books / f'group-{index % 5}' / f'part-{index % 3}' / f'shelf-{index % 2}'
    directory.mkdir(parents=True, exist_ok=True)
    filename = directory / f'book-{index:03d}.epub'
    with zipfile.ZipFile(filename, 'w') as archive:
        archive.writestr('mimetype', 'application/epub+zip')
        archive.writestr('META-INF/container.xml', '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="book.opf" media-type="application/oebps-package+xml"/></rootfiles></container>')
        archive.writestr('book.opf', f'<package version="2.0" xmlns="http://www.idpf.org/2007/opf" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">catalog-{index}</dc:identifier><dc:title>Fixture Book {index:03d}</dc:title><dc:creator>Generated Author</dc:creator><dc:language>en</dc:language></metadata><manifest><item id="text" href="text.xhtml" media-type="application/xhtml+xml"/></manifest><spine toc="ncx"><itemref idref="text"/></spine></package>')
        archive.writestr('text.xhtml', '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Generated</title></head><body><p>Generated catalog fixture.</p></body></html>')
    files.append(str(filename))
for directory in (books / '.notebooks', books / 'ignored.sdr'):
    directory.mkdir()
    (directory / 'private.epub').write_bytes(Path(files[0]).read_bytes())
with zipfile.ZipFile(files[0]) as source, zipfile.ZipFile(fixture / 'queue-source.epub', 'w') as target:
    for entry in source.infolist():
        data = source.read(entry.filename)
        if entry.filename == 'book.opf':
            data = data.decode().replace('</metadata>', '<meta name="cover" content="cover"/></metadata>').replace('</manifest>', '<item id="cover" href="cover.svg" media-type="image/svg+xml"/></manifest>').encode()
        target.writestr(entry, data)
    target.writestr('cover.svg', '<svg xmlns="http://www.w3.org/2000/svg" width="200" height="300"><rect width="200" height="300" fill="gray"/><text x="25" y="100">Generated cover</text></svg>')
os.symlink(books, books / 'loop')
(fixture / 'files.json').write_text(json.dumps(files), encoding='utf-8')
(fixture / 'patches').mkdir()
(fixture / 'patches' / '2-catalog-test.lua').write_text((root / 'kindlespouse' / 'test_catalog.lua').read_text(encoding='utf-8'), encoding='utf-8')
disabled = ','.join('[' + json.dumps(path.name.removesuffix('.koplugin')) + ']=true' for path in (runtime / 'plugins').iterdir() if path.name.endswith('.koplugin'))
settings = f'return {{language="en",last_migration_date=20260701,quickstart_shown_version=99999999,home_dir={json.dumps(str(start))},start_with="filemanager",disable_network_connection=true,auto_suspend_timeout_seconds=0,plugins_disabled={{{disabled}}}}}'
(fixture / 'settings.reader.lua').write_text(settings, encoding='utf-8')
environment = dict(os.environ, SDL_VIDEODRIVER='dummy', SDL_AUDIODRIVER='dummy', XDG_DATA_HOME=str(fixture), KO_HOME=str(fixture), KINDLESPOUSE_TEST_ROOT=str(root), KINDLESPOUSE_CATALOG_FIXTURE=str(fixture), LD_LIBRARY_PATH='libs')
for name in ('catalog', 'extractor'):
    result = subprocess.run([str(runtime / 'luajit'), '-e', f'assert(loadfile({json.dumps(str(root / "plugins" / "kindlespouse.koplugin" / (name + ".lua")))}))'], cwd=runtime, env=environment, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
result = subprocess.run([str(runtime / 'luajit'), 'reader.lua', str(start)], cwd=runtime, env=environment, capture_output=True, text=True, timeout=240)
(fixture / 'runtime.log').write_text(result.stdout + result.stderr, encoding='utf-8')
assert result.returncode == 0 and 'KindleSpouse catalog acceptance passed' in result.stdout, (result.stdout + result.stderr)[-9000:]
print(result.stdout[result.stdout.index('KindleSpouse catalog acceptance passed'):].strip())
print('Artifacts:', fixture)
