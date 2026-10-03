// Cote Matter du pont (voir pont_matter.h). Modeles : l'exemple light
// d'esp-matter (demarrage, Thread), ses exemples de pont (endpoints pontes recrees
// juste apres esp_matter::start, avec leur numero, puis actives), le pont Halo
// (plafond des abonnements, identite, fenetre rouverte quand la derniere fabrique
// part).
#include "pont_matter.h"

#include <inttypes.h>
#include <stdio.h>
#include <string.h>

#include "esp_app_desc.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_mac.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "nvs.h"

#include <esp_matter.h>
#include <esp_openthread_types.h>
#include <openthread/thread.h>
#include <platform/ESP32/OpenthreadLauncher.h>

#include <app/InteractionModelEngine.h>
#include <app/server/CommissioningWindowManager.h>
#include <app/server/Server.h>
#include <platform/DeviceInstanceInfoProvider.h>
#include <setup_payload/OnboardingCodesUtil.h>

#include "catalogue.h"
#include "mesh_amaran.h"
#include "status_led.h"

using namespace esp_matter;
using namespace chip::app::Clusters;

static const char *TAG = "pont";

// EP0 (noeud), EP1 (agregateur), puis une lampe par endpoint dynamique.
static_assert(CONFIG_ESP_MATTER_MAX_DYNAMIC_ENDPOINT_COUNT >= LISTE_CAPACITE + 2,
              "CONFIG_ESP_MATTER_MAX_DYNAMIC_ENDPOINT_COUNT : noeud, agregateur et LISTE_CAPACITE lampes");

static node_t *s_noeud;
static endpoint_t *s_agregateur;
static uint16_t s_ep_lampe[LISTE_CAPACITE];  // numero d'endpoint ; 0 = lampe non exposee
// Dernier numero de chaque lampe, garde quand elle est masquee : la liste de
// l'appelant peut dater d'avant un renumerotage (desappairage complet).
static uint16_t s_numero[LISTE_CAPACITE];
static char s_nom_lampe[LISTE_CAPACITE][LISTE_NOM_MAX];
// Exposer et masquer : une lampe a la fois (console, tache lampes, demarrage).
static SemaphoreHandle_t s_verrou_exposition;
static pont_ordre_cb_t s_ordre;
// Avant cette echeance, ce qui arrive sur l'endpoint d'une lampe vient de la pile
// (valeurs posees a sa creation), pas d'un controleur (lecon du Halo : 2 s).
static int64_t s_ordres_des_us[LISTE_CAPACITE];
static volatile bool s_ble_annonce;
static volatile int s_role = OT_DEVICE_ROLE_DISABLED;
// Fabriques, relues dans la tache CHIP (evenements, et apres start) : lues sans
// le verrou de la pile depuis nos taches (spec 4.3).
static volatile uint8_t s_fabriques;
static volatile uint32_t s_abo_demandes, s_abo_plafonnes, s_abo_etablis, s_abo_termines;
// Identify, par emplacement : 0 et 1 pour le noeud et l'agregateur, 2 + i pour la
// lampe i (les numeros d'endpoint, eux, croissent sans fin). Emplacements en
// IdentifyTime (bits), et fin d'effet (ms, 0 = aucun) : la pile n'envoie jamais de
// STOP apres un effet (lecon du Halo).
#define EMPLACEMENTS (LISTE_CAPACITE + 2)
static_assert(EMPLACEMENTS <= 32, "s_identifie : un bit par emplacement");
static volatile uint32_t s_identifie;
static volatile uint32_t s_effet_fin[EMPLACEMENTS];

// --- Abonnements : intervalle maximal plafonne (lecon du Halo : apres un
// redemarrage du noeud, Apple ne se reabonne que quand cet intervalle expire).

