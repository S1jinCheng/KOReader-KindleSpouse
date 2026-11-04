import argparse
import json
import os
from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parent.parent
plugin = root / 'plugins' / 'kindlespouse.koplugin'
pattern = re.compile(r'(?P<comment>--\[\[[\s\S]*?\]\]|--[^\n]*)|(?P<string>"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\')|(?P<identifier>[A-Za-z_][A-Za-z_0-9]*)|(?P<space>\s+)|(?P<other>\.\.|.)')
escapes = {'n': '\n', 'r': '\r', 't': '\t', 'a': '\a', 'b': '\b', 'f': '\f', 'v': '\v', '\\': '\\', '"': '"', "'": "'"}
non_ui_calls = {'assert', 'error', 'require', 'os.execute', 'io.open', 'logger.warn', 'logger.info', 'logger.err', 'logger.dbg', 'logger.error'}
visible_fields = {'text', 'title', 'description', 'input_hint', 'hint', 'label', 'subtitle'}


def decode(value):
    def replace(match):
        escaped = match.group(1)
        if escaped.startswith('u{'):
            return chr(int(escaped[2:-1], 16))
        if escaped.isdigit():
            return chr(int(escaped))
        return escapes.get(escaped, escaped)
    return re.sub(r'\\(u\{[0-9A-Fa-f]+\}|\d{1,3}|.)', replace, value[1:-1])


def tokens(source):
    result = []
    for match in pattern.finditer(source):
        if match.lastgroup in {'comment', 'space'}:
            continue
        value = match.group()
        result.append({'kind': match.lastgroup, 'value': decode(value) if match.lastgroup == 'string' else value,
                       'start': match.start(), 'end': match.end(), 'line': source.count('\n', 0, match.start()) + 1})
    return result


def call_name(values, index):
    if index < 0 or values[index]['kind'] != 'identifier':
        return ''
    result = values[index]['value']
    index -= 1
    while index > 0 and values[index]['value'] in {'.', ':'} and values[index - 1]['kind'] == 'identifier':
        result = values[index - 1]['value'] + values[index]['value'] + result
        index -= 2
    return result


def inspect(source):
    values = tokens(source)
    calls, literals, references = [], [], []
    for index, token in enumerate(values):
        value = token['value']
        if token['kind'] == 'string':
            caller = calls[-1] if calls else ''
            if caller == 'T' or caller.endswith('.T'):
                if index >= 1 and values[index - 1]['value'] == '(':
                    prefix = index + 1 < len(values) and values[index + 1]['value'] == '..'
                    references.append((value, prefix, token['line']))
            if not any(name in non_ui_calls for name in calls):
                previous = values[index - 1]['value'] if index else ''
                field = values[index - 2]['value'] if index >= 2 and previous == '=' else ''
                stripped = re.sub(r'%[-+ #0]*\d*(?:\.\d+)?[cdiouxXeEfgGqs%]', '', value)
                chinese = re.search(r'[\u3400-\u9fff]', value) is not None
                prose = re.search(r'\s', stripped) and len(re.findall(r'[A-Za-z]{2,}', stripped)) >= 2
                label = field in visible_fields and re.search(r'^[A-Z]|\s+[A-Za-z]', stripped)
                if chinese or prose or label:
                    literals.append(token)
        if value == '(':
            calls.append(call_name(values, index - 1))
        elif value == ')' and calls:
            calls.pop()
    return literals, references


def self_test():
    assert inspect('local tab = "Library"; G_reader_settings:saveSetting("kindlespouse_home", true)')[0] == []
    assert inspect('local fonts = {title="cfont",ui="cfont"}')[0] == []
    assert inspect('logger.warn("KindleSpouse:", "cannot read local JSON"); error("Unknown internal mode")')[0] == []
    assert inspect('text = T("sync_now"); title = T("notebook.summary")')[0] == []
    assert len(inspect('text = "同步状态"; notify("Connect Wi-Fi and retry")')[0]) == 2
    assert inspect('T("reader.highlight." .. color)')[1] == [('reader.highlight.', True, 1)]


def verify(runtime, references):
    code = 'require("setupkoenv"); local json=require("json"); local I=assert(loadfile(' + json.dumps(str(plugin / 'i18n.lua'), ensure_ascii=False) + '))(); '
    sources = [str(path) for path in sorted(plugin.rglob('*.lua'))]
    code += 'for _,path in ipairs(json.decode(' + json.dumps(json.dumps(sources, ensure_ascii=False), ensure_ascii=False) + ')) do assert(loadfile(path)) end; '
    code += 'local refs=json.decode(' + json.dumps(json.dumps(references, ensure_ascii=False), ensure_ascii=False) + '); '
    code += '''local checked={}; for _,ref in ipairs(refs) do
        if ref.prefix then local found=false; for key in pairs(I.en) do
            if key:sub(1,#ref.key)==ref.key then checked[key]=true; found=true end end
            assert(found,"Unknown translation prefix: "..ref.key.." at "..ref.source)
        else assert(I.en[ref.key]~=nil,"Unknown translation key: "..ref.key.." at "..ref.source); checked[ref.key]=true end end
        local count=0; for key in pairs(I.en) do checked[key]=true end
        for key in pairs(checked) do
            assert(type(I.en[key])=="string" and type(I.zh[key])=="string","Missing locale: "..key)
            for _,locale in ipairs({"en","zh_CN"}) do
                G_reader_settings={readSetting=function() return locale end}
                local expected=locale=="en" and I.en[key] or I.zh[key]
                assert(I.T(key)==expected,"Wrong locale lookup: "..key)
            end
            count=count+1
        end
        assert(not pcall(I.T,"__kindlespouse_unknown_translation__"),"Unknown keys must raise an error")
        print(json.encode({translations=count,references=#refs,locales=2}))'''
    environment = dict(os.environ, LD_LIBRARY_PATH='libs')
    result = subprocess.run([str(runtime / 'luajit'), '-e', code], cwd=runtime, env=environment, capture_output=True, text=True)
    if result.returncode:
        raise SystemExit(result.stdout + result.stderr)
    print(result.stdout.strip())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--runtime', type=Path, required=True)
    parser.add_argument('--all-ui', action='store_true')
    parser.add_argument('--files', nargs='*', type=Path)
    args = parser.parse_args()
    self_test()
    names = ['main.lua', 'home.lua', 'library.lua']
    if args.all_ui:
        names += ['shelf.lua', 'profile.lua', 'catalog.lua']
    targets = args.files if args.files is not None else [plugin / name for name in names]
    failures = []
    for filename in targets:
        path = filename if filename.is_absolute() else root / filename
        for token in inspect(path.read_text(encoding='utf-8'))[0]:
            failures.append(f'{path.relative_to(root)}:{token["line"]}: visible literal needs T(semantic_key): {token["value"]!r}')
    references = []
    reference_files = set(plugin.rglob('*.lua')) | {filename if filename.is_absolute() else root / filename for filename in targets}
    for filename in sorted(reference_files):
        if filename.name == 'i18n.lua':
            continue
        for key, prefix, line in inspect(filename.read_text(encoding='utf-8'))[1]:
            references.append({'key': key, 'prefix': prefix, 'source': str(filename.relative_to(root)) + ':' + str(line)})
    if failures:
        raise SystemExit('\n'.join(failures))
    verify(args.runtime.resolve(), references)
    print('Passed: visible strings use semantic keys, and both locales resolve in the pinned Lua runtime.')


if __name__ == '__main__':
    main()
