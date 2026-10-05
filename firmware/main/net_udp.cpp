// Canal du pont par Thread (voir net_udp.h). Sur le modele de net_udp.cpp du pont Halo
// (commit e114cd5), avec une difference : jamais le verrou d'OpenThread depuis nos
// taches (IDF 5.5.4 : un essai rate le laisse pris). Tout appel OpenThread passe par
// la file de taches de la tache d'OpenThread, qui l'execute verrou tenu ; la reception
// arrive deja dans cette tache.
//
// Taches :
// - OpenThread : rappel de reception (copie dans s_recus), envoi (anneau -> otUdpSend),
//   ouverture et fermeture du port, releve des adresses ;
// - udp (la notre) : enveloppe H1 (poignee de main, verification), lignes recues vers
//   json_pont, expiration des sessions, port remis d'accord avec la cle. Elle seule
//   poste l'envoi a OpenThread (la poste peut attendre 100 ms, puis journaliser) : les
//   autres taches mettent en file, sans attendre, sous le verrou de json_pont ;
// - json, distant, console : net_udp_envoyer (scelle, met en file, reveille la tache udp).
// s_verrou garde la table H1, les generations, l'anneau d'emission et le releve, et le
// contexte HMAC de components/h1 : tout calcul H1 se fait sous lui. Jamais pris par la
// tache d'OpenThread autrement que sans attente.
#include "net_udp.h"

#include <inttypes.h>
#include <stdio.h>
#include <string.h>

#include "esp_log.h"
#include "esp_openthread.h"
#include "esp_random.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "h1_proto.h"
#include "json_ligne.h"
#include "json_pont.h"
#include "nvs.h"
#include "openthread/ip6.h"
#include "openthread/message.h"
#include "openthread/srp_client.h"
#include "openthread/thread.h"
#include "openthread/udp.h"

// Fonction privee d'ESP-IDF (private_include/esp_openthread_task_queue.h), liee telle
// quelle : execute `tache(arg)` dans la tache d'OpenThread, verrou tenu.
extern "C" esp_err_t esp_openthread_task_queue_post(void (*tache)(void *), void *arg);

static_assert(NET_UDP_SESSIONS == h1::kSlots, "une session JSON par emplacement H1");

static const char *TAG = "udp";
static const char *const NVS_ESPACE = "amaran_udp";
static const char *const NVS_CLE = "cle";

// Commande de 127 octets et son en-tete de 56 : 256 laisse de la marge ; au-dela, le
// datagramme n'est pas pour nous (compte, jete).
static constexpr size_t RX_MAX = 256;
static constexpr int RX_N = 4;
// En-tete H1 et ligne machine sans RS ni LF : 56 + 1022 octets.
static constexpr size_t TX_MAX = h1::kHeaderMax + 1022;
// 12 places : les lignes periodiques n'en prennent que 5 (kPlacesPeriodique), le reste
// absorbe une rafale de reponses et d'evenements (deux sessions, ordres simultanes).
static constexpr int TX_N = 12;
static_assert(TX_N > jsonp::kPlacesPeriodique, "la file doit garder de la place apres une periodique");
static constexpr uint32_t TX_PERIME_MS = 4000;  // pas parti dans ce delai : perdu
static constexpr int TX_PAR_TOUR = 2;           // datagrammes remis a OpenThread par appel
// Debit moyen plafonne (10.3) : 3000 octets/s, credit de 2400 (deux lignes d'un Ko).
static constexpr uint32_t TX_OCTETS_S = 3000;
static constexpr uint32_t TX_RAFALE = 2400;
// Tampons OpenThread (65, partages avec Matter) laisses libres apres un envoi.
static constexpr uint16_t TAMPONS_RESERVE = 24;
static constexpr uint32_t RELEVE_MS = 5000;
static constexpr uint32_t EXPIRE_MS = 1000;
static constexpr uint8_t BRUT = 0xFF;  // DEFI : sans session

