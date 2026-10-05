// Mode JSON du pont (voir json_pont.h). Sur le modele de json_mode.cpp du pont
// Halo (commit e114cd5), pour ESP-IDF : une session (un « puits ») par origine,
// l'USB et chaque session H1 de net_udp. La console lit et execute les lignes de
// l'USB dans sa tache ; la tache udp, celles de Thread ; la tache distant execute
// les commandes a texte venues de Thread, sa sortie standard changee en messages
// texte ; la tache json forme les lignes periodiques et les evenements. Une ligne
// se forme et s'ecrit sous s_verrou, d'un seul appel au pilote de l'USB, ou
// scellee dans la file de net_udp, sans attendre (2.3). A distance, le debit se
// regle sur la place de cette file (10.3, json_ligne.h : kPlacesLigne) : une ligne
// de la file attend sa place, un evenement sans place est perdu et compte.
#include "json_pont.h"

#include <inttypes.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "bootloader_random.h"
#include "driver/usb_serial_jtag.h"
#include "esp_app_desc.h"
#include "esp_console.h"
#include "esp_heap_caps.h"
#include "esp_idf_version.h"
#include "esp_mac.h"
#include "esp_random.h"
#include "esp_system.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "sdkconfig.h"

#include "console_pont.h"
#include "json_amaran.h"
#include "json_ligne.h"
#include "liste.h"
#include "mesh_amaran.h"
#include "net_udp.h"
#include "pont_matter.h"
#include "socle.h"
#include "tache_lampes.h"
#include "texte.h"

using namespace jsonp;

static_assert(JSON_PONT_CMD_MAX == kCmdMax, "json_pont.h et json_ligne.h : meme longueur de ligne");
static_assert(NET_UDP_PLACES_LIGNE == kPlacesLigne, "net_udp.h et json_ligne.h : meme place pour une ligne");
static_assert(JSON_PONT_IDS_MAX == kIdsMax, "json_pont.h et json_amaran.h : meme nombre d'id par ordre");

#define ORIGINES (1 + NET_UDP_SESSIONS)  // l'USB, puis les sessions H1
#define USB JSON_PONT_USB
#define TIC_MS 10            // une ligne de la file par tic et par puits (2.3)
#define REGARD_MS 100        // changements des lampes
#define BATTEMENT_MS 2000    // hb, quand les etat sont coupes ou lents (3.5)
#define FILE_EVENEMENTS 32   // 32 x sizeof(evenement_t) en RAM
#define FILE_JOURNAL 6
#define FILE_TRAVAUX 2       // commandes a texte venues de Thread, en attente
#define DIFFEREES 4          // reponses qui attendent la fin d'un instantane
#define RETARD_USB_MS 500    // ligne periodique perdue au-dela (2.3)
#define RETARD_DISTANT_MS 10000  // deux instantanes de 16 lampes a la fois tiennent (3 Ko/s)
#define TRAMES_DISTANT_MS 60000  // json trames 1 a distance : coupe seul (7.6)
#define PLAFOND_DISTANT 10       // a distance : 10 log et 10 trames par seconde au plus (7.5, 7.6)

typedef enum { EV_ORDRE, EV_RELEVES, EV_MESH, EV_LAMPE, EV_LED, EV_TRAME } ev_type_t;

typedef struct {
  ev_type_t type;
  int8_t lampe;
  uint8_t a, b;         // ordre : signal, essai ; releves : manque, part ; mesh : diag ; lampe : quoi ;
                        // trame : rx, essai
  uint8_t n_ids;
  uint16_t endpoint;
  uint32_t delai_ms;    // ordre ; led : depuis_ms
  uint32_t ids[kIdsMax];
  uint8_t origines[kIdsMax];
  uint32_t ids_perdus;
  const char *motif, *avant;  // led ; trame : motif = quoi
  int8_t marche;        // trame
  int32_t intensite;    // trame
} evenement_t;

typedef struct {
  const char *src;
  bool alerte;
  char txt[kLogTextMax + 1];
} journal_t;

typedef struct {
  bool utilisee;
  uint32_t id, debut_ms;
  bool bail;
  char cmd[kCmdTextMax + 1];
} differee_t;

// Ce qu'une ligne etat lampe montre : une ligne part quand cela change (REGARD_MS).
typedef struct {
  bool entendue, connu, marche, joignable, alerte, veut_marche, veut_intensite, consigne_marche;
  uint8_t phase, essai, drapeaux;
  uint16_t intensite, consigne_intensite, endpoint;
} resume_t;

// Une session : sous s_verrou ; machine, log et trames se lisent aussi sans lui.
struct puits_t {
  volatile bool machine, log, trames;
  Session reglages;
  // Distant : generation de la session H1 de net_udp, posee par remettre. Une ligne
  // ou un travail d'une autre generation est ignore ; net_udp refuse un envoi qui
  // n'est pas de la sienne. L'USB : toujours 0.
  uint32_t generation;
  uint32_t dernier_rx, derniere_cmd;
  // Commande en cours : le bail ne court pas, et le bloc sante porte son id (6.2).
  bool en_commande;
  uint32_t cmd_id;
  uint32_t prochain_etat, prochain_lampes, prochain_compteurs, prochain_reseau, prochain_hb, prochain_regard,
      fin_trames;
  Queue file;
  differee_t differees[DIFFEREES];
  resume_t resumes[LISTE_CAPACITE];
  uint32_t n, perdus;
  Cadence cadence;
  RateCap plafond_journal{20}, plafond_trames{50};
  ReplyCache cache;  // distant : reponses deja donnees, par id (10.4)
  uint32_t id_max;
  // distant : id acceptes dont la reponse fin n'est pas encore partie (json 1, json etat,
  // commande a texte) ; un renvoi de l'un d'eux est ignore, sa reponse viendra.
  uint32_t en_attente[4];
};

// Distant : la reponse fin de l'id part ; elle entre dans le cache. Sous s_verrou.
static void garder_reponse(puits_t &P, const Reply &r) {
  if (!r.fin || !r.id) return;
  P.cache.put(r);
  for (uint32_t &a : P.en_attente)
    if (a == r.id) a = 0;
}

static bool en_attente(const puits_t &P, uint32_t id) {
  for (uint32_t a : P.en_attente)
    if (a == id) return true;
  return false;
}

// Commande a texte venue de Thread, executee par la tache distant.
typedef struct {
  uint8_t origine;
  uint32_t generation, id, debut_ms;
  char cmd[kCmdMax + 1];
  char vue[kCmdTextMax + 1];
} travail_t;

static const amaran_config_t *s_cfg;
static SemaphoreHandle_t s_verrou;   // puits, ecrivain
static SemaphoreHandle_t s_commande; // une commande a texte a la fois (console, distant)
static QueueHandle_t s_evenements, s_journal, s_travaux;
static TaskHandle_t s_tache_distant;
static uint32_t s_boot;
static puits_t s_puits[ORIGINES];
static volatile bool s_trames_actives, s_log_actif;

// Ecrivain : une ligne a la fois, sous s_verrou.
static Writer s_w;
static uint32_t s_trop_longs, s_rejets;
// Evenements refuses par une file pleine, postes depuis plusieurs taches : increment atomique.
static volatile uint32_t s_evenements_perdus;

// Copies de l'etat des lampes, relues sous s_verrou quand une ligne en a besoin.
static lampes_t s_lampes;
static liste_t s_liste;

static LineAssembler s_assembleur;  // tache de la console

static uint32_t maintenant_ms(void) { return (uint32_t)(esp_timer_get_time() / 1000); }
static bool echu(uint32_t t, uint32_t echeance) { return (int32_t)(t - echeance) >= 0; }

// Drapeaux lus sans verrou par les autres taches. Sous s_verrou.
static void recompter(void) {
  bool trames = false, log = false;
  for (const puits_t &p : s_puits) {
    trames = trames || (p.machine && p.trames);
    log = log || (p.machine && p.log);
  }
  s_trames_actives = trames;
  s_log_actif = log;
}

// --- Ecriture (2.3)

// Tout ou rien, sans attendre ; une seconde chance une milliseconde plus tard, si
// une autre tache tenait le pilote (son verrou d'emission).
static bool ecrire(const void *p, size_t n) {
  if (usb_serial_jtag_write_bytes(p, n, 0) == (int)n) return true;
  vTaskDelay(1);
  return usb_serial_jtag_write_bytes(p, n, 0) == (int)n;
}

