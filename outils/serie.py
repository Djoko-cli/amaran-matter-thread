"""Liaison serie avec le pont (USB natif du C6) et masquage des cles.

Sans pyserial : le port est ouvert a la main (os, termios), pour baisser DTR
et RTS en un seul appel (voir ouvrir_port).
"""
import fcntl
import os
import re
import select
import struct
import termios
import time

HEXA_CLE = re.compile(r"[0-9A-Fa-f]{32}")
DELAI_ECRITURE = 2.0  # sans aucun octet parti au-dela : la carte ne lit plus


class ErreurSerie(Exception):
    """Port serie inaccessible ou inutilisable."""
    pass


def masquer(texte):
    """Remplace toute suite de 32 chiffres hexa (une cle) par <cle masquee>."""
    return HEXA_CLE.sub("<cle masquee>", texte)


class PortSerie:
    """Port serie deja ouvert : write(), readline(), reset_input_buffer(), close()."""

    def __init__(self, fd, delai, delai_ecriture=DELAI_ECRITURE):
        self.fd = fd
        self.delai = delai
        self.delai_ecriture = delai_ecriture
        self._tampon = b""

    def write(self, octets):
        """Ecrit tout, ou leve ErreurSerie si rien ne part pendant delai_ecriture secondes."""
        limite = time.monotonic() + self.delai_ecriture
        while octets:
            try:
                n = os.write(self.fd, octets)
            except BlockingIOError:
                n = 0
            if n:
                octets = octets[n:]
                limite = time.monotonic() + self.delai_ecriture  # la carte lit : on repart pour un tour
                continue
            reste = limite - time.monotonic()
            if reste <= 0:
                raise ErreurSerie("la carte ne lit plus")
            select.select([], [self.fd], [], min(self.delai, reste))

    def readline(self):
        """Une ligne avec son \\n, sinon ce qui est arrive pendant delai secondes."""
        fin = time.monotonic() + self.delai
        while b"\n" not in self._tampon:
            reste = fin - time.monotonic()
            if reste <= 0:
                break
            prets, _, _ = select.select([self.fd], [], [], reste)
            if not prets:
                break
            try:
                octets = os.read(self.fd, 4096)
            except BlockingIOError:
                continue
            if not octets:
                raise ErreurSerie("port ferme")
            self._tampon += octets
        i = self._tampon.find(b"\n") + 1
        if i == 0:
            i = len(self._tampon)
        ligne, self._tampon = self._tampon[:i], self._tampon[i:]
        return ligne

    def reset_input_buffer(self):
        termios.tcflush(self.fd, termios.TCIFLUSH)
        self._tampon = b""

    def flush(self, delai=1.0):
        """Attend que la file de sortie soit vide, au plus delai secondes.

        Pas tcdrain() : il attendrait sans fin une carte qui ne lit plus.
        Rend faux si la file ne s'est pas videe a temps.
        """
        fin = time.monotonic() + delai
        while True:
            reste = struct.unpack("i", fcntl.ioctl(self.fd, termios.TIOCOUTQ, struct.pack("i", 0)))[0]
            if reste == 0:
                time.sleep(0.05)  # le pilote USB envoie encore son dernier paquet
                return True
            if time.monotonic() >= fin:
                return False
            time.sleep(0.01)

    def close(self):
        # Sans vidange, la fermeture d'un port non bloquant jette ce qui attend
        # encore : le `redemarre` final de cles_amaran.py se perdait.
        if self.fd is not None:
            try:
                self.flush()
            except OSError:
                pass
            os.close(self.fd)
            self.fd = None


def ouvrir_port(nom, debit=115200, delai=0.2):
    """Ouvre le port du C6 sans le redemarrer.

    RTS=1 avec DTR=0, meme un instant, redemarre le C6. pyserial baisse DTR
    puis RTS en deux appels et passe par cet etat : chaque ouverture relancait
    la carte (constate au banc du 30/09, deja vu sur le Halo et la hotte). Ici
    les deux tombent ensemble (TIOCMSET), comme dans les outils de ces projets.
    """
    try:
        fd = os.open(nom, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    except OSError as e:
        raise ErreurSerie("port %s inaccessible (%s)" % (nom, e))
    try:
        fcntl.ioctl(fd, termios.TIOCEXCL)
        fcntl.ioctl(fd, termios.TIOCMSET, struct.pack("I", 0))
        iflag, oflag, cflag, lflag, _, _, cc = termios.tcgetattr(fd)
        iflag &= ~(termios.IGNBRK | termios.BRKINT | termios.PARMRK | termios.ISTRIP | termios.INLCR
                   | termios.IGNCR | termios.ICRNL | termios.IXON)
        oflag &= ~termios.OPOST
        lflag &= ~(termios.ECHO | termios.ECHONL | termios.ICANON | termios.ISIG | termios.IEXTEN)
        cflag &= ~(termios.CSIZE | termios.PARENB | termios.HUPCL)
        cflag |= termios.CS8 | termios.CLOCAL | termios.CREAD
        vitesse = getattr(termios, "B%d" % debit)
        termios.tcsetattr(fd, termios.TCSANOW, [iflag, oflag, cflag, lflag, vitesse, vitesse, cc])
    except (OSError, termios.error, AttributeError) as e:
        os.close(fd)
        raise ErreurSerie("port %s inutilisable (%s)" % (nom, e))
    return PortSerie(fd, delai)


def lire_pendant(port, duree, ecrire):
    """Passe a ecrire() chaque ligne recue pendant duree secondes, masquee."""
    fin = time.monotonic() + duree
    while time.monotonic() < fin:
        brute = port.readline()
        if brute:
            ecrire(masquer(brute.decode(errors="replace").rstrip()))
