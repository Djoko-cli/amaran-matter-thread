#!/usr/bin/env python3
"""Charge dans le pont les cles du reseau Bluetooth Mesh d'amaran Desktop.

Lit la base locale d'amaran Desktop, puis envoie par la console du pont :
    mesh cles <reseau> <application>
    mesh lampe <n> <adresse> <mac> <nom>
    redemarre

Les cles ne sont jamais affichees : seulement leurs empreintes (8 premiers
chiffres hexa du SHA-256), les memes que la commande `mesh` du pont.

    python outils/cles_amaran.py                    # montre ce qui serait envoye
    python outils/cles_amaran.py --port /dev/cu.usbmodem1101

Avec --port, lancer avec le Python d'ESP-IDF (pyserial).
"""
import argparse
import glob
import hashlib
import os
import sqlite3
import sys
import time

from serie import masquer, ouvrir_port

MOTIFS_BASE = (
    "~/Library/Containers/com.sidus.amaran-desktop/Data/Library/Application Support/amaran Desktop/*/amaran.db",
    "~/Library/Application Support/amaran Desktop/*/amaran.db",
)
LAMPES_MAX = 2
INVITE = "amaran>"


class ErreurCles(Exception):
    pass


def trouver_base(motifs=MOTIFS_BASE):
    """La base d'amaran Desktop la plus recente parmi les motifs."""
    trouvees = [c for m in motifs for c in glob.glob(os.path.expanduser(m))]
    if not trouvees:
        raise ErreurCles("base d'amaran Desktop introuvable : passer --db")
    return max(trouvees, key=os.path.getmtime)


def lire_reseau(chemin):
    """Cles et lampes de la base, ouverte en lecture seule."""
    try:
        con = sqlite3.connect("file:%s?mode=ro" % chemin, uri=True)
        try:
            reseaux = con.execute(
                "select net_key, app_key from mesh where net_key is not null and app_key is not null").fetchall()
            lignes = con.execute(
                "select node_address, mac_address, name from fixtures "
                "where node_address is not null order by node_address").fetchall()
        finally:
            con.close()
    except sqlite3.Error as e:
        raise ErreurCles("base illisible (%s)" % e)
    if len(reseaux) != 1:
        raise ErreurCles("%d reseaux dans la base, 1 attendu" % len(reseaux))
    try:
        reseau, application = bytes.fromhex(reseaux[0][0]), bytes.fromhex(reseaux[0][1])
    except ValueError:
        raise ErreurCles("cle illisible dans la base")
    if len(reseau) != 16 or len(application) != 16:
        raise ErreurCles("cle de longueur inattendue")
    if not lignes:
        raise ErreurCles("aucune lampe dans la base")
    if len(lignes) > LAMPES_MAX:
        raise ErreurCles("%d lampes, le pont en gere %d" % (len(lignes), LAMPES_MAX))
    lampes = [{"adresse": a, "mac": m.upper(), "nom": n} for a, m, n in lignes]
    return {"reseau": reseau, "application": application, "lampes": lampes}


def empreinte(cle):
    """8 premiers chiffres hexa (majuscules) du SHA-256, comme le pont."""
    return hashlib.sha256(cle).hexdigest()[:8].upper()


def resume(r):
    lignes = ["cles : reseau %s, application %s" % (empreinte(r["reseau"]), empreinte(r["application"]))]
    for i, l in enumerate(r["lampes"], 1):
        lignes.append("lampe %d : 0x%04X %s (%s)" % (i, l["adresse"], l["nom"], l["mac"]))
    return lignes


def commandes(r):
    lignes = ["mesh cles %s %s" % (r["reseau"].hex().upper(), r["application"].hex().upper())]
    for i, l in enumerate(r["lampes"], 1):
        lignes.append("mesh lampe %d 0x%04X %s %s" % (i, l["adresse"], l["mac"], l["nom"]))
    return lignes


def envoyer(port, lignes, attente=3.0, sortie=print):
    """Envoie chaque ligne et attend la reponse `ok ...` ou `erreur ...` du pont."""
    for ligne in lignes:
        port.write((ligne + "\r\n").encode())
        fin = time.monotonic() + attente
        while True:
            if time.monotonic() > fin:
                raise ErreurCles("pas de reponse du pont a : %s" % masquer(ligne))
            brute = port.readline()
            if not brute:
                continue
            texte = brute.decode(errors="replace").split(INVITE)[-1].strip()
            if texte.startswith("ok"):
                sortie("pont : " + masquer(texte))
                break
            if texte.startswith("erreur"):
                raise ErreurCles("pont : " + masquer(texte))


def main(argv=None, sortie=print):
    ap = argparse.ArgumentParser(description="Charge les cles d'amaran Desktop dans le pont.")
    ap.add_argument("--db", help="base d'amaran Desktop (sinon : la plus recente)")
    ap.add_argument("--port", help="port serie du pont ; sans lui, rien n'est envoye")
    args = ap.parse_args(argv)
    try:
        r = lire_reseau(args.db or trouver_base())
        for ligne in resume(r):
            sortie(ligne)
        lignes = commandes(r)
        if not args.port:
            sortie("(sans --port : rien n'est envoye)")
            for ligne in lignes:
                sortie("  " + masquer(ligne))
            return 0
        port = ouvrir_port(args.port)
        try:
            time.sleep(0.3)
            port.reset_input_buffer()
            envoyer(port, lignes, sortie=sortie)
            port.write(b"redemarre\r\n")
            sortie("pont redemarre avec les nouvelles cles")
        finally:
            port.close()
        return 0
    except ErreurCles as e:
        sortie("erreur : %s" % e)
        return 1


if __name__ == "__main__":
    sys.exit(main())
