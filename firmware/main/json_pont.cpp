// Mode JSON du pont (voir json_pont.h). Sur le modele de json_mode.cpp du pont
// Halo (commit e114cd5), pour ESP-IDF : la console lit et execute dans sa tache,
// la tache json forme les lignes periodiques et les evenements. Une ligne se
// forme et s'ecrit sous s_verrou, d'un seul appel au pilote de l'USB, sans
// attendre (2.3).
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
#include "pont_matter.h"
#include "socle.h"
#include "tache_lampes.h"
#include "texte.h"

using namespace jsonp;

static_assert(JSON_PONT_CMD_MAX == kCmdMax, "json_pont.h et json_ligne.h : meme longueur de ligne");
static_assert(JSON_PONT_IDS_MAX == kIdsMax, "json_pont.h et json_amaran.h : meme nombre d'id par ordre");

#define TIC_MS 10            // une ligne de la file par tic (2.3)
#define REGARD_MS 100        // changements des lampes
#define BATTEMENT_MS 2000    // hb, quand les etat sont coupes ou lents (3.5)
#define FILE_EVENEMENTS 32   // 32 x sizeof(evenement_t) en RAM
#define FILE_JOURNAL 6
#define PLAFOND_JOURNAL 20   // log par seconde (7.5)
#define DIFFEREES 4          // reponses qui attendent la fin d'un instantane

typedef enum { EV_ORDRE, EV_RELEVES, EV_MESH, EV_LAMPE, EV_LED } ev_type_t;

