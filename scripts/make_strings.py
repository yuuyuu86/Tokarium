#!/usr/bin/env python3
"""ソースから翻訳キーを取り出し、Resources/*.lproj/Localizable.strings を作る。

使い方: scripts/make_strings.py
英語訳が足りないキーがあれば一覧を出して失敗する（scripts/translations_en.py に足す）。
"""
import glob, json, os, re, subprocess, sys, tempfile

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(root, 'scripts'))
from translations_en import EN

out = tempfile.mkdtemp()
subprocess.run(['swift', 'build', '-Xswiftc', '-emit-localized-strings', '-Xswiftc', '-emit-localized-strings-path', '-Xswiftc', out],
               cwd=root, check=True, stdout=subprocess.DEVNULL)
keys = set()
for f in glob.glob(out + '/*.stringsdata'):
    for tbl in json.load(open(f)).get('tables', {}).values():
        keys.update(e['key'] for e in tbl)

missing = sorted(k for k in keys if k not in EN)
if missing:
    print('英語訳がありません:')
    for k in missing: print('  ' + repr(k))
    sys.exit(1)

spec = re.compile(r'%(\d+\$)?(lld|@|d|%)')
def specs(s): return sorted(m.group(2) for m in spec.finditer(s) if m.group(2) != '%')
for k in keys:
    if specs(k) != specs(EN[k]):
        print('書式が合いません:', repr(k), '->', repr(EN[k])); sys.exit(1)

def esc(s): return s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')
for lang, table in (('en', EN), ('ja', {k: k for k in keys})):
    d = os.path.join(root, 'Resources', f'{lang}.lproj')
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, 'Localizable.strings'), 'w', encoding='utf-8') as f:
        f.write('/* scripts/make_strings.py が生成。直接編集しない */\n')
        for k in sorted(keys):
            f.write(f'"{esc(k)}" = "{esc(table[k])}";\n')
print(f'{len(keys)} 件を書き出しました')
