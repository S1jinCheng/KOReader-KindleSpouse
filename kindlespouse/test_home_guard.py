import argparse
import json
import os
import shutil
import subprocess
import tempfile
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--runtime', type=Path, required=True)
parser.add_argument('--fonts', type=Path, required=True)
parser.add_argument('--case', choices=['all', 'supported', 'unknown', 'missing', 'layout', 'layout_missing', 'postinit', 'chooser', 'books', 'tab', 'catalog'], default='all')
args = parser.parse_args()
runtime = args.runtime.resolve()
checks = root / 'kindlespouse/build/home-guard-checks'
checks.mkdir(parents=True, exist_ok=True)
modes = ['supported', 'unknown', 'missing', 'layout', 'layout_missing', 'postinit', 'chooser', 'books', 'tab', 'catalog'] if args.case == 'all' else [args.case]
for mode in modes:
    sandbox = Path(tempfile.mkdtemp(prefix=mode + '-', dir=checks))
    books = sandbox / 'books'
    (books / 'nested').mkdir(parents=True)
    (books / '.notebooks').mkdir()
    private = books / '.notebooks/private.txt'
    private.write_text('Untouched synthetic notebook fixture', encoding='utf-8')
    (sandbox / 'patches').mkdir()
    (sandbox / 'fonts').mkdir()
    for name in ['NotoSerifCJKsc-Regular.otf', 'NotoSansCJKsc-Regular.otf']:
        shutil.copyfile(args.fonts / name, sandbox / 'fonts' / name)
    for number in range(8):
        filename = books / ('nested' if number > 3 else '') / (str(number + 1) + '.epub')
        with zipfile.ZipFile(filename, 'w') as archive:
            archive.writestr('mimetype', 'application/epub+zip')
            archive.writestr('META-INF/container.xml', '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="book.opf" media-type="application/oebps-package+xml"/></rootfiles></container>')
            archive.writestr('book.opf', f'<package version="2.0" xmlns="http://www.idpf.org/2007/opf" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">synthetic-{number}</dc:identifier><dc:title>Synthetic Book {number}</dc:title><dc:creator>Generated Fixture</dc:creator><dc:language>en</dc:language></metadata><manifest><item id="text" href="text.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="text"/></spine></package>')
            archive.writestr('text.xhtml', '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Synthetic fixture</title></head><body><p>Generated test book. No personal content.</p></body></html>')
    disabled = ','.join('[' + json.dumps(path.name.removesuffix('.koplugin')) + ']=true' for path in (runtime / 'plugins').iterdir() if path.name.endswith('.koplugin'))
    settings = 'return {language="en",last_migration_date=20260701,quickstart_shown_version=99999999,home_dir=' + json.dumps(str(books)) + ',start_with="filemanager",kindlespouse_home=true,kindlespouse_sync_sentinel="unchanged",disable_network_connection=true,auto_suspend_timeout_seconds=0,plugins_disabled={' + disabled + '}}'
    (sandbox / 'settings.reader.lua').write_text(settings, encoding='utf-8')
    (sandbox / 'patches/2-home-guard-test.lua').write_text((root / 'kindlespouse/test_home_guard.lua').read_text(encoding='utf-8-sig'), encoding='utf-8')
    environment = dict(os.environ, SDL_VIDEODRIVER='dummy', SDL_AUDIODRIVER='dummy', XDG_DATA_HOME=str(sandbox), KO_HOME=str(sandbox), KINDLESPOUSE_TEST_ROOT=str(root), KINDLESPOUSE_GUARD_CASE=mode, KINDLESPOUSE_GUARD_OUTPUT=str(sandbox), EMULATE_READER_W='1860', EMULATE_READER_H='2480', EMULATE_READER_DPI='300', LD_LIBRARY_PATH='libs')
    result = subprocess.run([str(runtime / 'luajit'), 'reader.lua', str(books)], cwd=runtime, env=environment, capture_output=True, text=True, timeout=90)
    (sandbox / 'runtime.log').write_text(result.stdout + result.stderr, encoding='utf-8')
    assert private.read_text(encoding='utf-8') == 'Untouched synthetic notebook fixture'
    if result.returncode or 'HOME GUARD PASSED ' + mode not in result.stdout:
        print((result.stdout + result.stderr)[-6000:])
        raise SystemExit(result.returncode or 1)
    print('HOME GUARD PASSED ' + mode + ' ' + str(sandbox), flush=True)
print('Home guard integration passed all requested cases.')