// La ligne formee dans s_w vers l'origine o : n consomme, ecrite ou comptee
// perdue. A distance, sans RS ni LF : un datagramme est une ligne, pour la session
// de la generation du puits seulement. Sous s_verrou.
static void envoyer(int o) {
  puits_t &P = s_puits[o];
  P.n++;
  if (!s_w.finish()) {
    s_trop_longs++;
    return;
  }
  const bool ok = o == USB ? ecrire(s_w.data(), s_w.size())
                           : net_udp_envoyer((uint8_t)(o - 1), P.generation, s_w.data() + 1, s_w.size() - 2);
  if (!ok) P.perdus++;
}

// Distant : un evenement ne part que si la file d'emission de net_udp a encore `places`
// places libres (kPlacesLigne ; kPlacesPeriodique pour les trames et les log, frequents) ;
// sinon il est perdu pour cette session, n
// consomme (le trou le dit) et compte. Sous s_verrou.
static bool place_evenement(int o, uint8_t places) {
  if (o == USB || net_udp_libres() >= places) return true;
  s_puits[o].n++;
  s_puits[o].perdus++;
  return false;
}

// Marque d'un ordre de lampe (tache_lampes.h) : l'origine en 2 bits bas, puis 6 bits
// de la generation du puits. L'USB, dont la generation reste 0, a JSON_PONT_USB.
static_assert(ORIGINES <= 4 && JSON_PONT_USB == 0, "marque d'un ordre : 2 bits d'origine");
static uint8_t marque(int o) { return (uint8_t)((o & 0x03) | ((s_puits[o].generation & 0x3F) << 2)); }

// Texte du protocole (fin de session), par l'USB seulement. Sous s_verrou.
static void texte(int o, const char *t) {
  if (o == USB && !ecrire(t, strlen(t))) s_puits[USB].perdus++;
}

static void reponse(int o, const Reply &r) {
  reply(s_w, s_puits[o].n, maintenant_ms(), r);
  if (o != USB) garder_reponse(s_puits[o], r);
  envoyer(o);
}

static void repondre(int o, uint32_t id, const char *cmd, bool ok, const char *code, const char *msg,
                     uint32_t debut_ms) {
  Reply r;
  r.id = id;
  r.cmd = cmd;
  r.ok = ok;
  r.code = code;
  r.msg = msg;
  r.durMs = maintenant_ms() - debut_ms;
  reponse(o, r);
}

// --- Releves

static const char *code_reset(esp_reset_reason_t r) {
  switch (r) {
    case ESP_RST_POWERON: return "mise_sous_tension";
    case ESP_RST_EXT: return "broche";
    case ESP_RST_SW: return "logiciel";
    case ESP_RST_PANIC: return "panique";
    case ESP_RST_INT_WDT: return "chien_int";
    case ESP_RST_TASK_WDT: return "chien_tache";
    case ESP_RST_WDT: return "chien";
    case ESP_RST_BROWNOUT: return "baisse_tension";
    case ESP_RST_USB: return "usb";
    default: return "inconnue";
  }
}

static const char *code_diag(diagnostic_t d) {
  switch (d) {
    case DIAG_CLES_ABSENTES: return "cles_absentes";
    case DIAG_PAS_ENTRE: return "pas_entre";
    case DIAG_CLES_PERIMEES: return "cles_perimees";
    case DIAG_IV_FAUX: return "iv_faux";
    case DIAG_OK:
    default: return "ok";
  }
}

static uint32_t up_s(void) { return (uint32_t)(esp_timer_get_time() / 1000000); }

// json_perdus des blocs sante et hb : les lignes perdues de cette session (l'USB
// et chaque session distante comptent les leurs), plus les evenements perdus par
// leur file interne pleine, communs a toutes.
static uint32_t perdus_de(int o) {
  return __atomic_load_n(&s_evenements_perdus, __ATOMIC_RELAXED) + s_puits[o].perdus;
}

static void relire_lampes(void) {
  tache_lampes_lire(&s_lampes);
  tache_lampes_lire_liste(&s_liste);
}

static void resumer(int i, resume_t *r) {
  const lampe_t *p = &s_lampes.lampes[i];
  memset(r, 0, sizeof(*r));
  r->entendue = p->entendue;
  r->connu = p->connu;
  r->marche = p->lu.marche;
  r->intensite = p->lu.intensite;
  r->joignable = p->joignable;
  r->alerte = p->alerte;
  r->phase = (uint8_t)p->phase;
  r->essai = p->essai;
  r->veut_marche = p->veut_marche;
  r->veut_intensite = p->veut_intensite;
  r->consigne_marche = p->consigne.marche;
  r->consigne_intensite = p->consigne.intensite;
  r->drapeaux = s_liste.lampes[i].drapeaux;
  r->endpoint = pont_endpoint(i);
}

// --- Lignes de la file : formees a l'envoi, rien n'est perime. Sous s_verrou.

