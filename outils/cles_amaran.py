#!/usr/bin/env python3
"""Charge dans le pont les cles du reseau Bluetooth Mesh d'amaran Desktop.

Lit la base locale d'amaran Desktop, puis envoie par la console du pont :
    mesh cles <reseau> <application>
    mesh lampes <N>
    mesh lampe <n> <adresse> <mac> <code> [v<logiciel>[/<ble>]] "<nom>"   (une ligne par lampe)
    redemarre

Les cles ne sont jamais affichees : seulement leurs empreintes (8 premiers
chiffres hexa du SHA-256), les memes que la commande `mesh` du pont.

Quatre controles, pour ne jamais confier les cles a un autre appareil ni les
perdre en route :
    - avant les cles, la commande `mesh` doit rendre une ligne `mesh pret :`
      (sinon ce port n'est pas le pont, et rien n'est envoye) ;
    - apres `mesh cles`, les empreintes rendues par le pont doivent etre les
      notres (sinon erreur, et pas de redemarrage) ;
    - la derniere lampe envoyee, le pont doit dire la liste enregistree (sinon
      erreur, et pas de redemarrage) ;
    - apres `redemarre`, le pont doit ecrire `redemarrage` (sinon avertissement).

Le pont annonce le modele et les capacites de chaque lampe d'apres son
catalogue. Une lampe qui declare la temperature de couleur (Light CTL) ou la
couleur (Light HSL) dans sa composition, sans que le pont lui connaisse ces
capacites, est signalee : modele a cataloguer (marche et intensite seulement).

    python outils/cles_amaran.py                    # montre ce qui serait envoye
    python outils/cles_amaran.py --port /dev/cu.usbmodem1101
    python outils/cles_amaran.py --port ... --fictives 3   # banc : 3 lampes fictives en plus
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
CAPACITE = 16  # LISTE_CAPACITE du pont : il refuse lui-meme une liste plus longue
INVITE = "amaran>"
# Reponse du pont a `mesh cles` : ok cles <EMPREINTE RESEAU> <EMPREINTE APPLICATION> (...)
REPONSE_CLES = re.compile(r"ok cles ([0-9A-Fa-f]{8}) ([0-9A-Fa-f]{8})(?:\s|$)")
# Reponse a `mesh lampe` : ok lampe <n> 0x<adresse> modele <code> <nom du modele> [<capacites>]
# logiciel <version ou inconnu> : <nom>, et, pour la derniere, " ; liste de <N> lampe(s)
# enregistree (...)". Un pont d'avant le plan 3b-3 ne dit pas le logiciel.
REPONSE_LAMPE = re.compile(r"ok lampe (?P<n>\d+) 0x[0-9A-Fa-f]{4} modele (?P<code>\d+) (?P<modele>.+?) "
                           r"\[(?P<capacites>[a-z+]*)\](?: logiciel (?P<logiciel>.+?))? : (?P<nom>.*?)"
                           r"(?: ; liste de (?P<total>\d+) lampe\(s\) enregistree.*)?$")
# Version d'un logiciel de lampe (spec fiche des lampes 3) : comme le pont, sinon inconnue.
VERSION = re.compile(r"[0-9]{1,3}\.[0-9]{1,3}")
# Modeles SIG serveurs qui disent une capacite dans la composition d'une lampe.
MODELE_CTL = 0x1303  # Light CTL Server : temperature de couleur
MODELE_HSL = 0x1307  # Light HSL Server : couleur


class ErreurCles(Exception):
    pass


def trouver_base(motifs=MOTIFS_BASE):
    """La base d'amaran Desktop la plus recente parmi les motifs."""
    trouvees = [c for m in motifs for c in glob.glob(os.path.expanduser(m))]
    if not trouvees:
        raise ErreurCles("base d'amaran Desktop introuvable : passer --db")
    return max(trouvees, key=os.path.getmtime)


def modeles_sig(composition):
    """Modeles SIG declares par une lampe (composition_data, page 0, en hexa) ; vide si illisible.

    Page 0 : numero de page, CID, PID, VID, CRPL, fonctions (2 octets chacun),
    puis chaque element : emplacement (2), nombre de modeles SIG (1) et vendeur
    (1), les modeles SIG (2 octets) et vendeur (4 octets).
    """
    try:
        d = bytes.fromhex(composition or "")
    except (ValueError, TypeError):  # TypeError : valeur non texte dans la base
        return set()
    modeles = set()
    i = 11  # page, puis 5 champs de 2 octets
    while i + 4 <= len(d):
        nb_sig, nb_vendeur = d[i + 2], d[i + 3]
        i += 4
        if i + 2 * nb_sig + 4 * nb_vendeur > len(d):
            return set()
        for k in range(nb_sig):
            modeles.add(d[i + 2 * k] | (d[i + 2 * k + 1] << 8))
        i += 2 * nb_sig + 4 * nb_vendeur
    return modeles