struct recu_t {
  uint16_t lon;
  uint16_t port;
  uint8_t pair[16];
  uint8_t local[16];
  uint8_t donnees[RX_MAX];
};

struct emis_t {
  uint32_t a;     // mis en file a
  uint8_t slot;   // session qui l'a scelle ; BRUT : DEFI
  uint16_t lon;
  uint16_t port;
  uint8_t pair[16];
  uint8_t local[16];
  uint8_t donnees[TX_MAX];
};

static SemaphoreHandle_t s_verrou;
static QueueHandle_t s_recus;
static TaskHandle_t s_tache;    // tache udp
static volatile bool s_demarre;  // net_udp_demarrer a reussi
static recu_t s_recu_ot;  // tampon du rappel (tache d'OpenThread seulement)
static h1::Table s_table;
// Generation de chaque emplacement (s_verrou) : change a chaque session neuve, oubli
// ou cle changee, et json_pont l'apprend par json_pont_distant_fin (annoncer_fins).
static uint32_t s_gen[h1::kSlots];
static otUdpSocket s_socket;
// s_voulu : une cle existe, le port doit etre ouvert (ecrit sous s_verrou) ; s_ouvert :
// il l'est (tache d'OpenThread).
static volatile bool s_voulu, s_ouvert, s_envoi_poste;

// Anneau d'emission (s_verrou) ; s_emis_ot : copie de la tete, tache d'OpenThread.
static emis_t s_emis[TX_N];
static uint8_t s_tete, s_nb;
static emis_t s_emis_ot;
static uint32_t s_credit = TX_RAFALE, s_credit_a;

// Compteurs du bloc reseau ip, touches par la tache d'OpenThread et par les autres
// taches, avec ou sans s_verrou : increments atomiques.
static struct {
  uint32_t trop_grands, file_pleine, recus, rejets, emis, perdus, erreurs;
} s_st;

static void compter(uint32_t &c) { __atomic_fetch_add(&c, 1, __ATOMIC_RELAXED); }
static uint32_t lire(const uint32_t &c) { return __atomic_load_n(&c, __ATOMIC_RELAXED); }

// Releve des adresses et du nom SRP (tache d'OpenThread), lu sous s_verrou.
static net_udp_etat_t s_releve;

static uint32_t maintenant_ms(void) { return (uint32_t)(esp_timer_get_time() / 1000); }

static bool poster(void (*t)(void *)) { return esp_openthread_task_queue_post(t, nullptr) == ESP_OK; }

// ===========================================================================
//  Tache d'OpenThread (verrou d'OpenThread tenu)
// ===========================================================================

// Jamais de verrou ni d'impression ici : copie dans la file, reveil de la tache udp.
static void sur_reception(void *, otMessage *m, const otMessageInfo *info) {
  const uint16_t off = otMessageGetOffset(m), total = otMessageGetLength(m);
  if (total < off || (size_t)(total - off) > RX_MAX) {
    compter(s_st.trop_grands);
    return;
  }
  s_recu_ot.lon = otMessageRead(m, off, s_recu_ot.donnees, (uint16_t)(total - off));
  s_recu_ot.port = info->mPeerPort;
  memcpy(s_recu_ot.pair, info->mPeerAddr.mFields.m8, 16);
  memcpy(s_recu_ot.local, info->mSockAddr.mFields.m8, 16);
  if (xQueueSend(s_recus, &s_recu_ot, 0) != pdTRUE) {
    compter(s_st.file_pleine);
    return;
  }
  xTaskNotifyGive(s_tache);
}

