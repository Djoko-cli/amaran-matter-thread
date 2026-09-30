"""Tests de outils/serie.py et outils/console.py, sans carte."""
import contextlib
import io
import os
import struct
import tempfile
import termios
import threading
import time
import types
import unittest
from unittest import mock

import console
import serie
from port_factice import PortFactice


class TestMasquer(unittest.TestCase):
    def test_masque_les_cles_seulement(self):
        texte = "cles 00112233445566778899AABBCCDDEEFF empreinte A8FAED6A mac 70:3E:97:12:34:AB"
        self.assertEqual(serie.masquer(texte), "cles <cle masquee> empreinte A8FAED6A mac 70:3E:97:12:34:AB")


class TestConsole(unittest.TestCase):
    def test_executer_envoie_et_journalise(self):
        port = PortFactice([
            "amaran> ok envoi 0x0002 x1 : 0E00000000000000000E",
            "[1234 ms] etat lampe 1 (0x0002 -> 0x0001) : marche, intensite 930",
        ])
        lignes = []
        console.executer(port, ["lampe 1 releve", "@0.1"], lignes.append, apres_commande=0.1, avant=0)
        self.assertEqual(port.ecrit, ["lampe 1 releve\r\n"])
        self.assertEqual(lignes[0], "> lampe 1 releve")
        self.assertTrue(any("etat lampe 1" in l for l in lignes))

    def test_executer_masque_une_commande_a_cle(self):
        lignes = []
        console.executer(PortFactice(), ["mesh cles " + "AB" * 16 + " " + "CD" * 16], lignes.append,
                         apres_commande=0, avant=0)
        self.assertEqual(lignes, ["> mesh cles <cle masquee> <cle masquee>"])

    def test_executer_masque_une_ligne_recue(self):
        # L'echo d'une ligne `mesh cles ...` revient de la carte : lire_pendant
        # doit la masquer avant qu'elle n'atteigne l'ecran et le journal.
        lignes = []
        recu = "amaran> mesh cles " + "AB" * 16 + " " + "CD" * 16
        console.executer(PortFactice([recu]), ["@0.1"], lignes.append, apres_commande=0, avant=0)
        texte = "\n".join(lignes)
        self.assertNotIn("AB" * 16, texte)
        self.assertNotIn("CD" * 16, texte)
        self.assertEqual(lignes, ["amaran> mesh cles <cle masquee> <cle masquee>"])

    def test_port_inaccessible_rend_1(self):
        dossier = tempfile.mkdtemp()
        journal = os.path.join(dossier, "console.log")
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            result = console.main(["--port", "/dev/amaran-port-inexistant", "--journal", journal, "mesh"])
        self.assertEqual(result, 1)
        output = stdout.getvalue()
        self.assertTrue(any("erreur : " in line for line in output.split('\n')))


