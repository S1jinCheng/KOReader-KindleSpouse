import hashlib
import json
from pathlib import Path, PurePosixPath
import zipfile


def install_plugin(package, destination):
    assert not destination.exists(), "Package tests require a fresh plugin directory"
    root = Path(__file__).resolve().parent.parent
    manifest = json.loads((root / 'kindlespouse/fonts.json').read_text(encoding='utf-8'))
    prefix = 'koreader/plugins/kindlespouse.koplugin/'
    allowed = {asset['target'] for asset in manifest['assets']}
    allowed.update({'KindleSpouse-INSTALL.txt', 'kindlespouse/licenses/reader-fonts/manifest.json'})
    installed = set()
    with zipfile.ZipFile(package) as archive:
        for member in archive.infolist():
            path = PurePosixPath(member.filename)
            assert not path.is_absolute() and '..' not in path.parts and '\\' not in member.filename and ':' not in member.filename
            if member.filename.startswith(prefix):
                relative = path.relative_to(prefix)
                assert relative.suffix == '.lua' or relative.as_posix() == 'LICENSE', member.filename
                target = destination.joinpath(*relative.parts)
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(archive.read(member))
                installed.add(relative.as_posix())
            else:
                assert member.filename in allowed, 'Unexpected package file: ' + member.filename
        for asset in manifest['assets']:
            data = archive.read(asset['target'])
            assert len(data) == asset['bytes'] and hashlib.sha256(data).hexdigest() == asset['sha256'], asset['target']
    assert {'main.lua', 'home.lua', 'LICENSE'} <= installed
    print('Verified package: ' + str(len(installed)) + ' plugin files and all pinned fonts/licenses.')
    return destination
