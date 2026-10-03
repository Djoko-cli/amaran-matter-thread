// Tests sur le Mac de la liste des lampes et du catalogue des modeles (plan 3a).
// Lancer : sh tests/hote/lancer.sh
#include <string.h>

#include "catalogue.h"
#include "liste.h"
#include "unite.h"

static liste_lampe_t lampe(uint16_t adresse, uint8_t dernier_octet, const char *nom) {
  liste_lampe_t a;
  memset(&a, 0, sizeof(a));
  a.adresse = adresse;
  const uint8_t mac[6] = {0x70, 0x3E, 0x97, 0x00, 0x00, dernier_octet};
  memcpy(a.mac, mac, 6);
  strncpy(a.nom, nom, LISTE_NOM_MAX - 1);
  a.code = CATALOGUE_CODE_COB_60D;
  return a;
}

static liste_t deux_lampes(void) {
  liste_t l;
  memset(&l, 0, sizeof(l));
  l.n = 2;
  l.lampes[0] = lampe(0x0002, 0x01, "Lampe A");
  l.lampes[1] = lampe(0x0004, 0x02, "Lampe B");
  return l;
}

static void test_valider(void) {
  int fautive = 99;
  liste_t l = deux_lampes();
  VERIFIE(liste_valider(&l, &fautive) == LISTE_OK && fautive == -1, "deux lampes valides");

  l.n = LISTE_CAPACITE + 1;
  VERIFIE(liste_valider(&l, &fautive) == LISTE_TROP_LONGUE && fautive == -1, "au-dela de la capacite");

  const uint16_t mauvaises[] = {0x0000, 0x8000, 0xC000, LISTE_RESERVEE_MIN, LISTE_RESERVEE_MAX};
  for (unsigned k = 0; k < sizeof(mauvaises) / sizeof(mauvaises[0]); k++) {
    l = deux_lampes();
    l.lampes[1].adresse = mauvaises[k];
    VERIFIE(liste_valider(&l, &fautive) == LISTE_ADRESSE_INVALIDE && fautive == 1, "adresse 0x%04x refusee",
            (unsigned)mauvaises[k]);
  }
  l = deux_lampes();
  l.lampes[1].adresse = 0x7F80;  // juste apres nos adresses : une lampe peut l'avoir
  VERIFIE(liste_valider(&l, &fautive) == LISTE_OK, "0x7F80 acceptee");

  l = deux_lampes();
  l.lampes[1].adresse = 0x0002;
  VERIFIE(liste_valider(&l, &fautive) == LISTE_ADRESSE_EN_DOUBLE && fautive == 1, "adresse en double");

  l = deux_lampes();
  memset(l.lampes[0].mac, 0, 6);
  VERIFIE(liste_valider(&l, &fautive) == LISTE_MAC_NULLE && fautive == 0, "MAC nulle");

  l = deux_lampes();
  memcpy(l.lampes[1].mac, l.lampes[0].mac, 6);
  VERIFIE(liste_valider(&l, &fautive) == LISTE_MAC_EN_DOUBLE && fautive == 1, "MAC en double");

  l = deux_lampes();
  l.lampes[0].nom[0] = '\0';
  VERIFIE(liste_valider(&l, &fautive) == LISTE_NOM_INVALIDE && fautive == 0, "nom vide");

  l = deux_lampes();
  strcpy(l.lampes[0].nom, "a\r\nredemarre");
  VERIFIE(liste_valider(&l, &fautive) == LISTE_NOM_INVALIDE, "nom avec un retour a la ligne");

  l = deux_lampes();
  memset(l.lampes[0].nom, 'x', LISTE_NOM_MAX);  // aucun NUL
  VERIFIE(liste_valider(&l, &fautive) == LISTE_NOM_INVALIDE, "nom sans fin");

  l = deux_lampes();
  l.n = 0;
  VERIFIE(liste_valider(&l, &fautive) == LISTE_OK, "liste vide valide");
  VERIFIE(strcmp(liste_erreur_texte(LISTE_MAC_NULLE), "MAC nulle") == 0, "texte d'une erreur");
}

static void test_chercher_mac(void) {
  const liste_t l = deux_lampes();
  VERIFIE(liste_chercher_mac(&l, l.lampes[1].mac) == 1, "MAC trouvee");
  const uint8_t inconnue[6] = {1, 2, 3, 4, 5, 6};
  VERIFIE(liste_chercher_mac(&l, inconnue) == -1, "MAC inconnue");
}

