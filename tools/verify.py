#!/usr/bin/env python3
"""Offline package/signature integrity checks; not CMS trust or macOS codesign.
--dylib checks Mach-O only (legacy samples allowed); dist also enforces QQ identity.
"""
import argparse
import gzip
import hashlib
import io
import json
import plistlib
import struct
import tarfile
import zlib
from pathlib import Path
from xml.parsers.expat import ExpatError

ROOT = Path(__file__).resolve().parents[1]
MARKERS = (b'QQPCodec', b'QQPSession', b'AIFileManager',
           b'sendFileWithPath:uin:uid:chatType:', b'QQENC1')
ARCHES = {0: 'arm64', 0x80000002: 'arm64e'}
LIMIT = 128 * 1024 * 1024


def need(ok, message):
    if not ok:
        raise ValueError(message)


def part(data, offset, size):
    need(0 <= offset <= len(data) and 0 <= size <= len(data) - offset,
         f'out-of-bounds range {offset}+{size}/{len(data)}')
    return data[offset:offset + size]


def u(fmt, data, offset=0):
    return struct.unpack(fmt, part(data, offset, struct.calcsize(fmt)))


def disjoint(ranges):
    ordered = sorted(ranges)
    need(all(a[1] <= b[0] for a, b in zip(ordered, ordered[1:])), 'overlapping ranges')


