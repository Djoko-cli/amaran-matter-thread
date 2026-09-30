// Tests sur le Mac du diagnostic du Bluetooth Mesh (spec 7.3).
// Lancer : sh tests/hote/lancer.sh
#include <string.h>

#include "diagnostic.h"
#include "unite.h"

static void test_causes(void) {
  const diagnostic_ecarts_t calme = {0, 0, 0, 0}, sain = {40, 40, 0, 12}, etranger = {30, 0, 0, 0},
                            iv_faux = {30, 30, 30, 0}, melange = {30, 30, 5, 3};
  VERIFIE(diagnostic_mesh(false, false, &sain) == DIAG_CLES_ABSENTES, "cles absentes d'abord");
  VERIFIE(diagnostic_mesh(true, false, &sain) == DIAG_PAS_ENTRE, "pas entre dans le reseau");
  VERIFIE(diagnostic_mesh(true, true, &sain) == DIAG_OK, "trafic sain");
  VERIFIE(diagnostic_mesh(true, true, &calme) == DIAG_OK, "aucune annonce : rien a conclure");
  VERIFIE(diagnostic_mesh(true, true, &etranger) == DIAG_CLES_PERIMEES, "seulement d'autres NID : cles perimees");
  VERIFIE(diagnostic_mesh(true, true, &iv_faux) == DIAG_IV_FAUX, "NetMIC faux sans dechiffrement : IV faux");
  VERIFIE(diagnostic_mesh(true, true, &melange) == DIAG_OK, "quelques NetMIC faux mais du dechiffre : ok");
  VERIFIE(strstr(diagnostic_texte(DIAG_IV_FAUX), "mesh iv") != NULL, "le texte donne le remede");
  VERIFIE(strstr(diagnostic_texte(DIAG_CLES_ABSENTES), "cles_amaran.py") != NULL, "remede des cles absentes");
}

static void test_suivi(void) {
  diagnostic_suivi_t s = {0};
  diagnostic_ecarts_t c = {0, 0, 0, 0};
  // Demarrage normal : pas encore entre, mais pas d'alerte avant 2 min.
  VERIFIE(!diagnostic_suivre(&s, true, false, &c, 0) && s.etat == DIAG_OK, "pas de rouge au demarrage");
  VERIFIE(!diagnostic_suivre(&s, true, true, &c, 3000) && s.etat == DIAG_OK, "entre en 3 s : rien a dire");
  c = (diagnostic_ecarts_t){100, 100, 0, 30};
  VERIFIE(!diagnostic_suivre(&s, true, true, &c, 120000) && s.etat == DIAG_OK, "fenetre saine");
  // Reseau recree dans amaran Desktop : que des NID etrangers pendant 2 min.
  c.annonces += 50;
  VERIFIE(!diagnostic_suivre(&s, true, true, &c, 200000), "rien avant la fin de la fenetre");
  VERIFIE(diagnostic_suivre(&s, true, true, &c, 240000) && s.etat == DIAG_CLES_PERIMEES, "cles perimees");
  // IV Index faux : notre NID, NetMIC faux, rien de dechiffre.
  c.annonces += 20;
  c.nid_reconnu += 20;
  c.netmic_faux += 20;
  VERIFIE(diagnostic_suivre(&s, true, true, &c, 360000) && s.etat == DIAG_IV_FAUX, "IV faux");
  c.annonces += 20;
  c.nid_reconnu += 20;
  c.acces_dechiffres += 8;
  VERIFIE(diagnostic_suivre(&s, true, true, &c, 480000) && s.etat == DIAG_OK, "retour a la normale");
  // Cles oubliees : tout de suite.
  VERIFIE(diagnostic_suivre(&s, false, false, &c, 481000) && s.etat == DIAG_CLES_ABSENTES, "cles absentes aussitot");
  // Cles rechargees, carte redemarree : pas entre au bout d'une fenetre.
  diagnostic_suivi_t r = {0};
  VERIFIE(!diagnostic_suivre(&r, true, false, &c, 0), "nouveau demarrage");
  VERIFIE(diagnostic_suivre(&r, true, false, &c, 120000) && r.etat == DIAG_PAS_ENTRE, "pas entre en 2 min");
  VERIFIE(diagnostic_suivre(&r, true, true, &c, 121000) && r.etat == DIAG_OK, "entre : l'alerte tombe aussitot");
  // Horloge de 32 bits qui deborde : la fenetre se mesure en ecart non signe.
  diagnostic_suivi_t w = {0};
  VERIFIE(!diagnostic_suivre(&w, true, false, &c, 0xFFFFF000u), "depart pres du debordement");
  VERIFIE(!diagnostic_suivre(&w, true, false, &c, 0x00001000u), "8 s plus tard : pas encore");
  VERIFIE(diagnostic_suivre(&w, true, false, &c, 0xFFFFF000u + DIAGNOSTIC_FENETRE_MS) && w.etat == DIAG_PAS_ENTRE,
          "fenetre finie de l'autre cote de 0");
}

int main(void) {
  test_causes();
  test_suivi();
  return bilan("diagnostic");
}
