from pathlib import Path
import struct,zlib
p=Path('build/fixture.png');p.parent.mkdir(exist_ok=True)
def chunk(tag,data):return struct.pack('>I',len(data))+tag+data+struct.pack('>I',zlib.crc32(tag+data)&0xffffffff)
width=32;height=32
pixels=b''.join(b'\0'+b''.join(bytes((x*7%256,y*7%256,127,255))for x in range(width))for y in range(height))
png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',width,height,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(pixels))+chunk(b'IEND',b'')
p.write_bytes(png)
# A valid private ancillary chunk makes an exact-limit image, with many '/' Base64 symbols.
padding=b'\xff'*(32*1024*1024-len(png)-12)
boundary=png[:-12]+chunk(b'npAD',padding)+png[-12:]
assert len(boundary)==32*1024*1024
p.with_name('boundary.png').write_bytes(boundary)