static void former(int o, const Queued &q) {
  puits_t &P = s_puits[o];
  const uint32_t ms = maintenant_ms();
  pont_infos_t pont;
  switch (q.item) {
    case Item::HelloBase: {
      const esp_app_desc_t *app = esp_app_get_description();
      HelloBase h;
      h.fw = app->version;
      h.date = app->date;
      h.heure = app->time;
      h.idf = esp_get_idf_version();
      h.puce = CONFIG_IDF_TARGET;
      h.boot = s_boot;
      const esp_reset_reason_t r = esp_reset_reason();
      h.reset = code_reset(r);
      h.resetN = (uint8_t)r;
      h.upS = up_s();
      h.session = P.reglages;
      helloBase(s_w, P.n, ms, h);
      break;
    }
    case Item::HelloId: {
      HelloId h;
      h.boot = s_boot;
      uint8_t mac[8] = {0};  // 8 octets : lecon du Halo (certaines lectures rendent un EUI-64 sur le C6)
      esp_read_mac(mac, ESP_MAC_BASE);
      memcpy(h.mac, mac, 6);
      pont_lire(&pont);
      h.fabricant = pont.fabricant;
      h.produit = pont.produit;
      h.serie = pont.serie;
      h.nom = PONT_NOM;
      helloId(s_w, P.n, ms, h);
      break;
    }
    case Item::ConfigCatalogue:
      configCatalogue(s_w, P.n, ms);
      break;
    case Item::ConfigMesh: {
      relire_lampes();
      ConfigMesh c;
      char en[9], ea[9];
      c.cles = s_cfg->cles_presentes;
      if (c.cles) {
        config_empreinte(s_cfg->netkey, en);
        config_empreinte(s_cfg->appkey, ea);
        c.empReseau = en;
        c.empApp = ea;
      }
      c.adresse = s_cfg->adresse;
      c.ivNvs = s_cfg->iv;
      mesh_balayage(&c.fenetreMs, &c.intervalleMs);
      c.lampes = s_liste.n;
      c.releveMs = s_lampes.periode_ms;
      configMesh(s_w, P.n, ms, c);
      break;
    }
    case Item::ConfigLampe:
      relire_lampes();
      if (q.arg >= s_liste.n) return;
      configLampe(s_w, P.n, ms, q.arg, s_liste.lampes[q.arg]);
      break;
    case Item::EtatPont: {
      relire_lampes();
      EtatPont e;
      e.boot = s_boot;
      e.upS = up_s();
      e.meshPret = s_lampes.mesh_pret;
      e.diag = code_diag(tache_lampes_diagnostic());
      e.ordres = s_lampes.ordres;
      e.confirmes = s_lampes.confirmes;
      e.abandons = s_lampes.abandons;
      e.tenus = s_lampes.tenus;
      e.delaiTotalMs = s_lampes.delai_total_ms;
      e.delaiMaxMs = s_lampes.delai_max_ms;
      e.lents = s_lampes.lents;
      e.releves = s_lampes.releves;
      e.trames = s_lampes.trames_recues;
      etatPont(s_w, P.n, ms, e);
      break;
    }
    case Item::EtatLampe: {
      relire_lampes();
      const int i = q.arg;
      if (i >= s_lampes.n || i >= s_liste.n) return;
      resumer(i, &P.resumes[i]);
      etatLampe(s_w, P.n, ms, i, s_lampes.lampes[i], s_liste.lampes[i], P.resumes[i].endpoint,
                lampes_part_repondue(&s_lampes, i));
      break;
    }
    case Item::EtatSante: {
      EtatSante e;
      e.boot = s_boot;
      e.upS = up_s();
      e.cmdId = P.cmd_id;
      socle_voyant_t v;
      socle_voyant(&v);
      e.motif = v.motif;
      e.test = v.test;
      e.depuisMs = v.depuis_ms;
      pont_lire(&pont);
      e.enService = pont.fabriques > 0;
      e.threadAttache = pont.thread_attache;
      e.identifie = pont.identifie;
      e.ble = pont.ble_annonce;
      e.heap = esp_get_free_heap_size();
      e.heapMin = esp_get_minimum_free_heap_size();
      e.heapBloc = (uint32_t)heap_caps_get_largest_free_block(MALLOC_CAP_8BIT);
      Pile piles[CONSOLE_PONT_NB_TACHES];
      for (int i = 0; i < CONSOLE_PONT_NB_TACHES; i++) {
        const TaskHandle_t t = xTaskGetHandle(CONSOLE_PONT_TACHES[i]);
        piles[i] = Pile{CONSOLE_PONT_TACHES[i], t ? (int32_t)uxTaskGetStackHighWaterMark(t) : -1};
      }
      e.piles = piles;
      e.nPiles = CONSOLE_PONT_NB_TACHES;
      e.perdus = perdus_de(o);
      e.tropLongs = s_trop_longs;
      e.rejets = s_rejets;
      etatSante(s_w, P.n, ms, e);
      break;
    }
    case Item::CptMesh: {
      mesh_stats_t st;
      mesh_lire_stats(&st);
      CompteursMesh c;
      c.annonces = st.annonces;
      c.nidReconnu = st.nid_reconnu;
      c.nidInconnu = st.nid_inconnu;
      c.netmicFaux = st.netmic_faux;
      c.accesDechiffres = st.acces_dechiffres;
      c.etatsLampes = st.etats_lampes;
      c.doublons = st.doublons;
      c.balisesNotres = st.balises_notres;
      c.balisesAutres = st.balises_autres;
      c.balisesFausses = st.balises_fausses;
      c.baliseVue = st.derniere_balise_us != 0;
      c.baliseIv = st.derniere_balise_iv;
      c.baliseMs = (uint32_t)(st.derniere_balise_us / 1000);
      c.baliseDrapeaux = st.derniere_balise_flags;
      c.emis = st.emis;
      c.echecsEmission = st.echecs_emission;
      c.filePleine = st.file_pleine;
      c.iv = mesh_iv_courant();
      c.seq = mesh_sequence();
      c.plancher = mesh_pret() ? mesh_plancher() : s_cfg->plancher_seq;
      compteursMesh(s_w, P.n, ms, c);
      break;
    }
    case Item::NetMatter: {
      pont_lire(&pont);
      ReseauMatter r;
      r.demarre = pont.demarre;
      r.fabriques = pont.fabriques;
      r.ble = pont.ble_annonce;
      r.identifie = pont.identifie;
      r.demandes = pont.abo_demandes;
      r.plafonnes = pont.abo_plafonnes;
      r.etablis = pont.abo_etablis;
      r.termines = pont.abo_termines;
      r.plafondS = PONT_PLAFOND_ABONNEMENT_S;
      // Les codes d'appairage ne passent jamais par Thread (10.1) : null a distance.
      r.codeManuel = o == USB ? pont.code_manuel : nullptr;
      r.qr = o == USB ? pont.qr : nullptr;
      reseauMatter(s_w, P.n, ms, r);
      break;
    }
    case Item::NetThread:
      pont_lire(&pont);
      reseauThread(s_w, P.n, ms, pont.role, pont.thread_attache);
      break;
    case Item::NetIp: {
      net_udp_etat_t u;
      net_udp_lire(&u);
      ReseauIp r;
      r.srp = u.srp[0] ? u.srp : nullptr;
      static const char *const TYPES[] = {"omr", "ml_eid", "autre"};
      for (uint8_t i = 0; i < u.n && i < 4; i++) {
        memcpy(r.adresses[i].a, u.adresses[i].a, 16);
        r.adresses[i].type = TYPES[u.adresses[i].type % 3];
      }
      r.n = u.n;
      r.cle = u.cle;
      r.empreinte = u.cle ? u.empreinte : nullptr;
      r.ouvert = u.ouvert;
      r.sessions = u.sessions;
      r.recus = u.recus;
      r.emis = u.emis;
      r.rejets = u.rejets;
      r.perdus = u.perdus;
      reseauIp(s_w, P.n, ms, r);
      break;
    }
    case Item::Heartbeat:
      heartbeat(s_w, P.n, ms, s_boot, up_s(), perdus_de(o), P.cmd_id);
      break;
    case Item::Reply: {
      differee_t *d = &P.differees[q.arg % DIFFEREES];
      if (!d->utilisee) return;
      Reply r;
      r.id = d->id;
      r.cmd = d->cmd;
      r.durMs = ms - d->debut_ms;
      r.hasLease = d->bail;
      r.leaseS = P.reglages.bailS;
      r.upS = up_s();
      d->utilisee = false;
      reply(s_w, P.n, ms, r);
      if (o != USB) garder_reponse(P, r);
      break;
    }
  }
  envoyer(o);
}

// --- Session. Sous s_verrou.

static void pousser_hello(int o, uint32_t t, bool session) {
  Queue &f = s_puits[o].file;
  f.push(Item::HelloBase, t, session);
  f.push(Item::HelloId, t, session);
  f.push(Item::ConfigCatalogue, t, session);
  f.push(Item::ConfigMesh, t, session);
  for (uint8_t i = 0; i < s_cfg->liste.n; i++) f.push(Item::ConfigLampe, t, session, i);
}

static void pousser_reseau(int o, uint32_t t, bool session) {
  Queue &f = s_puits[o].file;
  f.push(Item::NetMatter, t, session);
  f.push(Item::NetThread, t, session);
  f.push(Item::NetIp, t, session);
}

static void pousser_etat(int o, uint32_t t, bool session) {
  Queue &f = s_puits[o].file;
  f.push(Item::EtatPont, t, session);
  for (uint8_t i = 0; i < s_cfg->liste.n; i++) f.push(Item::EtatLampe, t, session, i);
  f.push(Item::EtatSante, t, session);
  if (s_puits[o].reglages.compteursMs || o == USB) f.push(Item::CptMesh, t, session);
  pousser_reseau(o, t, session);
}

// Reponse fin apres les lignes en file. Sans place : tout de suite.
static void differer(int o, uint32_t id, const char *cmd, bool bail, uint32_t debut_ms) {
  puits_t &P = s_puits[o];
  for (uint8_t k = 0; k < DIFFEREES; k++) {
    differee_t *d = &P.differees[k];
    if (d->utilisee) continue;
    d->utilisee = true;
    d->id = id;
    d->debut_ms = debut_ms;
    d->bail = bail;
    copyCmd(d->cmd, cmd);
    if (P.file.push(Item::Reply, maintenant_ms(), false, k)) return;
    d->utilisee = false;
    break;
  }
  Reply r;
  r.id = id;
  r.cmd = cmd;
  r.durMs = maintenant_ms() - debut_ms;
  r.hasLease = bail;
  r.leaseS = P.reglages.bailS;
  r.upS = up_s();
  reponse(o, r);
}

static void entrer(int o, uint16_t bail_s, uint32_t t) {
  puits_t &P = s_puits[o];
  P.file.dropSession();
  P.reglages = o == USB ? Session() : sessionDistante();
  P.reglages.bailS = bail_s;
  P.log = false;
  P.trames = false;
  P.dernier_rx = P.derniere_cmd = t;
  P.prochain_etat = t + P.reglages.periodeMs;
  P.prochain_lampes = t + P.reglages.lampesMs;
  P.prochain_compteurs = t + P.reglages.compteursMs;
  P.prochain_reseau = t + P.reglages.reseauMs;
  P.prochain_hb = P.prochain_regard = t;
  memset(P.resumes, 0, sizeof(P.resumes));
  if (o == USB) s_assembleur.reset();
  P.machine = true;
  recompter();
  pousser_hello(o, t, true);
  pousser_etat(o, t, true);
}