def capacites_declarees(composition):
    """Capacites au-dela de l'intensite que la lampe declare : {"cct", "couleur"}."""
    m = modeles_sig(composition)
    return ({"cct"} if MODELE_CTL in m else set()) | ({"couleur"} if MODELE_HSL in m else set())


def lire_code(code):
    """Code produit Sidus (colonne `code`, texte) ; 0 s'il manque ou n'est pas un nombre."""
    texte = str(code).strip() if code is not None else ""
    return int(texte) if texte.isdigit() and int(texte) < 2 ** 32 else 0


LIGNE_MAX = 127  # la console du pont refuse une ligne plus longue


def lire_version(v):
    """Version x.y de la base, en texte seulement (un nombre perdrait ses zeros : 1.10), exacte
    (comme l'app : " 1.4" est inconnue), ou None."""
    return v if isinstance(v, str) and VERSION.fullmatch(v) else None


def nom_cite(nom):
    """Le nom entre guillemets, comme le decoupe la console (esp_console_split_argv) : un nom
    qui commence par v suivi d'un chiffre n'est jamais pris pour la version."""
    return '"%s"' % nom.replace("\\", "\\\\").replace('"', '\\"')


def jeton_logiciel(l):
    """Jeton de `mesh lampe` : v<logiciel>[/<ble>], ou "" si le logiciel est inconnu."""
    if not l.get("logiciel"):
        return ""
    return "v%s/%s" % (l["logiciel"], l["ble"]) if l.get("ble") else "v%s" % l["logiciel"]


def texte_logiciel(l):
    """Ce que le pont repond (et ce que Maison affiche) : 1.4 (BLE 1.69), 1.4, ou inconnu."""
    if not l.get("logiciel"):
        return "inconnu"
    return "%s (BLE %s)" % (l["logiciel"], l["ble"]) if l.get("ble") else l["logiciel"]


def lire_reseau(chemin):
    """Cles et lampes de la base, ouverte en lecture seule."""
    import re as _re
    try:
        con = sqlite3.connect("file:%s?mode=ro" % chemin, uri=True)
        try:
            reseaux = con.execute(
                "select net_key, app_key from mesh where net_key is not null and app_key is not null").fetchall()
            # `code` et `composition_data` : absentes d'une base plus ancienne, sans gravite.
            colonnes = {c[1] for c in con.execute("pragma table_info(fixtures)")}
            # Versions du logiciel (plan 3b-3) : absentes d'une base plus ancienne, sans gravite.
            extra = ", ".join(c if c in colonnes else "null" for c in
                              ("code", "composition_data", "control_software_version", "ble_software_version"))
            lignes = con.execute(
                "select node_address, mac_address, name, %s from fixtures "
                "where node_address is not null order by node_address" % extra).fetchall()
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
    if len(lignes) > CAPACITE:
        raise ErreurCles("%d lampes, le pont en gere %d" % (len(lignes), CAPACITE))
    lampes = []
    for adresse, mac, nom, code, composition, logiciel, ble in lignes:
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
        lampes.append({"adresse": adresse, "mac": mac.upper(), "nom": nom, "code": lire_code(code),
                       "declare": capacites_declarees(composition),
                       "logiciel": lire_version(logiciel), "ble": lire_version(ble)})
    return {"reseau": reseau, "application": application, "lampes": lampes}


def empreinte(cle):
    """8 premiers chiffres hexa (majuscules) du SHA-256, comme le pont."""
    return hashlib.sha256(cle).hexdigest()[:8].upper()


def resume(r):
    lignes = ["cles : reseau %s, application %s" % (empreinte(r["reseau"]), empreinte(r["application"]))]
    for i, l in enumerate(r["lampes"], 1):
        lignes.append("lampe %d : 0x%04X %s (%s), modele %s, logiciel %s" % (
            i, l["adresse"], l["nom"], l["mac"], l["code"] or "inconnu", texte_logiciel(l)))
    return lignes


# Reponse a `mesh lampes <N>` d'un pont qui prend la version (plan 3b-3) : un pont plus
# ancien lirait le jeton comme le debut du nom.
VERSION_PERMISE = "[v<x.y>[/<x.y>]]"