// Une MAC connue garde son numero et ses drapeaux, quelle que soit sa place ; une
// nouvelle part de zero ; une absente disparait.
static void test_fusionner(void) {
  liste_t actuelle = deux_lampes();
  actuelle.lampes[0].endpoint = 2;
  actuelle.lampes[0].drapeaux = LISTE_VUE;
  actuelle.lampes[1].endpoint = 3;
  actuelle.lampes[1].drapeaux = LISTE_VUE | LISTE_MASQUEE;

  liste_t nouvelle;
  memset(&nouvelle, 0, sizeof(nouvelle));
  nouvelle.n = 2;
  nouvelle.lampes[0] = lampe(0x0006, 0x03, "Lampe C");  // nouvelle
  nouvelle.lampes[1] = lampe(0x0008, 0x02, "Lampe B renommee");  // B, autre adresse, autre place
  nouvelle.lampes[1].endpoint = 77;  // ce que dit le chargement ne compte pas
  nouvelle.lampes[1].drapeaux = 0;
  liste_fusionner(&nouvelle, &actuelle);

  VERIFIE(nouvelle.lampes[0].endpoint == 0 && nouvelle.lampes[0].drapeaux == 0, "C : sans numero, jamais vue");
  VERIFIE(nouvelle.lampes[1].endpoint == 3 && nouvelle.lampes[1].drapeaux == (LISTE_VUE | LISTE_MASQUEE),
          "B garde EP3 et son masquage");
  VERIFIE(nouvelle.lampes[1].adresse == 0x0008 && !strcmp(nouvelle.lampes[1].nom, "Lampe B renommee"),
          "B prend sa nouvelle adresse et son nouveau nom");
  VERIFIE(liste_chercher_mac(&nouvelle, actuelle.lampes[0].mac) == -1, "A a disparu");
}

static void test_exposition(void) {
  liste_lampe_t a = lampe(0x0002, 0x01, "Lampe A");
  VERIFIE(!liste_exposee(&a) && liste_a_exposer_a_l_ecoute(&a), "jamais vue : pas exposee, a exposer a l'ecoute");
  liste_marquer_vue(&a);
  VERIFIE(liste_exposee(&a) && !liste_a_exposer_a_l_ecoute(&a), "vue : exposee");
  liste_masquer(&a);
  VERIFIE(!liste_exposee(&a) && !liste_a_exposer_a_l_ecoute(&a), "masquee : ni exposee ni a exposer");
  liste_afficher(&a);
  VERIFIE(liste_exposee(&a) && a.drapeaux == LISTE_VUE, "afficher : de nouveau exposee");

  liste_lampe_t fictive = lampe(0x0010, 0x10, "Fictive");
  liste_masquer(&fictive);
  liste_afficher(&fictive);
  VERIFIE(liste_exposee(&fictive), "afficher expose meme une lampe jamais entendue");
}

static void test_nvs_aller_retour(void) {
  liste_t l = deux_lampes();
  l.lampes[1].endpoint = 3;
  l.lampes[1].drapeaux = LISTE_VUE;
  uint8_t tampon[sizeof(liste_entete_t) + LISTE_CAPACITE * sizeof(liste_lampe_t)];
  const uint32_t n = liste_taille_nvs(&l);
  VERIFIE(n == sizeof(liste_entete_t) + 2 * sizeof(liste_lampe_t), "taille : en-tete et deux lampes");
  liste_vers_nvs(&l, tampon);
  liste_t relue;
  VERIFIE(liste_depuis_nvs(&relue, tampon, n) && relue.n == 2 && !memcmp(&relue.lampes[1], &l.lampes[1],
                                                                           sizeof(liste_lampe_t)),
          "aller-retour exact");

  VERIFIE(!liste_depuis_nvs(&relue, tampon, n - 1) && relue.n == 0, "tronquee : refusee, liste vide");
  VERIFIE(!liste_depuis_nvs(&relue, tampon, 3), "plus courte que l'en-tete");
  uint8_t autre[sizeof(tampon)];
  memcpy(autre, tampon, n);
  autre[0] = 3;  // version future
  VERIFIE(!liste_depuis_nvs(&relue, autre, n), "autre version refusee");
  memcpy(autre, tampon, n);
  autre[2] = (uint8_t)(sizeof(liste_lampe_t) + 4);  // lampe d'une autre taille
  VERIFIE(!liste_depuis_nvs(&relue, autre, n), "autre taille de lampe refusee");
  memcpy(autre, tampon, n);
  autre[1] = LISTE_CAPACITE + 1;
  VERIFIE(!liste_depuis_nvs(&relue, autre, n), "plus longue que la capacite refusee");

  l.n = 0;
  liste_vers_nvs(&l, tampon);
  VERIFIE(liste_depuis_nvs(&relue, tampon, liste_taille_nvs(&l)) && relue.n == 0, "liste vide relue");
}