static void sortir(int o, const char *cause, const char *message) {
  puits_t &P = s_puits[o];
  sessionEnd(s_w, P.n, maintenant_ms(), cause);
  envoyer(o);
  P.machine = false;
  P.log = false;
  P.trames = false;
  P.file.dropSession();
  recompter();
  texte(o, message);
  if (o != USB) net_udp_finir((uint8_t)(o - 1), P.generation);
}

// Les lignes etat lampe dont ce qu'elles montrent a change, pour chaque puits.
static void regarder(uint32_t t) {
  relire_lampes();
  for (int i = 0; i < s_lampes.n && i < s_liste.n; i++) {
    resume_t r;
    resumer(i, &r);
    for (int o = 0; o < ORIGINES; o++) {
      puits_t &P = s_puits[o];
      if (P.machine && memcmp(&r, &P.resumes[i], sizeof(r)) != 0) P.file.push(Item::EtatLampe, t, true, (uint8_t)i);
    }
  }
}

static void programmer(int o, uint32_t t) {
  puits_t &P = s_puits[o];
  if (!P.en_commande && leaseExpired(t, P.dernier_rx, P.derniere_cmd, P.reglages.bailS)) {
    char m[80];
    snprintf(m, sizeof(m), "json : mode machine coupe (hote muet depuis %u s)\r\n", (unsigned)P.reglages.bailS);
    sortir(o, "bail", m);
    return;
  }
  if (o != USB && P.trames && echu(t, P.fin_trames)) {
    P.trames = P.reglages.trames = false;
    recompter();
  }
  if (P.reglages.periodeMs && echu(t, P.prochain_etat)) {
    P.file.push(Item::EtatPont, t, true);
    P.file.push(Item::EtatSante, t, true);
    P.prochain_etat = t + P.reglages.periodeMs;
  }
  if (P.reglages.lampesMs && echu(t, P.prochain_lampes)) {
    for (uint8_t i = 0; i < s_cfg->liste.n; i++) P.file.push(Item::EtatLampe, t, true, i);
    P.prochain_lampes = t + P.reglages.lampesMs;
  }
  if (P.reglages.compteursMs && echu(t, P.prochain_compteurs)) {
    P.file.push(Item::CptMesh, t, true);
    P.prochain_compteurs = t + P.reglages.compteursMs;
  }
  if (P.reglages.reseauMs && echu(t, P.prochain_reseau)) {
    pousser_reseau(o, t, true);
    P.prochain_reseau = t + P.reglages.reseauMs;
  }
  if ((P.reglages.periodeMs == 0 || P.reglages.periodeMs > BATTEMENT_MS) && echu(t, P.prochain_hb)) {
    P.file.push(Item::Heartbeat, t, true);
    P.prochain_hb = t + BATTEMENT_MS;
  }
}

// --- Evenements. Sous s_verrou.

static void evenement(const evenement_t &e) {
  const uint32_t ms = maintenant_ms();
  for (int o = 0; o < ORIGINES; o++) {
    puits_t &P = s_puits[o];
    if (!P.machine) continue;
    if (e.type == EV_TRAME) {
      if (!P.trames) continue;
      if (!P.plafond_trames.available(ms)) {
        P.plafond_trames.skip();
        continue;
      }
    }
    // Trames : frequentes, elles ne prennent pas la place d'une reponse (eventRoom de Halo).
    if (!place_evenement(o, e.type == EV_TRAME ? kPlacesPeriodique : kPlacesLigne)) continue;
    switch (e.type) {
      case EV_ORDRE: {
        Ordre r;
        r.lampe = e.lampe;
        r.issue = e.a == LAMPES_SIGNAL_CONFIRME ? "confirme" : e.a == LAMPES_SIGNAL_ABANDON ? "abandon" : "tenu";
        r.delaiMs = e.delai_ms;
        r.essai = e.b;
        // Les id de cette session seulement : son origine et sa generation.
        for (uint8_t i = 0; i < e.n_ids; i++)
          if (e.origines[i] == marque(o)) r.ids[r.nIds++] = e.ids[i];
        r.idsPerdus = e.ids_perdus;
        ordre(s_w, P.n, ms, r);
        break;
      }
      case EV_RELEVES:
        alerteReleves(s_w, P.n, ms, e.lampe, e.a != 0, e.b);
        break;
      case EV_MESH:
        alerteMesh(s_w, P.n, ms, code_diag((diagnostic_t)e.a));
        break;
      case EV_LAMPE: {
        static const char *const QUOI[] = {"entree", "masquee", "remise", "echec"};
        lampe(s_w, P.n, ms, e.lampe, QUOI[e.a % 4], e.endpoint);
        break;
      }
      case EV_LED:
        led(s_w, P.n, ms, e.motif, e.avant, e.a != 0, e.delai_ms);
        break;
      case EV_TRAME: {
        P.plafond_trames.take();
        Trame t;
        t.sens = e.a ? "rx" : "tx";
        t.quoi = e.motif;
        t.lampe = e.lampe;
        t.marche = e.marche;
        t.intensite = e.intensite;
        t.essai = e.b;
        t.sautes = P.plafond_trames.takeSkipped();
        trame(s_w, P.n, ms, t);
        break;
      }
    }
    envoyer(o);
  }
}

static void journal(const journal_t &j) {
  const uint32_t t = maintenant_ms();
  for (int o = 0; o < ORIGINES; o++) {
    puits_t &P = s_puits[o];
    if (!P.machine || !P.log) continue;
    if (!P.plafond_journal.available(t)) {
      P.plafond_journal.skip();
      continue;
    }
    if (!place_evenement(o, kPlacesPeriodique)) continue;  // frequents, comme les trames
    P.plafond_journal.take();
    logLine(s_w, P.n, t, j.src, j.alerte ? "alerte" : "notice", j.txt, P.plafond_journal.takeSkipped());
    envoyer(o);
  }
}

static bool une_session(void) {
  for (const puits_t &p : s_puits)
    if (p.machine) return true;
  return false;
}

static void tache_json(void *arg) {
  (void)arg;
  uint32_t prochain_tic = maintenant_ms();
  uint8_t tour = 0;
  for (;;) {
    const int32_t attente = (int32_t)(prochain_tic - maintenant_ms());
    evenement_t e;
    if (xQueueReceive(s_evenements, &e, attente > 0 ? pdMS_TO_TICKS(attente) : 0) == pdTRUE) {
      xSemaphoreTake(s_verrou, portMAX_DELAY);
      evenement(e);
      xSemaphoreGive(s_verrou);
      // Les evenements d'abord (ils ne passent pas par la file), mais le tic a son heure.
      if (!echu(maintenant_ms(), prochain_tic)) continue;
    }
    journal_t j;
    while (xQueueReceive(s_journal, &j, 0) == pdTRUE) {
      xSemaphoreTake(s_verrou, portMAX_DELAY);
      journal(j);
      xSemaphoreGive(s_verrou);
    }
    const uint32_t t = maintenant_ms();
    xSemaphoreTake(s_verrou, portMAX_DELAY);
    bool regard = false;
    for (int o = 0; o < ORIGINES; o++) {
      puits_t &P = s_puits[o];
      if (P.machine) {
        programmer(o, t);
        if (echu(t, P.prochain_regard)) {
          regard = true;
          P.prochain_regard = t + REGARD_MS;
        }
      }
    }
    if (regard && une_session()) regarder(t);
    // L'USB, puis les sessions distantes, qui partagent la file d'emission de net_udp
    // et son debit, a tour de role : deux instantanes simultanes avancent ensemble.
    tour = (uint8_t)(tour + 1);
    for (int k = 0; k < ORIGINES; k++) {
      const int o = k == 0 ? USB : 1 + (k - 1 + tour) % NET_UDP_SESSIONS;
      puits_t &P = s_puits[o];
      P.perdus += P.file.dropLate(t, o == USB ? RETARD_USB_MS : RETARD_DISTANT_MS);
      const Queued *q = P.file.front();
      if (!q) continue;
      // A distance, la ligne attend sa place dans la file de net_udp (10.3) : 7 places
      // libres pour une periodique, 2 pour une reponse ; sinon au tic suivant.
      if (o != USB && !P.file.frontReady(net_udp_libres())) continue;
      const Queued copie = *q;
      P.file.pop();
      former(o, copie);
    }
    xSemaphoreGive(s_verrou);
    prochain_tic = t + TIC_MS;
  }
}

