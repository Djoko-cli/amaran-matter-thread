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

  // La capacite pile : 16 lampes valides, et relues telles quelles depuis le format NVS.
  liste_t pleine;
  memset(&pleine, 0, sizeof(pleine));
  pleine.n = LISTE_CAPACITE;
  for (int k = 0; k < LISTE_CAPACITE; k++) pleine.lampes[k] = lampe((uint16_t)(2 + 2 * k), (uint8_t)(k + 1), "Lampe");
  VERIFIE(liste_valider(&pleine, &fautive) == LISTE_OK, "%d lampes : la capacite pile", LISTE_CAPACITE);
  uint8_t tampon[sizeof(liste_entete_t) + LISTE_CAPACITE * sizeof(liste_lampe_t)];
  liste_vers_nvs(&pleine, tampon);
  liste_t relue;
  VERIFIE(liste_depuis_nvs(&relue, tampon, liste_taille_nvs(&pleine)) && relue.n == LISTE_CAPACITE,
          "%d lampes relues depuis le format NVS", LISTE_CAPACITE);

  const uint16_t mauvaises[] = {0x0000, 0x8000, 0xC000, LISTE_RESERVEE_MIN, LISTE_RESERVEE_MAX};
  for (unsigned k = 0; k < sizeof(mauvaises) / sizeof(mauvaises[0]); k++) {
    l = deux_lampes();
    l.lampes[1].adresse = mauvaises[k];
    VERIFIE(liste_valider(&l, &fautive) == LISTE_ADRESSE_INVALIDE && fautive == 1, "adresse 0x%04x refusee",
            (unsigned)mauvaises[k]);
  }
  const uint16_t bonnes[] = {0x0001, 0x7EFF, 0x7F80, 0x7FFF};  // bornes de l'unicast, autour de nos adresses
  for (unsigned k = 0; k < sizeof(bonnes) / sizeof(bonnes[0]); k++) {
    l = deux_lampes();
    l.lampes[1].adresse = bonnes[k];
    VERIFIE(liste_valider(&l, &fautive) == LISTE_OK, "adresse 0x%04x acceptee", (unsigned)bonnes[k]);
  }

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
  strcpy(l.lampes[0].nom, "a\x7f");
  VERIFIE(liste_valider(&l, &fautive) == LISTE_NOM_INVALIDE, "nom avec DEL (0x7F)");

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
  nouvelle.lampes[0] = lampe(0x0008, 0x02, "Lampe B renommee");  // B : autre adresse, et place 2 -> 1
  nouvelle.lampes[0].endpoint = 77;  // ce que dit le chargement ne compte pas
  nouvelle.lampes[1] = lampe(0x0006, 0x03, "Lampe C");  // nouvelle
  nouvelle.lampes[1].endpoint = 99;                       // le chargement ne lui donne rien
  nouvelle.lampes[1].drapeaux = LISTE_VUE | LISTE_MASQUEE;
  liste_fusionner(&nouvelle, &actuelle);

  VERIFIE(nouvelle.lampes[0].endpoint == 3 && nouvelle.lampes[0].drapeaux == (LISTE_VUE | LISTE_MASQUEE),
          "B, changee de place, garde EP3 et son masquage");
  VERIFIE(nouvelle.lampes[0].adresse == 0x0008 && !strcmp(nouvelle.lampes[0].nom, "Lampe B renommee"),
          "B prend sa nouvelle adresse et son nouveau nom");
  VERIFIE(nouvelle.lampes[1].endpoint == 0 && nouvelle.lampes[1].drapeaux == 0, "C : sans numero, jamais vue");
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

  liste_lampe_t c = lampe(0x0012, 0x12, "Masquee avant d'etre vue");
  liste_masquer(&c);
  liste_marquer_vue(&c);  // elle repond ensuite
  VERIFIE(!liste_exposee(&c), "masquee, meme si elle repond : pas exposee");
}

