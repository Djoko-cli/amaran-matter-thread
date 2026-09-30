"""Tests de outils/cles_amaran.py, sans carte.

    python3 -m unittest discover -s outils -p "test_*.py" -v
"""
import os
import sqlite3
import tempfile
import time
import unittest

import cles_amaran as ca
from port_factice import PortFactice
from serie import ErreurSerie

NET = "00112233445566778899aabbccddeeff"
APP = "ffeeddccbbaa99887766554433221100"
LAMPES = ((4, "70:3e:97:00:00:02", "Lampe B"), (2, "70:3E:97:00:00:01", "Lampe A"))


def base_factice(dossier, lampes=LAMPES, reseaux=1, net=NET.upper()):
    chemin = os.path.join(dossier, "amaran.db")
    con = sqlite3.connect(chemin)
    con.execute("create table mesh (uuid text, net_key varchar(32), app_key varchar(32), state integer)")
    con.execute("create table fixtures (uuid text, mac_address text, name text, node_address integer, device_key text)")
    for i in range(reseaux):
        con.execute("insert into mesh values (?, ?, ?, 3)", ("m%d" % i, net, APP.upper()))
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

    def test_masque_une_cle_dans_une_erreur(self):
        port = PortFactice(["erreur : cle refusee " + NET.upper()])
        capture = []
        with self.assertRaises(ca.ErreurCles) as cm:
            ca.envoyer(port, ["mesh cles X Y"], attente=1, sortie=capture.append)
        texte = "\n".join(capture)
        self.assertNotIn(NET.lower(), texte.lower())
        self.assertNotIn(APP.lower(), texte.lower())
        self.assertNotIn(NET.lower(), str(cm.exception).lower())
        self.assertNotIn(APP.lower(), str(cm.exception).lower())

    def test_masque_une_cle_dans_un_ok(self):
        port = PortFactice(["ok cles " + APP.upper()])
        capture = []
        ca.envoyer(port, ["mesh cles X Y"], attente=1, sortie=capture.append)
        texte = "\n".join(capture)
        self.assertNotIn(NET.lower(), texte.lower())
        self.assertNotIn(APP.lower(), texte.lower())

    def test_masque_la_commande_en_cas_de_silence(self):
        port = PortFactice([])
        with self.assertRaises(ca.ErreurCles) as cm:
            ca.envoyer(port, ["mesh cles %s %s" % (NET.upper(), APP.upper())], attente=0.2, sortie=lambda t: None)
        texte = str(cm.exception)
        self.assertNotIn(NET.lower(), texte.lower())
        self.assertNotIn(APP.lower(), texte.lower())


class TestReponsesRendues(unittest.TestCase):
    def test_envoyer_rend_les_reponses_ok_masquees(self):
        port = PortFactice(["ok cles A8FAED6A 811407F1 " + NET.upper(), "amaran> ok lampe 1 0x0002 Lampe A"])
        reponses = ca.envoyer(port, ["mesh cles X Y", "mesh lampe 1 0x0002 M Lampe A"], attente=1,
                              sortie=lambda t: None)
        self.assertEqual(reponses, ["ok cles A8FAED6A 811407F1 <cle masquee>", "ok lampe 1 0x0002 Lampe A"])


class PortQuiSeFerme(PortFactice):
    """Comme PortFactice, mais le port disparait (carte qui repart) quand il n'y a plus rien a lire."""

    def readline(self):
        if not self.reponses:
            raise ErreurSerie("port ferme")
        return super().readline()


