#!/usr/bin/env python3
"""Verify each final deb and ask macOS codesign to check extracted binaries."""
import json,subprocess,sys,tarfile,tempfile
from pathlib import Path
from verify import ar, package

def main():
    results=[]
    for argument in sys.argv[1:]:
        path=Path(argument);result,_=package(path)
        members=ar(path.read_bytes())
        data=next(v for n,v in members.items() if n.startswith('data.tar'))
        import io
        with tempfile.TemporaryDirectory(prefix='qqp-codesign-') as temporary:
            with tarfile.open(fileobj=io.BytesIO(data),mode='r:*') as archive:
                items=[m for m in archive.getmembers() if m.isfile() and m.name.endswith('/QQPhotoBase64.dylib')]
                assert len(items)==1
                output=Path(temporary)/'QQPhotoBase64.dylib'
                output.write_bytes(archive.extractfile(items[0]).read())
                subprocess.run(['codesign','--verify','--strict','--all-architectures','--verbose=2',str(output)],check=True)
        results.append({'file':path.name,'codesign_strict_all_architectures':True,'validation':result})
    assert len(results)==2,'Expected RootHide and rootless packages'
    Path('dist/final-codesign.json').write_text(json.dumps(results,indent=2)+'\n')
    print(json.dumps({'ok':True,'packages':len(results)}))
if __name__=='__main__':main()