class PlafondAbonnements : public chip::app::ReadHandler::ApplicationCallback {
  CHIP_ERROR OnSubscriptionRequested(chip::app::ReadHandler &rh, chip::Transport::SecureSession &session) override {
    (void)session;
    uint16_t plancher = 0, max = 0;
    rh.GetReportingIntervals(plancher, max);
    s_abo_demandes++;
    const uint16_t voulu = plancher > PONT_PLAFOND_ABONNEMENT_S ? plancher : PONT_PLAFOND_ABONNEMENT_S;
    if (voulu < max && rh.SetMaxReportingInterval(voulu) == CHIP_NO_ERROR) s_abo_plafonnes++;
    return CHIP_NO_ERROR;  // jamais de refus : l'abonnement tomberait
  }
  void OnSubscriptionEstablished(chip::app::ReadHandler &rh) override {
    (void)rh;
    s_abo_etablis++;
  }
  void OnSubscriptionTerminated(chip::app::ReadHandler &rh) override {
    (void)rh;
    s_abo_termines++;
  }
};

static PlafondAbonnements s_plafond;

// --- Rappels de la pile (tache CHIP : jamais bloquer)

static int lampe_de(uint16_t ep) {
  if (ep < 2) return -1;
  for (int i = 0; i < LISTE_CAPACITE; i++) {
    if (s_ep_lampe[i] == ep) return i;
  }
  return -1;
}

static int emplacement_de(uint16_t ep) {
  if (ep < 2) return ep;
  const int i = lampe_de(ep);
  return i < 0 ? -1 : 2 + i;
}

// POST_UPDATE : la valeur est posee. Nos propres publications passent par
// attribute::report(), qui ne rappelle pas : tout ce qui arrive ici vient d'un
// controleur, d'une scene ou du cluster lui-meme (spec 6.4).
static esp_err_t rappel_attribut(attribute::callback_type_t type, uint16_t ep, uint32_t cluster, uint32_t attr,
                                 esp_matter_attr_val_t *val, void *priv) {
  (void)priv;
  if (type != attribute::POST_UPDATE || !s_ordre) return ESP_OK;
  const int lampe = lampe_de(ep);
  if (lampe < 0 || esp_timer_get_time() < s_ordres_des_us[lampe]) return ESP_OK;
  if (cluster == OnOff::Id && attr == OnOff::Attributes::OnOff::Id) {
    const bool marche = val->val.b;
    s_ordre(lampe, &marche, NULL);
  } else if (cluster == LevelControl::Id && attr == LevelControl::Attributes::CurrentLevel::Id) {
    const uint8_t niveau = val->val.u8;
    if (niveau < 1 || niveau > 254) return ESP_OK;  // nul (0xFF) ou hors plage
    const uint16_t intensite = lampes_niveau_vers_intensite(niveau);
    s_ordre(lampe, NULL, &intensite);
  }
  return ESP_OK;
}

// Identify reste sans effet sur la lampe (Maison ne le propose pas, spec 6.1) :
// seul le voyant fait l'arc-en-ciel, pour un autre controleur.
static esp_err_t rappel_identification(identification::callback_type_t type, uint16_t ep, uint8_t effet,
                                       uint8_t variante, void *priv) {
  (void)variante;
  (void)priv;
  const int e = emplacement_de(ep);
  if (e < 0) return ESP_OK;
  switch (type) {
    case identification::callback_type_t::START:
      s_identifie = s_identifie | (1u << e);
      break;
    case identification::callback_type_t::STOP:
      s_identifie = s_identifie & ~(1u << e);
      break;
    case identification::callback_type_t::EFFECT:
      s_effet_fin[e] = statusled::effectEnd(s_effet_fin[e], effet, (uint32_t)(esp_timer_get_time() / 1000));
      break;
  }
  return ESP_OK;
}