// Le port suit la cle : s_voulu est lu quand la demande s'execute, une demande
// perimee (cle changee entre-temps) ne defait donc rien. Un echec (otUdpOpen,
// otUdpBind) est repris par la tache udp tous les RELEVE_MS.
static void accorder_ot(void *) {
  otInstance *ot = esp_openthread_get_instance();
  if (!s_voulu) {
    if (s_ouvert) {
      otUdpClose(ot, &s_socket);
      s_ouvert = false;
    }
    return;
  }
  if (s_ouvert) return;
  memset(&s_socket, 0, sizeof(s_socket));
  if (otUdpOpen(ot, &s_socket, sur_reception, nullptr) != OT_ERROR_NONE) return;
  otSockAddr a;
  memset(&a, 0, sizeof(a));
  a.mPort = NET_UDP_PORT;
  // Interne a OpenThread : pas de socket lwIP en double ; un port tenu par OpenThread
  // n'est plus remis a lwIP.
  if (otUdpBind(ot, &s_socket, &a, OT_NETIF_THREAD_INTERNAL) == OT_ERROR_NONE) {
    s_ouvert = true;
  } else {
    otUdpClose(ot, &s_socket);
  }
}

// La tete de l'anneau, si le credit et les tampons le permettent, copiee sous s_verrou
// pris sans attente ; envoyee ensuite, sans lui. Un datagramme sorti de l'anneau et
// non remis a OpenThread est perdu, et compte.
static void envoyer_ot(void *) {
  s_envoi_poste = false;
  otInstance *ot = esp_openthread_get_instance();
  for (int envoyes = 0; envoyes < TX_PAR_TOUR; envoyes++) {
    if (xSemaphoreTake(s_verrou, 0) != pdTRUE) return;  // la tache udp relancera
    const uint32_t t = maintenant_ms();
    while (s_nb && (int32_t)(t - s_emis[s_tete].a) > (int32_t)TX_PERIME_MS) {
      s_tete = (uint8_t)((s_tete + 1) % TX_N);
      s_nb--;
      compter(s_st.perdus);
    }
    const uint32_t ecoule = t - s_credit_a;
    s_credit_a = t;
    const uint32_t ajout = (ecoule > 10000 ? 10000 : ecoule) * TX_OCTETS_S / 1000;
    s_credit = s_credit + ajout > TX_RAFALE ? TX_RAFALE : s_credit + ajout;
    bool pris = false;
    if (s_nb && s_ouvert) {
      const emis_t &e = s_emis[s_tete];
      otBufferInfo bi;
      otMessageGetBufferInfo(ot, &bi);
      const bool tampons = bi.mFreeBuffers == 0xFFFF || bi.mFreeBuffers >= (uint16_t)(e.lon / 100 + 2) + TAMPONS_RESERVE;
      const bool credit = e.slot == BRUT || s_credit >= e.lon;
      if (tampons && credit) {
        s_emis_ot = e;
        if (e.slot != BRUT) s_credit -= e.lon;
        s_tete = (uint8_t)((s_tete + 1) % TX_N);
        s_nb--;
        pris = true;
      }
    }
    xSemaphoreGive(s_verrou);
    if (!pris) return;
    // Priorite basse : devant un manque de tampons, OpenThread evince nos messages
    // avant ceux de Matter.
    otMessageSettings ms;
    ms.mLinkSecurityEnabled = true;
    ms.mPriority = OT_MESSAGE_PRIORITY_LOW;
    otMessage *m = otUdpNewMessage(ot, &ms);
    if (!m || otMessageAppend(m, s_emis_ot.donnees, s_emis_ot.lon) != OT_ERROR_NONE) {
      if (m) otMessageFree(m);
      compter(s_st.erreurs);
      compter(s_st.perdus);
      continue;
    }
    otMessageInfo mi;
    memset(&mi, 0, sizeof(mi));
    memcpy(mi.mPeerAddr.mFields.m8, s_emis_ot.pair, 16);
    mi.mPeerPort = s_emis_ot.port;
    // Reponse depuis l'adresse que l'app a visee, si elle est encore a nous.
    otIp6Address local;
    memcpy(local.mFields.m8, s_emis_ot.local, 16);
    if (!otIp6IsAddressUnspecified(&local) && otIp6HasUnicastAddress(ot, &local)) mi.mSockAddr = local;
    mi.mSockPort = NET_UDP_PORT;
    if (otUdpSend(ot, &s_socket, m, &mi) != OT_ERROR_NONE) {
      otMessageFree(m);
      compter(s_st.erreurs);
      compter(s_st.perdus);
    } else {
      compter(s_st.emis);
    }
  }
}

