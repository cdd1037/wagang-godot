"""Check the HD export filter: every original picture an export preset leaves out has an HD version.

    python3 -I tools/check_hd_exclude.py [--apply]

Release builds ship the HD pack (game/assets_hd) in place of the original PNGs. The originals they leave out are
the assets/ entries of the iOS and Android presets' exclude_filter in game/export_presets.cfg. A PNG left out
without an HD version would be missing from the build (the game draws nothing there), so this lists them and
fails. Pictures without an HD version (data such as Qusi.wa 12..14, or art the game does not draw) simply stay
in the build. Godot matches the filters case-insensitively, `*` and `?` also match `/`, and there are no
[...] classes.

--apply first copies the iOS preset's assets/ entries into every preset that has none (the macOS and Windows
presets; .github/scripts/add_hd_pack.sh does this for the release builds).
"""
import fnmatch
import os
import re
import sys

GAME = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "game")
CFG = os.path.join(GAME, "export_presets.cfg")


def presets(text: str) -> list:
    """[(name, start, end)] of each [preset.N] section."""
    heads = [m for m in re.finditer(r"^\[preset\.(\d+)\]$", text, re.M)]
    out = []
    for i, m in enumerate(heads):
        end = heads[i + 1].start() if i + 1 < len(heads) else len(text)
        name = re.search(r'^name="([^"]*)"$', text[m.start():end], re.M).group(1)
        out.append((name, m.start(), end))
    return out


def get_filter(section: str) -> list:
    v = re.search(r'^exclude_filter="([^"]*)"$', section, re.M).group(1)
    return [p for p in v.split(",") if p]


def set_filter(section: str, pats: list) -> str:
    return re.sub(r'^exclude_filter="[^"]*"$', 'exclude_filter="%s"' % ",".join(pats), section, count=1, flags=re.M)


def apply(text: str) -> str:
    secs = presets(text)
    ios = [get_filter(text[s:e]) for n, s, e in secs if n == "iOS"][0]
    hd = [p for p in ios if p.startswith("assets/")]
    for n, s, e in reversed(secs):
        sec = text[s:e]
        pats = get_filter(sec)
        if not any(p.startswith("assets/") for p in pats):
            text = text[:s] + set_filter(sec, hd + pats) + text[e:]
    return text


def main() -> int:
    text = open(CFG, encoding="utf-8").read()
    if "--apply" in sys.argv:
        text = apply(text)
        open(CFG, "w", encoding="utf-8").write(text)
    files = []
    for root, _, names in os.walk(os.path.join(GAME, "assets")):
        files += [os.path.relpath(os.path.join(root, f), GAME).replace(os.sep, "/") for f in names]
    bad = 0
    for name, s, e in presets(text):
        pats = [p.lower() for p in get_filter(text[s:e]) if p.startswith("assets/")]
        if not pats:
            print("%s: ships the original pictures" % name)
            continue
        if any("[" in p for p in pats):
            print("%s: a filter uses [ ], which Godot does not support" % name)
            bad += 1
        left, missing, extra = 0, [], 0
        for f in files:
            hd = os.path.join(GAME, "assets_hd", f[len("assets/"):-4] + ".webp")
            if any(fnmatch.fnmatchcase(f.lower(), p) for p in pats):
                left += 1
                if not f.endswith(".png") or not os.path.exists(hd):
                    missing.append(f)
            elif f.endswith(".png") and os.path.exists(hd):
                extra += 1
        print("%s: %d originals left out, %d with an HD version kept as well, %d without an HD version"
              % (name, left, extra, len(missing)))
        for f in missing[:40]:
            print("  missing in the build:", f)
        if len(missing) > 40:
            print("  … and %d more" % (len(missing) - 40))
        bad += len(missing)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
