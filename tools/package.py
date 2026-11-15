from pathlib import Path
import io,gzip,tarfile,json,hashlib
ROOT=Path(__file__).resolve().parents[1]

def tar_bytes(files):
    b=io.BytesIO()
    with tarfile.open(fileobj=b,mode='w',format=tarfile.USTAR_FORMAT) as t:
        dirs=set()
        for name in files:
            p=Path(name).parent
            while str(p)!='.':dirs.add(p.as_posix());p=p.parent
        for name in sorted(dirs,key=lambda x:(x.count('/'),x)):
            i=tarfile.TarInfo(name+'/');i.type=tarfile.DIRTYPE;i.mode=0o755;i.uid=i.gid=0;i.mtime=0;t.addfile(i)
        for name,(data,mode) in sorted(files.items()):
            i=tarfile.TarInfo(name);i.size=len(data);i.mode=mode;i.uid=i.gid=0;i.mtime=0;t.addfile(i,io.BytesIO(data))
    return gzip.compress(b.getvalue(),compresslevel=9,mtime=0)
def ar(members):
    result=bytearray(b'!<arch>\n')
    for name,data in members:
        h=f'{name+"/":<16}{0:<12}{0:<6}{0:<6}{0o100644:<8o}{len(data):<10}`\n'.encode()
        assert len(h)==60
        result+=h+data
        if len(data)%2:result+=b'\n'
    return bytes(result)
def main():
    plist=(ROOT/'layout/Library/MobileSubstrate/DynamicLibraries/QQPhotoBase64.plist').read_bytes()
    out=ROOT/'dist';out.mkdir(exist_ok=True)
    records=[]
    for arch,prefix,subtype in [('iphoneos-arm64','var/jb/','arm64'),('iphoneos-arm64e','','arm64e')]:
        dylib=(ROOT/f'build/QQPhotoBase64-{subtype}.dylib').read_bytes()
        control=(ROOT/'control').read_text().replace('Architecture: iphoneos-arm64e','Architecture: '+arch)
        payload={prefix+'Library/MobileSubstrate/DynamicLibraries/QQPhotoBase64.dylib':(dylib,0o755),prefix+'Library/MobileSubstrate/DynamicLibraries/QQPhotoBase64.plist':(plist,0o644)}
        package=ar([('debian-binary',b'2.0\n'),('control.tar.gz',tar_bytes({'control':(control.encode(),0o644)})),('data.tar.gz',tar_bytes(payload))])
        name=f'com.ning.qqphotobase64_0.1.4_{arch}.deb';(out/name).write_bytes(package)
        records.append({'name':name,'bytes':len(package),'sha256':hashlib.sha256(package).hexdigest(),'layout':'rootless' if prefix else 'RootHide-loader-layout'})
    (ROOT/'build/package-manifest.json').write_text(json.dumps(records,indent=2))
if __name__=='__main__':main()