static void test_nvs_aller_retour(void) {
  liste_t l = deux_lampes();
  l.lampes[0].endpoint = 2;
  l.lampes[0].drapeaux = LISTE_VUE | LISTE_MASQUEE;
  l.lampes[1].endpoint = 3;
  l.lampes[1].drapeaux = LISTE_VUE;
  uint8_t tampon[sizeof(liste_entete_t) + LISTE_CAPACITE * sizeof(liste_lampe_t)];
  const uint32_t n = liste_taille_nvs(&l);
  VERIFIE(n == sizeof(liste_entete_t) + 2 * sizeof(liste_lampe_v2_t), "taille : en-tete et deux lampes");
  liste_vers_nvs(&l, tampon);
  liste_t relue;
  VERIFIE(liste_depuis_nvs(&relue, tampon, n) && relue.n == 2 &&
              !memcmp(&relue.lampes[0], &l.lampes[0], sizeof(liste_lampe_t)) &&
              !memcmp(&relue.lampes[1], &l.lampes[1], sizeof(liste_lampe_t)),
          "aller-retour exact, masquage compris");

  VERIFIE(!liste_depuis_nvs(&relue, tampon, n - 1) && relue.n == 0, "tronquee : refusee, liste vide");
  VERIFIE(!liste_depuis_nvs(&relue, tampon, 3), "plus courte que l'en-tete");
  uint8_t autre[sizeof(tampon)];
  memcpy(autre, tampon, n);
  autre[0] = 3;  // version future
  VERIFIE(!liste_depuis_nvs(&relue, autre, n), "autre version refusee");
  memcpy(autre, tampon, n);
  autre[2] = (uint8_t)(sizeof(liste_lampe_v2_t) + 4);  // lampe d'une autre taille
  VERIFIE(!liste_depuis_nvs(&relue, autre, n), "autre taille de lampe refusee");
  // Plus longue que la capacite, avec une longueur coherente : seul le plafond la refuse.
  uint8_t trop[sizeof(liste_entete_t) + (LISTE_CAPACITE + 1) * sizeof(liste_lampe_v2_t)];
  memset(trop, 0, sizeof(trop));
  const liste_entete_t e = {LISTE_VERSION, LISTE_CAPACITE + 1, (uint8_t)sizeof(liste_lampe_v2_t), 0};
  memcpy(trop, &e, sizeof(e));
  VERIFIE(!liste_depuis_nvs(&relue, trop, sizeof(trop)) && relue.n == 0, "plus longue que la capacite refusee");

  // Une liste non validee trop longue n'ecrit jamais au-dela de la capacite.
  liste_t longue;
  memset(&longue, 0, sizeof(longue));
  longue.n = LISTE_CAPACITE + 1;
  VERIFIE(liste_taille_nvs(&longue) == sizeof(liste_entete_t) + LISTE_CAPACITE * sizeof(liste_lampe_v2_t),
          "taille bornee a la capacite");
  liste_vers_nvs(&longue, tampon);
  VERIFIE(tampon[1] == LISTE_CAPACITE, "en-tete borne a la capacite");

  // Un nom sans fin relu de la NVS est termine.
  l.n = 1;
  memset(l.lampes[0].nom, 'z', LISTE_NOM_MAX);
  liste_vers_nvs(&l, tampon);
  VERIFIE(liste_depuis_nvs(&relue, tampon, liste_taille_nvs(&l)) && strlen(relue.lampes[0].nom) == LISTE_NOM_MAX - 1,
          "nom sans fin relu : termine");

  l.n = 0;
  liste_vers_nvs(&l, tampon);
  VERIFIE(liste_depuis_nvs(&relue, tampon, liste_taille_nvs(&l)) && relue.n == 0, "liste vide relue");
}