// --- Commandes

static bool lire_ms(const char *texte, uint32_t min, uint32_t max, uint32_t *v) {
  return texte_lire_nombre(texte, v) && (*v == 0 || (*v >= min && *v <= max));
}

static bool hexa(const char *s, uint8_t *out, size_t n) {
  if (strlen(s) != 2 * n) return false;
  for (size_t i = 0; i < n; i++) {
    unsigned v = 0;
    for (int k = 0; k < 2; k++) {
      const char c = s[2 * i + k];
      const unsigned d = c >= '0' && c <= '9' ? (unsigned)(c - '0')
                         : c >= 'A' && c <= 'F' ? (unsigned)(c - 'A' + 10)
                         : c >= 'a' && c <= 'f' ? (unsigned)(c - 'a' + 10)
                                                : 16u;
      if (d > 15) return false;
      v = v << 4 | d;
    }
    out[i] = (uint8_t)v;
  }
  return true;
}

// Pourquoi `json cle` a echoue, pour la reponse (msg, 120 octets au plus) et la
// console texte.
static const char *raison_cle(bool efface, esp_err_t err, char *t, size_t n) {
  if (err == ESP_ERR_INVALID_STATE) return "acces par Thread non demarre (Matter non demarre) : rien n'a change";
  if (efface) {
    snprintf(t, n, "cle effacee de la memoire, pas de la NVS (%s) : elle reviendra au redemarrage",
             esp_err_to_name(err));
  } else {
    snprintf(t, n, "cle non creee (%s) : rien n'a change", esp_err_to_name(err));
  }
  return t;
}

// `json cle nouvelle <64 hexa>` et `json cle efface` (10.2), par l'USB seulement :
// hors de s_verrou (net_udp annonce les fins de session, qui le prennent). true : traitee.
static bool commande_cle(int o, uint32_t id, const char *vue, int argc, char **argv, uint32_t debut_ms) {
  if (argc < 2 || strcmp(argv[0], "json") || strcmp(argv[1], "cle")) return false;
  const bool nouvelle = argc == 4 && !strcmp(argv[2], "nouvelle");
  const bool efface = argc == 3 && !strcmp(argv[2], "efface");
  uint8_t alea[32];
  char cle[65] = {}, emp[9] = {}, raison[kMsgMax + 1];
  const char *erreur = nullptr;
  esp_err_t err = ESP_OK;
  if (o != USB) {
    erreur = "USB seulement";
  } else if (nouvelle && id && !s_puits[USB].machine) {
    // json cle nouvelle avec id : en mode machine seulement. Rien ne change.
    erreur = "json cle nouvelle avec id : en mode machine seulement (json 1)";
  } else if (nouvelle && hexa(argv[3], alea, sizeof(alea))) {
    err = net_udp_cle_nouvelle(alea, cle, emp);
    memset(alea, 0, sizeof(alea));
  } else if (efface) {
    err = net_udp_cle_effacer();
  } else {
    erreur = "json cle nouvelle <64 hexa> | json cle efface";
  }
  if (!erreur && err != ESP_OK) erreur = raison_cle(efface, err, raison, sizeof(raison));
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  if (id) {
    Reply r;
    r.id = id;
    r.cmd = vue;
    r.durMs = maintenant_ms() - debut_ms;
    if (erreur) {
      r.ok = false;
      r.code = err == ESP_OK ? "usage" : "erreur";
      r.msg = erreur;
    } else if (nouvelle) {
      r.key = cle;
      r.kid = emp;
    }
    reponse(o, r);
  } else if (erreur) {
    printf("erreur : %s\n", erreur);
  } else {
    // A la console, jamais la cle : seulement son empreinte.
    printf(nouvelle ? "ok cle UDP %s, port %u ouvert\n" : "ok cle UDP effacee%s, port %u ferme\n", emp, NET_UDP_PORT);
  }
  s_puits[o].derniere_cmd = maintenant_ms();
  xSemaphoreGive(s_verrou);
  memset(cle, 0, sizeof(cle));
  return true;
}

// La famille `json` (3.3). id 0 : sans reponse, texte pour un humain. Sous s_verrou.
static void commande_json(int o, uint32_t id, const char *vue, int argc, char **argv, uint32_t debut_ms) {
  static const char USAGE[] =
      "json [1 [bail <s>]|0|etat|hello|ping|periode|lampes|compteurs|reseau <ms>|log 0|1|trames 0|1|cle ...]";
  puits_t &P = s_puits[o];
  const uint32_t t = maintenant_ms();
  const char *sous = argc >= 2 ? argv[1] : "";
  uint32_t v = 0;
  const char *erreur = nullptr;
  if (argc == 1) {
    printf("json : mode %s, bail %u s, etat %" PRIu32 " ms, lampes %" PRIu32 " ms, compteurs %" PRIu32
           " ms, reseau %" PRIu32 " ms, log %s, trames %s ; lignes %" PRIu32 ", perdues %" PRIu32
           ", refusees %" PRIu32 "\n",
           P.machine ? "machine" : "texte", (unsigned)P.reglages.bailS, P.reglages.periodeMs, P.reglages.lampesMs,
           P.reglages.compteursMs, P.reglages.reseauMs, P.reglages.log ? "oui" : "non",
           P.reglages.trames ? "oui" : "non", P.n, perdus_de(o), s_rejets);
    for (int k = 1; k < ORIGINES; k++)
      if (s_puits[k].machine)
        printf("json : session distante %d en mode machine ; lignes %" PRIu32 ", perdues %" PRIu32 "\n", k,
               s_puits[k].n, s_puits[k].perdus);
  } else if (!strcmp(sous, "1")) {
    if (argc == 2 || (argc == 4 && !strcmp(argv[2], "bail") && lire_ms(argv[3], 10, 600, &v))) {
      entrer(o, argc == 4 ? (uint16_t)v : 30, t);
      if (id) {
        differer(o, id, vue, true, debut_ms);
        return;
      }
    } else {
      erreur = "json 1 [bail 0|10-600]";
    }
  } else if (!strcmp(sous, "0") && argc == 2) {
    if (id) repondre(o, id, vue, true, "ok", nullptr, debut_ms);
    if (P.machine) sortir(o, "commande", "json : mode machine coupe\r\n");
    return;
  } else if ((!strcmp(sous, "etat") || !strcmp(sous, "hello")) && argc == 2) {
    if (!strcmp(sous, "etat")) pousser_etat(o, t, false);
    else pousser_hello(o, t, false);
    if (id) {
      differer(o, id, vue, false, debut_ms);
      return;
    }
  } else if (!strcmp(sous, "ping") && argc == 2) {
    P.dernier_rx = t;
    if (id) {
      Reply r;
      r.id = id;
      r.cmd = vue;
      r.durMs = t - debut_ms;
      r.hasLease = true;
      r.leaseS = P.reglages.bailS;
      r.upS = up_s();
      reponse(o, r);
      return;
    }
  } else if (argc == 3 && !strcmp(sous, "periode")) {
    if (lire_ms(argv[2], 200, 60000, &v)) {
      P.reglages.periodeMs = v;
      P.prochain_etat = P.prochain_hb = t;
    } else {
      erreur = "json periode <0|200-60000 ms>";
    }
  } else if (argc == 3 && !strcmp(sous, "lampes")) {
    if (lire_ms(argv[2], 1000, 60000, &v)) {
      P.reglages.lampesMs = v;
      P.prochain_lampes = t;
    } else {
      erreur = "json lampes <0|1000-60000 ms>";
    }
  } else if (argc == 3 && !strcmp(sous, "compteurs")) {
    if (lire_ms(argv[2], 200, 60000, &v)) {
      P.reglages.compteursMs = v;
      P.prochain_compteurs = t;
    } else {
      erreur = "json compteurs <0|200-60000 ms>";
    }
  } else if (argc == 3 && !strcmp(sous, "reseau")) {
    if (lire_ms(argv[2], 1000, 60000, &v)) {
      P.reglages.reseauMs = v;
      P.prochain_reseau = t;
    } else {
      erreur = "json reseau <0|1000-60000 ms>";
    }
  } else if (argc == 3 && !strcmp(sous, "log") && (!strcmp(argv[2], "0") || !strcmp(argv[2], "1"))) {
    P.reglages.log = !strcmp(argv[2], "1");
    P.log = P.reglages.log;
    recompter();
  } else if (argc == 3 && !strcmp(sous, "trames") && (!strcmp(argv[2], "0") || !strcmp(argv[2], "1"))) {
    P.reglages.trames = !strcmp(argv[2], "1");
    P.trames = P.reglages.trames;
    P.fin_trames = t + TRAMES_DISTANT_MS;
    recompter();
  } else {
    erreur = USAGE;
  }
  if (id) {
    repondre(o, id, vue, !erreur, erreur ? "usage" : "ok", erreur, debut_ms);
  } else if (erreur) {
    printf("erreur : %s\n", erreur);
  } else if (argc > 1) {
    printf("ok json %s\n", sous);
  }
}

