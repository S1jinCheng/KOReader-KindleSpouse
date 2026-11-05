import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--runtime', type=Path, required=True)
    parser.add_argument('--fonts', type=Path, required=True)
    args = parser.parse_args()
    project = Path(__file__).resolve().parent.parent
    runtime = args.runtime.resolve()
    output = project / 'kindlespouse/build/cached-startup-checks'
    output.mkdir(parents=True, exist_ok=True)
    fixture = Path(tempfile.mkdtemp(prefix='run-', dir=output))
    books = fixture / 'books'
    count = 120
    for index in range(count):
        directory = books / f'group-{index % 4}'
        directory.mkdir(parents=True, exist_ok=True)
        filename = directory / f'book-{index:03d}.epub'
        with zipfile.ZipFile(filename, 'w') as archive:
            archive.writestr('mimetype', 'application/epub+zip')
            archive.writestr('META-INF/container.xml', '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="book.opf" media-type="application/oebps-package+xml"/></rootfiles></container>')
            archive.writestr('book.opf', f'<package version="2.0" xmlns="http://www.idpf.org/2007/opf" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">cached-{index}</dc:identifier><dc:title>缓存书籍 {index:03d}</dc:title><dc:creator>KindleSpouse</dc:creator><dc:language>zh-CN</dc:language></metadata><manifest><item id="text" href="text.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="text"/></spine></package>')
            archive.writestr('text.xhtml', '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>缓存书籍</title></head><body><p>缓存启动验收。</p></body></html>')
    (fixture / 'patches').mkdir()
    (fixture / 'patches/2-cached-startup-test.lua').write_text((project / 'kindlespouse/test_cached_startup.lua').read_text(encoding='utf-8'), encoding='utf-8')
    (fixture / 'fonts').mkdir()
    for name in ('NotoSerifCJKsc-Regular.otf', 'NotoSansCJKsc-Regular.otf'):
        shutil.copyfile(args.fonts / name, fixture / 'fonts' / name)
    (fixture / 'plugins').mkdir()
    (fixture / 'plugins/kindlespouse.koplugin').symlink_to(project / 'plugins/kindlespouse.koplugin', target_is_directory=True)
    disabled = ','.join('[' + json.dumps(path.name.removesuffix('.koplugin')) + ']=true' for path in (runtime / 'plugins').iterdir() if path.name.endswith('.koplugin') and path.name != 'coverbrowser.koplugin')
    settings = f'return {{language="zh_CN",last_migration_date=20260701,quickstart_shown_version=99999999,home_dir={json.dumps(str(books))},start_with="filemanager",disable_network_connection=true,auto_suspend_timeout_seconds=0,plugins_disabled={{{disabled}}}}}'
    (fixture / 'settings.reader.lua').write_text(settings, encoding='utf-8')
    environment = dict(os.environ, SDL_VIDEODRIVER='dummy', SDL_AUDIODRIVER='dummy', XDG_DATA_HOME=str(fixture), KO_HOME=str(fixture), KINDLESPOUSE_TEST_ROOT=str(project), KINDLESPOUSE_CACHED_FIXTURE=str(fixture), KINDLESPOUSE_CACHED_COUNT=str(count), EMULATE_READER_W='1860', EMULATE_READER_H='2480', EMULATE_READER_DPI='300', LD_LIBRARY_PATH='libs')
    reports = {}
    for phase in ('warm', 'cached'):
        if phase == 'cached':
            shutil.copyfile(books / 'group-0/book-000.epub', books / 'external-added.epub')
        result = subprocess.run([str(runtime / 'luajit'), 'reader.lua', str(books)], cwd=runtime, env=dict(environment, KINDLESPOUSE_CACHED_PHASE=phase), capture_output=True, text=True, timeout=240)
        (fixture / (phase + '-runtime.log')).write_text(result.stdout + result.stderr, encoding='utf-8')
        marker = 'KindleSpouse cached startup ' + phase + ' acceptance passed '
        assert result.returncode == 0 and marker in result.stdout, (result.stdout + result.stderr)[-9000:]
        reports[phase] = json.loads(next(line[len(marker):] for line in result.stdout.splitlines() if line.startswith(marker)))
    assert reports['warm']['pid'] != reports['cached']['pid'], 'Warm and cached launches must use distinct processes'
    assert reports['cached']['snapshotScanning'] and reports['cached']['snapshotCount'] == count
    assert reports['cached']['quietReopen'], 'Cancelling cached startup must preserve quiet reopening'
    assert reports['cached']['scanningEvents'] == 0 and reports['cached']['finalCount'] == count + 1
    assert (fixture / 'cached-startup-in-progress.png').stat().st_size > 1000
    (fixture / 'result.json').write_text(json.dumps({'passed': True, 'processes': reports}, indent=2) + '\n', encoding='utf-8')
    print('KindleSpouse cached startup acceptance passed: separate warm/cached processes, in-progress cached shelf, quiet events, external additions, zero hot scans.')
    print('Artifacts:', fixture)


if __name__ == '__main__':
    main()