typedef struct {
  ev_type_t type;
  int8_t lampe;
  uint8_t a, b;         // ordre : signal, essai ; releves : manque, part ; mesh : diag ; lampe : quoi
  uint8_t n_ids;
  uint16_t endpoint;
  uint32_t delai_ms;    // ordre ; led : depuis_ms
  uint32_t ids[kIdsMax];
  uint32_t ids_perdus;
  const char *motif, *avant;  // led
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

static const amaran_config_t *s_cfg;
static SemaphoreHandle_t s_verrou;  // session, file, ecrivain, id en attente de reponse
static QueueHandle_t s_evenements, s_journal;
static uint32_t s_boot;

// Session : sous s_verrou ; s_machine et s_log se lisent aussi sans lui.
static volatile bool s_machine, s_log;
static Session s_reglages;
static uint32_t s_dernier_rx, s_derniere_cmd;
// Commande de la console en cours : le bail ne court pas (la console ne lit plus
// l'USB), et le bloc sante porte son id (une reponse fin perdue s'y voit, 6.2).
static bool s_en_commande;
static uint32_t s_cmd_id;
static uint32_t s_prochain_etat, s_prochain_lampes, s_prochain_compteurs, s_prochain_reseau, s_prochain_hb,
    s_prochain_regard;
static Queue s_file;
static differee_t s_differees[DIFFEREES];
static Cadence s_cadence;
static RateCap s_plafond_journal(PLAFOND_JOURNAL);
static resume_t s_resumes[LISTE_CAPACITE];

// Ecrivain : une ligne a la fois, sous s_verrou.
static Writer s_w;
static uint32_t s_n;
static uint32_t s_perdus, s_trop_longs, s_rejets;
// Evenements refuses par une file pleine, postes depuis plusieurs taches : increment atomique.
static volatile uint32_t s_evenements_perdus;

// Copies de l'etat des lampes, relues sous s_verrou quand une ligne en a besoin.
static lampes_t s_lampes;
static liste_t s_liste;

static LineAssembler s_assembleur;  // tache de la console

static uint32_t maintenant_ms(void) { return (uint32_t)(esp_timer_get_time() / 1000); }
static bool echu(uint32_t t, uint32_t echeance) { return (int32_t)(t - echeance) >= 0; }

// --- Ecriture (2.3)

// Tout ou rien, sans attendre ; une seconde chance une milliseconde plus tard, si
// une autre tache tenait le pilote (son verrou d'emission).
static bool ecrire(const void *p, size_t n) {
  if (usb_serial_jtag_write_bytes(p, n, 0) == (int)n) return true;
  vTaskDelay(1);
  return usb_serial_jtag_write_bytes(p, n, 0) == (int)n;
}

// La ligne formee dans s_w : n consomme, ecrite ou comptee perdue. Sous s_verrou.
static void envoyer(void) {
  s_n++;
  if (!s_w.finish()) {
    s_trop_longs++;
    return;
  }
  if (!ecrire(s_w.data(), s_w.size())) s_perdus++;
}

// Texte du protocole (fin de session) : meme chemin, sans attendre. Sous s_verrou.
static void texte(const char *t) {
  if (!ecrire(t, strlen(t))) s_perdus++;
}

static void reponse(const Reply &r) {
  reply(s_w, s_n, maintenant_ms(), r);
  envoyer();
}

static void repondre(uint32_t id, const char *cmd, bool ok, const char *code, const char *msg, uint32_t debut_ms) {
  Reply r;
  r.id = id;
  r.cmd = cmd;
  r.ok = ok;
  r.code = code;
  r.msg = msg;
  r.durMs = maintenant_ms() - debut_ms;
  reponse(r);
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

static void former(const Queued &q) {
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
      h.session = s_reglages;
      helloBase(s_w, s_n, ms, h);
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
      helloId(s_w, s_n, ms, h);
      break;
    }
    case Item::ConfigCatalogue:
      configCatalogue(s_w, s_n, ms);
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
      configMesh(s_w, s_n, ms, c);
      break;
    }
    case Item::ConfigLampe:
      relire_lampes();
      if (q.arg >= s_liste.n) return;
      configLampe(s_w, s_n, ms, q.arg, s_liste.lampes[q.arg]);
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
      etatPont(s_w, s_n, ms, e);
      break;
    }
    case Item::EtatLampe: {
      relire_lampes();
      const int i = q.arg;
      if (i >= s_lampes.n || i >= s_liste.n) return;
      resumer(i, &s_resumes[i]);
      etatLampe(s_w, s_n, ms, i, s_lampes.lampes[i], s_liste.lampes[i], s_resumes[i].endpoint,
                lampes_part_repondue(&s_lampes, i));
      break;
    }
    case Item::EtatSante: {
      EtatSante e;
      e.boot = s_boot;
      e.upS = up_s();
      e.cmdId = s_cmd_id;
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
      e.perdus = s_perdus + s_evenements_perdus;
      e.tropLongs = s_trop_longs;
      e.rejets = s_rejets;
      etatSante(s_w, s_n, ms, e);
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
      compteursMesh(s_w, s_n, ms, c);
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
      r.codeManuel = pont.code_manuel;
      r.qr = pont.qr;
      reseauMatter(s_w, s_n, ms, r);
      break;
    }
    case Item::NetThread:
      pont_lire(&pont);
      reseauThread(s_w, s_n, ms, pont.role, pont.thread_attache);
      break;
    case Item::Heartbeat:
      heartbeat(s_w, s_n, ms, s_boot, up_s(), s_perdus + s_evenements_perdus, s_cmd_id);
      break;
    case Item::Reply: {
      differee_t *d = &s_differees[q.arg % DIFFEREES];
      if (!d->utilisee) return;
      Reply r;
      r.id = d->id;
      r.cmd = d->cmd;
      r.durMs = ms - d->debut_ms;
      r.hasLease = d->bail;
      r.leaseS = s_reglages.bailS;
      r.upS = up_s();
      d->utilisee = false;
      reply(s_w, s_n, ms, r);
      break;
    }
  }
  envoyer();
}

// --- Session. Sous s_verrou.

static void pousser_hello(uint32_t t, bool session) {
  s_file.push(Item::HelloBase, t, session);
  s_file.push(Item::HelloId, t, session);
  s_file.push(Item::ConfigCatalogue, t, session);
  s_file.push(Item::ConfigMesh, t, session);
  for (uint8_t i = 0; i < s_cfg->liste.n; i++) s_file.push(Item::ConfigLampe, t, session, i);
}