// Le format 2 (plan 3a) se relit : memes lampes, versions inconnues.
static void test_nvs_format2(void) {
  liste_lampe_v2_t v2[2];
  memset(v2, 0, sizeof(v2));
  const liste_t l = deux_lampes();
  for (int i = 0; i < 2; i++) {
    v2[i].adresse = l.lampes[i].adresse;
    memcpy(v2[i].mac, l.lampes[i].mac, 6);
    memcpy(v2[i].nom, l.lampes[i].nom, LISTE_NOM_MAX);
    v2[i].code = l.lampes[i].code;
    v2[i].endpoint = (uint16_t)(2 + i);
    v2[i].drapeaux = LISTE_VUE;
  }
  uint8_t tampon[sizeof(liste_entete_t) + sizeof(v2)];
  const liste_entete_t e = {2, 2, (uint8_t)sizeof(liste_lampe_v2_t), 0};
  memcpy(tampon, &e, sizeof(e));
  memcpy(tampon + sizeof(e), v2, sizeof(v2));
  liste_t relue;
  VERIFIE(liste_depuis_nvs(&relue, tampon, sizeof(tampon)) && relue.n == 2, "format 2 relu");
  int fautive = 0;
  VERIFIE(liste_valider(&relue, &fautive) == LISTE_OK, "format 2 relu : liste valide");
  VERIFIE(relue.lampes[1].adresse == 0x0004 && !memcmp(relue.lampes[1].mac, l.lampes[1].mac, 6) &&
              !strcmp(relue.lampes[1].nom, "Lampe B") && relue.lampes[1].code == CATALOGUE_CODE_COB_60D &&
              relue.lampes[1].endpoint == 3 && relue.lampes[1].drapeaux == LISTE_VUE,
          "format 2 : champs gardes");
  VERIFIE(!relue.lampes[0].logiciel[0] && !relue.lampes[0].ble[0], "format 2 : versions inconnues");
  VERIFIE(!liste_depuis_nvs(&relue, tampon, sizeof(tampon) - 1), "format 2 tronque refuse");
  tampon[2] = (uint8_t)sizeof(liste_lampe_t);
  VERIFIE(!liste_depuis_nvs(&relue, tampon, sizeof(tampon)), "format 2 avec une taille de format 3 refuse");

  // Les versions ne vont jamais dans la cle "lampes" : un firmware d'avant le plan
  // 3b-3 la relit telle quelle.
  liste_t l2 = deux_lampes();
  strcpy(l2.lampes[0].logiciel, "1.4");
  strcpy(l2.lampes[0].ble, "1.69");
  uint8_t t2[sizeof(liste_entete_t) + 2 * sizeof(liste_lampe_v2_t)];
  VERIFIE(liste_taille_nvs(&l2) == sizeof(t2), "cle lampes : 48 octets par lampe");
  liste_vers_nvs(&l2, t2);
  VERIFIE(t2[0] == 2 && t2[2] == 48, "en-tete du format 2");
  VERIFIE(liste_depuis_nvs(&relue, t2, sizeof(t2)) && !relue.lampes[0].logiciel[0], "versions absentes de la cle lampes");
}

