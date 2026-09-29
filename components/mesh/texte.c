#include "texte.h"

#include <string.h>

static int valeur_hexa(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}

bool texte_hex_vers_octets(const char *hex, uint8_t *sortie, size_t n) {
  if (!hex || strlen(hex) != 2 * n) return false;
  for (size_t i = 0; i < n; i++) {
    const int h = valeur_hexa(hex[2 * i]);
    const int l = valeur_hexa(hex[2 * i + 1]);
    if (h < 0 || l < 0) return false;
    sortie[i] = (uint8_t)((h << 4) | l);
  }
  return true;
}

void texte_octets_vers_hex(const uint8_t *octets, size_t n, char *sortie) {
  static const char chiffres[] = "0123456789ABCDEF";
  for (size_t i = 0; i < n; i++) {
    sortie[2 * i] = chiffres[octets[i] >> 4];
    sortie[2 * i + 1] = chiffres[octets[i] & 0x0F];
  }
  sortie[2 * n] = '\0';
}

bool texte_lire_mac(const char *texte, uint8_t mac[6]) {
  if (!texte || strlen(texte) != 17) return false;
  for (int i = 0; i < 6; i++) {
    if (i < 5 && texte[3 * i + 2] != ':') return false;
    const int h = valeur_hexa(texte[3 * i]);
    const int l = valeur_hexa(texte[3 * i + 1]);
    if (h < 0 || l < 0) return false;
    mac[i] = (uint8_t)((h << 4) | l);
  }
  return true;
}

bool texte_lire_nombre(const char *texte, uint32_t *sortie) {
  if (!texte || !*texte) return false;
  const char *p = texte;
  unsigned base = 10;
  if (p[0] == '0' && (p[1] == 'x' || p[1] == 'X')) {
    base = 16;
    p += 2;
    if (!*p) return false;
  }
  uint64_t v = 0;
  for (; *p; p++) {
    const int c = base == 16 ? valeur_hexa(*p) : ((*p >= '0' && *p <= '9') ? *p - '0' : -1);
    if (c < 0) return false;
    v = v * base + (unsigned)c;
    if (v > 0xFFFFFFFFu) return false;
  }
  *sortie = (uint32_t)v;
  return true;
}
