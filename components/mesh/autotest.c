// Autotest du dechiffrement avec les exemples chiffres de la specification
// Bluetooth Mesh (8.3.1, 8.3.22, 8.4.3), releves dans les tests unitaires de
// BlueZ (unit/test-mesh-crypto.c). Passe par les memes fonctions que le crochet.
#include <stdio.h>
#include <string.h>

#include "crypto.h"  // bt_mesh_k2, bt_mesh_k3, bt_mesh_app_id, bt_mesh_secure_beacon_key, bt_mesh_secure_beacon_auth

#include "crochet.h"
#include "crochet_tri.h"
#include "mesh_amaran.h"
#include "texte.h"

static int s_echecs;

static void verifie(bool ok, const char *quoi) {
  printf("  %s %s\n", ok ? "ok   " : "ECHEC", quoi);
  if (!ok) s_echecs++;
}

static void hexa(const char *h, uint8_t *sortie, size_t n) {
  if (!texte_hex_vers_octets(h, sortie, n)) memset(sortie, 0, n);
}

int mesh_autotest(void) {
  s_echecs = 0;
  uint8_t netkey[16], appkey[16], enc[16], privacy[16], attendu[32], pdu[32], nid = 0;
  hexa("7dd7364cd842ad18c17c2b820c84c3d6", netkey, 16);
  hexa("63964771734fbd76e3b40519d1d94a48", appkey, 16);

  const uint8_t p = 0x00;
  verifie(bt_mesh_k2(netkey, &p, 1, &nid, enc, privacy) == 0 && nid == 0x68, "k2 : NID 0x68");
  hexa("0953fa93e7caac9638f58820220a398e", attendu, 16);
  verifie(memcmp(enc, attendu, 16) == 0, "k2 : cle de chiffrement");
  hexa("8b84eedec100067d670971dd2aa700cf", attendu, 16);
  verifie(memcmp(privacy, attendu, 16) == 0, "k2 : cle d'obfuscation");

  // 8.3.1, message #1 : controle, IV 0x12345678, NetMIC de 64 bits.
  size_t n = 28;
  hexa("68eca487516765b5e5bfdacbaf6cb7fb6bff871f035444ce83a670df", pdu, n);
  bool ok = crochet_dechiffrer_reseau(enc, privacy, 0x12345678, pdu, &n) == 0;
  hexa("68800000011201fffd034b50057e400000010000", attendu, 20);
  verifie(ok && n == 20 && memcmp(pdu, attendu, 20) == 0, "8.3.1 : message reseau");

  // 8.3.22, message #22 : acces par AppKey (AID 0x26), IV 0x12345677, vers une
  // adresse virtuelle (le Label UUID entre dans le chiffrement).
  n = 26;
  hexa("e8d85caecef1e3ed31f3fdcf88a411135fea55df730b6b28e255", pdu, n);
  ok = crochet_dechiffrer_reseau(enc, privacy, 0x12345677, pdu, &n) == 0;
  hexa("e80307080b1234b529663871b904d431526316ca48a0", attendu, 22);
  verifie(ok && n == 22 && memcmp(pdu, attendu, 22) == 0, "8.3.22 : message reseau");
  uint8_t aid = 0;
  verifie(bt_mesh_app_id(appkey, &aid) == 0 && aid == 0x26, "k4 : AID 0x26");
  uint8_t uuid[16], acces[16];
  hexa("0073e7e4d8b9440faf8415df4c56c0e1", uuid, 16);
  size_t na = sizeof(acces);
  ok = crochet_dechiffrer_acces(appkey, pdu, n, 0x12345677, uuid, acces, &na) == 0;
  hexa("d50a0048656c6c6f", attendu, 8);
  verifie(ok && na == 8 && memcmp(acces, attendu, 8) == 0, "8.3.22 : message d'acces");

  // 8.4.3 : balise reseau securisee.
  uint8_t balise[22], net_id[8];
  hexa("01003ecaff672f673370123456788ea261582f364f6f", balise, 22);
  tri_balise_t b;
  verifie(tri_lire_balise(balise, 22, &b) && b.iv_index == 0x12345678, "8.4.3 : IV Index");
  verifie(bt_mesh_k3(netkey, net_id) == 0 && memcmp(net_id, b.net_id, 8) == 0, "8.4.3 : NetID (k3)");
  // 8.2.6 : BeaconKey ; 8.4.3 : authentification de la balise, comme le crochet.
  uint8_t cle_balise[16], auth[8];
  hexa("5423d967da639a99cb02231a83f7d254", attendu, 16);
  verifie(bt_mesh_secure_beacon_key(netkey, cle_balise) == 0 && memcmp(cle_balise, attendu, 16) == 0,
          "8.2.6 : cle de balise");
  verifie(bt_mesh_secure_beacon_auth(cle_balise, b.flags, b.net_id, b.iv_index, auth) == 0 &&
              memcmp(auth, b.auth, 8) == 0,
          "8.4.3 : authentification de la balise");

  printf("autotest : %d echec(s)\n", s_echecs);
  return s_echecs;
}