static void relever_ot(void *) {
  otInstance *ot = esp_openthread_get_instance();
  net_udp_etat_t r = {};
  const otSrpClientHostInfo *h = otSrpClientGetHostInfo(ot);
  if (h && h->mName) snprintf(r.srp, sizeof(r.srp), "%s", h->mName);
  const otMeshLocalPrefix *ml = otThreadGetMeshLocalPrefix(ot);
  for (const otNetifAddress *a = otIp6GetUnicastAddresses(ot); a && r.n < NET_UDP_ADRESSES; a = a->mNext) {
    const uint8_t *b = a->mAddress.mFields.m8;
    if (b[0] == 0xfe && (b[1] & 0xc0) == 0x80) continue;  // lien local
    const bool maillage = ml && !memcmp(b, ml->m8, 8);
    // RLOC et ALOC : 0000:00ff:fe00:xxxx, sans interet pour l'app.
    if (maillage && b[8] == 0 && b[9] == 0 && b[10] == 0 && b[11] == 0xff && b[12] == 0xfe && b[13] == 0) continue;
    memcpy(r.adresses[r.n].a, b, 16);
    r.adresses[r.n].type = maillage ? NET_UDP_ML_EID : a->mPreferred ? NET_UDP_OMR : NET_UDP_AUTRE;
    r.n++;
  }
  if (xSemaphoreTake(s_verrou, 0) != pdTRUE) return;  // releve suivant dans 5 s
  memcpy(s_releve.srp, r.srp, sizeof(r.srp));
  memcpy(s_releve.adresses, r.adresses, sizeof(r.adresses));
  s_releve.n = r.n;
  xSemaphoreGive(s_verrou);
}

// ===========================================================================
//  Tache udp, et les autres taches
// ===========================================================================

static void aleatoire(void *p, size_t n) { esp_fill_random(p, n); }

// Sous s_verrou. Datagramme brut (DEFI) en tete de file, hors plafond de debit : une
// poignee de main n'attend pas derriere l'instantane d'une autre session.
static void mettre_brut(const h1::Peer &vers, const char *d, size_t n) {
  if (s_nb >= TX_N || n > TX_MAX) {
    compter(s_st.perdus);
    return;
  }
  s_tete = (uint8_t)((s_tete + TX_N - 1) % TX_N);
  s_nb++;
  emis_t &e = s_emis[s_tete];
  e.a = maintenant_ms();
  e.slot = BRUT;
  e.lon = (uint16_t)n;
  e.port = vers.port;
  memcpy(e.pair, vers.ip, 16);
  memcpy(e.local, vers.local, 16);
  memcpy(e.donnees, d, n);
}

// Sous s_verrou. Les datagrammes deja scelles d'une session partie ne prennent plus
// le debit de la suivante.
static void oublier_emis(uint8_t slot) {
  uint8_t gardes = 0;
  for (uint8_t i = 0; i < s_nb; i++) {
    const uint8_t de = (uint8_t)((s_tete + i) % TX_N);
    if (s_emis[de].slot == slot) {
      compter(s_st.perdus);
      continue;
    }
    const uint8_t vers = (uint8_t)((s_tete + gardes) % TX_N);
    if (vers != de) s_emis[vers] = s_emis[de];
    gardes++;
  }
  s_nb = gardes;
}

// Sous s_verrou : les sessions du masque sont parties (oubliees, remplacees, cle
// changee). Leurs datagrammes en file sont perdus, leur generation change ; gens
// recoit la nouvelle, a annoncer hors de s_verrou (annoncer_fins).
static void terminer(uint8_t masque, uint32_t gens[h1::kSlots]) {
  for (uint8_t s = 0; s < h1::kSlots; s++) {
    if (!(masque & (1u << s))) continue;
    oublier_emis(s);
    gens[s] = ++s_gen[s];
  }
}

