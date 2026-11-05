import argparse
import json
from pathlib import Path
import subprocess


root = Path(__file__).resolve().parent.parent


def git(*args):
    return subprocess.check_output(['git', *args], cwd=root)


def snapshot(revision):
    tree = git('ls-tree', '-r', revision, '--', 'plugins/kindlespouse.koplugin', 'kindlespouse').decode().splitlines()
    sources, tests = [], {}
    for entry in tree:
        metadata, name = entry.split('\t', 1)
        blob = metadata.split()[2]
        path = Path(name)
        if name.startswith('plugins/kindlespouse.koplugin/') and path.suffix == '.lua':
            sources.append(git('cat-file', 'blob', blob))
        if name.startswith('kindlespouse/') and path.suffix in ('.lua', '.py') and (
                path.name.startswith(('test', 'check')) or path.name == 'package_test.py'):
            tests[name] = blob
    return {'lua_files': len(sources), 'lines': sum(len(value.splitlines()) for value in sources),
            'nonblank_lines': sum(sum(bool(line.strip()) for line in value.splitlines()) for value in sources),
            'bytes': sum(len(value) for value in sources)}, tests


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--base', required=True)
    parser.add_argument('--head', default='HEAD')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    before, tests_before = snapshot(args.base)
    after, tests_after = snapshot(args.head)
    unchanged = tests_before == tests_after
    result = {'base': git('rev-parse', args.base).decode().strip(),
              'head': git('rev-parse', args.head).decode().strip(), 'before': before, 'after': after,
              'reduction_percent': {key: round(100 * (before[key] - after[key]) / before[key], 4)
                                    for key in ('lines', 'nonblank_lines', 'bytes')},
              'tests_and_checkers_unchanged': unchanged, 'frozen_files': len(tests_before)}
    text = json.dumps(result, indent=2) + '\n'
    print(text, end='')
    if args.output:
        args.output.write_text(text, encoding='utf-8')
    if not unchanged:
        raise SystemExit('Tests or checkers changed during simplification.')


if __name__ == '__main__':
    main()
