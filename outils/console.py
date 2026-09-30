#!/usr/bin/env python3
"""Console de banc : envoie des commandes au pont et journalise ses reponses.

    python outils/console.py --port /dev/cu.usbmodem1101 "mesh" "@5" "lampe 1 releve" "@3"

"@N" lit pendant N secondes. Tout est copie, horodate, dans
logs/AAAA-MM-JJ-HHMM-console.log (logs/ est ignore par git). Les cles sont
masquees.
"""
import argparse
import os
import sys
import time

from serie import ErreurSerie, lire_pendant, masquer, ouvrir_port

RACINE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")


def executer(port, etapes, ecrire, apres_commande=1.0, avant=0.5):
    lire_pendant(port, avant, ecrire)
    for etape in etapes:
        if etape.startswith("@"):
            lire_pendant(port, float(etape[1:]), ecrire)
        else:
            ecrire("> " + masquer(etape))
            port.write((etape + "\r\n").encode())
            lire_pendant(port, apres_commande, ecrire)


def main(argv=None):
    ap = argparse.ArgumentParser(description="Console de banc du pont amaran.")
    ap.add_argument("--port", required=True)
    ap.add_argument("--journal", help="fichier journal (defaut : logs/<date>-console.log)")
    ap.add_argument("etapes", nargs="*", help='commandes, ou "@N" pour lire N secondes')
    args = ap.parse_args(argv)
    chemin = args.journal or os.path.join(RACINE, "logs", time.strftime("%Y-%m-%d-%H%M-console.log"))
    os.makedirs(os.path.dirname(os.path.abspath(chemin)), exist_ok=True)

    port = None
    try:
        with open(chemin, "a", encoding="utf-8") as journal:

            def ecrire(texte):
                ligne = time.strftime("%H:%M:%S ") + texte
                print(ligne, flush=True)
                journal.write(ligne + "\n")
                journal.flush()

            port = ouvrir_port(args.port)
            try:
                executer(port, args.etapes, ecrire)
            finally:
                if port:
                    port.close()
        return 0
    except (ErreurSerie, OSError) as e:
        print("erreur : " + masquer(str(e)), flush=True)
        return 1


if __name__ == "__main__":
    sys.exit(main())
