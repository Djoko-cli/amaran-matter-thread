#!/usr/bin/env python3
"""Repare amaran Desktop sur macOS 27 : pose le cache de polices de matplotlib.

Au demarrage, amaran Desktop (matplotlib 3.10.8, embarque par Nuitka) construit
son cache de polices. Sur macOS 27, `system_profiler -xml SPFontsDataType` rend
un dictionnaire sans `_items`, et matplotlib plante (KeyError '_items') avant
meme d'ouvrir la fenetre. S'il trouve deja son cache, il ne l'interroge pas.

Ce script ecrit ce cache (fontlist-v390.json) avec les 38 polices embarquees
dans l'application, sans matplotlib : il reproduit ttfFontProperty
(font_manager.py de la v3.10.8) avec un lecteur TrueType minimal.

    python3 outils/polices_amaran_desktop.py             # chemins par defaut
    python3 outils/polices_amaran_desktop.py MPL_DATA SORTIE.json

Pour annuler : supprimer le fichier ecrit. Si une mise a jour de l'application
change de version de matplotlib (autre numero que 390), le cache est a refaire.
"""
import dataclasses
import json
import os
import re
import struct
import sys

WEIGHT_REGEXES = [
    ("thin", 100), ("extralight", 200), ("ultralight", 200), ("demilight", 350),
    ("semilight", 350), ("light", 300), ("book", 380), ("regular", 400),
    ("normal", 400), ("medium", 500), ("demibold", 600), ("demi", 600),
    ("semibold", 600), ("extrabold", 800), ("superbold", 800), ("ultrabold", 800),
    ("bold", 700), ("ultrablack", 1000), ("superblack", 1000), ("extrablack", 1000),
    (r"\bultra", 1000), ("black", 900), ("heavy", 900),
]
MAC_KEY = (1, 0, 0)
MS_KEY = (3, 1, 0x0409)


def lire_tables(data):
    sfnt_version, num_tables = struct.unpack(">IH", data[:6])
    if sfnt_version not in (0x00010000, 0x74727565):  # TrueType seulement
        raise ValueError("pas une police TrueType")
    tables = {}
    for i in range(num_tables):
        tag, _, off, length = struct.unpack(">4sIII", data[12 + 16 * i:28 + 16 * i])
        tables[tag.decode("latin-1")] = data[off:off + length]
    return tables


def lire_noms(name_table):
    _, count, string_off = struct.unpack(">HHH", name_table[:6])
    noms = {}
    for i in range(count):
        pid, eid, lid, nid, length, off = struct.unpack(">6H", name_table[6 + 12 * i:18 + 12 * i])
        noms[(pid, eid, lid, nid)] = name_table[string_off + off:string_off + off + length]
    return noms


def nom(noms, nid):
    """Comme FreeType : Microsoft Unicode anglais d'abord, sinon Mac roman."""
    b = noms.get((*MS_KEY, nid))
    if b:
        return b.decode("utf-16-be")
    b = noms.get((*MAC_KEY, nid))
    if b:
        return b.decode("latin-1")
    return ""


