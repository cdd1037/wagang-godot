"""Mark every converted asset under game/assets as importer=keep so Godot ships the raw
file and the game loads it at runtime (Image.load_from_file, AudioStreamMP3.load_from_file...)."""
import os, sys
ROOT = '/Users/f2pgod/Downloads/rea/game/assets'
EXTS = ('.png', '.json', '.mp3', '.wav', '.ogv', '.txt', '.bin')
KEEP = '[remap]\n\nimporter="keep"\n'
n = 0
for dp, dn, fn in os.walk(ROOT):
    for f in fn:
        if f.lower().endswith(EXTS):
            ip = os.path.join(dp, f + '.import')
            try:
                if open(ip).read() == KEEP: continue
            except FileNotFoundError:
                pass
            open(ip, 'w').write(KEEP); n += 1
print('marked', n)