static void test_nvs_logiciels(void) {
  liste_t l = deux_lampes();
  strcpy(l.lampes[0].logiciel, "1.4");
  strcpy(l.lampes[0].ble, "1.69");
  strcpy(l.lampes[1].logiciel, "2.0");
  uint8_t t[sizeof(liste_entete_t) + LISTE_CAPACITE * sizeof(liste_logiciel_nvs_t)];
  const uint32_t n = liste_logiciels_taille_nvs(&l);
  VERIFIE(n == sizeof(liste_entete_t) + 2 * 22, "deux lampes connues : deux entrees");
  liste_logiciels_vers_nvs(&l, t);
  VERIFIE(t[0] == LISTE_LOGICIELS_VERSION && t[1] == 2 && t[2] == 22, "en-tete des logiciels");

  // Relue sur une liste dans un autre ordre (rechargee par un ancien firmware) : par MAC.
  liste_t autre = deux_lampes();
  const liste_lampe_t x = autre.lampes[0];
  autre.lampes[0] = autre.lampes[1];
  autre.lampes[1] = x;
  VERIFIE(liste_logiciels_depuis_nvs(&autre, t, n), "logiciels relus");
  VERIFIE(!strcmp(autre.lampes[1].logiciel, "1.4") && !strcmp(autre.lampes[1].ble, "1.69") &&
              !strcmp(autre.lampes[0].logiciel, "2.0") && !autre.lampes[0].ble[0],
          "chaque lampe recoit les versions de sa MAC");

  // Une MAC absente de la liste : ignoree ; une lampe sans entree : versions inconnues.
  liste_t une = deux_lampes();
  une.n = 1;
  une.lampes[0].mac[5] = 0x77;
  VERIFIE(liste_logiciels_depuis_nvs(&une, t, n) && !une.lampes[0].logiciel[0], "MAC absente : rien");

  // Entree mal formee : ignoree ; format faux : refuse, rien ne change.
  liste_logiciel_nvs_t abimee;
  memcpy(&abimee, t + sizeof(liste_entete_t), sizeof(abimee));
  strcpy(abimee.logiciel, "1.x");
  memcpy(t + sizeof(liste_entete_t), &abimee, sizeof(abimee));
  liste_t l3 = deux_lampes();
  VERIFIE(liste_logiciels_depuis_nvs(&l3, t, n) && !l3.lampes[0].logiciel[0] && !strcmp(l3.lampes[1].logiciel, "2.0"),
          "entree mal formee ignoree, les autres relues");
  VERIFIE(!liste_logiciels_depuis_nvs(&l3, t, n - 1), "tronquee : refusee");
  t[0] = 2;
  VERIFIE(!liste_logiciels_depuis_nvs(&l3, t, n), "autre version : refusee");

  // Aucune version connue : un en-tete seul.
  liste_t vide = deux_lampes();
  VERIFIE(liste_logiciels_taille_nvs(&vide) == sizeof(liste_entete_t), "aucune version : en-tete seul");
  liste_logiciels_vers_nvs(&vide, t);
  VERIFIE(t[1] == 0 && liste_logiciels_depuis_nvs(&vide, t, sizeof(liste_entete_t)), "en-tete seul relu");
}

