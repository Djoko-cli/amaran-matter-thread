"""Liaison serie avec le pont (USB natif du C6) et masquage des cles.

ouvrir_port() demande pyserial : lancer les outils avec le Python d'ESP-IDF
(`export PATH="/opt/homebrew/bin:$PATH" && source ~/esp/esp-idf/export.sh`).
Les tests n'en ont pas besoin.
"""
import re
import time

HEXA_CLE = re.compile(r"[0-9A-Fa-f]{32}")


class ErreurSerie(Exception):
    """Port serie inaccessible, ou pyserial absent."""
    pass


def masquer(texte):
    """Remplace toute suite de 32 chiffres hexa (une cle) par <cle masquee>."""
    return HEXA_CLE.sub("<cle masquee>", texte)


def ouvrir_port(nom, debit=115200, delai=0.2):
    try:
        import serial  # pyserial
    except ImportError:
        raise ErreurSerie("pyserial absent : lancer avec le Python d'ESP-IDF")

    port = serial.Serial()
    port.port = nom
    port.baudrate = debit
    port.timeout = delai
    # Jamais RTS=1/DTR=0 : cette combinaison redemarre le C6 (lecon du Halo).
    port.dtr = False
    port.rts = False
    try:
        port.open()
    except OSError as e:
        raise ErreurSerie("port %s inaccessible (%s)" % (nom, e))
    return port


def lire_pendant(port, duree, ecrire):
    """Passe a ecrire() chaque ligne recue pendant duree secondes, masquee."""
    fin = time.monotonic() + duree
    while time.monotonic() < fin:
        brute = port.readline()
        if brute:
            ecrire(masquer(brute.decode(errors="replace").rstrip()))