int json_pont_commande(int argc, char **argv) {
  if (commande_cle(USB, 0, "", argc, argv, maintenant_ms())) return 0;
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  commande_json(USB, 0, "", argc, argv, maintenant_ms());
  xSemaphoreGive(s_verrou);
  return 0;
}

// `lampe <n> on|off|niveau <0-1000>` : true et l'ordre rempli ; *usage : la
// ligne en a la forme, mais un argument est invalide.
static bool ordre_de_lampe(int argc, char **argv, int *lampe, int8_t *marche, int32_t *intensite, bool *usage) {
  *usage = false;
  if (argc < 3 || strcmp(argv[0], "lampe")) return false;
  const bool on_off = argc == 3 && (!strcmp(argv[2], "on") || !strcmp(argv[2], "off"));
  const bool niveau = argc == 4 && !strcmp(argv[2], "niveau");
  if (!on_off && !niveau) return false;
  uint32_t n = 0, v = 0;
  if (!texte_lire_nombre(argv[1], &n) || n < 1 || n > s_cfg->liste.n ||
      (niveau && (!texte_lire_nombre(argv[3], &v) || v > TELINK_INTENSITE_MAX))) {
    *usage = true;
    return true;
  }
  *lampe = (int)n - 1;
  *marche = on_off ? !strcmp(argv[2], "on") : -1;
  *intensite = niveau ? (int32_t)v : -1;
  return true;
}

// La commande telle que la reponse la cite : jamais une cle (mesh cles, json cle
// nouvelle, avec ou sans guillemets), puis tronquee. Jugee sur les mots decoupes.
static void citer(const char *cmd, int argc, char **argv, char vue[kCmdTextMax + 1]) {
  char masquee[kCmdMax + 1];
  snprintf(masquee, sizeof(masquee), "%s", cmd);
  maskCmd(masquee);
  if (argc >= 1 && (!strncmp(argv[0], "mesh cles", 9) || (!strcmp(argv[0], "mesh") && argc >= 2 && !strncmp(argv[1], "cles", 4))))
    snprintf(masquee, sizeof(masquee), "mesh cles");
  if (argc >= 1 && (!strncmp(argv[0], "json cle", 8) || (!strcmp(argv[0], "json") && argc >= 2 && !strncmp(argv[1], "cle", 3))))
    snprintf(masquee, sizeof(masquee), argc >= 3 && !strcmp(argv[2], "nouvelle") ? "json cle nouvelle" : "json cle");
  copyCmd(vue, masquee);
}

// Ordre de lampe asynchrone (6.2), avec un id. Sous s_verrou. true : traite.
static bool ordre_asynchrone(int o, uint32_t id, const char *vue, int argc, char **argv, uint32_t debut) {
  int lampe = 0;
  int8_t marche = -1;
  int32_t intensite = -1;
  bool usage = false;
  if (!ordre_de_lampe(argc, argv, &lampe, &marche, &intensite, &usage)) return false;
  if (usage) {
    char msg[64];
    snprintf(msg, sizeof(msg), "lampe <1-%u> on|off|niveau <0-1000>", (unsigned)s_cfg->liste.n);
    repondre(o, id, vue, false, "usage", msg, debut);
  } else {
    // L'id part avec l'ordre, et la marque de cette session (origine, generation) :
    // l'evenement ordre qui le finira le portera, vers elle seulement (7.1), pas vers
    // une session qui aurait pris sa place entre-temps.
    const bool m = marche == 1;
    const uint16_t v = (uint16_t)intensite;
    if (tache_lampes_ordre_id(lampe, marche >= 0 ? &m : nullptr, intensite >= 0 ? &v : nullptr, id, marque(o))) {
      Reply r;
      r.id = id;
      r.cmd = vue;
      r.code = "accepte";
      r.suite = Reply::SuiteOrder;
      r.lampe = (uint8_t)(lampe + 1);
      r.durMs = maintenant_ms() - debut;
      reponse(o, r);
    } else {
      repondre(o, id, vue, false, "erreur", "file des lampes pleine", debut);
    }
  }
  s_puits[o].derniere_cmd = maintenant_ms();
  return true;
}

void json_pont_executer(char *ligne, bool trop_long) {
  const uint32_t debut = maintenant_ms();
  uint32_t id = 0;
  char *cmd = ligne;
  const bool a_id = parseIdPrefix(ligne, &id, &cmd);
  // Ligne vide (l'effacement 0x15 + LF que l'app envoie a l'ouverture) : rien a faire.
  if (!a_id && !trop_long && strspn(cmd, " ") == strlen(cmd)) return;
  // Les mots de la commande (esp_console_run decoupe une copie de son cote). Decoupes avant
  // la reponse : les guillemets sont retires ici comme par la console, et la commande citee
  // se juge sur ses mots, pas sur la ligne brute. Tache de la console seulement.
  static char copie[kCmdMax + 1];
  static char *argv[8];
  snprintf(copie, sizeof(copie), "%s", cmd);
  const int argc = (int)esp_console_split_argv(copie, argv, sizeof(argv) / sizeof(argv[0]));
  char vue[kCmdTextMax + 1];
  citer(cmd, argc, argv, vue);
  puits_t &P = s_puits[USB];
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  P.dernier_rx = debut;
  const char *refus = nullptr, *code = nullptr;
  if (trop_long) {
    refus = "ligne de plus de 127 octets : rien n'est execute";
    code = "trop_long";
  } else if (P.machine && !P.cadence.allow(debut)) {
    refus = "plus de 20 lignes par seconde : rien n'est execute";
    code = "cadence";
  }
  if (refus) {
    s_rejets++;
    if (a_id) repondre(USB, id, vue, false, code, refus, debut);
    xSemaphoreGive(s_verrou);
    if (!a_id) printf("erreur : %s\n", refus);
    return;
  }
  xSemaphoreGive(s_verrou);
  if (commande_cle(USB, a_id ? id : 0, vue, argc, argv, debut)) return;
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  if (argc >= 1 && !strcmp(argv[0], "json")) {
    commande_json(USB, a_id ? id : 0, vue, argc, argv, debut);
    P.derniere_cmd = maintenant_ms();
    xSemaphoreGive(s_verrou);
    return;
  }
  if (a_id && ordre_asynchrone(USB, id, vue, argc, argv, debut)) {
    xSemaphoreGive(s_verrou);
    return;
  }
  xSemaphoreGive(s_verrou);
  // Toute autre commande : debut, son texte, fin (6.2), une commande a texte a la fois.
  // Rien sous s_verrou pendant qu'elle tourne : la tache json continue d'emettre. L'id
  // de la commande entre dans le bloc sante avec le debut, et en sort avec la fin.
  xSemaphoreTake(s_commande, portMAX_DELAY);
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  P.en_commande = true;
  if (a_id) {
    P.cmd_id = id;
    Reply r;
    r.id = id;
    r.fin = false;
    r.cmd = vue;
    r.code = "en_cours";
    reponse(USB, r);
  }
  xSemaphoreGive(s_verrou);
  int ret = 0;
  const esp_err_t err = argc >= 1 ? esp_console_run(cmd, &ret) : ESP_ERR_INVALID_ARG;
  if (err == ESP_ERR_NOT_FOUND) printf("Commande inconnue : \"%s\" (help)\n", argv[0]);
  fflush(stdout);  // le texte de la commande passe avant la reponse fin
  xSemaphoreGive(s_commande);
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  P.derniere_cmd = maintenant_ms();
  P.en_commande = false;
  P.cmd_id = 0;
  if (a_id) {
    const bool inconnue = err != ESP_OK;
    const bool ok = !inconnue && ret == 0;
    repondre(USB, id, vue, ok, inconnue ? "inconnue" : ok ? "ok" : "erreur", nullptr, debut);
  }
  // Une commande mesh reussie a pu changer la configuration du Mesh (5.2).
  if (err == ESP_OK && ret == 0 && argc >= 1 && !strcmp(argv[0], "mesh"))
    for (puits_t &p : s_puits)
      if (p.machine) p.file.push(Item::ConfigMesh, maintenant_ms(), false);
  xSemaphoreGive(s_verrou);
}