static void pousser_etat(uint32_t t, bool session) {
  s_file.push(Item::EtatPont, t, session);
  for (uint8_t i = 0; i < s_cfg->liste.n; i++) s_file.push(Item::EtatLampe, t, session, i);
  s_file.push(Item::EtatSante, t, session);
  s_file.push(Item::CptMesh, t, session);
  s_file.push(Item::NetMatter, t, session);
  s_file.push(Item::NetThread, t, session);
}

// Reponse fin apres les lignes en file. Sans place : tout de suite.
static void differer(uint32_t id, const char *cmd, bool bail, uint32_t debut_ms) {
  for (uint8_t k = 0; k < DIFFEREES; k++) {
    differee_t *d = &s_differees[k];
    if (d->utilisee) continue;
    d->utilisee = true;
    d->id = id;
    d->debut_ms = debut_ms;
    d->bail = bail;
    copyCmd(d->cmd, cmd);
    if (s_file.push(Item::Reply, maintenant_ms(), false, k)) return;
    d->utilisee = false;
    break;
  }
  Reply r;
  r.id = id;
  r.cmd = cmd;
  r.durMs = maintenant_ms() - debut_ms;
  r.hasLease = bail;
  r.leaseS = s_reglages.bailS;
  r.upS = up_s();
  reponse(r);
}

static void entrer(uint16_t bail_s, uint32_t t) {
  s_file.dropSession();
  s_reglages = Session();
  s_reglages.bailS = bail_s;
  s_log = false;
  s_dernier_rx = s_derniere_cmd = t;
  s_prochain_etat = t + s_reglages.periodeMs;
  s_prochain_lampes = t + s_reglages.lampesMs;
  s_prochain_compteurs = t + s_reglages.compteursMs;
  s_prochain_reseau = t + s_reglages.reseauMs;
  s_prochain_hb = s_prochain_regard = t;
  memset(s_resumes, 0, sizeof(s_resumes));
  s_assembleur.reset();
  s_machine = true;
  pousser_hello(t, true);
  pousser_etat(t, true);
}

static void sortir(const char *cause, const char *message) {
  sessionEnd(s_w, s_n, maintenant_ms(), cause);
  envoyer();
  s_machine = false;
  s_log = false;
  s_file.dropSession();
  texte(message);
}

// Les lignes etat lampe dont ce qu'elles montrent a change.
static void regarder(uint32_t t) {
  relire_lampes();
  for (int i = 0; i < s_lampes.n && i < s_liste.n; i++) {
    resume_t r;
    resumer(i, &r);
    if (memcmp(&r, &s_resumes[i], sizeof(r)) != 0) s_file.push(Item::EtatLampe, t, true, (uint8_t)i);
  }
}

static void programmer(uint32_t t) {
  if (!s_en_commande && leaseExpired(t, s_dernier_rx, s_derniere_cmd, s_reglages.bailS)) {
    char m[80];
    snprintf(m, sizeof(m), "json : mode machine coupe (hote muet depuis %u s)\r\n", (unsigned)s_reglages.bailS);
    sortir("bail", m);
    return;
  }
  if (s_reglages.periodeMs && echu(t, s_prochain_etat)) {
    s_file.push(Item::EtatPont, t, true);
    s_file.push(Item::EtatSante, t, true);
    s_prochain_etat = t + s_reglages.periodeMs;
  }
  if (s_reglages.lampesMs && echu(t, s_prochain_lampes)) {
    for (uint8_t i = 0; i < s_cfg->liste.n; i++) s_file.push(Item::EtatLampe, t, true, i);
    s_prochain_lampes = t + s_reglages.lampesMs;
  }
  if (echu(t, s_prochain_regard)) {
    regarder(t);
    s_prochain_regard = t + REGARD_MS;
  }
  if (s_reglages.compteursMs && echu(t, s_prochain_compteurs)) {
    s_file.push(Item::CptMesh, t, true);
    s_prochain_compteurs = t + s_reglages.compteursMs;
  }
  if (s_reglages.reseauMs && echu(t, s_prochain_reseau)) {
    s_file.push(Item::NetMatter, t, true);
    s_file.push(Item::NetThread, t, true);
    s_prochain_reseau = t + s_reglages.reseauMs;
  }
  if ((s_reglages.periodeMs == 0 || s_reglages.periodeMs > BATTEMENT_MS) && echu(t, s_prochain_hb)) {
    s_file.push(Item::Heartbeat, t, true);
    s_prochain_hb = t + BATTEMENT_MS;
  }
}

