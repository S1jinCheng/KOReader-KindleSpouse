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
parser.add_argument('--fonts', type=Path)
parser.add_argument('--statistics', action='store_true')
parser.add_argument('--integrated', action='store_true')
parser.add_argument('--package', type=Path)
parser.add_argument('--feature', choices=['highlight'], default='highlight')
args = parser.parse_args()
if args.package:
    args.integrated = True
runtime = args.runtime.resolve()
checks = root / 'kindlespouse/build/reader-checks'
checks.mkdir(parents=True, exist_ok=True)
sandbox = Path(tempfile.mkdtemp(prefix=args.feature + '-', dir=checks))
(sandbox / 'patches').mkdir()
(sandbox / 'fonts').mkdir()
if args.fonts:
    for name in ['NotoSerifCJKsc-Regular.otf', 'NotoSansCJKsc-Regular.otf']:
        shutil.copyfile(args.fonts / name, sandbox / 'fonts' / name)
plugin = root / 'plugins/kindlespouse.koplugin'
if args.integrated:
    target = sandbox / 'plugins/kindlespouse.koplugin'
    target.parent.mkdir()
    if args.package:
        from package_test import install_plugin
        plugin = install_plugin(args.package, target)
    else:
        target.symlink_to(plugin, target_is_directory=True)
book = sandbox / 'generated.epub'
with zipfile.ZipFile(book, 'w') as archive:
    archive.writestr('mimetype', 'application/epub+zip')
    archive.writestr('META-INF/container.xml', '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="book.opf" media-type="application/oebps-package+xml"/></rootfiles></container>')
    archive.writestr('book.opf', '<package version="2.0" xmlns="http://www.idpf.org/2007/opf" unique-identifier="book"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="book">synthetic-reader</dc:identifier><dc:title>A Quiet Morning · 阅读</dc:title><dc:creator>Generated Fixture</dc:creator><dc:language>en</dc:language></metadata><manifest><item id="text" href="chapter.xhtml" media-type="application/xhtml+xml"/><item id="toc" href="toc.ncx" media-type="application/x-dtbncx+xml"/></manifest><spine toc="toc"><itemref idref="text"/></spine></package>')
    archive.writestr('chapter.xhtml', '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>A Quiet Morning</title></head><body><h1 id="chapter">A Quiet Morning</h1>' + ''.join('<p>A quiet morning brings time to read. These generated words test a real selection without any personal book or account. The river flows beside the garden and the reader turns another page.</p>' for _ in range(180)) + '</body></html>')
    archive.writestr('toc.ncx', '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1"><head><meta name="dtb:uid" content="synthetic-reader"/></head><docTitle><text>A Quiet Morning</text></docTitle><navMap><navPoint id="chapter" playOrder="1"><navLabel><text>A Quiet Morning</text></navLabel><content src="chapter.xhtml#chapter"/></navPoint></navMap></ncx>')
disabled = ','.join('[' + json.dumps(path.name.removesuffix('.koplugin')) + ']=true' for path in (runtime / 'plugins').iterdir() if path.name.endswith('.koplugin') and not (args.statistics and path.name == 'statistics.koplugin'))
(sandbox / 'settings.reader.lua').write_text('return {language="en",last_migration_date=20260701,quickstart_shown_version=99999999,color_rendering=false,color_rendering_shown=true,disable_network_connection=true,auto_suspend_timeout_seconds=0,default_highlight_action="ask",show_bottom_menu=false,plugins_disabled={' + disabled + '}}', encoding='utf-8')
(sandbox / 'patches/2-reader-check.lua').write_text((root / 'kindlespouse/test_reader.lua').read_text(encoding='utf-8'), encoding='utf-8')
environment = dict(os.environ, KINDLESPOUSE_TEST_INTEGRATED='1' if args.integrated else '0', KINDLESPOUSE_PLUGIN_DIR=str(plugin), SDL_VIDEODRIVER='dummy', SDL_AUDIODRIVER='dummy', XDG_DATA_HOME=str(sandbox), KO_HOME=str(sandbox), KINDLESPOUSE_TEST_ROOT=str(root), KINDLESPOUSE_TEST_SANDBOX=str(sandbox), KINDLESPOUSE_READER_FEATURE=args.feature, EMULATE_READER_W='1860', EMULATE_READER_H='2480', EMULATE_READER_DPI='300', LD_LIBRARY_PATH='libs')
result = subprocess.run([str(runtime / 'luajit'), 'reader.lua', str(book)], cwd=runtime, env=environment, capture_output=True, text=True, timeout=120)
(sandbox / 'runtime.log').write_text(result.stdout + result.stderr, encoding='utf-8')
print(str(sandbox))
print('\n'.join(line for line in result.stdout.splitlines() if 'READER CHECK' in line))
if result.returncode or 'READER CHECK PASSED' not in result.stdout:
    print((result.stdout + result.stderr)[-6000:])
    raise SystemExit(result.returncode or 1)