def commandes(r, versions=True):
    """`mesh cles`, `mesh lampes <N>`, puis une ligne par lampe : le code, la version, le nom.

    versions=False : sans jeton, pour un pont qui ne prend pas la version.
    """
    lignes = ["mesh cles %s %s" % (r["reseau"].hex().upper(), r["application"].hex().upper()),
              "mesh lampes %d" % len(r["lampes"])]
    for i, l in enumerate(r["lampes"], 1):
        jeton = jeton_logiciel(l) if versions else ""
        ligne = "mesh lampe %d 0x%04X %s %d %s%s" % (i, l["adresse"], l["mac"], l["code"],
                                                    jeton + " " if jeton else "", nom_cite(l["nom"]))
        if len(ligne.encode()) > LIGNE_MAX:
            raise ErreurCles("lampe %d : nom trop long pour la console du pont (%s) : le raccourcir dans "
                             "amaran Desktop" % (i, l["nom"]))
        lignes.append(ligne)
    return lignes


def ajouter_fictives(r, n):
    """Banc de capacite (plan 3a) : n lampes fictives apres les vraies, qui ne repondront jamais.

    Adresses a partir de 0x0100 (sautant celles des vraies lampes), MAC
    administrees localement (02:00:00:00:00:kk), code 0 (modele non catalogue).
    """
    if n < 0 or len(r["lampes"]) + n > CAPACITE:
        raise ErreurCles("%d lampes et %d fictives : le pont en gere %d" % (len(r["lampes"]), n, CAPACITE))
    prises = {l["adresse"] for l in r["lampes"]}
    adresse = 0x0100
    for k in range(1, n + 1):
        while adresse in prises:
            adresse += 1
        r["lampes"].append({"adresse": adresse, "mac": "02:00:00:00:00:%02X" % k, "nom": "Fictive %d" % k,
                            "code": 0, "declare": set(), "logiciel": None, "ble": None})
        prises.add(adresse)
    return r


def verifier_lampes(reponses, r, sortie=print, versions=True):
    """Lit les reponses aux lignes `mesh lampe` : modeles a cataloguer, et liste enregistree.

    Les reponses sont celles des lampes, dans l'ordre. Leve ErreurCles si la
    derniere ne dit pas la liste enregistree.
    """
    for i, (reponse, l) in enumerate(zip(reponses, r["lampes"]), 1):
        m = REPONSE_LAMPE.match(reponse)
        if not m or int(m.group("n")) != i:
            raise ErreurCles("reponse inattendue du pont a mesh lampe %d : %s" % (i, reponse))
        if versions and l.get("logiciel") and m.group("logiciel") != texte_logiciel(l):
            raise ErreurCles("le pont n'a pas pris la version de la lampe %d (%s) : mettre a jour son firmware"
                             % (i, m.group("logiciel") or "non dite"))
        connues = set(m.group("capacites").split("+"))
        for capacite, modele in (("cct", "temperature de couleur (Light CTL)"), ("couleur", "couleur (Light HSL)")):
            if capacite in l["declare"] and capacite not in connues:
                sortie("modele a cataloguer : lampe %d (%s, code %s) declare la %s, que le pont ne lui connait "
                       "pas : marche et intensite seulement" % (i, l["nom"], l["code"] or "inconnu", modele))
    dernier = REPONSE_LAMPE.match(reponses[-1]) if reponses else None
    if not dernier or dernier.group("total") is None or int(dernier.group("total")) != len(r["lampes"]):
        raise ErreurCles("le pont n'a pas enregistre la liste des lampes : ne pas le redemarrer, relancer l'outil")


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
    commandes(r)  # toute ligne trop longue est refusee ici, avant d'envoyer les cles
    verifier_pont(port, attente)
    cles, liste, *_ = commandes(r)  # `mesh cles`, `mesh lampes <N>`, puis une ligne par lampe
    verifier_empreintes(envoyer(port, [cles], attente=attente, sortie=sortie)[0], r)
    sortie("empreintes du pont identiques aux notres")
    versions = VERSION_PERMISE in envoyer(port, [liste], attente=attente, sortie=sortie)[0]
    if not versions and any(l.get("logiciel") for l in r["lampes"]):
        sortie("avertissement : ce pont ne prend pas la version des lampes (firmware d'avant le plan 3b-3) : "
               "liste chargee sans versions")
    lampes = commandes(r, versions=versions)[2:]
    verifier_lampes(envoyer(port, lampes, attente=attente, sortie=sortie), r, sortie=sortie, versions=versions)
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
    ap.add_argument("--fictives", type=int, default=0,
                    help="banc de capacite : N lampes fictives en plus, qui ne repondront jamais")
    args = ap.parse_args(argv)
    try:
        r = ajouter_fictives(lire_reseau(args.db or trouver_base()), args.fictives)
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
