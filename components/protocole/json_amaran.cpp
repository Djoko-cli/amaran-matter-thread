// Messages du pont amaran (voir json_amaran.h).
#include "json_amaran.h"

#include <stdio.h>
#include <string.h>

#include <initializer_list>

#include "catalogue.h"

namespace jsonp {

// --- Codes

const char *phaseCode(lampe_phase_t p) {
  switch (p) {
    case LAMPE_TRAMES: return "trames";
    case LAMPE_ATTENTE: return "attente";
    case LAMPE_REPOS:
    default: return "repos";
  }
}

static const char *typeCode(catalogue_type_t t) {
  switch (t) {
    case CATALOGUE_LAMPE_TEMPERATURE: return "temperature";
    case CATALOGUE_LAMPE_COULEUR: return "couleur";
    case CATALOGUE_LAMPE_VARIABLE:
    default: return "variable";
  }
}

// ["intensite","cct","couleur"] : les capacites, une par mot.
static void capacites(Writer &w, uint8_t c) {
  w.arr("capacites");
  if (c & CATALOGUE_INTENSITE) w.str(nullptr, "intensite");
  if (c & CATALOGUE_CCT) w.str(nullptr, "cct");
  if (c & CATALOGUE_COULEUR) w.str(nullptr, "couleur");
  w.end();
}

static void modele(Writer &w, const char *k, const catalogue_modele_t *m, bool code) {
  w.obj(k);
  if (code) w.u32("code", m->code);
  w.str("nom", m->nom);
  capacites(w, m->capacites);
  w.str("type", typeCode(m->type));
  if (m->capacites & CATALOGUE_CCT) {
    w.obj("cct_k");
    w.u32("min", m->cct_min_k);
    w.u32("max", m->cct_max_k);
    w.end();
  } else {
    w.null("cct_k");
  }
  w.end();
}

static void etatLu(Writer &w, const char *k, const lampe_etat_t &e) {
  w.obj(k);
  w.boolean("marche", e.marche);
  w.u32("intensite", e.intensite);
  w.end();
}

// --- hello

void helloBase(Writer &w, uint32_t n, uint32_t ms, const HelloBase &h) {
  w.begin("hello", n, ms);
  w.str("bloc", "base");
  w.u32("rev", kRev);
  w.str("fw", h.fw, 32);
  w.str("date", h.date, 16);
  w.str("heure", h.heure, 16);
  w.str("idf", h.idf, 32);
  w.str("puce", h.puce, 16);
  w.hexU32("boot", h.boot, 8);
  w.str("reset", h.reset);
  w.u32("reset_n", h.resetN);
  w.u32("up_s", h.upS);
  w.obj("session");
  w.str("transport", h.session.transport);
  w.u32("periode_ms", h.session.periodeMs);
  w.u32("lampes_ms", h.session.lampesMs);
  w.u32("compteurs_ms", h.session.compteursMs);
  w.u32("reseau_ms", h.session.reseauMs);
  w.u32("bail_s", h.session.bailS);
  w.boolean("log", h.session.log);
  w.boolean("trames", h.session.trames);
  w.end();
  w.obj("limites");
  w.u32("ligne_max", (uint32_t)kLineMax);
  w.u32("cmd_max", (uint32_t)kCmdMax);
  w.end();
}

void helloId(Writer &w, uint32_t n, uint32_t ms, const HelloId &h) {
  w.begin("hello", n, ms);
  w.str("bloc", "identite");
  w.hexU32("boot", h.boot, 8);
  w.hex("mac", h.mac, 6);
  w.obj("id");
  w.str("fabricant", h.fabricant, 32);
  w.str("produit", h.produit, 32);
  w.str("serie", h.serie, 32);
  w.str("nom", h.nom, 32);
  w.end();
  w.arr("caps");
  for (const char *c : {"matter", "thread", "mesh", "catalogue", "ordres", "led", "log", "trames", "udp", "cle", "texte"})
    w.str(nullptr, c);
  w.end();
}

// --- config

void configCatalogue(Writer &w, uint32_t n, uint32_t ms) {
  w.begin("config", n, ms);
  w.str("bloc", "catalogue");
  w.arr("modeles");
  for (unsigned i = 0; i < catalogue_nombre(); i++) modele(w, nullptr, catalogue_modele(i), true);
  w.end();
  modele(w, "repli", catalogue_repli(), false);
}

void configMesh(Writer &w, uint32_t n, uint32_t ms, const ConfigMesh &c) {
  w.begin("config", n, ms);
  w.str("bloc", "mesh");
  w.boolean("cles", c.cles);
  if (c.cles) {
    w.obj("empreintes");
    w.str("reseau", c.empReseau, 8);
    w.str("application", c.empApp, 8);
    w.end();
  } else {
    w.null("empreintes");
  }
  w.hexU32("adresse", c.adresse, 4);
  w.u32("iv_nvs", c.ivNvs);
  w.obj("balayage");
  w.u32("fenetre_ms", c.fenetreMs);
  w.u32("intervalle_ms", c.intervalleMs);
  w.end();
  w.u32("lampes", c.lampes);
  w.u32("capacite", LISTE_CAPACITE);
  w.u32("releve_ms", c.releveMs);
  w.hexU32("groupe", LAMPES_GROUPE, 4);
}

void configLampe(Writer &w, uint32_t n, uint32_t ms, int lampe, const liste_lampe_t &l) {
  const catalogue_modele_t *m = catalogue_trouver(l.code);
  w.begin("config", n, ms);
  w.str("bloc", "lampe");
  w.u32("lampe", (uint32_t)lampe + 1);
  w.hexU32("adresse", l.adresse, 4);
  w.hex("mac", l.mac, 6);
  w.str("nom", l.nom, LISTE_NOM_MAX - 1);
  w.u32("code", l.code);
  w.str("modele", m->nom);
  w.boolean("catalogue", catalogue_connu(l.code));
  capacites(w, m->capacites);
  w.str("type", typeCode(m->type));
}

// --- etat

void etatPont(Writer &w, uint32_t n, uint32_t ms, const EtatPont &e) {
  w.begin("etat", n, ms);
  w.str("bloc", "pont");
  w.hexU32("boot", e.boot, 8);
  w.u32("up_s", e.upS);
  w.obj("mesh");
  w.boolean("pret", e.meshPret);
  w.str("diag", e.diag);
  w.end();
  w.obj("ordres");
  w.u32("total", e.ordres);
  w.u32("confirmes", e.confirmes);
  w.u32("abandons", e.abandons);
  w.u32("tenus", e.tenus);
  w.u32("delai_total_ms", e.delaiTotalMs);
  w.u32("delai_max_ms", e.delaiMaxMs);
  w.u32("lents", e.lents);
  w.end();
  w.u32("releves", e.releves);
  w.u32("trames", e.trames);
}

void etatLampe(Writer &w, uint32_t n, uint32_t ms, int lampe, const lampe_t &p, const liste_lampe_t &l,
               uint16_t endpoint, int part) {
  w.begin("etat", n, ms);
  w.str("bloc", "lampe");
  w.u32("lampe", (uint32_t)lampe + 1);
  w.obj("maison");
  if (endpoint) w.u32("endpoint", endpoint);
  else w.null("endpoint");
  w.boolean("vue", (l.drapeaux & LISTE_VUE) != 0);
  w.boolean("masquee", (l.drapeaux & LISTE_MASQUEE) != 0);
  w.end();
  w.boolean("entendue", p.entendue);
  if (p.connu) etatLu(w, "lue", p.lu);
  else w.null("lue");
  w.boolean("joignable", p.joignable);
  if (p.entendue) w.u32("reponse_ms", p.reponse_ms);
  else w.null("reponse_ms");
  if (p.phase == LAMPE_REPOS) {
    w.null("consigne");
  } else {
    w.obj("consigne");
    if (p.veut_marche) w.boolean("marche", p.consigne.marche);
    else w.null("marche");
    if (p.veut_intensite) w.u32("intensite", p.consigne.intensite);
    else w.null("intensite");
    w.str("phase", phaseCode(p.phase));
    w.u32("essai", p.essai);
    w.end();
  }
  w.u32("repondues", p.releves_repondues);
  if (part >= 0) w.u32("part_10min", (uint32_t)part);
  else w.null("part_10min");
  w.boolean("alerte", p.alerte);
}

void etatSante(Writer &w, uint32_t n, uint32_t ms, const EtatSante &e) {
  w.begin("etat", n, ms);
  w.str("bloc", "sante");
  w.hexU32("boot", e.boot, 8);
  w.u32("up_s", e.upS);
  if (e.cmdId) w.u32("commande", e.cmdId);
  else w.null("commande");
  w.obj("led");
  w.str("motif", e.motif);
  w.boolean("test", e.test);
  w.u32("depuis_ms", e.depuisMs);
  w.end();
  w.obj("matter");
  w.boolean("en_service", e.enService);
  w.boolean("thread", e.threadAttache);
  w.boolean("identifie", e.identifie);
  w.boolean("ble", e.ble);
  w.end();
  w.obj("sys");
  w.u32("heap", e.heap);
  w.u32("heap_min", e.heapMin);
  w.u32("heap_bloc", e.heapBloc);
  w.obj("piles");
  for (uint8_t i = 0; i < e.nPiles; i++) {
    if (e.piles[i].libre >= 0) w.u32(e.piles[i].nom, (uint32_t)e.piles[i].libre);
    else w.null(e.piles[i].nom);
  }
  w.end();
  w.u32("json_perdus", e.perdus);
  w.u32("json_trop_longs", e.tropLongs);
  w.u32("rejets", e.rejets);
  w.end();
}

// --- compteurs

void compteursMesh(Writer &w, uint32_t n, uint32_t ms, const CompteursMesh &c) {
  w.begin("compteurs", n, ms);
  w.str("bloc", "mesh");
  w.u32("annonces", c.annonces);
  w.u32("nid_reconnu", c.nidReconnu);
  w.u32("nid_inconnu", c.nidInconnu);
  w.u32("netmic_faux", c.netmicFaux);
  w.u32("acces_dechiffres", c.accesDechiffres);
  w.u32("etats_lampes", c.etatsLampes);
  w.u32("doublons", c.doublons);
  w.obj("balises");
  w.u32("notres", c.balisesNotres);
  w.u32("autres", c.balisesAutres);
  w.u32("fausses", c.balisesFausses);
  if (c.baliseVue) {
    w.obj("derniere");
    w.u32("iv", c.baliseIv);
    w.u32("drapeaux", c.baliseDrapeaux);
    w.u32("ms", c.baliseMs);
    w.end();
  } else {
    w.null("derniere");
  }
  w.end();
  w.u32("emis", c.emis);
  w.u32("echecs_emission", c.echecsEmission);
  w.u32("file_pleine", c.filePleine);
  w.u32("iv", c.iv);
  w.u32("seq", c.seq);
  w.u32("plancher", c.plancher);
}

// --- reseau

void reseauMatter(Writer &w, uint32_t n, uint32_t ms, const ReseauMatter &r) {
  w.begin("reseau", n, ms);
  w.str("bloc", "matter");
  w.boolean("demarre", r.demarre);
  w.u32("fabriques", r.fabriques);
  w.boolean("ble", r.ble);
  w.boolean("identifie", r.identifie);
  w.obj("abonnements");
  w.u32("demandes", r.demandes);
  w.u32("plafonnes", r.plafonnes);
  w.u32("etablis", r.etablis);
  w.u32("termines", r.termines);
  w.u32("plafond_s", r.plafondS);
  w.end();
  w.str("code_manuel", r.codeManuel, 32);
  w.str("qr", r.qr, 64);
}

void reseauThread(Writer &w, uint32_t n, uint32_t ms, const char *role, bool attache) {
  w.begin("reseau", n, ms);
  w.str("bloc", "thread");
  w.str("role", role, 16);
  w.boolean("attache", attache);
}

void ip6Texte(const uint8_t a[16], char out[40]) {
  uint16_t g[8];
  for (int i = 0; i < 8; i++) g[i] = (uint16_t)(a[2 * i] << 8 | a[2 * i + 1]);
  // Plus longue suite d'au moins deux groupes nuls (la premiere a egalite).
  int debut = -1, lon = 0;
  for (int i = 0; i < 8;) {
    if (g[i]) {
      i++;
      continue;
    }
    int j = i;
    while (j < 8 && !g[j]) j++;
    if (j - i > lon && j - i >= 2) {
      debut = i;
      lon = j - i;
    }
    i = j;
  }
  char *p = out;
  for (int i = 0; i < 8; i++) {
    if (i == debut) {
      *p++ = ':';
      if (i == 0) *p++ = ':';
      i += lon - 1;
      continue;
    }
    p += snprintf(p, 6, "%x", g[i]);
    if (i < 7) *p++ = ':';
  }
  *p = 0;
}

void reseauIp(Writer &w, uint32_t n, uint32_t ms, const ReseauIp &r) {
  w.begin("reseau", n, ms);
  w.str("bloc", "ip");
  if (r.srp) w.str("srp", r.srp, 63);
  else w.null("srp");
  w.arr("adresses");
  for (uint8_t i = 0; i < r.n && i < 4; i++) {
    char t[40];
    ip6Texte(r.adresses[i].a, t);
    w.obj(nullptr);
    w.str("type", r.adresses[i].type);
    w.str("adresse", t);
    w.end();
  }
  w.end();
  w.obj("udp");
  w.u32("port", 5480);
  w.boolean("cle", r.cle);
  if (r.empreinte) w.str("empreinte", r.empreinte, 8);
  else w.null("empreinte");
  w.boolean("ouvert", r.ouvert);
  w.u32("sessions", r.sessions);
  w.u32("recus", r.recus);
  w.u32("emis", r.emis);
  w.u32("rejets", r.rejets);
  w.u32("perdus", r.perdus);
  w.end();
}

Session sessionDistante() {
  Session s;
  s.transport = "udp";
  s.periodeMs = 2000;
  s.lampesMs = 30000;
  s.compteursMs = 0;
  s.reseauMs = 30000;
  return s;
}

// Entier decimal (chiffres seulement, au plus 9) : false sinon.
static bool nombre(const char *s, uint32_t *v) {
  uint32_t x = 0;
  int n = 0;
  for (; s[n]; n++) {
    if (s[n] < '0' || s[n] > '9' || n >= 9) return false;
    x = x * 10 + (uint32_t)(s[n] - '0');
  }
  if (!n) return false;
  *v = x;
  return true;
}

const char *refusDistant(int argc, const char *const *argv) {
  static const char kInterdite[] = "interdite a distance : USB seulement";
  auto est = [&](int i, const char *k) { return i < argc && !strcmp(argv[i], k); };
  uint32_t v = 0;
  if (argc < 1) return kInterdite;
  if (est(0, "json")) {
    if (argc == 2 && (est(1, "0") || est(1, "etat") || est(1, "hello") || est(1, "ping"))) return nullptr;
    if (est(1, "1")) {
      // Jamais de bail 0 a distance : le pont emettrait sur Thread pour un
      // hote parti, jusqu'a l'oubli de la session.
      if (argc == 2) return nullptr;
      if (argc == 4 && est(2, "bail") && nombre(argv[3], &v) && v >= 10 && v <= 120) return nullptr;
      return "json 1 : bail de 10 a 120 s a distance";
    }
    if (argc == 3 && (est(1, "trames") || est(1, "log")) && (est(2, "0") || est(2, "1"))) return nullptr;
    static const struct {
      const char *k;
      uint32_t min;
      const char *msg;
    } kBornes[] = {
        {"periode", 2000, "json periode : 0 ou 2000..60000 ms a distance"},
        {"lampes", 10000, "json lampes : 0 ou 10000..60000 ms a distance"},
        {"compteurs", 5000, "json compteurs : 0 ou 5000..60000 ms a distance"},
        {"reseau", 10000, "json reseau : 0 ou 10000..60000 ms a distance"},
    };
    for (const auto &b : kBornes) {
      if (!est(1, b.k)) continue;
      if (argc == 3 && nombre(argv[2], &v) && (v == 0 || (v >= b.min && v <= 60000))) return nullptr;
      return b.msg;
    }
    return kInterdite;  // 'json' seul, 'json cle ...'
  }
  if (est(0, "lampe")) {
    if (argc >= 2 && !nombre(argv[1], &v)) return kInterdite;
    if (argc == 2) return nullptr;  // detail
    if (argc == 3 && (est(2, "on") || est(2, "off") || est(2, "releve"))) return nullptr;
    if (argc == 4 && est(2, "niveau") && nombre(argv[3], &v)) return nullptr;
    return kInterdite;
  }
  if (est(0, "mesh")) {
    if (argc == 1) return nullptr;  // lecture
    if (argc == 4 && est(1, "lampe") && nombre(argv[2], &v) && (est(3, "masquer") || est(3, "afficher")))
      return nullptr;
    return kInterdite;
  }
  if (argc == 2 && est(0, "led") && (est(1, "test") || est(1, "stop"))) return nullptr;
  if (argc == 1 && (est(0, "lampes") || est(0, "matter") || est(0, "taches") || est(0, "cause"))) return nullptr;
  return kInterdite;
}

void trame(Writer &w, uint32_t n, uint32_t ms, const Trame &t) {
  w.begin("trame", n, ms);
  w.str("sens", t.sens);
  w.str("quoi", t.quoi);
  if (t.lampe >= 0) w.u32("lampe", (uint32_t)t.lampe + 1);
  else w.null("lampe");
  if (t.marche >= 0) w.boolean("marche", t.marche != 0);
  else w.null("marche");
  if (t.intensite >= 0) w.u32("intensite", (uint32_t)t.intensite);
  else w.null("intensite");
  if (!strcmp(t.quoi, "ordre")) w.u32("essai", t.essai);
  w.u32("sautes", t.sautes);
}

// --- evenements

void ordre(Writer &w, uint32_t n, uint32_t ms, const Ordre &o) {
  w.begin("ordre", n, ms);
  w.u32("lampe", (uint32_t)o.lampe + 1);
  w.str("issue", o.issue);
  w.u32("delai_ms", o.delaiMs);
  w.u32("essai", o.essai);
  w.arr("ids");
  for (uint8_t i = 0; i < o.nIds && i < kIdsMax; i++) w.u32(nullptr, o.ids[i]);
  w.end();
  w.u32("ids_perdus", o.idsPerdus);
}

void alerteReleves(Writer &w, uint32_t n, uint32_t ms, int lampe, bool manque, uint8_t part) {
  w.begin("alerte", n, ms);
  w.str("quoi", "releves");
  w.u32("lampe", (uint32_t)lampe + 1);
  w.boolean("manque", manque);
  w.u32("part", part);
}

void alerteMesh(Writer &w, uint32_t n, uint32_t ms, const char *diag) {
  w.begin("alerte", n, ms);
  w.str("quoi", "mesh");
  w.str("diag", diag);
}

void lampe(Writer &w, uint32_t n, uint32_t ms, int lampe, const char *quoi, uint16_t endpoint) {
  w.begin("lampe", n, ms);
  w.u32("lampe", (uint32_t)lampe + 1);
  w.str("quoi", quoi);
  if (endpoint) w.u32("endpoint", endpoint);
  else w.null("endpoint");
}

}  // namespace jsonp