class TestChargement(unittest.TestCase):
    """charger() : le port doit etre le pont, les empreintes rendues doivent etre les notres."""

    def setUp(self):
        self.r = ca.lire_reseau(base_factice(tempfile.mkdtemp()))
        self.cles = "mesh cles %s %s" % (NET.upper(), APP.upper())
        self.capture = []

    def reponses(self, ok_cles="ok cles A8FAED6A 811407F1 (redemarrer pour les appliquer)",
                 fin=("redemarre", "redemarrage")):
        """Ce que dit le pont : etat (reponse a `mesh`), puis un `ok` par ligne, puis le redemarrage."""
        return ["mesh", "mesh pret : oui", "cles : reseau A8FAED6A, application 811407F1", "amaran>",
                self.cles, ok_cles,
                "ok lampe 1 0x0002 Lampe A (redemarrer pour l'appliquer)",
                "ok lampe 2 0x0004 Lampe B (redemarrer pour l'appliquer)"] + list(fin)

    def charger(self, port, attente=1):
        return ca.charger(port, self.r, attente=attente, sortie=self.capture.append)

    def assert_aucune_cle(self, *textes):
        tout = "\n".join(textes).lower()
        self.assertNotIn(NET.lower(), tout)
        self.assertNotIn(APP.lower(), tout)

    def test_chargement_complet_dans_l_ordre(self):
        port = PortFactice(self.reponses())
        self.charger(port)
        self.assertEqual(port.ecrit, [
            "mesh\r\n",  # d'abord verifier le pont
            self.cles + "\r\n",
            "mesh lampe 1 0x0002 70:3E:97:00:00:01 Lampe A\r\n",
            "mesh lampe 2 0x0004 70:3E:97:00:00:02 Lampe B\r\n",
            "redemarre\r\n",
        ])
        self.assertIn("empreintes du pont identiques aux notres", self.capture)
        self.assertEqual(self.capture[-1], "pont redemarre avec les nouvelles cles")
        self.assert_aucune_cle(*self.capture)

    def test_un_autre_appareil_ne_recoit_pas_les_cles(self):
        # Un terminal quelconque : il ne rend jamais `mesh pret :`.
        port = PortFactice(["$ ", "bash: mesh: command not found"])
        with self.assertRaises(ca.ErreurCles) as cm:
            self.charger(port, attente=0.3)
        self.assertIn("n'est pas le pont", str(cm.exception))
        self.assertEqual(port.ecrit, ["mesh\r\n"])  # seule la commande de controle est partie
        self.assert_aucune_cle("".join(port.ecrit), str(cm.exception))

    def test_port_muet_ne_recoit_pas_les_cles(self):
        port = PortFactice([])
        with self.assertRaises(ca.ErreurCles):
            self.charger(port, attente=0.3)
        self.assertEqual(port.ecrit, ["mesh\r\n"])

    def test_le_pont_pas_pret_est_accepte(self):
        # `mesh pret : non` (cles pas encore chargees) reste bien le pont.
        reponses = self.reponses()
        reponses[1] = "mesh pret : non"
        port = PortFactice(reponses)
        self.charger(port)
        self.assertEqual(port.ecrit[1], self.cles + "\r\n")

    def test_empreinte_reseau_differente_arrete_tout(self):
        port = PortFactice(self.reponses(ok_cles="ok cles DEADBEEF 811407F1 (redemarrer pour les appliquer)"))
        with self.assertRaises(ca.ErreurCles) as cm:
            self.charger(port)
        self.assertIn("DEADBEEF", str(cm.exception))
        self.assertIn("A8FAED6A", str(cm.exception))  # l'empreinte attendue
        # Ni les lampes ni le redemarrage : le pont garde ses cles d'avant en memoire.
        self.assertEqual(port.ecrit, ["mesh\r\n", self.cles + "\r\n"])
        self.assert_aucune_cle(str(cm.exception), *self.capture)

    def test_empreinte_application_differente_arrete_tout(self):
        port = PortFactice(self.reponses(ok_cles="ok cles A8FAED6A DEADBEEF (redemarrer pour les appliquer)"))
        with self.assertRaises(ca.ErreurCles):
            self.charger(port)
        self.assertEqual(port.ecrit, ["mesh\r\n", self.cles + "\r\n"])

    def test_reponse_sans_empreintes_arrete_tout(self):
        port = PortFactice(self.reponses(ok_cles="ok cles (redemarrer pour les appliquer)"))
        with self.assertRaises(ca.ErreurCles) as cm:
            self.charger(port)
        self.assertIn("inattendue", str(cm.exception))
        self.assertEqual(port.ecrit, ["mesh\r\n", self.cles + "\r\n"])

    def test_redemarrage_non_confirme_avertit(self):
        port = PortFactice(self.reponses(fin=("redemarre",)))  # jamais de ligne `redemarrage`
        self.charger(port, attente=0.3)
        self.assertEqual(port.ecrit[-1], "redemarre\r\n")
        self.assertTrue(self.capture[-1].startswith("avertissement"))
        self.assertNotIn("pont redemarre avec les nouvelles cles", self.capture)

    def test_port_qui_disparait_avant_la_confirmation_avertit(self):
        port = PortQuiSeFerme(self.reponses(fin=("redemarre",)))
        self.charger(port)  # pas d'exception : la carte a peut-etre bien redemarre
        self.assertTrue(self.capture[-1].startswith("avertissement"))


