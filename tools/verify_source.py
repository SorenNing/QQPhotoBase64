#!/usr/bin/env python3
"""Verify exactly the reviewed source set before running any build."""
import hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def files():
    return {p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest()
            for p in ROOT.rglob('*') if p.is_file()
            and not any(x in ('.git','build','dist','__pycache__') for x in p.relative_to(ROOT).parts)
            and p.name!='reviewed-source.json'}
def main():
    expected=json.loads((ROOT/'reviewed-source.json').read_text())['files']
    actual=files()
    missing=sorted(expected.keys()-actual.keys());extra=sorted(actual.keys()-expected.keys())
    changed=sorted(k for k in expected.keys()&actual.keys() if expected[k]!=actual[k])
    if missing or extra or changed:raise SystemExit(json.dumps({'missing':missing,'extra':extra,'changed':changed}))
    print(json.dumps({'ok':True,'verified_files':len(actual)}))
if __name__=='__main__':main()