// --- Evenements. Sous s_verrou.

static void evenement(const evenement_t &e) {
  const uint32_t ms = maintenant_ms();
  switch (e.type) {
    case EV_ORDRE: {
      Ordre o;
      o.lampe = e.lampe;
      o.issue = e.a == LAMPES_SIGNAL_CONFIRME ? "confirme" : e.a == LAMPES_SIGNAL_ABANDON ? "abandon" : "tenu";
      o.delaiMs = e.delai_ms;
      o.essai = e.b;
      o.nIds = e.n_ids;
      memcpy(o.ids, e.ids, sizeof(o.ids));
      o.idsPerdus = e.ids_perdus;
      ordre(s_w, s_n, ms, o);
      break;
    }
    case EV_RELEVES:
      alerteReleves(s_w, s_n, ms, e.lampe, e.a != 0, e.b);
      break;
    case EV_MESH:
      alerteMesh(s_w, s_n, ms, code_diag((diagnostic_t)e.a));
      break;
    case EV_LAMPE: {
      static const char *const QUOI[] = {"entree", "masquee", "remise", "echec"};
      lampe(s_w, s_n, ms, e.lampe, QUOI[e.a % 4], e.endpoint);
      break;
    }
    case EV_LED:
      led(s_w, s_n, ms, e.motif, e.avant, e.a != 0, e.delai_ms);
      break;
  }
  envoyer();
}

static void journal(const journal_t &j) {
  const uint32_t t = maintenant_ms();
  if (!s_plafond_journal.available(t)) {
    s_plafond_journal.skip();
    return;
  }
  s_plafond_journal.take();
  logLine(s_w, s_n, t, j.src, j.alerte ? "alerte" : "notice", j.txt, s_plafond_journal.takeSkipped());
  envoyer();
}

static void tache_json(void *arg) {
  (void)arg;
  uint32_t prochain_tic = maintenant_ms();
  for (;;) {
    const int32_t attente = (int32_t)(prochain_tic - maintenant_ms());
    evenement_t e;
    if (xQueueReceive(s_evenements, &e, attente > 0 ? pdMS_TO_TICKS(attente) : 0) == pdTRUE) {
      xSemaphoreTake(s_verrou, portMAX_DELAY);
      if (s_machine) evenement(e);
      xSemaphoreGive(s_verrou);
      // Les evenements d'abord (ils ne passent pas par la file), mais le tic a son heure.
      if (!echu(maintenant_ms(), prochain_tic)) continue;
    }
    journal_t j;
    while (xQueueReceive(s_journal, &j, 0) == pdTRUE) {
      xSemaphoreTake(s_verrou, portMAX_DELAY);
      if (s_machine) journal(j);
      xSemaphoreGive(s_verrou);
    }
    const uint32_t t = maintenant_ms();
    xSemaphoreTake(s_verrou, portMAX_DELAY);
    if (s_machine) programmer(t);
    s_perdus += s_file.dropLate(t);
    const Queued *q = s_file.front();
    if (q) {
      const Queued copie = *q;
      s_file.pop();
      former(copie);
    }
    xSemaphoreGive(s_verrou);
    prochain_tic = t + TIC_MS;
  }
}

// --- Commandes

static bool lire_ms(const char *texte, uint32_t min, uint32_t max, uint32_t *v) {
  return texte_lire_nombre(texte, v) && (*v == 0 || (*v >= min && *v <= max));
}

