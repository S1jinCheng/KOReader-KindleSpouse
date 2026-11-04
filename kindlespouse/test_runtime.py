import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--runtime', type=Path, required=True)
    parser.add_argument('--fonts', type=Path, required=True)
    parser.add_argument('--package', type=Path, required=True)
    parser.add_argument('--expected-version', type=int, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    runtime = args.runtime.resolve()
    directory = root / 'kindlespouse/build/runtime-checks'
    directory.mkdir(parents=True, exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix='suite-', dir=directory))
    report = {'expected_version': args.expected_version, 'runtime': str(runtime),
              'luajit_sha256': hashlib.sha256((runtime / 'luajit').read_bytes()).hexdigest(),
              'passed': False, 'checks': []}
    probe = 'require("setupkoenv"); local V=require("version"); print("KINDLESPOUSE_VERSION="..tostring(V:getNormalizedCurrentVersion()))'
    environment = dict(os.environ, LD_LIBRARY_PATH='libs')
    result = subprocess.run([str(runtime / 'luajit'), '-e', probe], cwd=runtime,
                            env=environment, capture_output=True, text=True, timeout=30)
    (output / 'version.log').write_text(result.stdout + result.stderr, encoding='utf-8')
    marker = 'KINDLESPOUSE_VERSION=' + str(args.expected_version)
    report['version_verified'] = result.returncode == 0 and marker in result.stdout.splitlines()
    report_path = output / 'result.json'
    report_path.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(output, flush=True)
    if not report['version_verified']:
        raise SystemExit('Runtime version does not match the requested artifact. See version.log.')
    runtime_args = ['--runtime', str(runtime)]
    font_args = ['--fonts', str(args.fonts.resolve())]
    package_args = ['--package', str(args.package.resolve())]
    checks = []

    def add(name, script, extra=(), env=None):
        checks.append((name, [sys.executable, 'kindlespouse/' + script, *runtime_args, *extra], env))

    for name in ('annotation', 'patches', 'scheduler', 'launcher', 'scheduler_integration', 'main_lifecycle'):
        add(name, 'test_plugin.py', ['--test', name])
    for timezone in ('UTC', 'Asia/Shanghai', 'America/New_York'):
        add('services-' + timezone.replace('/', '-'), 'test_plugin.py', ['--test', 'services'], {'TZ': timezone})
    add('localization', 'check_i18n.py', ['--all-ui'])
    add('version-guard', 'test_version_guard.py')
    add('home-guard', 'test_home_guard.py', font_args)
    add('catalog-500', 'test_catalog.py')
    add('notebook', 'test_notebook_summary.py', font_args)
    add('home', 'test_home.py', font_args)
    for language in ('en', 'zh_CN'):
        add('home-' + language, 'test_home.py', [*font_args, '--integrated', '--language', language])
    add('home-500', 'test_home.py', [*font_args, '--scale'])
    add('highlight', 'test_reader.py', [*font_args, '--feature', 'highlight', '--integrated'])
    for screen in ('monochrome', 'color'):
        add('reader-' + screen, 'test_reader.py', [*font_args, '--feature', 'all', '--statistics', '--integrated', '--screen', screen])
        add('package-reader-' + screen, 'test_reader.py', [*font_args, *package_args, '--feature', 'all', '--statistics', '--screen', screen])
    add('package-home', 'test_home.py', [*font_args, *package_args, '--language', 'zh_CN'])
    for name, command, overrides in checks:
        print('Running ' + name, flush=True)
        with (output / (name + '.log')).open('w', encoding='utf-8') as log:
            result = subprocess.run(command, cwd=root, env=dict(os.environ, **(overrides or {})),
                                    stdout=log, stderr=subprocess.STDOUT, timeout=900)
        report['checks'].append({'name': name, 'exit_code': result.returncode})
        report_path.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
        if result.returncode:
            raise SystemExit('Failed ' + name + '. See ' + str(output / (name + '.log')))
    report['passed'] = True
    report_path.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print('All ' + str(len(checks)) + ' runtime checks passed.', flush=True)


if __name__ == '__main__':
    main()
