#!/usr/bin/env python3
"""Charge dans le pont les cles du reseau Bluetooth Mesh d'amaran Desktop.

Lit la base locale d'amaran Desktop, puis envoie par la console du pont :
    mesh cles <reseau> <application>
    mesh lampe <n> <adresse> <mac> <nom>
    redemarre

Les cles ne sont jamais affichees : seulement leurs empreintes (8 premiers
chiffres hexa du SHA-256), les memes que la commande `mesh` du pont.

Trois controles, pour ne jamais confier les cles a un autre appareil ni les
perdre en route :
    - avant les cles, la commande `mesh` doit rendre une ligne `mesh pret :`
      (sinon ce port n'est pas le pont, et rien n'est envoye) ;
    - apres `mesh cles`, les empreintes rendues par le pont doivent etre les
      notres (sinon erreur, et pas de redemarrage) ;
    - apres `redemarre`, le pont doit ecrire `redemarrage` (sinon avertissement).

    python outils/cles_amaran.py                    # montre ce qui serait envoye
    python outils/cles_amaran.py --port /dev/cu.usbmodem1101
"""
import argparse
import glob
import hashlib
import os
import re
import sqlite3
import sys
import time

from serie import ErreurSerie, masquer, ouvrir_port

MOTIFS_BASE = (
    "~/Library/Containers/com.sidus.amaran-desktop/Data/Library/Application Support/amaran Desktop/*/amaran.db",
    "~/Library/Application Support/amaran Desktop/*/amaran.db",
)
LAMPES_MAX = 2
INVITE = "amaran>"
# Reponse du pont a `mesh cles` : ok cles <EMPREINTE RESEAU> <EMPREINTE APPLICATION> (...)
REPONSE_CLES = re.compile(r"ok cles ([0-9A-Fa-f]{8}) ([0-9A-Fa-f]{8})(?:\s|$)")


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
    import re as _re
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
    except (ValueError, TypeError):
        raise ErreurCles("cle illisible dans la base")
    if len(reseau) != 16 or len(application) != 16:
        raise ErreurCles("cle de longueur inattendue")
    if not lignes:
        raise ErreurCles("aucune lampe dans la base")
    if len(lignes) > LAMPES_MAX:
        raise ErreurCles("%d lampes, le pont en gere %d" % (len(lignes), LAMPES_MAX))
    lampes = []
    for adresse, mac, nom in lignes:
        try:
            # Valider l'adresse : int, 1..0x7FFF
            if not isinstance(adresse, int) or adresse < 1 or adresse > 0x7FFF:
                raise ErreurCles("lampe illisible dans la base (adresse %r)" % (adresse,))
            # Valider la MAC : format XX:XX:XX:XX:XX:XX
            if mac is None or not _re.fullmatch(r"[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}", mac):
                raise ErreurCles("lampe illisible dans la base (adresse %r)" % (adresse,))
            # Valider le nom : non-vide, pas de caractere < 0x20
            if not isinstance(nom, str) or not nom or any(ord(c) < 0x20 for c in nom):
                raise ErreurCles("lampe illisible dans la base (adresse %r)" % (adresse,))
        except ErreurCles:
            raise
        except (AttributeError, TypeError):
            raise ErreurCles("lampe illisible dans la base (adresse %r)" % (adresse,))
        lampes.append({"adresse": adresse, "mac": mac.upper(), "nom": nom})
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


def texte_de_ligne(brute):
    """Une ligne du pont, sans l'invite qui la precede parfois."""
    return brute.decode(errors="replace").split(INVITE)[-1].strip()


def envoyer(port, lignes, attente=3.0, sortie=print):
    """Envoie chaque ligne et attend la reponse `ok ...` ou `erreur ...` du pont.

    Rend les reponses `ok ...`, masquees, dans l'ordre des lignes.
    """
    reponses = []
    for ligne in lignes:
        port.write((ligne + "\r\n").encode())
        fin = time.monotonic() + attente
        while True:
            if time.monotonic() > fin:
                raise ErreurCles("pas de reponse du pont a : %s" % masquer(ligne))
            brute = port.readline()
            if not brute:
                continue
            texte = texte_de_ligne(brute)
            if texte.startswith("ok"):
                sortie("pont : " + masquer(texte))
                reponses.append(masquer(texte))
                break
            if texte.startswith("erreur"):
                raise ErreurCles("pont : " + masquer(texte))
    return reponses


def verifier_pont(port, attente=3.0):
    """Envoie `mesh` et exige une ligne `mesh pret :` : sinon ce port n'est pas le pont.

    A appeler avant tout envoi de cles : sur un port qui ne repond pas comme le
    pont, seule la commande `mesh` est ecrite.
    """
    port.write(b"mesh\r\n")
    fin = time.monotonic() + attente
    while time.monotonic() <= fin:
        brute = port.readline()
        if brute and texte_de_ligne(brute).startswith("mesh pret :"):
            return
    raise ErreurCles("ce port n'est pas le pont : pas de ligne \"mesh pret :\" en reponse a la commande "
                     "mesh (ou il demarre encore). Aucune cle n'a ete envoyee.")


def verifier_empreintes(reponse, r):
    """Compare les empreintes de `ok cles <EMP> <EMP>` a celles des cles envoyees."""
    attendues = (empreinte(r["reseau"]), empreinte(r["application"]))
    m = REPONSE_CLES.match(reponse)
    if not m:
        raise ErreurCles("reponse inattendue du pont a mesh cles : %s" % masquer(reponse))
    rendues = (m.group(1).upper(), m.group(2).upper())
    if rendues != attendues:
        raise ErreurCles("le pont a enregistre d'autres cles que celles envoyees (empreintes rendues %s %s, "
                         "attendues %s %s) : ne pas le redemarrer, relancer l'outil"
                         % (rendues + attendues))


def attendre_redemarrage(port, attente=3.0):
    """Lit jusqu'a la ligne `redemarrage` que le pont ecrit avant de repartir. Faux si elle ne vient pas."""
    fin = time.monotonic() + attente
    while time.monotonic() <= fin:
        try:
            brute = port.readline()
        except (ErreurSerie, OSError):
            return False  # le port a disparu : la carte repart peut-etre, mais rien ne le confirme
        if brute and texte_de_ligne(brute).startswith("redemarrage"):
            return True
    return False


def charger(port, r, attente=3.0, sortie=print):
    """Charge les cles et les lampes de r dans le pont, puis le redemarre."""
    verifier_pont(port, attente)
    cles, *lampes = commandes(r)  # `mesh cles` d'abord, puis une ligne par lampe
    verifier_empreintes(envoyer(port, [cles], attente=attente, sortie=sortie)[0], r)
    sortie("empreintes du pont identiques aux notres")
    envoyer(port, lampes, attente=attente, sortie=sortie)
    port.write(b"redemarre\r\n")
    if attendre_redemarrage(port, attente):
        sortie("pont redemarre avec les nouvelles cles")
    else:
        sortie("avertissement : pas de ligne \"redemarrage\" recue : verifier avec la commande mesh "
               "que le pont a redemarre")


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
            charger(port, r, sortie=sortie)
        finally:
            port.close()
        return 0
    except (ErreurCles, ErreurSerie, OSError) as e:
        sortie("erreur : %s" % masquer(str(e)))
        return 1


if __name__ == "__main__":
    sys.exit(main())