static void test_logiciel(void) {
  const char *bons[] = {"", "1.4", "1.69", "123.456", "0.0"};
  for (unsigned i = 0; i < sizeof(bons) / sizeof(bons[0]); i++) VERIFIE(liste_logiciel_valide(bons[i]), "%s", bons[i]);
  const char *mauvais[] = {"1", "1.", ".4", "1.4.2", "1234.5", "1.2345", "a.b", "1,4", " 1.4", "v1.4"};
  for (unsigned i = 0; i < sizeof(mauvais) / sizeof(mauvais[0]); i++) {
    VERIFIE(!liste_logiciel_valide(mauvais[i]), "%s", mauvais[i]);
  }

  char a[LISTE_LOGICIEL_MAX] = "x", b[LISTE_LOGICIEL_MAX] = "y";
  VERIFIE(liste_lire_jeton_logiciel("v1.4/1.69", a, b) == 1 && !strcmp(a, "1.4") && !strcmp(b, "1.69"),
          "jeton complet");
  VERIFIE(liste_lire_jeton_logiciel("v1.4", a, b) == 1 && !strcmp(a, "1.4") && !b[0], "jeton sans ble");
  strcpy(a, "x");
  strcpy(b, "y");
  const char *pas_jeton[] = {"Lampe", "v", "va", "vx1.4", "V1.4", "1.4", ""};
  for (unsigned i = 0; i < sizeof(pas_jeton) / sizeof(pas_jeton[0]); i++) {
    VERIFIE(liste_lire_jeton_logiciel(pas_jeton[i], a, b) == 0, "%s", pas_jeton[i]);
  }
  const char *abimes[] = {"v1", "v2", "v1.4/", "v1.4/1", "v1.4/1.69/2", "v1.4x", "v12345.6", "v1.4/1234567.8", "v1/1.6",
                          "v1.4 bureau"};
  for (unsigned i = 0; i < sizeof(abimes) / sizeof(abimes[0]); i++) {
    VERIFIE(liste_lire_jeton_logiciel(abimes[i], a, b) == -1, "%s", abimes[i]);
  }
  VERIFIE(!strcmp(a, "x") && !strcmp(b, "y"), "pas un jeton, ou jeton abime : rien n'est ecrit");

  // Regle des mots de `mesh lampe` : un jeton n'est lu que suivi d'un nom, et sans espace.
  {
    char *m1[] = {"v1.4/1.69", "Lampe"};
    char lo[LISTE_LOGICIEL_MAX] = "", bl[LISTE_LOGICIEL_MAX] = "";
    VERIFIE(liste_lire_logiciel_argv(2, m1, 0, lo, bl) == 1 && !strcmp(lo, "1.4") && !strcmp(bl, "1.69"),
            "jeton puis nom");
    char *m2[] = {"v2"};
    lo[0] = bl[0] = '\0';
    VERIFIE(liste_lire_logiciel_argv(1, m2, 0, lo, bl) == 0 && !lo[0], "\"v2\" seul : le nom");
    char *m3[] = {"v1.4"};
    VERIFIE(liste_lire_logiciel_argv(1, m3, 0, lo, bl) == 0 && !lo[0], "\"v1.4\" seul : le nom, pas un jeton");
    char *m4[] = {"v2", "bureau"};
    VERIFIE(liste_lire_logiciel_argv(2, m4, 0, lo, bl) == 0 && !lo[0], "v2 bureau : le nom (jeton mal forme)");
    char *m5[] = {"v1.4 bureau"};
    VERIFIE(liste_lire_logiciel_argv(1, m5, 0, lo, bl) == 0 && !lo[0], "\"v1.4 bureau\" entre guillemets : le nom");
    char *m6[] = {"v1.4 bureau", "x"};
    VERIFIE(liste_lire_logiciel_argv(2, m6, 0, lo, bl) == 0 && !lo[0], "mot avec espace suivi d'un mot : le nom");
    char *m7[] = {"Lampe", "2"};
    VERIFIE(liste_lire_logiciel_argv(2, m7, 0, lo, bl) == 0, "nom ordinaire");
  }

  liste_t l = deux_lampes();
  int fautive = 0;
  strcpy(l.lampes[1].logiciel, "1.4");
  strcpy(l.lampes[1].ble, "1.69");
  VERIFIE(liste_valider(&l, &fautive) == LISTE_OK, "versions bien formees : valide");
  strcpy(l.lampes[1].ble, "1.6x");
  VERIFIE(liste_valider(&l, &fautive) == LISTE_LOGICIEL_INVALIDE && fautive == 1, "ble mal forme : refuse");
  l.lampes[1].logiciel[0] = '\0';
  strcpy(l.lampes[1].ble, "1.69");
  VERIFIE(liste_valider(&l, &fautive) == LISTE_LOGICIEL_INVALIDE, "ble sans logiciel : refuse");
  memset(l.lampes[1].logiciel, '1', LISTE_LOGICIEL_MAX);
  VERIFIE(liste_valider(&l, &fautive) == LISTE_LOGICIEL_INVALIDE, "logiciel sans fin : refuse");

  char t[32];
  liste_lampe_t x = lampe(0x0002, 1, "x");
  liste_texte_logiciel(&x, t, sizeof(t));
  VERIFIE(!t[0], "inconnu : texte vide");
  strcpy(x.logiciel, "1.4");
  liste_texte_logiciel(&x, t, sizeof(t));
  VERIFIE(!strcmp(t, "1.4"), "logiciel seul");
  strcpy(x.ble, "1.69");
  liste_texte_logiciel(&x, t, sizeof(t));
  VERIFIE(!strcmp(t, "1.4 (BLE 1.69)"), "logiciel et ble");
  strcpy(x.logiciel, "123.456");
  strcpy(x.ble, "789.123");
  liste_texte_logiciel(&x, t, sizeof(t));
  VERIFIE(!strcmp(t, "123.456 (BLE 789.123)") && strlen(t) < 64, "le plus long tient dans SoftwareVersionString");
}

