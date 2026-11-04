import io
import os
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
    for directory, directories, names in os.walk(root / folder, followlinks=False):
        directories[:] = [name for name in directories if name not in ('build', '__pycache__')]
        for name in names:
            path = Path(directory) / name
            text = path.read_text(encoding='utf-8') if path.suffix in ('.lua', '.py') else ''
            if path.suffix == '.lua' and lua_comments(text):
                failures.append(str(path.relative_to(root)))
            if path.suffix == '.py' and any(token.type == tokenize.COMMENT for token in tokenize.generate_tokens(io.StringIO(text).readline)):
                failures.append(str(path.relative_to(root)))
if failures:
    print('Authored code comments are not allowed: ' + ', '.join(failures))
    raise SystemExit(1)
print('Authored plugin and test code contains no comments.')