def signature(image, offset, size):
    sig = part(image, offset, size)
    magic, length, count = u('>III', sig)
    need(magic == 0xfade0cc0 and 12 + count * 8 <= length <= size, 'invalid signature SuperBlob')
    blobs, ranges = {}, []
    for i in range(count):
        slot, start = u('>II', sig, 12 + 8 * i)
        need(slot not in blobs and start >= 12 + count * 8, 'duplicate/invalid signature slot')
        bm, bl = u('>II', part(sig, start, length - start))
        need(bl >= 8 and start + bl <= length, 'invalid signature blob length')
        blobs[slot] = (bm, part(sig, start, bl)); ranges.append((start, start + bl))
    disjoint(ranges)
    need(0 in blobs and blobs[0][0] == 0xfade0c02, 'missing primary CodeDirectory')
    for slot, magic in ((2, 0xfade0c01), (5, 0xfade7171), (7, 0xfade7172)):
        need(slot not in blobs or blobs[slot][0] == magic, f'invalid special blob {slot}')
    result = []
    for slot, (magic, cd) in sorted(blobs.items()):
        need(not 0x1000 <= slot < 0x10000 or magic == 0xfade0c02, 'invalid alternate CodeDirectory')
        need(magic != 0xfade0c02 or slot == 0 or 0x1000 <= slot < 0x10000, 'unexpected CodeDirectory slot')
        if magic != 0xfade0c02:
            continue
        (_, _, version, flags, ho, ident, ns, nc, limit, hs, ht, _, exp, _) = u('>9I4BI', cd)
        minimum = max(n for v, n in ((0, 44), (0x20100, 48), (0x20200, 52),
                      (0x20300, 64), (0x20400, 88), (0x20500, 96), (0x20600, 108)) if version >= v)
        need(version >= 0x20001 and len(cd) >= minimum, 'invalid CodeDirectory version/header')
        hashes = {1: ('sha1', 20), 2: ('sha256', 32), 3: ('sha256', 20), 4: ('sha384', 48)}
        need(ht in hashes and hs == hashes[ht][1], 'unsupported CodeDirectory hash type/size')
        algorithm = hashes[ht][0]
        need(version < 0x20100 or u('>I', cd, 44)[0] == 0, 'scatter CodeDirectory unsupported')
        if version >= 0x20300:
            limit = u('>Q', cd, 56)[0] or limit
        need(limit == offset and limit > 0 and exp <= 30, 'unsigned gap/code limit/page exponent invalid')
        page = (1 << exp) if exp else limit
        need(nc == (limit + page - 1) // page, 'wrong code slot count')
        special_start = ho - ns * hs
        need(special_start >= minimum and ho + nc * hs <= len(cd), 'invalid hash table bounds')
        need(minimum <= ident < special_start and b'\0' in cd[ident:special_start], 'invalid signing identifier')
        if version >= 0x20200:
            team = u('>I', cd, 48)[0]
            need(not team or (minimum <= team < special_start and b'\0' in cd[team:special_start]), 'invalid team identifier')
        for i in range(nc):
            digest = hashlib.new(algorithm, image[i * page:min((i + 1) * page, limit)]).digest()[:hs]
            need(part(cd, ho + i * hs, hs) == digest, f'CodeDirectory {slot}: code page {i} hash mismatch')
        for special in (2, 5, 7):
            need(special not in blobs or special <= ns, f'unsealed special slot {special}')
        sealed = []
        for special in range(1, ns + 1):
            expected = hashlib.new(algorithm, blobs[special][1]).digest()[:hs] if special in blobs else bytes(hs)
            need(part(cd, ho - special * hs, hs) == expected, f'CodeDirectory {slot}: special slot {special} mismatch/missing blob')
            if special in blobs:
                sealed.append(special)
        result.append({'slot': slot, 'version': hex(version), 'hash_type': ht, 'hash_size': hs,
                       'code_pages': nc, 'page_size': page, 'code_limit': limit, 'verified_special_slots': sealed})
    need(any(cd['hash_type'] in (2, 3) for cd in result), 'signature has no SHA-256 CodeDirectory')
    return result


def fixups(data):
    version, starts, imports, symbols, count, fmt, compression = u('<7I', data)
    need(version == 0 and 28 <= starts <= len(data) - 4, 'invalid chained fixups header')
    need(imports <= len(data) and symbols <= len(data), 'chained fixups offsets out of bounds')
    segments, = u('<I', data, starts)
    table = part(data, starts + 4, segments * 4)
    formats, ranges = set(), []
    for i in range(segments):
        relative, = u('<I', table, i * 4)
        if not relative:
            continue
        pos = starts + relative
        need(relative >= 4 + segments * 4, 'chained starts overlaps segment table')
        size, page, pointer_format, seg_offset, max_pointer, pages = u('<IHHQIH', data, pos)
        need(size >= 22 + 2 * pages and page > 0 and pointer_format > 0, 'invalid chained starts segment')
        part(data, pos, size); ranges.append((pos, pos + size)); formats.add(pointer_format)
    disjoint(ranges)
    return {'pointer_formats': sorted(formats), 'imports_count': count, 'imports_format': fmt,
            'symbols_format': compression, 'chain_walk_verified': False}


def macho(data, identity=False):
    formats = {b'\xca\xfe\xba\xbe': ('>', False), b'\xca\xfe\xba\xbf': ('>', True),
               b'\xbe\xba\xfe\xca': ('<', False), b'\xbf\xba\xfe\xca': ('<', True)}
    magic = bytes(data[:4])
    need(magic in formats, 'expected fat Mach-O')
    endian, wide = formats[magic]
    count, = u(endian + 'I', data, 4)
    need(count == 2, 'expected exactly two fat slices')
    stride = 32 if wide else 20
    ranges, slices, seen = [], [], set()
    for i in range(count):
        fields = u(endian + ('IIQQII' if wide else 'IIIII'), data, 8 + stride * i)
        cpu, sub, off, size, align = fields[:5]
        need(cpu == 0x100000c and sub in ARCHES and sub not in seen, 'wrong/duplicate fat architecture')
        need(align <= 30 and off >= 8 + stride * count and off % (1 << align) == 0, 'invalid slice alignment/offset')
        image = part(data, off, size); ranges.append((off, off + size)); seen.add(sub)
        magic, icpu, isub, kind, ncmds, cmdbytes, flags, reserved = u('<8I', image)
        need((magic, icpu, isub, kind) == (0xfeedfacf, cpu, sub, 6), 'slice header disagrees with fat/MH_DYLIB')
        end = 32 + cmdbytes; part(image, 32, cmdbytes)
        need(ncmds <= cmdbytes // 8, 'invalid load command count')
        pos, commands = 32, {}
        for _ in range(ncmds):
            cmd, length = u('<II', part(image, pos, end - pos))
            need(length >= 8 and length % 8 == 0 and pos + length <= end, 'invalid load command size')
            if cmd in (0x1d, 0x80000034):
                need(cmd not in commands and length == 16, 'duplicate/invalid signature or fixups command')
                start, size = u('<II', image, pos + 8)
                need(start >= end and size > 0, 'invalid linkedit payload range')
                part(image, start, size); commands[cmd] = (start, size)
            pos += length
        need(pos == end and set(commands) == {0x1d, 0x80000034}, 'missing signature/chained fixups or malformed commands')
        so, ss = commands[0x1d]; fo, fs = commands[0x80000034]
        need(fo + fs <= so, 'chained fixups overlaps signature')
        hits = {m.decode(): m in image for m in MARKERS}
        need(not identity or all(hits.values()), f'{ARCHES[sub]} missing QQ markers: {[k for k, v in hits.items() if not v]}')
        slices.append({'architecture': ARCHES[sub], 'cpu_subtype': hex(sub), 'offset': off, 'size': len(image),
                       'code_directories': signature(image, so, ss), 'chained_fixups': fixups(part(image, fo, fs)), 'markers': hits})
    disjoint(ranges)
    return {'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data), 'slices': slices,
            'qq_identity_required': identity, 'cms_trust_verified': False}


def ar(data):
    need(data[:8] == b'!<arch>\n', 'invalid AR magic')
    pos, members = 8, {}
    while pos < len(data):
        header = part(data, pos, 60); pos += 60
        need(header[58:] == b'`\n', 'invalid AR header terminator')
        name = header[:16].decode('ascii').strip().removesuffix('/')
        need(name not in members, 'duplicate AR member')
        need(int(header[28:34]) == int(header[34:40]) == 0 and int(header[40:48], 8) == 0o100644, 'AR member metadata must be root/0644')
        size = int(header[48:58]); members[name] = part(data, pos, size); pos += size
        if size % 2:
            need(part(data, pos, 1) == b'\n', 'invalid AR padding'); pos += 1
    need(list(members) == ['debian-binary', 'control.tar.gz', 'data.tar.gz'], 'wrong AR member names/order')
    need(members['debian-binary'] == b'2.0\n', 'wrong Debian format version')
    return members


def tar(data):
    with gzip.GzipFile(fileobj=io.BytesIO(data)) as gz:
        raw = gz.read(LIMIT + 1)
    need(len(raw) <= LIMIT, 'tar exceeds 128 MiB limit')
    files, directories = {}, set()
    with tarfile.open(fileobj=io.BytesIO(raw), mode='r:') as archive:
        for item in archive:
            name = item.name.removesuffix('/') if item.isdir() else item.name
            need(name and not name.startswith('/') and '\\' not in name and
                 all(p not in ('', '.', '..') for p in name.split('/')), f'unsafe tar path: {name!r}')
            need(name not in files and name not in directories, 'duplicate tar path')
            need((item.isfile() or item.isdir()) and not item.issparse() and not item.pax_headers, 'links/special/sparse/PAX members forbidden')
            need(item.uid == item.gid == 0 and item.uname in ('', 'root') and item.gname in ('', 'root'), 'tar ownership must be root')
            mode = 0o755 if item.isdir() or name.endswith('.dylib') else 0o644
            need(item.mode == mode, f'wrong mode for {name}: {oct(item.mode)}')
            if item.isdir():
                directories.add(name)
            else:
                files[name] = archive.extractfile(item).read()
    parents = {str(p) for name in files for p in Path(name).parents if str(p) != '.'}
    need(directories == parents, 'missing or extraneous parent directories')
    return files


def package(path):
    data = path.read_bytes(); members = ar(data); control_files = tar(members['control.tar.gz'])
    need(set(control_files) == {'control'}, 'control archive must contain only control')
    fields, last = {}, None
    for line in control_files['control'].decode('utf-8').splitlines():
        if line.startswith((' ', '\t')) and last:
            fields[last] += '\n' + line; continue
        if not line:
            last = None; continue
        key, sep, value = line.partition(':')
        need(sep and key not in fields and key.strip() == key, 'invalid/duplicate control field')
        fields[key] = value.strip(); last = key
    expected = {'Package': 'com.ning.qqphotobase64', 'Name': 'QQ图片编码', 'Version': '0.1.1', 'Maintainer': 'Ning', 'Author': 'Ning'}
    need(all(fields.get(k) == v for k, v in expected.items()), 'control identity/version/author mismatch')
    arch = fields.get('Architecture')
    need(arch in ('iphoneos-arm64', 'iphoneos-arm64e'), 'wrong package architecture')
    need(path.name == f'com.ning.qqphotobase64_0.1.1_{arch}.deb', 'package filename disagrees with control')
    prefix = 'var/jb/' if arch == 'iphoneos-arm64' else ''
    base = prefix + 'Library/MobileSubstrate/DynamicLibraries/QQPhotoBase64'
    files = tar(members['data.tar.gz'])
    need(set(files) == {base + '.dylib', base + '.plist'}, 'wrong package payload layout')
    need(plistlib.loads(files[base + '.plist']) == {'Filter': {'Bundles': ['com.tencent.mqq']}}, 'plist filter must be exactly com.tencent.mqq')
    dylib = files[base + '.dylib']
    return {'name': path.name, 'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data),
            'architecture': arch, 'layout': 'rootless' if prefix else 'RootHide-loader-layout',
            'control': fields, 'payload': sorted(files)}, dylib


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dylib', type=Path, help='Mach-O-only check; does not require QQ strings or write build report')
    parser.add_argument('--dist', type=Path, default=ROOT / 'dist', help='directory containing both final .deb files')
    args = parser.parse_args()
    report = {'ok': False, 'scope': 'dylib' if args.dylib else 'dist', 'packages': []}
    try:
        if args.dylib:
            report['dylib'] = macho(args.dylib.read_bytes())
        else:
            paths = sorted(args.dist.glob('*.deb'))
            need(len(paths) == 2, f'expected two final .deb files in {args.dist}; found {len(paths)}')
            payloads = []
            for path in paths:
                record, payload = package(path); report['packages'].append(record); payloads.append(payload)
            need({p['architecture'] for p in report['packages']} == {'iphoneos-arm64', 'iphoneos-arm64e'}, 'missing architecture variant')
            need(payloads[0] == payloads[1], 'package dylib bytes differ')
            report['dylib'] = macho(payloads[0], identity=True)
            report['dylibs_byte_identical'] = True
        report['ok'] = True
    except (ValueError, OSError, EOFError, tarfile.TarError, struct.error, OverflowError, zlib.error, ExpatError) as error:
        report['error'] = f'{type(error).__name__}: {error}'
    if not args.dylib:
        target = ROOT / 'build' / 'package-verification.json'; target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report['ok'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