class TestPortSerie(unittest.TestCase):
    """Le port brut, sur une paire de pseudo-terminaux (pas de carte)."""

    def setUp(self):
        import tty

        self.maitre, esclave = os.openpty()
        tty.setraw(esclave)
        os.set_blocking(esclave, False)
        self.port = serie.PortSerie(esclave, 0.1)

    def tearDown(self):
        self.port.close()
        os.close(self.maitre)

    def test_readline_rend_une_ligne_a_la_fois(self):
        os.write(self.maitre, b"mesh\r\nok cles A B\r\namaran> ")
        self.assertEqual(self.port.readline(), b"mesh\r\n")
        self.assertEqual(self.port.readline(), b"ok cles A B\r\n")
        self.assertEqual(self.port.readline(), b"amaran> ")  # sans fin de ligne : rendu au bout du delai

    def test_readline_sans_rien_rend_vide(self):
        self.assertEqual(self.port.readline(), b"")

    def test_write_arrive_de_l_autre_cote(self):
        self.port.write(b"lampe 1 releve\r\n")
        self.assertEqual(os.read(self.maitre, 100), b"lampe 1 releve\r\n")

    def vider_le_maitre(self):
        """Lit tout ce qui attend de l'autre cote, pour que close() ne patiente pas dans flush()."""
        os.set_blocking(self.maitre, False)
        try:
            while os.read(self.maitre, 65536):
                pass
        except BlockingIOError:
            pass

    def test_write_leve_erreur_serie_si_la_carte_ne_lit_plus(self):
        # Personne ne lit de l'autre cote : le pseudo-terminal se remplit (1 Ko sur macOS).
        self.port.delai_ecriture = 0.3
        debut = time.monotonic()
        with self.assertRaises(serie.ErreurSerie) as cm:
            self.port.write(b"x" * 100000)
        self.assertIn("la carte ne lit plus", str(cm.exception))
        self.assertGreaterEqual(time.monotonic() - debut, 0.3)  # il a bien attendu delai_ecriture
        self.assertLess(time.monotonic() - debut, 2.0)  # et n'a pas attendu sans fin
        self.vider_le_maitre()

    def test_write_continue_tant_que_la_carte_lit(self):
        # Le delai court depuis le dernier octet parti, pas depuis le debut de l'appel :
        # un lecteur lent (60 ms entre deux lectures) ne fait pas abandonner l'ecriture,
        # meme si le total (8 Ko a 1 Ko par lecture) depasse largement delai_ecriture.
        self.port.delai_ecriture = 0.25
        os.set_blocking(self.maitre, False)
        recu = []
        fini = threading.Event()

        def lecteur():
            while not fini.is_set():
                try:
                    recu.append(os.read(self.maitre, 65536))
                except BlockingIOError:
                    pass
                time.sleep(0.06)

        fil = threading.Thread(target=lecteur)
        fil.start()
        try:
            debut = time.monotonic()
            self.port.write(b"y" * 8192)
            duree = time.monotonic() - debut
            time.sleep(0.15)  # laisser le lecteur prendre la fin
        finally:
            fini.set()
            fil.join()
        self.assertGreater(duree, 0.25)  # sans progres, delai_ecriture aurait deja tranche
        self.vider_le_maitre()
        self.assertEqual(sum(len(r) for r in recu), 8192)

    def test_reset_input_buffer_oublie_le_tampon(self):
        os.write(self.maitre, b"vieux\r\nreste")
        self.assertEqual(self.port.readline(), b"vieux\r\n")
        self.port.reset_input_buffer()
        self.assertEqual(self.port.readline(), b"")

    def test_close_deux_fois_sans_erreur(self):
        self.port.close()
        self.port.close()

    def test_flush_rend_vrai_quand_tout_est_parti(self):
        self.port.write(b"redemarre\r\n")
        self.assertEqual(os.read(self.maitre, 100), b"redemarre\r\n")  # l'autre cote a tout lu
        self.assertTrue(self.port.flush(delai=0.5))

    def test_flush_n_attend_pas_sans_fin(self):
        # Personne ne lit de l'autre cote : la file ne se vide pas.
        self.port.write(b"x" * 64)
        debut = time.monotonic()
        self.assertFalse(self.port.flush(delai=0.2))
        self.assertLess(time.monotonic() - debut, 1.0)

    def test_close_vide_la_sortie_avant_de_fermer(self):
        appels = []
        vrai_flush = self.port.flush
        self.port.flush = lambda: appels.append("flush") or vrai_flush(delai=0.2)
        self.port.close()
        self.assertEqual(appels, ["flush"])
        self.assertIsNone(self.port.fd)

    def test_port_inexistant_leve_erreur_serie(self):
        with self.assertRaises(serie.ErreurSerie):
            serie.ouvrir_port("/dev/amaran-port-inexistant")


class TestOuvrirPort(unittest.TestCase):
    """DTR et RTS doivent tomber ensemble : RTS=1 avec DTR=0, meme un instant, redemarre le C6."""

    def test_un_seul_tiocmset_a_zero_jamais_bis_ni_bic(self):
        maitre, esclave = os.openpty()  # un pseudo-terminal : pas de carte
        self.addCleanup(os.close, maitre)
        self.addCleanup(os.close, esclave)
        appels = []

        def faux_ioctl(fd, requete, arg=0, *reste):
            appels.append((requete, arg))
            return arg  # TIOCOUTQ (vidange a la fermeture) : le tampon d'octets nuls dit "file vide"

        faux_fcntl = types.SimpleNamespace(ioctl=faux_ioctl)
        with mock.patch.object(serie, "fcntl", faux_fcntl):
            serie.ouvrir_port(os.ttyname(esclave)).close()
        requetes = [requete for requete, _ in appels]
        self.assertEqual(requetes.count(termios.TIOCMSET), 1)
        self.assertNotIn(termios.TIOCMBIS, requetes)  # mettre DTR ou RTS a 1 seul
        self.assertNotIn(termios.TIOCMBIC, requetes)  # ou en baisser un seul
        arg = [a for r, a in appels if r == termios.TIOCMSET][0]
        self.assertEqual(struct.unpack("I", arg)[0], 0)  # tous les signaux a 0 d'un coup


if __name__ == "__main__":
    unittest.main()
