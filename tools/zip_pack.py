"""Zip a folder so that the same files always give the same bytes: entries in name order, stored (no
compression), with a fixed date and mode and no extra fields, so neither file times nor the user who made the
pictures change the archive. tools/publish_hd_pack.sh builds the HD pack with it.
usage: zip_pack.py DIR OUT.zip
"""
import os
import sys
import zipfile


def main():
    src, out = sys.argv[1], sys.argv[2]
    names = []
    for root, dirs, files in os.walk(src):
        for f in files:
            if f.endswith('.tmp') or f == '.DS_Store':
                continue
            names.append(os.path.relpath(os.path.join(root, f), src).replace(os.sep, '/'))
    names.sort()
    tmp = out + '.part'
    with zipfile.ZipFile(tmp, 'w', zipfile.ZIP_STORED) as z:
        for n in names:
            info = zipfile.ZipInfo(n, date_time=(1980, 1, 1, 0, 0, 0))
            info.create_system = 3                 # unix, so the mode below is read
            info.external_attr = 0o644 << 16
            with open(os.path.join(src, n), 'rb') as f:
                z.writestr(info, f.read())
    os.replace(tmp, out)
    print('%s: %d files' % (out, len(names)))


if __name__ == '__main__':
    main()