void json_pont_lire(void) {
  uint8_t octets[64];
  const int n = usb_serial_jtag_read_bytes(octets, sizeof(octets), pdMS_TO_TICKS(200));
  if (n <= 0) return;
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  s_puits[USB].dernier_rx = maintenant_ms();
  xSemaphoreGive(s_verrou);
  for (int i = 0; i < n; i++) {
    if (s_assembleur.feed(octets[i]) != LineAssembler::Ev::Line) continue;
    json_pont_executer(s_assembleur.text(), s_assembleur.tooLong());
    s_assembleur.reset();
  }
}

bool json_pont_machine(void) { return s_puits[USB].machine; }

// --- A distance (10.4)

// Puits remis a zero, a la generation gen de net_udp (session neuve, oubliee, cle
// changee) : rien de la session d'avant ne lui reste. Sous s_verrou.
static void remettre(int o, uint32_t gen) {
  puits_t &P = s_puits[o];
  P.machine = P.log = P.trames = false;
  P.reglages = sessionDistante();
  P.generation = gen;
  P.en_commande = false;
  P.cmd_id = 0;
  P.file.clear();
  memset(P.differees, 0, sizeof(P.differees));
  P.cache.clear();
  P.id_max = 0;
  memset(P.en_attente, 0, sizeof(P.en_attente));
  P.n = P.perdus = 0;
  P.cadence = Cadence();
  P.plafond_journal = RateCap(PLAFOND_DISTANT);
  P.plafond_trames = RateCap(PLAFOND_DISTANT);
  recompter();
}

void json_pont_distant_fin(uint8_t slot, uint32_t gen) {
  if (slot >= NET_UDP_SESSIONS || !s_verrou) return;
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  // Une fin plus ancienne que la generation du puits (annoncee par une autre tache,
  // arrivee apres la suivante) ne defait pas la session neuve.
  if ((int32_t)(gen - s_puits[1 + slot].generation) > 0) remettre(1 + slot, gen);
  xSemaphoreGive(s_verrou);
}

void json_pont_distant_ligne(uint8_t slot, uint32_t gen, char *ligne, size_t n) {
  if (slot >= NET_UDP_SESSIONS) return;
  const int o = 1 + slot;
  puits_t &P = s_puits[o];
  const uint32_t debut = maintenant_ms();
  uint32_t id = 0;
  char *cmd = ligne;
  const bool a_id = parseIdPrefix(ligne, &id, &cmd);
  char copie[kCmdMax + 1];
  char *argv[8];
  snprintf(copie, sizeof(copie), "%s", cmd);
  const int argc = (int)esp_console_split_argv(copie, argv, sizeof(argv) / sizeof(argv[0]));
  char vue[kCmdTextMax + 1];
  citer(cmd, argc, argv, vue);
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  if (P.generation != gen) {  // session deja remplacee ou tombee : plus pour ce puits
    xSemaphoreGive(s_verrou);
    return;
  }
  P.dernier_rx = debut;
  if (!a_id) {  // a distance, toute ligne porte un id (10.4)
    s_rejets++;
    xSemaphoreGive(s_verrou);
    return;
  }
  // Un id deja traite : la meme reponse, sans executer de nouveau ; plus ancien que
  // le cache : deja_traite.
  const Reply *deja = P.cache.find(id);
  if (deja) {
    Reply r = *deja;
    reply(s_w, P.n, maintenant_ms(), r);
    envoyer(o);
    xSemaphoreGive(s_verrou);
    return;
  }
  if (en_attente(P, id)) {  // renvoi d'une commande encore en cours : sa reponse viendra
    xSemaphoreGive(s_verrou);
    return;
  }
  if (id <= P.id_max) {
    repondre(o, id, vue, false, "deja_traite", "id deja traite : reponse oubliee", debut);
    xSemaphoreGive(s_verrou);
    return;
  }
  P.id_max = id;
  // Nouvelle commande admise, permise ou refusee ensuite : la session sert de nouveau,
  // meme apres json 0 (qui, s'il est cette commande, la termine ensuite a son tour).
  // Jamais pour un renvoi, ni pour une ligne sans id.
  net_udp_reprendre(slot, gen);
  uint32_t *place = &P.en_attente[0];  // la plus ancienne attente cede la place
  for (uint32_t &a : P.en_attente)
    if (!a || a < *place) place = &a;
  *place = id;
  const char *refus = nullptr, *code = nullptr;
  if (n > kCmdMax) {
    refus = "ligne de plus de 127 octets : rien n'est execute";
    code = "trop_long";
  } else if (!P.cadence.allow(debut)) {
    refus = "plus de 20 lignes par seconde : rien n'est execute";
    code = "cadence";
  } else if ((refus = refusDistant(argc, argv)) != nullptr) {
    code = "interdite";
  }
  if (refus) {
    s_rejets++;
    repondre(o, id, vue, false, code, refus, debut);
    xSemaphoreGive(s_verrou);
    return;
  }
  if (!strcmp(argv[0], "json")) {
    commande_json(o, id, vue, argc, argv, debut);
    P.derniere_cmd = maintenant_ms();
    xSemaphoreGive(s_verrou);
    return;
  }
  if (ordre_asynchrone(o, id, vue, argc, argv, debut)) {
    xSemaphoreGive(s_verrou);
    return;
  }
  // Commande a texte permise (lectures, masquer, led) : la tache distant l'execute.
  travail_t w = {};
  w.origine = (uint8_t)o;
  w.generation = P.generation;
  w.id = id;
  w.debut_ms = debut;
  snprintf(w.cmd, sizeof(w.cmd), "%s", cmd);
  memcpy(w.vue, vue, sizeof(w.vue));
  if (xQueueSend(s_travaux, &w, 0) != pdTRUE) repondre(o, id, vue, false, "erreur", "commande deja en cours", debut);
  xSemaphoreGive(s_verrou);
}

// Sortie standard de la tache distant pendant esp_console_run, gardee ici ligne par
// ligne (OutputLines, json_ligne.h : 4 096 octets, lignes coupees a kLogTextMax). Le
// crochet ne prend aucun verrou et n'attend jamais : la commande tient peut-etre un
// verrou (celui des lampes dans mesh lampe <n> masquer, celui de la pile Matter), et
// son journal (ESP_LOG, par vprintf) passe par cette sortie ; or la tache json prend
// le verrou des lampes en tenant s_verrou. Les lignes partent apres la commande,
// sortie rendue ; au-dela de 4 096 octets, une derniere ligne dit que la suite manque.
// Tache distant seulement.
static OutputLines s_sortie;

static ssize_t sortie_ecrire(void *cookie, const char *buf, size_t n) {
  ((OutputLines *)cookie)->write(buf, n);
  return (ssize_t)n;
}

// La tache distant attend une place dans la file d'emission de net_udp (1 s au plus)
// avant chacune de ses lignes : la sortie d'une commande va plus vite que le debit de
// Thread. Jamais sous s_verrou.
static void attendre_place(void) {
  for (int k = 0; k < 100 && net_udp_libres() < kPlacesLigne; k++) vTaskDelay(pdMS_TO_TICKS(10));
}

// Une ligne texte du travail w : sa place d'abord, puis formee et envoyee sous
// s_verrou si la session est encore la sienne. false : session partie.
static bool texte_distant(const travail_t &w, const char *txt) {
  attendre_place();
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  puits_t &P = s_puits[w.origine];
  const bool vivante = P.generation == w.generation;
  if (vivante) {
    textLine(s_w, P.n, maintenant_ms(), w.id, txt);
    envoyer(w.origine);
  }
  xSemaphoreGive(s_verrou);
  return vivante;
}