// La famille `json` (3.3). id 0 : sans reponse, texte pour un humain. Sous s_verrou.
static void commande_json(uint32_t id, const char *vue, int argc, char **argv, uint32_t debut_ms) {
  static const char USAGE[] = "json [1 [bail <s>]|0|etat|hello|ping|periode|lampes|compteurs|reseau <ms>|log 0|1]";
  const uint32_t t = maintenant_ms();
  const char *sous = argc >= 2 ? argv[1] : "";
  uint32_t v = 0;
  const char *erreur = nullptr;
  if (argc == 1) {
    printf("json : mode %s, bail %u s, etat %" PRIu32 " ms, lampes %" PRIu32 " ms, compteurs %" PRIu32
           " ms, reseau %" PRIu32 " ms, log %s ; lignes %" PRIu32 ", perdues %" PRIu32 ", refusees %" PRIu32 "\n",
           s_machine ? "machine" : "texte", (unsigned)s_reglages.bailS, s_reglages.periodeMs, s_reglages.lampesMs,
           s_reglages.compteursMs, s_reglages.reseauMs, s_reglages.log ? "oui" : "non", s_n, s_perdus + s_evenements_perdus, s_rejets);
  } else if (!strcmp(sous, "1")) {
    if (argc == 2 || (argc == 4 && !strcmp(argv[2], "bail") && lire_ms(argv[3], 10, 600, &v))) {
      entrer(argc == 4 ? (uint16_t)v : 30, t);
      if (id) {
        differer(id, vue, true, debut_ms);
        return;
      }
    } else {
      erreur = "json 1 [bail 0|10-600]";
    }
  } else if (!strcmp(sous, "0") && argc == 2) {
    if (id) repondre(id, vue, true, "ok", nullptr, debut_ms);
    if (s_machine) sortir("commande", "json : mode machine coupe\r\n");
    return;
  } else if ((!strcmp(sous, "etat") || !strcmp(sous, "hello")) && argc == 2) {
    if (!strcmp(sous, "etat")) pousser_etat(t, false);
    else pousser_hello(t, false);
    if (id) {
      differer(id, vue, false, debut_ms);
      return;
    }
  } else if (!strcmp(sous, "ping") && argc == 2) {
    s_dernier_rx = t;
    if (id) {
      Reply r;
      r.id = id;
      r.cmd = vue;
      r.durMs = t - debut_ms;
      r.hasLease = true;
      r.leaseS = s_reglages.bailS;
      r.upS = up_s();
      reponse(r);
      return;
    }
  } else if (argc == 3 && !strcmp(sous, "periode")) {
    if (lire_ms(argv[2], 200, 60000, &v)) {
      s_reglages.periodeMs = v;
      s_prochain_etat = s_prochain_hb = t;
    } else {
      erreur = "json periode <0|200-60000 ms>";
    }
  } else if (argc == 3 && !strcmp(sous, "lampes")) {
    if (lire_ms(argv[2], 1000, 60000, &v)) {
      s_reglages.lampesMs = v;
      s_prochain_lampes = t;
    } else {
      erreur = "json lampes <0|1000-60000 ms>";
    }
  } else if (argc == 3 && !strcmp(sous, "compteurs")) {
    if (lire_ms(argv[2], 200, 60000, &v)) {
      s_reglages.compteursMs = v;
      s_prochain_compteurs = t;
    } else {
      erreur = "json compteurs <0|200-60000 ms>";
    }
  } else if (argc == 3 && !strcmp(sous, "reseau")) {
    if (lire_ms(argv[2], 1000, 60000, &v)) {
      s_reglages.reseauMs = v;
      s_prochain_reseau = t;
    } else {
      erreur = "json reseau <0|1000-60000 ms>";
    }
  } else if (argc == 3 && !strcmp(sous, "log") && (!strcmp(argv[2], "0") || !strcmp(argv[2], "1"))) {
    s_reglages.log = !strcmp(argv[2], "1");
    s_log = s_reglages.log;
  } else {
    erreur = USAGE;
  }
  if (id) {
    repondre(id, vue, !erreur, erreur ? "usage" : "ok", erreur, debut_ms);
  } else if (erreur) {
    printf("erreur : %s\n", erreur);
  } else if (argc > 1) {
    printf("ok json %s\n", sous);
  }
}