static void test_migration_v1(void) {
  liste_v1_t v1[2];
  memset(v1, 0, sizeof(v1));
  v1[0].adresse = 0x0002;
  v1[0].mac[5] = 0x01;
  strcpy(v1[0].nom, "amaran COB 60d #1");
  v1[1].adresse = 0x0004;
  v1[1].mac[5] = 0x02;
  memset(v1[1].nom, 'y', LISTE_NOM_MAX);  // nom sans NUL : tronque
  const bool lus[2] = {true, true};
  liste_t l;
  liste_migrer_v1(&l, v1, lus);
  VERIFIE(l.n == 2, "deux lampes");
  VERIFIE(l.lampes[0].endpoint == 2 && l.lampes[1].endpoint == 3, "EP2 et EP3 gardes");
  VERIFIE(l.lampes[0].drapeaux == LISTE_VUE && l.lampes[1].drapeaux == LISTE_VUE, "vues : leurs tuiles restent");
  VERIFIE(l.lampes[0].code == LISTE_CODE_V1 && l.lampes[1].code == LISTE_CODE_V1, "modele : la 60d");
  VERIFIE(!strcmp(l.lampes[0].nom, "amaran COB 60d #1") && l.lampes[0].adresse == 0x0002 &&
              l.lampes[0].mac[5] == 0x01,
          "nom, adresse et MAC repris");
  VERIFIE(strlen(l.lampes[1].nom) == LISTE_NOM_MAX - 1, "nom sans fin : tronque");

  memset(v1, 0, sizeof(v1));
  v1[1].adresse = 0x0004;
  v1[1].mac[5] = 0x02;
  strcpy(v1[1].nom, "B");
  liste_migrer_v1(&l, v1, lus);
  VERIFIE(l.n == 1 && l.lampes[0].endpoint == 3, "emplacement 1 libre : la lampe 2 garde EP3");

  const bool un_seul[2] = {true, false};
  v1[0] = v1[1];
  liste_migrer_v1(&l, v1, un_seul);
  VERIFIE(l.n == 1 && l.lampes[0].endpoint == 2, "emplacement non lu : ignore");
}

static void test_catalogue(void) {
  const catalogue_modele_t *m = catalogue_trouver(CATALOGUE_CODE_COB_60D);
  VERIFIE(m->code == 40065u && !strcmp(m->nom, "amaran COB 60d") && m->capacites == CATALOGUE_INTENSITE &&
              m->type == CATALOGUE_LAMPE_VARIABLE,
          "la 60d : intensite seule, lampe a intensite variable");
  VERIFIE(catalogue_connu(40065u), "60d connue");
  const catalogue_modele_t *r = catalogue_trouver(99999u);
  VERIFIE(r != NULL && r->capacites == CATALOGUE_INTENSITE && r->type == CATALOGUE_LAMPE_VARIABLE &&
              !strcmp(r->nom, "modele non catalogue"),
          "code inconnu : repli en intensite seule");
  VERIFIE(!catalogue_connu(99999u) && !catalogue_connu(0), "inconnu, et 0");
  VERIFIE(!strcmp(catalogue_capacites_texte(CATALOGUE_INTENSITE), "intensite"), "texte : intensite");
  VERIFIE(!strcmp(catalogue_capacites_texte(CATALOGUE_INTENSITE | CATALOGUE_CCT), "intensite+cct"),
          "texte : intensite+cct");
  VERIFIE(!strcmp(catalogue_capacites_texte(CATALOGUE_INTENSITE | CATALOGUE_COULEUR), "intensite+couleur"),
          "texte : intensite+couleur");
}

int main(void) {
  test_valider();
  test_chercher_mac();
  test_fusionner();
  test_exposition();
  test_nvs_aller_retour();
  test_migration_v1();
  test_catalogue();
  return bilan("liste");
}
