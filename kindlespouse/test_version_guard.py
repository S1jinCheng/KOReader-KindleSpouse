import argparse
import os
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--runtime', type=Path, required=True)
args = parser.parse_args()
runtime = args.runtime.resolve()
checks = root / 'kindlespouse/build/version-checks'
checks.mkdir(parents=True, exist_ok=True)
sandbox = Path(tempfile.mkdtemp(prefix='guard-', dir=checks))
environment = dict(os.environ, SDL_VIDEODRIVER='dummy', SDL_AUDIODRIVER='dummy', KO_HOME=str(sandbox), XDG_DATA_HOME=str(sandbox), KINDLESPOUSE_TEST_ROOT=str(root), KINDLESPOUSE_TEST_SANDBOX=str(sandbox), LD_LIBRARY_PATH='libs')
result = subprocess.run([str(runtime / 'luajit'), str(root / 'kindlespouse/test_version_guard.lua')], cwd=runtime, env=environment, capture_output=True, text=True, timeout=30)
(sandbox / 'runtime.log').write_text(result.stdout + result.stderr, encoding='utf-8')
print(str(sandbox))
print(result.stdout)
if result.returncode:
    print(result.stderr)
    raise SystemExit(result.returncode)
if 'KindleSpouse version guard acceptance passed' not in result.stdout:
    raise SystemExit('Version guard did not complete its assertions')