static void rappel_evenement(const chip::DeviceLayer::ChipDeviceEvent *ev, intptr_t arg) {
  (void)arg;
  using namespace chip::DeviceLayer;
  switch (ev->Type) {
    case DeviceEventType::kCHIPoBLEAdvertisingChange:
      // Un seul jeu d'annonces BLE : le Mesh se tait pendant que Matter annonce.
      s_ble_annonce = ev->CHIPoBLEAdvertisingChange.Result == kActivity_Started;
      mesh_autoriser_emission(!s_ble_annonce);
      break;
    case DeviceEventType::kCommissioningComplete:
      ESP_LOGI(TAG, "mise en service terminee");
      s_fabriques = chip::Server::GetInstance().GetFabricTable().FabricCount();
      break;
    case DeviceEventType::kFabricCommitted:
      s_fabriques = chip::Server::GetInstance().GetFabricTable().FabricCount();
      break;
    case DeviceEventType::kFabricRemoved: {
      // Derniere fabrique retiree depuis Maison : la fenetre de mise en service
      // se rouvre (DNS-SD, 300 s), comme la bibliotheque Arduino du Halo le faisait.
      s_fabriques = chip::Server::GetInstance().GetFabricTable().FabricCount();
      if (s_fabriques != 0) break;
      chip::CommissioningWindowManager &fenetre = chip::Server::GetInstance().GetCommissioningWindowManager();
      if (!fenetre.IsCommissioningWindowOpen()) {
        const CHIP_ERROR err = fenetre.OpenBasicCommissioningWindow(chip::System::Clock::Seconds16(300),
                                                                    chip::CommissioningWindowAdvertisement::kDnssdOnly);
        if (err != CHIP_NO_ERROR) ESP_LOGE(TAG, "fenetre de mise en service non rouverte : %" CHIP_ERROR_FORMAT, err.Format());
      }
      break;
    }
    default:
      break;
  }
}

static void rappel_role(void *arg, esp_event_base_t base, int32_t id, void *donnees) {
  (void)arg;
  (void)base;
  (void)id;
  s_role = static_cast<const esp_openthread_role_changed_event_t *>(donnees)->current_role;
}

// --- Identite (spec 6.1)

