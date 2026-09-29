"""Tests de outils/cles_amaran.py, sans carte ni pyserial.

    python3 -m unittest discover -s outils -p "test_*.py" -v
"""
import os
import sqlite3
import tempfile
import time
import unittest

import cles_amaran as ca
from port_factice import PortFactice

NET = "00112233445566778899aabbccddeeff"
APP = "ffeeddccbbaa99887766554433221100"
LAMPES = ((4, "70:3e:97:00:00:02", "Lampe B"), (2, "70:3E:97:00:00:01", "Lampe A"))


def base_factice(dossier, lampes=LAMPES, reseaux=1):
    chemin = os.path.join(dossier, "amaran.db")
    con = sqlite3.connect(chemin)
    con.execute("create table mesh (uuid text, net_key varchar(32), app_key varchar(32), state integer)")
    con.execute("create table fixtures (uuid text, mac_address text, name text, node_address integer, device_key text)")
    for i in range(reseaux):
        con.execute("insert into mesh values (?, ?, ?, 3)", ("m%d" % i, NET.upper(), APP.upper()))
    for adresse, mac, nom in lampes:
        con.execute("insert into fixtures values (?, ?, ?, ?, ?)", ("f%d" % adresse, mac, nom, adresse, "00" * 16))
    con.commit()
    con.close()
    return chemin


class TestLecture(unittest.TestCase):
    def setUp(self):
        self.dossier = tempfile.mkdtemp()

    def test_cles_et_lampes_par_adresse(self):
        r = ca.lire_reseau(base_factice(self.dossier))
        self.assertEqual(r["reseau"], bytes.fromhex(NET))
        self.assertEqual(r["application"], bytes.fromhex(APP))
        self.assertEqual([l["adresse"] for l in r["lampes"]], [2, 4])
        self.assertEqual(r["lampes"][1]["mac"], "70:3E:97:00:00:02")

    def test_refuse_deux_reseaux(self):
        with self.assertRaises(ca.ErreurCles):
            ca.lire_reseau(base_factice(self.dossier, reseaux=2))

    def test_refuse_trois_lampes(self):
        trois = LAMPES + ((6, "70:3E:97:00:00:03", "Lampe C"),)
        with self.assertRaises(ca.ErreurCles):
            ca.lire_reseau(base_factice(self.dossier, lampes=trois))

    def test_refuse_base_sans_lampe(self):
        with self.assertRaises(ca.ErreurCles):
            ca.lire_reseau(base_factice(self.dossier, lampes=()))

    def test_refuse_base_absente(self):
        with self.assertRaises(ca.ErreurCles):
            ca.lire_reseau(os.path.join(self.dossier, "absente.db"))

    def test_trouve_la_base_la_plus_recente(self):
        for sous in ("1_secure_id", "2_secure_id"):
            os.makedirs(os.path.join(self.dossier, sous))
        ancienne = base_factice(os.path.join(self.dossier, "1_secure_id"))
        recente = base_factice(os.path.join(self.dossier, "2_secure_id"))
        passe = time.time() - 100
        os.utime(ancienne, (passe, passe))
        motif = os.path.join(self.dossier, "*", "amaran.db")
        self.assertEqual(ca.trouver_base((motif,)), recente)

    def test_base_introuvable(self):
        with self.assertRaises(ca.ErreurCles):
            ca.trouver_base((os.path.join(self.dossier, "*", "amaran.db"),))


class TestEmpreintesEtCommandes(unittest.TestCase):
    def test_empreintes_fixes(self):
        self.assertEqual(ca.empreinte(bytes.fromhex(NET)), "A8FAED6A")
        self.assertEqual(ca.empreinte(bytes.fromhex(APP)), "811407F1")

    def test_commandes(self):
        r = ca.lire_reseau(base_factice(tempfile.mkdtemp()))
        self.assertEqual(ca.commandes(r), [
            "mesh cles %s %s" % (NET.upper(), APP.upper()),
            "mesh lampe 1 0x0002 70:3E:97:00:00:01 Lampe A",
            "mesh lampe 2 0x0004 70:3E:97:00:00:02 Lampe B",
        ])


class TestSortie(unittest.TestCase):
    def test_sans_port_aucune_cle_affichee(self):
        capture = []
        code = ca.main(["--db", base_factice(tempfile.mkdtemp())], sortie=capture.append)
        texte = "\n".join(capture)
        self.assertEqual(code, 0)
        for cle in (NET, APP):
            self.assertNotIn(cle, texte.lower())
        self.assertIn("A8FAED6A", texte)
        self.assertIn("<cle masquee>", texte)

    def test_erreur_rend_1(self):
        capture = []
        absente = os.path.join(tempfile.mkdtemp(), "absente.db")
        self.assertEqual(ca.main(["--db", absente], sortie=capture.append), 1)
        self.assertTrue(capture[-1].startswith("erreur : "))


class TestEnvoi(unittest.TestCase):
    def test_attend_ok_et_masque(self):
        cles = "mesh cles %s %s" % (NET.upper(), APP.upper())
        port = PortFactice([
            cles,  # echo de la console
            "ok cles A8FAED6A 811407F1 (redemarrer pour les appliquer)",
            "amaran> ok lampe 1 0x0002 Lampe A",
        ])
        capture = []
        ca.envoyer(port, [cles, "mesh lampe 1 0x0002 70:3E:97:00:00:01 Lampe A"], attente=1, sortie=capture.append)
        self.assertEqual(len(port.ecrit), 2)
        self.assertTrue(all(l.endswith("\r\n") for l in port.ecrit))
        self.assertEqual(capture, [
            "pont : ok cles A8FAED6A 811407F1 (redemarrer pour les appliquer)",
            "pont : ok lampe 1 0x0002 Lampe A",
        ])

    def test_erreur_du_pont(self):
        with self.assertRaises(ca.ErreurCles):
            ca.envoyer(PortFactice(["erreur : ecriture NVS"]), ["mesh cles X Y"], attente=1, sortie=lambda t: None)

    def test_silence_du_pont(self):
        with self.assertRaises(ca.ErreurCles):
            ca.envoyer(PortFactice([]), ["mesh cles X Y"], attente=0.2, sortie=lambda t: None)


if __name__ == "__main__":
    unittest.main()