static void test_fiche(void) {
  liste_lampe_t a = lampe(0x0002, 0x01, "Lampe A");
  liste_fiche_t f;
  liste_fiche(&a, &f);
  VERIFIE(!strcmp(f.produit, "amaran COB 60d") && !strcmp(f.serie, "AMARAN-703E97000001") && !f.logiciel[0],
          "fiche d'une 60d sans version");
  VERIFIE(f.logiciel_nombre == 0, "sans version : SoftwareVersion inconnue");
  strcpy(a.logiciel, "1.4");
  strcpy(a.ble, "1.69");
  a.code = 12345;
  liste_fiche(&a, &f);
  VERIFIE(!strcmp(f.produit, "amaran 12345") && !strcmp(f.logiciel, "1.4 (BLE 1.69)"), "modele non catalogue, version");
  VERIFIE(f.logiciel_nombre == 1004, "SoftwareVersion de 1.4 : 1004");
  strcpy(a.logiciel, "123.456");
  liste_fiche(&a, &f);
  VERIFIE(f.logiciel_nombre == 123456, "SoftwareVersion de 123.456 : 123456");
  a.code = 4294967295u;
  liste_fiche(&a, &f);
  VERIFIE(!strcmp(f.produit, "amaran 4294967295"), "plus long modele non catalogue");
  VERIFIE(!strcmp(LISTE_FABRICANT, "Aputure"), "fabricant");

  liste_t l = deux_lampes();
  const liste_lampe_t *p[2] = {&l.lampes[0], &l.lampes[1]};
  const liste_lampe_t *q[2] = {&l.lampes[1], &l.lampes[0]};
  const uint16_t e[2] = {2, 3}, e_inv[2] = {3, 2};
  const uint32_t h = liste_empreinte_fiches(p, e, 2);
  VERIFIE(h == liste_empreinte_fiches(p, e, 2), "empreinte stable");
  VERIFIE(h == liste_empreinte_fiches(q, e_inv, 2), "independante de l'ordre de chargement");
  VERIFIE(h != liste_empreinte_fiches(q, e, 2), "change si les numeros changent de lampe");
  VERIFIE(h != liste_empreinte_fiches(p, e, 1), "change si une lampe disparait");
  VERIFIE(liste_empreinte_fiches(p, e, 0) != h, "aucune lampe : autre empreinte");
  liste_t m = l;
  const liste_lampe_t *pm[2] = {&m.lampes[0], &m.lampes[1]};
  strcpy(m.lampes[1].nom, "Lampe C");
  VERIFIE(liste_empreinte_fiches(pm, e, 2) != h, "change avec le nom");
  m = l;
  strcpy(m.lampes[1].logiciel, "1.4");
  VERIFIE(liste_empreinte_fiches(pm, e, 2) != h, "change avec la version");
  m = l;
  m.lampes[1].mac[0] = 0x02;
  VERIFIE(liste_empreinte_fiches(pm, e, 2) != h, "change avec le numero de serie");
  m = l;
  m.lampes[1].code = 1;
  VERIFIE(liste_empreinte_fiches(pm, e, 2) != h, "change avec le modele");
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
  VERIFIE(!l.lampes[0].logiciel[0] && !l.lampes[0].ble[0] && !l.lampes[1].logiciel[0], "versions inconnues");

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
  VERIFIE(!strcmp(catalogue_capacites_texte(CATALOGUE_INTENSITE | CATALOGUE_CCT | CATALOGUE_COULEUR),
                  "intensite+cct+couleur"),
          "texte : intensite+cct+couleur");
  VERIFIE(!strcmp(catalogue_capacites_texte(0), "aucune"), "texte : aucune");
  VERIFIE(LISTE_CODE_V1 == CATALOGUE_CODE_COB_60D && catalogue_connu(LISTE_CODE_V1),
          "les lampes converties du plan 2 sont des 60d cataloguees");
  // Parcours du catalogue (protocole JSON) : chaque modele une fois, puis le repli.
  VERIFIE(catalogue_nombre() == 1 && catalogue_modele(0) == m, "un modele : la 60d");
  VERIFIE(catalogue_modele(catalogue_nombre()) == r && catalogue_repli() == r, "au-dela : le repli");
}

int main(void) {
  test_valider();
  test_chercher_mac();
  test_fusionner();
  test_exposition();
  test_nvs_aller_retour();
  test_nvs_format2();
  test_nvs_logiciels();
  test_logiciel();
  test_fiche();
  test_migration_v1();
  test_catalogue();
  return bilan("liste");
}