int json_pont_commande(int argc, char **argv) {
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  commande_json(0, "", argc, argv, maintenant_ms());
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

void json_pont_executer(char *ligne, bool trop_long) {
  const uint32_t debut = maintenant_ms();
  uint32_t id = 0;
  char *cmd = ligne;
  const bool a_id = parseIdPrefix(ligne, &id, &cmd);
  // Ligne vide (l'effacement 0x15 + LF que l'app envoie a l'ouverture) : rien a faire.
  if (!a_id && !trop_long && strspn(cmd, " ") == strlen(cmd)) return;
  // La commande telle que la reponse la cite : masquee (mesh cles), puis tronquee.
  char vue[kCmdTextMax + 1];
  {
    char masquee[kCmdMax + 1];
    snprintf(masquee, sizeof(masquee), "%s", cmd);
    maskCmd(masquee);
    copyCmd(vue, masquee);
  }
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  s_dernier_rx = debut;
  const char *refus = nullptr, *code = nullptr;
  if (trop_long) {
    refus = "ligne de plus de 127 octets : rien n'est execute";
    code = "trop_long";
  } else if (s_machine && !s_cadence.allow(debut)) {
    refus = "plus de 20 lignes par seconde : rien n'est execute";
    code = "cadence";
  }
  if (refus) {
    s_rejets++;
    if (a_id) repondre(id, vue, false, code, refus, debut);
    xSemaphoreGive(s_verrou);
    if (!a_id) printf("erreur : %s\n", refus);
    return;
  }
  // Les mots de la commande (esp_console_run decoupe une copie de son cote).
  static char copie[kCmdMax + 1];
  static char *argv[8];
  snprintf(copie, sizeof(copie), "%s", cmd);
  const int argc = (int)esp_console_split_argv(copie, argv, sizeof(argv) / sizeof(argv[0]));
  if (argc >= 1 && !strcmp(argv[0], "json")) {
    commande_json(a_id ? id : 0, vue, argc, argv, debut);
    s_derniere_cmd = maintenant_ms();
    xSemaphoreGive(s_verrou);
    return;
  }
  int lampe = 0;
  int8_t marche = -1;
  int32_t intensite = -1;
  bool usage = false;
  if (a_id && ordre_de_lampe(argc, argv, &lampe, &marche, &intensite, &usage)) {
    if (usage) {
      char msg[64];
      snprintf(msg, sizeof(msg), "lampe <1-%u> on|off|niveau <0-1000>", (unsigned)s_cfg->liste.n);
      repondre(id, vue, false, "usage", msg, debut);
    } else {
      // L'id part avec l'ordre : l'evenement ordre qui le finira le portera (7.1).
      const bool m = marche == 1;
      const uint16_t v = (uint16_t)intensite;
      if (tache_lampes_ordre_id(lampe, marche >= 0 ? &m : nullptr, intensite >= 0 ? &v : nullptr, id)) {
        Reply r;
        r.id = id;
        r.cmd = vue;
        r.code = "accepte";
        r.suite = Reply::SuiteOrder;
        r.lampe = (uint8_t)(lampe + 1);
        r.durMs = maintenant_ms() - debut;
        reponse(r);
      } else {
        repondre(id, vue, false, "erreur", "file des lampes pleine", debut);
      }
    }
    s_derniere_cmd = maintenant_ms();
    xSemaphoreGive(s_verrou);
    return;
  }
  // Toute autre commande : debut, son texte, fin (6.2). Rien sous s_verrou pendant
  // qu'elle tourne : la tache json continue d'emettre. L'id de la commande entre
  // dans le bloc sante avec le debut, et en sort avec la fin.
  s_en_commande = true;
  if (a_id) {
    s_cmd_id = id;
    Reply r;
    r.id = id;
    r.fin = false;
    r.cmd = vue;
    r.code = "en_cours";
    reponse(r);
  }
  xSemaphoreGive(s_verrou);
  int ret = 0;
  const esp_err_t err = argc >= 1 ? esp_console_run(cmd, &ret) : ESP_ERR_INVALID_ARG;
  if (err == ESP_ERR_NOT_FOUND) printf("Commande inconnue : \"%s\" (help)\n", argv[0]);
  fflush(stdout);  // le texte de la commande passe avant la reponse fin
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  s_derniere_cmd = maintenant_ms();
  s_en_commande = false;
  s_cmd_id = 0;
  if (a_id) {
    const bool inconnue = err != ESP_OK;
    const bool ok = !inconnue && ret == 0;
    repondre(id, vue, ok, inconnue ? "inconnue" : ok ? "ok" : "erreur", nullptr, debut);
    // Une commande mesh reussie a pu changer la configuration du Mesh (5.2).
    if (ok && !strcmp(argv[0], "mesh")) s_file.push(Item::ConfigMesh, maintenant_ms(), false);
  }
  xSemaphoreGive(s_verrou);
}

void json_pont_lire(void) {
  uint8_t octets[64];
  const int n = usb_serial_jtag_read_bytes(octets, sizeof(octets), pdMS_TO_TICKS(200));
  if (n <= 0) return;
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  s_dernier_rx = maintenant_ms();
  xSemaphoreGive(s_verrou);
  for (int i = 0; i < n; i++) {
    if (s_assembleur.feed(octets[i]) != LineAssembler::Ev::Line) continue;
    json_pont_executer(s_assembleur.text(), s_assembleur.tooLong());
    s_assembleur.reset();
  }
}

bool json_pont_machine(void) { return s_machine; }

// --- Evenements, depuis les autres taches

static void poster(const evenement_t &e) {
  if (s_machine && s_evenements && xQueueSend(s_evenements, &e, 0) != pdTRUE)
    __atomic_fetch_add(&s_evenements_perdus, 1, __ATOMIC_RELAXED);
}

void json_pont_ordre(int lampe, lampes_signal_t signal, uint32_t delai_ms, uint8_t essai, const uint32_t *ids,
                     uint8_t n_ids, uint32_t ids_perdus) {
  evenement_t e = {};
  e.type = EV_ORDRE;
  e.lampe = (int8_t)lampe;
  e.a = (uint8_t)signal;
  e.b = essai;
  e.delai_ms = delai_ms;
  e.n_ids = n_ids > kIdsMax ? kIdsMax : n_ids;
  for (uint8_t i = 0; i < e.n_ids; i++) e.ids[i] = ids[i];
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

void json_pont_annoncer(const char *src, bool alerte, const char *format, ...) {
  char txt[192];
  va_list ap;
  va_start(ap, format);
  vsnprintf(txt, sizeof(txt), format, ap);
  va_end(ap);
  if (s_machine && s_log && s_journal) {
    journal_t j;
    j.src = src;
    j.alerte = alerte;
    const size_t n = strnlen(txt, sizeof(j.txt) - 1);  // log.txt : 127 octets au plus (7.5)
    memcpy(j.txt, txt, n);
    j.txt[n] = 0;
    if (xQueueSend(s_journal, &j, 0) == pdTRUE) return;
  }
  printf("%s\n", txt);
}

esp_err_t json_pont_demarrer(const amaran_config_t *cfg) {
  s_cfg = cfg;
  // Aucune radio n'est encore active : le generateur tire de vrai bruit (comme Halo).
  bootloader_random_enable();
  s_boot = esp_random();
  bootloader_random_disable();
  s_verrou = xSemaphoreCreateMutex();
  s_evenements = xQueueCreate(FILE_EVENEMENTS, sizeof(evenement_t));
  s_journal = xQueueCreate(FILE_JOURNAL, sizeof(journal_t));
  if (!s_verrou || !s_evenements || !s_journal) return ESP_ERR_NO_MEM;
  // Basse priorite : les lampes, Matter et la console passent avant.
  return xTaskCreate(tache_json, "json", 4096, NULL, 1, NULL) == pdPASS ? ESP_OK : ESP_ERR_NO_MEM;
}
