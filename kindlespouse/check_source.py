import io
import re
import tokenize
from pathlib import Path

root = Path(__file__).resolve().parent.parent
failures = []

def lua_comments(text):
    position = 0
    while position < len(text):
        char = text[position]
        if char in ("'", '"'):
            quote = char
            position += 1
            while position < len(text):
                if text[position] == "\\":
                    position += 2
                elif text[position] == quote:
                    position += 1
                    break
                else:
                    position += 1
        elif char == '[' and (match := re.match(r'\[(=*)\[', text[position:])):
            close = ']' + match.group(1) + ']'
            end = text.find(close, position + len(match.group(0)))
            position = len(text) if end < 0 else end + len(close)
        elif text.startswith('--', position):
            return True
        else:
            position += 1
    return False

for folder in ('plugins/kindlespouse.koplugin', 'kindlespouse'):
    for path in (root / folder).rglob('*'):
        if not path.is_file() or 'build' in path.relative_to(root).parts:
            continue
        text = path.read_text(encoding='utf-8') if path.suffix in ('.lua', '.py') else ''
        if path.suffix == '.lua' and lua_comments(text):
            failures.append(str(path.relative_to(root)))
        if path.suffix == '.py' and any(token.type == tokenize.COMMENT for token in tokenize.generate_tokens(io.StringIO(text).readline)):
            failures.append(str(path.relative_to(root)))
if failures:
    print('Authored code comments are not allowed: ' + ', '.join(failures))
    raise SystemExit(1)
print('Authored plugin and test code contains no comments.')
