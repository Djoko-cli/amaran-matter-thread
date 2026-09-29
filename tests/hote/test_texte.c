// Tests sur le Mac des outils de texte. Lancer : sh tests/hote/lancer.sh
#include <string.h>

#include "texte.h"
#include "unite.h"

static void test_hex(void) {
  uint8_t o[4];
  VERIFIE(texte_hex_vers_octets("00a1FF7e", o, 4) && o[0] == 0x00 && o[1] == 0xA1 && o[2] == 0xFF && o[3] == 0x7E,
          "hexa, casse mixte");
  VERIFIE(!texte_hex_vers_octets("00a1FF7", o, 4), "hexa trop court");
  VERIFIE(!texte_hex_vers_octets("00a1FF7e0", o, 4), "hexa trop long");
  VERIFIE(!texte_hex_vers_octets("00g1FF7e", o, 4), "caractere non hexa");
  char s[9];
  const uint8_t valeurs[4] = {0x00, 0xA1, 0xFF, 0x7E};
  texte_octets_vers_hex(valeurs, 4, s);
  VERIFIE(strcmp(s, "00A1FF7E") == 0, "octets vers hexa (%s)", s);
}

static void test_mac(void) {
  uint8_t m[6];
  VERIFIE(texte_lire_mac("70:3E:97:12:34:ab", m) && m[0] == 0x70 && m[3] == 0x12 && m[5] == 0xAB, "MAC");
  VERIFIE(!texte_lire_mac("70:3E:97:12:34", m), "MAC courte");
  VERIFIE(!texte_lire_mac("70-3E-97-12-34-AB", m), "MAC mal separee");
  VERIFIE(!texte_lire_mac("70:3E:97:12:34:AB:00", m), "MAC longue");
}

static void test_nombre(void) {
  uint32_t v = 0;
  VERIFIE(texte_lire_nombre("42", &v) && v == 42, "decimal");
  VERIFIE(texte_lire_nombre("0x2A", &v) && v == 42, "hexa");
  VERIFIE(texte_lire_nombre("0X7f00", &v) && v == 0x7F00, "hexa, X majuscule");
  VERIFIE(texte_lire_nombre("4294967295", &v) && v == 4294967295u, "maximum");
  VERIFIE(!texte_lire_nombre("4294967296", &v), "debordement decimal");
  VERIFIE(!texte_lire_nombre("0x100000000", &v), "debordement hexa");
  VERIFIE(!texte_lire_nombre("", &v), "vide");
  VERIFIE(!texte_lire_nombre("0x", &v), "0x seul");
  VERIFIE(!texte_lire_nombre("12a", &v), "caractere parasite");
  VERIFIE(!texte_lire_nombre("-1", &v), "negatif");
}

int main(void) {
  test_hex();
  test_mac();
  test_nombre();
  return bilan("texte");
}