// Les commandes a texte venues de Thread, une a la fois avec la console : reponse
// debut, la commande (sa sortie gardee dans s_sortie), une ligne texte par ligne
// gardee, puis reponse fin. La sortie standard n'est changee que pendant
// esp_console_run, hors de s_verrou ; sous s_verrou, rien ne s'imprime ni ne se
// journalise (net_udp_envoyer ne poste rien a OpenThread).
static void tache_distant(void *arg) {
  (void)arg;
  static travail_t w;
  for (;;) {
    if (xQueueReceive(s_travaux, &w, portMAX_DELAY) != pdTRUE) continue;
    const int o = w.origine;
    xSemaphoreTake(s_commande, portMAX_DELAY);
    attendre_place();
    xSemaphoreTake(s_verrou, portMAX_DELAY);
    puits_t &P = s_puits[o];
    bool vivante = P.generation == w.generation;
    if (vivante) {
      P.en_commande = true;
      P.cmd_id = w.id;
      Reply r;
      r.id = w.id;
      r.fin = false;
      r.cmd = w.vue;
      r.code = "en_cours";
      reponse(o, r);
    }
    xSemaphoreGive(s_verrou);
    int ret = 0;
    esp_err_t err = ESP_FAIL;
    s_sortie.clear();
    if (vivante) {
      // La sortie standard est propre a chaque tache (ESP-IDF) : seule celle-ci change.
      cookie_io_functions_t f = {};
      f.write = sortie_ecrire;
      FILE *flux = fopencookie(&s_sortie, "w", f);
      FILE *ancien = stdout;
      if (flux) {
        setvbuf(flux, NULL, _IOLBF, 128);
        stdout = flux;
      }
      err = esp_console_run(w.cmd, &ret);
      if (flux) {
        fflush(flux);
        stdout = ancien;
        fclose(flux);
      }
      s_sortie.flush();
    }
    xSemaphoreGive(s_commande);
    // Le texte, la commande sortie de ses verrous ; plus rien vers une session partie.
    size_t pos = 0;
    for (const char *l = s_sortie.next(&pos); vivante && l; l = s_sortie.next(&pos)) vivante = texte_distant(w, l);
    if (vivante && s_sortie.lost()) vivante = texte_distant(w, "(sortie tronquee)");
    if (vivante) attendre_place();
    xSemaphoreTake(s_verrou, portMAX_DELAY);
    if (vivante && P.generation == w.generation) {
      P.derniere_cmd = maintenant_ms();
      P.en_commande = false;
      P.cmd_id = 0;
      const bool inconnue = err != ESP_OK;
      const bool ok = !inconnue && ret == 0;
      repondre(o, w.id, w.vue, ok, inconnue ? "inconnue" : ok ? "ok" : "erreur", nullptr, w.debut_ms);
    }
    xSemaphoreGive(s_verrou);
  }
}

bool json_pont_tache_distante(void) { return s_tache_distant && xTaskGetCurrentTaskHandle() == s_tache_distant; }

// --- Evenements, depuis les autres taches

static void poster(const evenement_t &e) {
  if (!s_evenements) return;
  bool session = false;
  for (const puits_t &p : s_puits) session = session || p.machine;
  if (session && xQueueSend(s_evenements, &e, 0) != pdTRUE) __atomic_fetch_add(&s_evenements_perdus, 1, __ATOMIC_RELAXED);
}

void json_pont_ordre(int lampe, lampes_signal_t signal, uint32_t delai_ms, uint8_t essai, const uint32_t *ids,
                     const uint8_t *origines, uint8_t n_ids, uint32_t ids_perdus) {
  evenement_t e = {};
  e.type = EV_ORDRE;
  e.lampe = (int8_t)lampe;
  e.a = (uint8_t)signal;
  e.b = essai;
  e.delai_ms = delai_ms;
  e.n_ids = n_ids > kIdsMax ? kIdsMax : n_ids;
  for (uint8_t i = 0; i < e.n_ids; i++) {
    e.ids[i] = ids[i];
    e.origines[i] = origines[i];
  }
  e.ids_perdus = ids_perdus;
  poster(e);
}

void json_pont_alerte_releves(int lampe, bool manque, uint8_t pour_cent) {
  evenement_t e = {};
  e.type = EV_RELEVES;
  e.lampe = (int8_t)lampe;
  e.a = manque;
  e.b = pour_cent;
  poster(e);
}

void json_pont_alerte_mesh(diagnostic_t etat) {
  evenement_t e = {};
  e.type = EV_MESH;
  e.a = (uint8_t)etat;
  poster(e);
}

void json_pont_lampe(int lampe, json_lampe_t quoi, uint16_t endpoint) {
  evenement_t e = {};
  e.type = EV_LAMPE;
  e.lampe = (int8_t)lampe;
  e.a = (uint8_t)quoi;
  e.endpoint = endpoint;
  poster(e);
}

void json_pont_led(const char *motif, const char *avant, bool test, uint32_t depuis_ms) {
  evenement_t e = {};
  e.type = EV_LED;
  e.motif = motif;
  e.avant = avant;
  e.a = test;
  e.delai_ms = depuis_ms;
  poster(e);
}

bool json_pont_trames_actives(void) { return s_trames_actives; }

void json_pont_trame(bool rx, const char *quoi, int lampe, int8_t marche, int32_t intensite, uint8_t essai) {
  if (!s_trames_actives) return;
  evenement_t e = {};
  e.type = EV_TRAME;
  e.lampe = (int8_t)lampe;
  e.a = rx;
  e.b = essai;
  e.motif = quoi;
  e.marche = marche;
  e.intensite = intensite;
  poster(e);
}

void json_pont_annoncer(const char *src, bool alerte, const char *format, ...) {
  char txt[192];
  va_list ap;
  va_start(ap, format);
  vsnprintf(txt, sizeof(txt), format, ap);
  va_end(ap);
  // En message log pour chaque session qui l'a demande ; en texte sur l'USB tant que
  // l'USB n'est pas lui-meme en mode machine avec json log 1.
  const bool usb_log = s_puits[USB].machine && s_puits[USB].log;
  if (s_log_actif && s_journal) {
    journal_t j;
    j.src = src;
    j.alerte = alerte;
    const size_t n = strnlen(txt, sizeof(j.txt) - 1);  // log.txt : 127 octets au plus (7.5)
    memcpy(j.txt, txt, n);
    j.txt[n] = 0;
    if (xQueueSend(s_journal, &j, 0) != pdTRUE) __atomic_fetch_add(&s_evenements_perdus, 1, __ATOMIC_RELAXED);
  }
  if (!usb_log) printf("%s\n", txt);
}

esp_err_t json_pont_demarrer(const amaran_config_t *cfg) {
  s_cfg = cfg;
  // Aucune radio n'est encore active : le generateur tire de vrai bruit (comme Halo).
  bootloader_random_enable();
  s_boot = esp_random();
  bootloader_random_disable();
  s_verrou = xSemaphoreCreateMutex();
  s_commande = xSemaphoreCreateMutex();
  s_evenements = xQueueCreate(FILE_EVENEMENTS, sizeof(evenement_t));
  s_journal = xQueueCreate(FILE_JOURNAL, sizeof(journal_t));
  s_travaux = xQueueCreate(FILE_TRAVAUX, sizeof(travail_t));
  if (!s_verrou || !s_commande || !s_evenements || !s_journal || !s_travaux) return ESP_ERR_NO_MEM;
  for (int o = 0; o < ORIGINES; o++) {
    s_puits[o].reglages = o == USB ? Session() : sessionDistante();
    if (o != USB) {
      s_puits[o].plafond_journal = RateCap(PLAFOND_DISTANT);
      s_puits[o].plafond_trames = RateCap(PLAFOND_DISTANT);
    }
  }
  // Basse priorite : les lampes, Matter et la console passent avant.
  if (xTaskCreate(tache_json, "json", 4096, NULL, 1, NULL) != pdPASS) return ESP_ERR_NO_MEM;
  return xTaskCreate(tache_distant, "distant", 6144, NULL, 1, &s_tache_distant) == pdPASS ? ESP_OK : ESP_ERR_NO_MEM;
}
