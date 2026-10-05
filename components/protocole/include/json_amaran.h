#pragma once
// ===========================================================================
//  Messages du pont amaran (docs/PROTOCOLE-JSON.md, sections 5 et 7), formes
//  depuis des donnees simples : les structures du coeur (lampes.h) et de la
//  liste (liste.h), et des releves remplis par firmware/main/json_pont.cpp.
//  Pur et sans ESP-IDF : teste sur le Mac (tests/hote/test_json.cpp), qui
//  verifie aussi que chaque exemple du document sort tel quel d'ici.
// ===========================================================================
#include <stddef.h>
#include <stdint.h>

#include "json_ligne.h"
#include "lampes.h"
#include "liste.h"

namespace jsonp {

// --- hello (5.1)

struct Session {
  uint32_t periodeMs = 1000;    // etat : blocs pont et sante
  uint32_t lampesMs = 10000;    // etat : toutes les lampes (une lampe part aussi a chaque changement)
  uint32_t compteursMs = 1000;
  uint32_t reseauMs = 5000;
  uint16_t bailS = 30;
  bool log = false;
};

struct HelloBase {
  const char *fw = "";          // esp_app_get_description()->version
  const char *date = "", *heure = "";
  const char *idf = "";
  const char *puce = "";
  uint32_t boot = 0;
  const char *reset = "";       // code de la cause du demarrage (json_pont.cpp)
  uint8_t resetN = 0;           // esp_reset_reason()
  uint32_t upS = 0;
  Session session;
};
void helloBase(Writer &w, uint32_t n, uint32_t ms, const HelloBase &h);

struct HelloId {
  uint32_t boot = 0;
  uint8_t mac[6] = {};
  const char *fabricant = nullptr, *produit = nullptr, *serie = nullptr, *nom = nullptr;  // nul : inconnu
};
void helloId(Writer &w, uint32_t n, uint32_t ms, const HelloId &h);

// --- config (5.2)

void configCatalogue(Writer &w, uint32_t n, uint32_t ms);

struct ConfigMesh {
  bool cles = false;
  const char *empReseau = nullptr, *empApp = nullptr;  // 8 hexa ; nul sans cles
  uint16_t adresse = 0;
  uint32_t ivNvs = 0;
  uint16_t fenetreMs = 0, intervalleMs = 0;            // balayage
  uint8_t lampes = 0;                                  // N de la liste du demarrage
  uint32_t releveMs = 0;
};
void configMesh(Writer &w, uint32_t n, uint32_t ms, const ConfigMesh &c);

// lampe : index (0..15) ; le message porte son numero (1..16).
void configLampe(Writer &w, uint32_t n, uint32_t ms, int lampe, const liste_lampe_t &l);

// --- etat (5.3)

struct EtatPont {
  uint32_t boot = 0, upS = 0;
  bool meshPret = false;
  const char *diag = "ok";
  uint32_t ordres = 0, confirmes = 0, abandons = 0, tenus = 0;
  uint32_t delaiTotalMs = 0, delaiMaxMs = 0, lents = 0;
  uint32_t releves = 0, trames = 0;
};
void etatPont(Writer &w, uint32_t n, uint32_t ms, const EtatPont &e);

// part : lampes_part_repondue (-1 : aucune relecture comptee) ; endpoint : 0 si
// la lampe n'est pas dans Maison.
void etatLampe(Writer &w, uint32_t n, uint32_t ms, int lampe, const lampe_t &p, const liste_lampe_t &l,
               uint16_t endpoint, int part);

struct Pile {
  const char *nom;
  int32_t libre;  // octets jamais utilises ; -1 : tache absente
};
struct EtatSante {
  uint32_t boot = 0, upS = 0;
  uint32_t cmdId = 0;           // id de la commande de la console en cours ; 0 : aucune
  const char *motif = nullptr;  // code du voyant (status_led.h : patternCode)
  bool test = false;
  uint32_t depuisMs = 0;
  bool enService = false, threadAttache = false, identifie = false, ble = false;
  uint32_t heap = 0, heapMin = 0, heapBloc = 0;
  const Pile *piles = nullptr;
  uint8_t nPiles = 0;
  uint32_t perdus = 0, tropLongs = 0, rejets = 0;
};
void etatSante(Writer &w, uint32_t n, uint32_t ms, const EtatSante &e);

// --- compteurs (5.4)

struct CompteursMesh {
  uint32_t annonces = 0, nidReconnu = 0, nidInconnu = 0, netmicFaux = 0, accesDechiffres = 0, etatsLampes = 0,
           doublons = 0;
  uint32_t balisesNotres = 0, balisesAutres = 0, balisesFausses = 0;
  bool baliseVue = false;
  uint32_t baliseIv = 0, baliseMs = 0;
  uint8_t baliseDrapeaux = 0;
  uint32_t emis = 0, echecsEmission = 0, filePleine = 0;
  uint32_t iv = 0, seq = 0, plancher = 0;
};
void compteursMesh(Writer &w, uint32_t n, uint32_t ms, const CompteursMesh &c);

// --- reseau (5.5)

struct ReseauMatter {
  bool demarre = false;
  uint8_t fabriques = 0;
  bool ble = false, identifie = false;
  uint32_t demandes = 0, plafonnes = 0, etablis = 0, termines = 0;
  uint16_t plafondS = 0;
  const char *codeManuel = nullptr, *qr = nullptr;  // nul : inconnus
};
void reseauMatter(Writer &w, uint32_t n, uint32_t ms, const ReseauMatter &r);
void reseauThread(Writer &w, uint32_t n, uint32_t ms, const char *role, bool attache);

// --- evenements (7)

constexpr uint8_t kIdsMax = 4;  // id en attente par lampe

struct Ordre {
  int lampe = 0;                 // index
  const char *issue = "confirme";  // confirme, abandon, tenu
  uint32_t delaiMs = 0;
  uint8_t essai = 0;
  uint32_t ids[kIdsMax] = {};
  uint8_t nIds = 0;
  uint32_t idsPerdus = 0;
};
void ordre(Writer &w, uint32_t n, uint32_t ms, const Ordre &o);
void alerteReleves(Writer &w, uint32_t n, uint32_t ms, int lampe, bool manque, uint8_t part);
void alerteMesh(Writer &w, uint32_t n, uint32_t ms, const char *diag);
// quoi : entree, masquee, remise, echec ; endpoint 0 : null.
void lampe(Writer &w, uint32_t n, uint32_t ms, int lampe, const char *quoi, uint16_t endpoint);

// Codes du protocole.
const char *phaseCode(lampe_phase_t p);  // repos, trames, attente

}  // namespace jsonp