// Tache udp seulement : la poste peut attendre 100 ms (file d'OpenThread pleine), puis
// journaliser.
static void relancer_envoi(void) {
  if (s_envoi_poste || !s_nb) return;
  s_envoi_poste = true;
  if (!poster(envoyer_ot)) s_envoi_poste = false;
}

// Fins de session (masque d'emplacements, et leurs generations) : sans s_verrou, la
// tache json prend le sien.
static void annoncer_fins(uint8_t masque, const uint32_t gens[h1::kSlots]) {
  for (uint8_t s = 0; s < h1::kSlots; s++)
    if (masque & (1u << s)) json_pont_distant_fin(s, gens[s]);
}

static void traiter(const recu_t &r) {
  static uint8_t ligne[RX_MAX + 1];
  const h1::Parsed p = h1::parse(r.donnees, r.lon);
  h1::Peer de;
  memcpy(de.ip, r.pair, 16);
  de.port = r.port;
  memcpy(de.local, r.local, 16);
  const uint32_t t = maintenant_ms();
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  compter(s_st.recus);
  if (p.kind == h1::Kind::Salut) {
    // Sans place pour le DEFI, la poignee de main en cours (celle d'un autre client
    // peut-etre) n'est pas remplacee.
    char defi[h1::kDefiLen];
    if (s_nb < TX_N && s_table.onSalut(p, aleatoire, de, t, defi) == h1::Verdict::Ok) {
      mettre_brut(de, defi, sizeof(defi));
    } else {
      compter(s_st.rejets);
    }
    xSemaphoreGive(s_verrou);
    relancer_envoi();
    return;
  }
  if (p.kind != h1::Kind::Data) {
    compter(s_st.rejets);
    xSemaphoreGive(s_verrou);
    return;
  }
  uint8_t slot = 0;
  bool neuve = false;
  uint32_t gens[h1::kSlots] = {};
  const h1::Verdict v = s_table.onData(p, de, t, &slot, &neuve);
  size_t n = 0;
  if (v == h1::Verdict::Ok) {
    n = p.payloadLen;
    memcpy(ligne, p.payload, n);
    ligne[n] = 0;
    if (neuve) terminer((uint8_t)(1u << slot), gens);  // l'emplacement servait peut-etre a une session partie
  } else {
    compter(s_st.rejets);
  }
  const uint32_t gen = s_gen[slot];
  xSemaphoreGive(s_verrou);
  if (v != h1::Verdict::Ok) return;
  if (neuve) json_pont_distant_fin(slot, gen);  // session neuve : son puits repart de zero
  // json_pont reprend la session (h1::Table::resume) s'il admet une nouvelle commande.
  json_pont_distant_ligne(slot, gen, (char *)ligne, n);
}

static void tache_udp(void *) {
  static recu_t r;
  uint32_t prochain_expire = 0, prochain_releve = 0;
  for (;;) {
    // Reveillee par un datagramme recu ou une ligne mise en file ; sinon toutes les
    // 20 ms tant que l'anneau attend du credit ou des tampons, 250 ms au repos.
    ulTaskNotifyTake(pdTRUE, s_nb ? pdMS_TO_TICKS(20) : pdMS_TO_TICKS(250));
    while (xQueueReceive(s_recus, &r, 0) == pdTRUE) traiter(r);
    const uint32_t t = maintenant_ms();
    if ((int32_t)(t - prochain_expire) >= 0) {
      prochain_expire = t + EXPIRE_MS;
      uint32_t gens[h1::kSlots] = {};
      xSemaphoreTake(s_verrou, portMAX_DELAY);
      const uint8_t parties = s_table.expire(t);
      terminer(parties, gens);
      xSemaphoreGive(s_verrou);
      annoncer_fins(parties, gens);
    }
    if ((int32_t)(t - prochain_releve) >= 0) {
      prochain_releve = t + RELEVE_MS;
      poster(relever_ot);
      // Port et cle en desaccord (file d'OpenThread pleine, otUdpOpen ou otUdpBind en
      // echec) : nouvel essai.
      if (s_voulu != s_ouvert) poster(accorder_ot);
    }
    relancer_envoi();
  }
}