class TestValidationLampes(unittest.TestCase):
    def setUp(self):
        self.dossier = tempfile.mkdtemp()

    def test_refuse_mac_nulle(self):
        chemin = os.path.join(self.dossier, "amaran.db")
        con = sqlite3.connect(chemin)
        con.execute("create table mesh (uuid text, net_key varchar(32), app_key varchar(32), state integer)")
        con.execute("create table fixtures (uuid text, mac_address text, name text, node_address integer, device_key text)")
        con.execute("insert into mesh values (?, ?, ?, 3)", ("m0", NET.upper(), APP.upper()))
        con.execute("insert into fixtures values (?, ?, ?, ?, ?)", ("f1", None, "Lampe", 1, "00" * 16))
        con.commit()
        con.close()
        with self.assertRaises(ca.ErreurCles):
            ca.lire_reseau(chemin)

    def test_refuse_cle_blob(self):
        chemin = os.path.join(self.dossier, "amaran.db")
        con = sqlite3.connect(chemin)
        con.execute("create table mesh (uuid text, net_key varchar(32), app_key varchar(32), state integer)")
        con.execute("create table fixtures (uuid text, mac_address text, name text, node_address integer, device_key text)")
        con.execute("insert into mesh values (?, ?, ?, 3)", ("m0", bytes.fromhex(NET), APP.upper()))
        con.execute("insert into fixtures values (?, ?, ?, ?, ?)", ("f1", "70:3E:97:00:00:01", "Lampe", 1, "00" * 16))
        con.commit()
        con.close()
        with self.assertRaises(ca.ErreurCles):
            ca.lire_reseau(chemin)

    def test_refuse_nom_avec_retour_ligne(self):
        chemin = os.path.join(self.dossier, "amaran.db")
        con = sqlite3.connect(chemin)
        con.execute("create table mesh (uuid text, net_key varchar(32), app_key varchar(32), state integer)")
        con.execute("create table fixtures (uuid text, mac_address text, name text, node_address integer, device_key text)")
        con.execute("insert into mesh values (?, ?, ?, 3)", ("m0", NET.upper(), APP.upper()))
        con.execute("insert into fixtures values (?, ?, ?, ?, ?)", ("f1", "70:3E:97:00:00:01", "a\r\nredemarre", 1, "00" * 16))
        con.commit()
        con.close()
        with self.assertRaises(ca.ErreurCles):
            ca.lire_reseau(chemin)


class TestErreurs(unittest.TestCase):
    def setUp(self):
        self.dossier = tempfile.mkdtemp()

    def test_port_inaccessible_rend_1(self):
        capture = []
        base = base_factice(self.dossier)
        code = ca.main(["--db", base, "--port", "/dev/amaran-port-inexistant"], sortie=capture.append)
        self.assertEqual(code, 1)
        self.assertTrue(capture[-1].startswith("erreur : "))


if __name__ == "__main__":
    unittest.main()
