// Petits outils de texte purs (hexa, MAC, nombres), testes sur le Mac.
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// Exactement 2*n chiffres hexa (casse libre) -> n octets.
bool texte_hex_vers_octets(const char *hex, uint8_t *sortie, size_t n);
// n octets -> 2*n chiffres hexa majuscules suivis d'un NUL (sortie : 2*n+1).
void texte_octets_vers_hex(const uint8_t *octets, size_t n, char *sortie);
// "70:3E:97:12:34:AB" -> 6 octets.
bool texte_lire_mac(const char *texte, uint8_t mac[6]);
// Decimal ou 0x... -> uint32 (refuse vide, signe, parasites, debordement).
bool texte_lire_nombre(const char *texte, uint32_t *sortie);
