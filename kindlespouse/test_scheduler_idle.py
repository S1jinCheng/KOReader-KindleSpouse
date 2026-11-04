import argparse
import hashlib
import json
import os
import subprocess
import tempfile
import time
from pathlib import Path

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--runtime', type=Path, required=True)
parser.add_argument('--seconds', type=int, default=600)
args = parser.parse_args()
if args.seconds < 3:
    parser.error('--seconds must be at least 3')
runtime = args.runtime.resolve()
checks = root / 'kindlespouse/build/checks'
checks.mkdir(parents=True, exist_ok=True)
sandbox = Path(tempfile.mkdtemp(prefix='scheduler-idle-', dir=checks))
environment = dict(os.environ, SDL_VIDEODRIVER='dummy', SDL_AUDIODRIVER='dummy', KO_HOME=str(sandbox), XDG_DATA_HOME=str(sandbox), KINDLESPOUSE_TEST_ROOT=str(root), KINDLESPOUSE_TEST_SANDBOX=str(sandbox), KINDLESPOUSE_IDLE_SECONDS=str(args.seconds), LD_LIBRARY_PATH='libs')
started = time.monotonic()
print(json.dumps({'event': 'runner_started', 'sandbox': str(sandbox), 'runtime': str(runtime), 'requested_seconds': args.seconds, 'runtime_luajit_sha256': hashlib.sha256((runtime / 'luajit').read_bytes()).hexdigest()}), flush=True)
with (sandbox / 'runtime.log').open('w', encoding='utf-8') as log:
    result = subprocess.run([str(runtime / 'luajit'), str(root / 'kindlespouse/test_scheduler_idle.lua')], cwd=runtime, env=environment, stdout=log, stderr=subprocess.STDOUT, text=True, timeout=args.seconds + 90)
elapsed = time.monotonic() - started
print((sandbox / 'runtime.log').read_text(encoding='utf-8'), flush=True)
if result.returncode:
    raise SystemExit(result.returncode)
value = json.loads((sandbox / 'result.json').read_text(encoding='utf-8'))
value['runner_elapsed_seconds'] = elapsed
value['runtime_luajit_sha256'] = hashlib.sha256((runtime / 'luajit').read_bytes()).hexdigest()
(sandbox / 'result.json').write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
assert value['passed'] and value['launch_count'] <= 1 and elapsed >= args.seconds - 0.05, value
print(json.dumps({'passed': True, 'launch_count': value['launch_count'], 'requested_seconds': args.seconds, 'uimanager_elapsed_seconds': value['elapsed_seconds'], 'runner_elapsed_seconds': elapsed, 'result': str(sandbox / 'result.json')}), flush=True)
