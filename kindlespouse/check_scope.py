import argparse
import subprocess
from pathlib import Path

PIN = '9192014d8bd82a91dc1012473be0f238dedfdb54'
parser = argparse.ArgumentParser()
parser.add_argument('--ref', default='HEAD')
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent

def git(*arguments):
    return subprocess.check_output(['git', '-C', str(root), *arguments], text=True).splitlines()

def allowed(filename):
    return filename.startswith(('plugins/kindlespouse.koplugin/', 'kindlespouse/', 'README')) or filename == '.github/workflows/kindlespouse.yml'

files = set(git('diff', '--name-only', '--no-renames', PIN, args.ref))
if args.ref == 'HEAD':
    files.update(git('diff', '--name-only', 'HEAD'))
    files.update(git('ls-files', '--others', '--exclude-standard'))
blocked = sorted(filename for filename in files if not allowed(filename))
if blocked:
    print('Changes outside the approved plugin overlay:')
    print('\n'.join(blocked))
    raise SystemExit(1)
print('Pinned v2026.07.1 core unchanged; all changes are inside approved paths.')
