"""Tests de outils/serie.py et outils/console.py, sans carte ni pyserial."""
import contextlib
import io
import os
import tempfile
import unittest

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

    def test_port_inaccessible_rend_1(self):
        dossier = tempfile.mkdtemp()
        journal = os.path.join(dossier, "console.log")
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            result = console.main(["--port", "/dev/amaran-port-inexistant", "--journal", journal, "mesh"])
        self.assertEqual(result, 1)
        output = stdout.getvalue()
        self.assertTrue(any("erreur : " in line for line in output.split('\n')))


if __name__ == "__main__":
    unittest.main()