bool net_udp_envoyer(uint8_t slot, uint32_t gen, const uint8_t *ligne, size_t n) {
  if (!s_demarre || slot >= h1::kSlots || n + h1::kHeaderMax > TX_MAX) return false;
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  bool ok = false;
  if (s_gen[slot] == gen && s_table.slot(slot).used && TX_N - s_nb >= NET_UDP_PLACES_LIGNE) {
    emis_t &e = s_emis[(s_tete + s_nb) % TX_N];
    char tete[h1::kHeaderMax + 1];
    const size_t hn = s_table.seal(slot, ligne, n, tete);
    if (hn) {
      const h1::Peer &vers = s_table.slot(slot).peer;
      e.a = maintenant_ms();
      e.slot = slot;
      e.lon = (uint16_t)(hn + n);
      e.port = vers.port;
      memcpy(e.pair, vers.ip, 16);
      memcpy(e.local, vers.local, 16);
      memcpy(e.donnees, tete, hn);
      memcpy(e.donnees + hn, ligne, n);
      s_nb++;
      ok = true;
    }
  }
  if (!ok) compter(s_st.perdus);
  xSemaphoreGive(s_verrou);
  if (ok) xTaskNotifyGive(s_tache);  // la tache udp la remet a OpenThread
  return ok;
}

uint8_t net_udp_libres(void) {
  if (!s_demarre) return 0;
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  const uint8_t libres = s_ouvert ? (uint8_t)(TX_N - s_nb) : 0;
  xSemaphoreGive(s_verrou);
  return libres;
}

void net_udp_finir(uint8_t slot, uint32_t gen) {
  if (!s_demarre || slot >= h1::kSlots) return;
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  if (s_gen[slot] == gen) s_table.end(slot);
  xSemaphoreGive(s_verrou);
}

void net_udp_reprendre(uint8_t slot, uint32_t gen) {
  if (!s_demarre || slot >= h1::kSlots) return;
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  if (s_gen[slot] == gen) s_table.resume(slot);
  xSemaphoreGive(s_verrou);
}

// Sous s_verrou : nouvelle cle (ou aucune) ; les sessions tombent (masque rendu, gens
// recoit leurs generations), le port suit la cle.
static uint8_t poser_cle(const uint8_t *cle, uint32_t gens[h1::kSlots]) {
  const uint8_t parties = s_table.clear();
  terminer(parties, gens);
  s_table.setKey(cle);
  s_voulu = s_table.hasKey();
  return parties;
}

esp_err_t net_udp_cle_nouvelle(const uint8_t alea_app[32], char cle_hex[65], char empreinte[9]) {
  if (!s_demarre) return ESP_ERR_INVALID_STATE;
  uint8_t alea_pont[32], cle[32];
  esp_fill_random(alea_pont, sizeof(alea_pont));
  const h1::Part parts[] = {{alea_pont, sizeof(alea_pont)}};
  xSemaphoreTake(s_verrou, portMAX_DELAY);  // contexte HMAC partage (h1_crypto.cpp)
  const bool calculee = h1::hmacSha256(alea_app, 32, parts, 1, cle);
  xSemaphoreGive(s_verrou);
  h1::wipe(alea_pont, sizeof(alea_pont));
  if (!calculee) {
    h1::wipe(cle, sizeof(cle));
    return ESP_FAIL;
  }
  nvs_handle_t h;
  esp_err_t err = nvs_open(NVS_ESPACE, NVS_READWRITE, &h);
  if (err == ESP_OK) {
    err = nvs_set_blob(h, NVS_CLE, cle, sizeof(cle));
    if (err == ESP_OK) err = nvs_commit(h);
    nvs_close(h);
  }
  if (err != ESP_OK) {
    h1::wipe(cle, sizeof(cle));
    return err;
  }
  uint32_t gens[h1::kSlots] = {};
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  const uint8_t parties = poser_cle(cle, gens);
  xSemaphoreGive(s_verrou);
  annoncer_fins(parties, gens);
  h1::toHex(cle, sizeof(cle), cle_hex);
  h1::keyId(cle, empreinte);  // SHA-256 seul : pas de contexte partage
  h1::wipe(cle, sizeof(cle));
  poster(accorder_ot);  // en echec : la tache udp reessaie
  return ESP_OK;
}