// Numero de serie AMARAN-<MAC en 12 hexa>, lu par la pile dans chip-factory.
static void ecrire_numero_de_serie(void) {
  uint8_t mac[8] = {0};  // 8 octets : lecon du Halo (certaines lectures rendent un EUI-64 sur le C6)
  if (esp_read_mac(mac, ESP_MAC_BASE) != ESP_OK) return;
  char serie[20];
  snprintf(serie, sizeof(serie), "AMARAN-%02X%02X%02X%02X%02X%02X", mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
  nvs_handle_t h;
  if (nvs_open("chip-factory", NVS_READWRITE, &h) != ESP_OK) return;
  char lu[20] = {0};
  size_t n = sizeof(lu);
  if (nvs_get_str(h, "serial-num", lu, &n) != ESP_OK || strcmp(lu, serie) != 0) {
    if (nvs_set_str(h, "serial-num", serie) == ESP_OK) nvs_commit(h);
  }
  nvs_close(h);
}

// --- Lampes dans Maison (spec N lampes 5 et 7)

// Le type d'appareil que donne le catalogue. Seule la lampe a intensite variable
// est realisee : un modele CCT ou couleur s'ajoutera ici, une fois verifie avec la
// vraie lampe.
static esp_err_t ajouter_type(endpoint_t *ep, const catalogue_modele_t *m) {
  switch (m->type) {
    case CATALOGUE_LAMPE_VARIABLE:
    case CATALOGUE_LAMPE_TEMPERATURE:
    case CATALOGUE_LAMPE_COULEUR:
    default: {
      endpoint::dimmable_light::config_t cfg_lampe;
      // Defauts d'esp-matter a 0 : ils eteindraient les lampes, ou les baisseraient
      // au minimum, a chaque demarrage. Nuls : rien ne change (spec 6.5).
      cfg_lampe.on_off_lighting.start_up_on_off = nullptr;
      cfg_lampe.level_control_lighting.start_up_current_level = nullptr;
      return endpoint::dimmable_light::add(ep, &cfg_lampe);
    }
  }
}

esp_err_t pont_exposer(int lampe, const liste_lampe_t *l) {
  if (lampe < 0 || lampe >= LISTE_CAPACITE || !l) return ESP_ERR_INVALID_ARG;
  if (!esp_matter::is_started() || !s_verrou_exposition) return ESP_ERR_INVALID_STATE;
  xSemaphoreTake(s_verrou_exposition, portMAX_DELAY);
  if (s_ep_lampe[lampe]) {
    xSemaphoreGive(s_verrou_exposition);
    return ESP_OK;
  }
  const catalogue_modele_t *m = catalogue_trouver(l->code);
  endpoint_t *ep = NULL;
  bool pret = false;
  {
    lock::ScopedChipStackLock verrou(portMAX_DELAY);
    endpoint::bridged_node::config_t cfg_pontee;
    snprintf(cfg_pontee.bridged_device_basic_information.unique_id,
             sizeof(cfg_pontee.bridged_device_basic_information.unique_id), "%02X%02X%02X%02X%02X%02X", l->mac[0],
             l->mac[1], l->mac[2], l->mac[3], l->mac[4], l->mac[5]);
    // Son numero s'il en a un, deja passe par le compteur d'esp-matter (resume) ;
    // sinon, ou si ce compteur est reparti (desappairage complet), le suivant.
    const uint16_t numero = s_numero[lampe] ? s_numero[lampe] : l->endpoint;
    if (numero) ep = endpoint::bridged_node::resume(s_noeud, &cfg_pontee, ENDPOINT_FLAG_BRIDGE, numero, NULL);
    if (!ep) ep = endpoint::bridged_node::create(s_noeud, &cfg_pontee, ENDPOINT_FLAG_BRIDGE, NULL);
    if (ep) pret = ajouter_type(ep, m) == ESP_OK && endpoint::set_parent_endpoint(ep, s_agregateur) == ESP_OK;
    if (pret) {
      snprintf(s_nom_lampe[lampe], sizeof(s_nom_lampe[lampe]), "%s", l->nom);
      cluster_t *pontee = cluster::get(ep, BridgedDeviceBasicInformation::Id);
      if (pontee) {
        // Sans NONVOLATILE (create_node_label le mettrait en NVS, et ce premier nom
        // resterait) : le nom de la base prime a chaque demarrage.
        attribute::create(pontee, BridgedDeviceBasicInformation::Attributes::NodeLabel::Id,
                          ATTRIBUTE_FLAG_WRITABLE, esp_matter_char_str(s_nom_lampe[lampe], strlen(s_nom_lampe[lampe])),
                          32);
      }
      // Les etats relus changent CurrentLevel souvent : ecriture en flash differee.
      attribute::set_deferred_persistence(
          attribute::get(endpoint::get_id(ep), LevelControl::Id, LevelControl::Attributes::CurrentLevel::Id));
    }
  }
  if (!pret) {
    if (ep) endpoint::destroy(s_noeud, ep);  // prend le verrou de la pile lui-meme
    xSemaphoreGive(s_verrou_exposition);
    ESP_LOGE(TAG, "lampe %d : endpoint non cree", lampe + 1);
    return ESP_FAIL;
  }
  const uint16_t id = endpoint::get_id(ep);
  s_ordres_des_us[lampe] = esp_timer_get_time() + 2000000;
  // Prend le verrou de la pile : rappels d'init des clusters, liste des parties de
  // l'agregateur annoncee aux abonnes (Maison montre la tuile).
  endpoint::enable(ep);
  s_ep_lampe[lampe] = id;
  s_numero[lampe] = id;
  if (id != l->endpoint) {
    const esp_err_t err = config_maj_endpoint(l->mac, id);
    if (err != ESP_OK) ESP_LOGE(TAG, "lampe %d : numero EP%u non sauve (%s)", lampe + 1, id, esp_err_to_name(err));
  }
  xSemaphoreGive(s_verrou_exposition);
  ESP_LOGI(TAG, "lampe %d dans Maison : EP%u, %s", lampe + 1, id,
           catalogue_connu(l->code) ? m->nom : "modele non catalogue, intensite seule");
  return ESP_OK;
}

esp_err_t pont_masquer(int lampe) {
  if (lampe < 0 || lampe >= LISTE_CAPACITE) return ESP_ERR_INVALID_ARG;
  if (!esp_matter::is_started() || !s_verrou_exposition) return ESP_ERR_INVALID_STATE;
  xSemaphoreTake(s_verrou_exposition, portMAX_DELAY);
  const uint16_t id = s_ep_lampe[lampe];
  esp_err_t err = ESP_OK;
  if (id) {
    endpoint_t *ep;
    {
      lock::ScopedChipStackLock verrou(portMAX_DELAY);
      ep = endpoint::get(s_noeud, id);
    }
    s_ep_lampe[lampe] = 0;  // plus de publication, plus d'ordre
    s_identifie = s_identifie & ~(1u << (2 + lampe));
    s_effet_fin[2 + lampe] = 0;
    // Prend le verrou de la pile : la liste des parties change, Maison retire la tuile.
    if (ep) err = endpoint::destroy(s_noeud, ep);
    ESP_LOGI(TAG, "lampe %d retiree de Maison (EP%u)", lampe + 1, id);
  }
  xSemaphoreGive(s_verrou_exposition);
  return err;
}

uint16_t pont_endpoint(int lampe) { return lampe >= 0 && lampe < LISTE_CAPACITE ? s_ep_lampe[lampe] : 0; }

// --- API

esp_err_t pont_demarrer(const amaran_config_t *cfg, pont_ordre_cb_t ordre) {
  s_ordre = ordre;
  s_verrou_exposition = xSemaphoreCreateMutex();
  if (!s_verrou_exposition) return ESP_ERR_NO_MEM;
  ecrire_numero_de_serie();

  node::config_t cfg_noeud;
  snprintf(cfg_noeud.root_node.basic_information.node_label,
           sizeof(cfg_noeud.root_node.basic_information.node_label), "%s", "Pont amaran");
  // Identify reste sans effet sur la lampe (Maison ne le propose pas, spec 6.1).
  s_noeud = node::create(&cfg_noeud, rappel_attribut, rappel_identification);
  if (!s_noeud) return ESP_FAIL;
  // SerialNumber est facultatif : cree vide, la pile le lit dans chip-factory.
  cluster_t *infos = cluster::get(endpoint::get(s_noeud, 0), BasicInformation::Id);
  if (infos) cluster::basic_information::attribute::create_serial_number(infos, NULL, 0);

  endpoint::aggregator::config_t cfg_agregateur;
  s_agregateur = endpoint::aggregator::create(s_noeud, &cfg_agregateur, ENDPOINT_FLAG_NONE, NULL);
  if (!s_agregateur) return ESP_FAIL;

  // Thread sur la radio du C6 (exemple light d'esp-matter).
  esp_openthread_platform_config_t ot = {};
  ot.radio_config.radio_mode = RADIO_MODE_NATIVE;
  ot.host_config.host_connection_mode = HOST_CONNECTION_MODE_NONE;
  ot.port_config.storage_partition_name = "nvs";
  ot.port_config.netif_queue_size = 10;
  ot.port_config.task_queue_size = 10;
  set_openthread_platform_config(&ot);

  // Role Thread lu dans ses evenements : jamais le verrou d'OpenThread depuis
  // nos taches (lecon du Halo ; sur IDF 5.5.4 un essai rate le laisserait pris).
  const esp_err_t boucle = esp_event_loop_create_default();
  if (boucle != ESP_OK && boucle != ESP_ERR_INVALID_STATE) return boucle;
  esp_event_handler_register(OPENTHREAD_EVENT, OPENTHREAD_EVENT_ROLE_CHANGED, rappel_role, NULL);

  const esp_err_t err = esp_matter::start(rappel_evenement);
  if (err != ESP_OK) return err;
  {
    lock::ScopedChipStackLock verrou(portMAX_DELAY);
    chip::app::InteractionModelEngine::GetInstance()->RegisterReadHandlerAppCallback(&s_plafond);
    s_fabriques = chip::Server::GetInstance().GetFabricTable().FabricCount();
  }
  // Les lampes exposees, juste apres start (le compteur d'esp-matter vient d'etre
  // relu) : dans l'ordre croissant de leur numero, pour qu'apres un desappairage
  // complet (compteur reparti) les memes numeros reviennent. Sans numero : a la fin.
  int ordre_ep[LISTE_CAPACITE];
  int n = 0;
  for (int i = 0; i < cfg->liste.n; i++) {
    if (liste_exposee(&cfg->liste.lampes[i])) ordre_ep[n++] = i;
  }
  for (int a = 1; a < n; a++) {
    const int i = ordre_ep[a];
    const uint32_t cle = cfg->liste.lampes[i].endpoint ? cfg->liste.lampes[i].endpoint : UINT32_MAX;
    int b = a - 1;
    while (b >= 0) {
      const uint16_t eb = cfg->liste.lampes[ordre_ep[b]].endpoint;
      if ((eb ? eb : UINT32_MAX) <= cle) break;
      ordre_ep[b + 1] = ordre_ep[b];
      b--;
    }
    ordre_ep[b + 1] = i;
  }
  for (int k = 0; k < n; k++) pont_exposer(ordre_ep[k], &cfg->liste.lampes[ordre_ep[k]]);
  return ESP_OK;
}

void pont_publier(int lampe, const lampe_etat_t *etat, bool joignable) {
  // Si esp_matter::start() a echoue, app_main garde la console : la pile n'existe pas, et
  // attribute::report y prendrait le verrou et marquerait des attributs. Rien a publier.
  if (lampe < 0 || lampe >= LISTE_CAPACITE || !s_ep_lampe[lampe] || !esp_matter::is_started()) return;
  const uint16_t ep = s_ep_lampe[lampe];
  esp_matter_attr_val_t v = esp_matter_bool(joignable);
  attribute::report(ep, BridgedDeviceBasicInformation::Id, BridgedDeviceBasicInformation::Attributes::Reachable::Id,
                    &v);
  if (!etat) return;
  v = esp_matter_bool(etat->marche);
  attribute::report(ep, OnOff::Id, OnOff::Attributes::OnOff::Id, &v);
  if (etat->intensite == 0) return;  // lampe noire jamais vue allumee : CurrentLevel reste celui de Matter
  uint8_t niveau = lampes_intensite_vers_niveau(etat->intensite);
  if (niveau < PONT_NIVEAU_PLANCHER) niveau = PONT_NIVEAU_PLANCHER;
  v = esp_matter_nullable_uint8(niveau);
  attribute::report(ep, LevelControl::Id, LevelControl::Attributes::CurrentLevel::Id, &v);
}

bool pont_appaire(void) { return s_fabriques > 0; }

bool pont_ble_annonce(void) { return s_ble_annonce; }

bool pont_thread_attache(void) {
  const int r = s_role;
  return r == OT_DEVICE_ROLE_CHILD || r == OT_DEVICE_ROLE_ROUTER || r == OT_DEVICE_ROLE_LEADER;
}

void pont_desappairer(void) {
  if (!esp_matter::is_started()) {
    printf("Matter non demarre : rien a desappairer\n");
    return;
  }
  esp_matter::factory_reset();
}

bool pont_identifie(void) {
  if (s_identifie) return true;
  const uint32_t t = (uint32_t)(esp_timer_get_time() / 1000);
  for (int e = 0; e < EMPLACEMENTS; e++) {
    if (statusled::effectPending(s_effet_fin[e], t)) return true;
  }
  return false;
}

void pont_afficher(void) {
  if (!esp_matter::is_started()) {  // sans la pile, ses fournisseurs n'existent pas (VerifyOrDie)
    printf("Matter non demarre (voir le journal de demarrage)\n");
    return;
  }
  // Tout est lu sous le verrou de la pile, puis imprime apres (la sortie USB
  // peut attendre : la pile n'attend pas avec elle).
  char qr[128] = {0}, manuel[32] = {0}, fabricant[33] = {0}, produit[33] = {0}, serie[33] = {0};
  uint8_t fabriques = 0;
  uint32_t actifs = 0;
  bool codes = false;
  {
    lock::ScopedChipStackLock verrou(portMAX_DELAY);
    fabriques = chip::Server::GetInstance().GetFabricTable().FabricCount();
    actifs = chip::app::InteractionModelEngine::GetInstance()->GetNumActiveReadHandlers(
        chip::app::ReadHandler::InteractionType::Subscribe);
    chip::DeviceLayer::DeviceInstanceInfoProvider *infos = chip::DeviceLayer::GetDeviceInstanceInfoProvider();
    if (!infos || infos->GetVendorName(fabricant, sizeof(fabricant)) != CHIP_NO_ERROR) snprintf(fabricant, sizeof(fabricant), "?");
    if (!infos || infos->GetProductName(produit, sizeof(produit)) != CHIP_NO_ERROR) snprintf(produit, sizeof(produit), "?");
    if (!infos || infos->GetSerialNumber(serie, sizeof(serie)) != CHIP_NO_ERROR) snprintf(serie, sizeof(serie), "?");
    if (fabriques == 0) {
      // Codes d'appairage montres seulement avant la mise en service (lecon du Halo).
      chip::MutableCharSpan qr_span(qr), manuel_span(manuel);
      const chip::RendezvousInformationFlags ble(chip::RendezvousInformationFlag::kBLE);
      codes = GetQRCode(qr_span, ble) == CHIP_NO_ERROR && GetManualPairingCode(manuel_span, ble) == CHIP_NO_ERROR;
    }
  }
  printf("\n=== Matter ===\n");
  if (fabriques) {
    printf("  mise en service : faite (%u fabrique(s))\n", (unsigned)fabriques);
  } else {
    printf("  mise en service : EN ATTENTE\n");
  }
  printf("  Thread          : %s%s\n", otThreadDeviceRoleToString(static_cast<otDeviceRole>(s_role)),
         pont_thread_attache() ? " (attache)" : "");
  printf("  BLE             : %s\n", s_ble_annonce ? "annonce de mise en service EN COURS (Mesh muet)" : "sans annonce");
  printf("  abonnements     : %" PRIu32 " actif(s) ; demandes %" PRIu32 ", plafonnees a %d s %" PRIu32
         ", etablis %" PRIu32 ", termines %" PRIu32 "\n",
         actifs, s_abo_demandes, PONT_PLAFOND_ABONNEMENT_S, s_abo_plafonnes, s_abo_etablis, s_abo_termines);
  if (codes) {
    printf("  code manuel     : %s\n", manuel);
    printf("  QR code         : %s\n", qr);
  }
  printf("  identite        : %s, %s, n/s %s\n", fabricant, produit, serie);
  printf("  version         : %s\n", esp_app_get_description()->version);
  for (int i = 0; i < LISTE_CAPACITE; i++) {
    if (s_ep_lampe[i]) printf("  EP%u             : %s\n", (unsigned)s_ep_lampe[i], s_nom_lampe[i]);
  }
}