def propriete(chemin, relatif):
    data = open(chemin, "rb").read()
    t = lire_tables(data)
    noms = lire_noms(t["name"])
    # FreeType : famille typographique (16) si presente, sinon famille (1).
    family = nom(noms, 16) or nom(noms, 1)
    style_name = (nom(noms, 17) if nom(noms, 16) else "") or nom(noms, 2) or "Regular"
    os2 = t.get("OS/2")
    os2_version = struct.unpack(">H", os2[:2])[0] if os2 else None
    us_weight = struct.unpack(">H", os2[4:6])[0] if os2 else None
    fs_selection = struct.unpack(">H", os2[62:64])[0] if os2 else 0
    mac_style = struct.unpack(">H", t["head"][44:46])[0]
    italique = bool(fs_selection & 0x01) or bool(mac_style & 0x02)
    gras = bool(fs_selection & 0x20) or bool(mac_style & 0x01)

    sfnt2 = (noms.get((*MAC_KEY, 2), b"").decode("latin-1").lower()
             or noms.get((*MS_KEY, 2), b"").decode("utf_16_be").lower())
    sfnt4 = (noms.get((*MAC_KEY, 4), b"").decode("latin-1").lower()
             or noms.get((*MS_KEY, 4), b"").decode("utf_16_be").lower())
    if sfnt4.find("oblique") >= 0:
        style = "oblique"
    elif sfnt4.find("italic") >= 0:
        style = "italic"
    elif sfnt2.find("regular") >= 0:
        style = "normal"
    elif italique:
        style = "italic"
    else:
        style = "normal"
    variant = "small-caps" if family.lower() in ["capitals", "small-caps"] else "normal"

    styles = [
        noms.get((*MAC_KEY, 22), b"").decode("latin-1"),
        noms.get((*MAC_KEY, 16), b"").decode("latin-1"),
        noms.get((*MAC_KEY, 2), b"").decode("latin-1"),
        noms.get((*MS_KEY, 22), b"").decode("utf-16-be"),
        noms.get((*MS_KEY, 16), b"").decode("utf-16-be"),
        noms.get((*MS_KEY, 2), b"").decode("utf-16-be"),
    ]
    styles = [*filter(None, styles)] or [style_name]

    def poids():
        if os2 and os2_version != 0xFFFF:
            return us_weight
        # (ps_font_info : sans objet pour une TrueType)
        for s in styles:
            s = s.replace(" ", "")
            for regex, w in WEIGHT_REGEXES:
                if re.search(regex, s, re.I):
                    return w
        return 700 if gras else 500

    weight = int(poids())
    if any(w in sfnt4 for w in ["narrow", "condensed", "cond"]):
        stretch = "condensed"
    elif "demi cond" in sfnt4:
        stretch = "semi-condensed"
    elif any(w in sfnt4 for w in ["wide", "expanded", "extended"]):
        stretch = "expanded"
    else:
        stretch = "normal"
    return {"fname": relatif, "name": family, "style": style, "variant": variant,
            "weight": weight, "stretch": stretch, "size": "scalable", "__class__": "FontEntry"}


MPL_DATA = "/Applications/amaran Desktop.app/Contents/Resources/matplotlib/mpl-data"
SORTIE = "~/Library/Containers/com.sidus.amaran-desktop/Data/.matplotlib/fontlist-v390.json"


def main():
    if len(sys.argv) not in (1, 3):
        sys.exit("usage : polices_amaran_desktop.py [MPL_DATA SORTIE.json]")
    mpl_data, sortie = sys.argv[1:] if len(sys.argv) == 3 else (MPL_DATA, os.path.expanduser(SORTIE))
    os.makedirs(os.path.dirname(os.path.abspath(sortie)), exist_ok=True)
    ttflist = []
    for sous in ("ttf",):
        dossier = os.path.join(mpl_data, "fonts", sous)
        for f in sorted(os.listdir(dossier)):
            if f.lower().endswith((".ttf", ".otf", ".ttc")):
                ttflist.append(propriete(os.path.join(dossier, f), "fonts/%s/%s" % (sous, f)))
    fm = {
        "_version": 390,
        "_FontManager__default_weight": "normal",
        "default_size": None,
        "defaultFamily": {"ttf": "DejaVu Sans", "afm": "Helvetica"},
        "afmlist": [],
        "ttflist": ttflist,
        "__class__": "FontManager",
    }
    with open(sortie, "w") as fh:
        json.dump(fm, fh, indent=2)

    # Controle : relecture comme _json_decode de matplotlib 3.10.8.
    @dataclasses.dataclass(frozen=True)
    class FontEntry:
        fname: str = ""
        name: str = ""
        style: str = "normal"
        variant: str = "normal"
        weight: object = "normal"
        stretch: str = "normal"
        size: str = "medium"

    def decode(o):
        cls = o.pop("__class__", None)
        if cls == "FontEntry":
            return FontEntry(**o)
        return o

    relu = json.load(open(sortie), object_hook=decode)
    assert relu["_version"] == 390 and len(relu["ttflist"]) == len(ttflist)
    for e in relu["ttflist"]:
        print("%-38s %-24s %-8s %4d %s" % (e.fname, e.name, e.style, e.weight, e.stretch))
    print("%d polices ; relecture OK" % len(relu["ttflist"]))


if __name__ == "__main__":
    main()