esp_err_t net_udp_cle_effacer(void) {
  // La NVS d'abord, toujours, meme avant le demarrage de l'acces par Thread (Matter non
  // demarre, ou pas encore) : decommission et BOOT 8 s doivent la retirer pour de bon.
  nvs_handle_t h;
  esp_err_t err = nvs_open(NVS_ESPACE, NVS_READWRITE, &h);
  if (err == ESP_OK) {
    err = nvs_erase_key(h, NVS_CLE);
    if (err == ESP_ERR_NVS_NOT_FOUND) err = ESP_OK;  // deja sans cle
    if (err == ESP_OK) err = nvs_commit(h);
    nvs_close(h);
  }
  if (!s_demarre) return err;  // rien en memoire : ni table, ni port
  // En memoire, la cle part quoi qu'il arrive (sessions tombees, port ferme) ; l'erreur
  // de la NVS est rendue : la cle y est peut-etre encore.
  uint32_t gens[h1::kSlots] = {};
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  const uint8_t parties = poser_cle(nullptr, gens);
  s_nb = 0;
  xSemaphoreGive(s_verrou);
  annoncer_fins(parties, gens);
  poster(accorder_ot);  // en echec : la tache udp reessaie
  return err;
}

void net_udp_lire(net_udp_etat_t *e) {
  memset(e, 0, sizeof(*e));
  if (!s_demarre) return;
  xSemaphoreTake(s_verrou, portMAX_DELAY);
  *e = s_releve;
  e->cle = s_table.hasKey();
  if (e->cle) snprintf(e->empreinte, sizeof(e->empreinte), "%s", s_table.kid());
  e->ouvert = s_ouvert;
  // Les sessions finies par json 0 gardent leur place (reprenable) : pas comptees.
  for (uint8_t i = 0; i < h1::kSlots; i++) e->sessions += s_table.slot(i).used && !s_table.slot(i).ended;
  e->recus = lire(s_st.recus);
  e->emis = lire(s_st.emis);
  e->rejets = lire(s_st.rejets) + lire(s_st.trop_grands) + lire(s_st.file_pleine);
  e->perdus = lire(s_st.perdus);
  xSemaphoreGive(s_verrou);
}

esp_err_t net_udp_demarrer(void) {
  s_verrou = xSemaphoreCreateMutex();
  s_recus = xQueueCreate(RX_N, sizeof(recu_t));
  if (!s_verrou || !s_recus) return ESP_ERR_NO_MEM;
  uint8_t cle[32];
  size_t lon = sizeof(cle);
  nvs_handle_t h;
  bool avec_cle = false;
  if (nvs_open(NVS_ESPACE, NVS_READONLY, &h) == ESP_OK) {
    avec_cle = nvs_get_blob(h, NVS_CLE, cle, &lon) == ESP_OK && lon == sizeof(cle);
    nvs_close(h);
  }
  if (avec_cle) {
    xSemaphoreTake(s_verrou, portMAX_DELAY);
    s_table.setKey(cle);
    s_voulu = s_table.hasKey();
    xSemaphoreGive(s_verrou);
  }
  h1::wipe(cle, sizeof(cle));
  if (xTaskCreate(tache_udp, "udp", 4096, nullptr, 1, &s_tache) != pdPASS) return ESP_ERR_NO_MEM;
  s_demarre = true;
  if (s_voulu && !poster(accorder_ot)) {
    ESP_LOGW(TAG, "port %u pas encore ouvert : nouvel essai dans %u s", NET_UDP_PORT, (unsigned)(RELEVE_MS / 1000));
  }
  return ESP_OK;
}
