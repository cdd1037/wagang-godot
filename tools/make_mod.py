"""Build a mod for the Godot game (docs/MODDING.md) from a modified copy of the original game.

usage: tools/venv/bin/python -I tools/make_mod.py MODDED_GAME_DIR OUT.zip [EXTRA_DIR]

Converts the copy's scenario scripts (R_xx / S_xx .wagan, tools/eex.py), data tables (tools/conv_data.py) and
program image (wagan.wa, tools/dump_image.py) into a temporary folder, compares each file with the game's own in
game/assets, and packs the ones that differ or are new into OUT.zip under assets/, the layout the game mounts
from user://mods/. EXTRA_DIR, if given, is a folder laid out like game/assets (pictures as PNG, sounds, ...) whose
files go in as they are. Prints what went in; exit status 1 when nothing differs. The copy is only read.
"""
import os as _os
_REPO = _os.path.dirname(_os.path.dirname(_os.path.abspath(__file__)))   # repository root
import filecmp, os, subprocess, sys, tempfile, zipfile

TOOLS = os.path.join(_REPO, 'tools')
ASSETS = os.path.join(_REPO, 'game', 'assets')


def run(args):
    subprocess.run([sys.executable, '-I'] + args, check=True, stdout=subprocess.DEVNULL)


def changed(conv, sub):
    """{rel: path} of the converted files under conv/sub that the game lacks or has otherwise."""
    out = {}
    for name in sorted(os.listdir(os.path.join(conv, sub))):
        p = os.path.join(conv, sub, name)
        if os.path.isdir(p):
            continue                      # eex.py's text listings
        rel = sub + '/' + name
        base = os.path.join(ASSETS, sub, name)
        if not os.path.exists(base) or not filecmp.cmp(p, base, shallow=False):
            out[rel] = p
    return out


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    game, out = os.path.abspath(argv[0]), os.path.abspath(argv[1])
    extra = os.path.abspath(argv[2]) if len(argv) > 2 else None
    if not os.path.isfile(os.path.join(game, 'wagan.wa')):
        print('%s: no wagan.wa there (give the folder of the modified game)' % game)
        return 2
    files = {}
    with tempfile.TemporaryDirectory() as tmp:
        for sub in ('scripts', 'data'):
            os.makedirs(os.path.join(tmp, sub))
        run([os.path.join(TOOLS, 'eex.py'), '--src=' + game, '--out=' + os.path.join(tmp, 'scripts')])
        run([os.path.join(TOOLS, 'conv_data.py'), game, os.path.join(tmp, 'data')])
        run([os.path.join(TOOLS, 'dump_image.py'), os.path.join(game, 'wagan.wa'),
             os.path.join(tmp, 'data', 'exe_image.bin')])
        files.update(changed(tmp, 'scripts'))
        files.update(changed(tmp, 'data'))
        if extra:
            for root, _dirs, names in os.walk(extra):
                for name in names:
                    if name.endswith('.import') or name.startswith('.'):
                        continue
                    p = os.path.join(root, name)
                    files[os.path.relpath(p, extra).replace(os.sep, '/')] = p
        if not files:
            print('no differences from the game: nothing to pack')
            return 1
        with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
            for rel, p in sorted(files.items()):
                z.write(p, 'assets/' + rel)
                print('  assets/' + rel)
    print('%s: %d files' % (out, len(files)))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
