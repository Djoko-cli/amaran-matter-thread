#pragma once
// ===========================================================================
//  Protocole JSON du pont, v1 (docs/PROTOCOLE-JSON.md) : briques pures
//
//  Reprises de json_out.h du pont Halo (commit e114cd5), sans ses messages
//  propres a la lampe BenQ :
//  - Writer : une ligne machine, RS + objet JSON compact + LF, 1024 octets au
//    plus (section 2.2). Chaines echappees ('"' et '\') ; octet de controle
//    remplace par '?' ; UTF-8 valide garde tel quel (noms des lampes), tout
//    autre octet haut remplace par '?' ; jamais de \uXXXX. Au-dela de 1024
//    octets, la ligne est marquee trop longue : jamais emise.
//  - Messages communs : reponse, battement, fin de session, voyant, journal.
//  - Mecaniques de la session : prefixe id= des lignes de l'hote, assemblage
//    des lignes recues, plafonds de debit, cadence, file des lignes
//    periodiques, bail.
//
//  Pur et sans ESP-IDF : teste sur le Mac (tests/hote/test_json.cpp). La
//  session, l'ecriture sur l'USB et les instantanes sont dans
//  firmware/main/json_pont.cpp.
// ===========================================================================
#include <stddef.h>
#include <stdint.h>

namespace jsonp {

constexpr uint8_t kVersion = 1;         // v : version majeure
constexpr uint8_t kRev = 0;             // hello.rev : revision mineure (ajouts)
constexpr size_t kLineMax = 1024;       // RS et LF compris
constexpr size_t kBudget = 896;         // pire cas vise par message (marge de 128 pour les ajouts)
constexpr size_t kCmdMax = 127;         // ligne de l'hote, prefixe id= compris
constexpr size_t kCmdTextMax = 40;      // reponse.cmd
constexpr size_t kMsgMax = 120;         // reponse.msg
constexpr size_t kLogTextMax = 127;     // log.txt
constexpr size_t kStrMax = 255;         // toute autre chaine
constexpr uint8_t kRS = 0x1E;
constexpr uint8_t kCtrlU = 0x15;        // vide la ligne en cours de saisie
constexpr uint32_t kIdMax = 999999999;  // id=<1..999999999>

// ---------------------------------------------------------------------------
//  Ecrivain d'une ligne machine
// ---------------------------------------------------------------------------

class Writer {
 public:
  // Ouvre la ligne : RS {"v":1,"t":type,"n":n,"ms":ms. Le champ suivant d'un
  // message en blocs est "bloc" (str("bloc", ...)).
  void begin(const char *type, uint32_t n, uint32_t ms);
  // Champs. k nul : element du tableau ouvert. Les cles sont des litteraux
  // ASCII du firmware, jamais echappees.
  void str(const char *k, const char *v, size_t max = kStrMax);  // v nul : null ; max octets de v
  void u32(const char *k, uint32_t v);
  void i32(const char *k, int32_t v);
  void boolean(const char *k, bool v);
  void null(const char *k);
  void hex(const char *k, const uint8_t *p, size_t n);  // "C5A5" (majuscules, sans 0x) ; n == 0 : ""
  void hexU32(const char *k, uint32_t v, uint8_t digits);  // "3FA2C901", "7F38"
  void obj(const char *k);
  void arr(const char *k);
  void end();  // ferme l'objet ou le tableau ouvert
  // Ferme la ligne (} LF). false : plus de kLineMax octets, ou objets mal
  // fermes (bogue) ; la ligne ne doit pas etre emise.
  bool finish();
  const uint8_t *data() const { return buf_; }
  size_t size() const { return len_; }
  bool overflow() const { return over_; }

 private:
  static constexpr uint8_t kDepth = 8;
  void put(char c);
  void puts(const char *s);
  void sep(const char *k);
  void num(uint32_t v, bool neg);
  void open(const char *k, char o, char c);
  uint8_t buf_[kLineMax];
  size_t len_ = 0;
  bool over_ = false, bad_ = false;
  uint8_t depth_ = 0;
  bool first_[kDepth] = {};
  char close_[kDepth] = {};
};

// Longueur de la sequence UTF-8 valide qui commence en s (2 a 4 octets, s[0]
// >= 0x80), au plus n octets lus ; 0 si elle n'est pas valide (octet de
// suite isole, sequence trop longue ou coupee, surrogat, au-dela de U+10FFFF).
size_t utf8Seq(const uint8_t *s, size_t n);

// ---------------------------------------------------------------------------
//  Messages communs
// ---------------------------------------------------------------------------

// cmdId : id de la commande de la console en cours (0 : null), comme le bloc sante.
void heartbeat(Writer &w, uint32_t n, uint32_t ms, uint32_t boot, uint32_t upS, uint32_t lost, uint32_t cmdId);
void sessionEnd(Writer &w, uint32_t n, uint32_t ms, const char *cause);  // t "fin" : commande, bail
void led(Writer &w, uint32_t n, uint32_t ms, const char *motif, const char *before, bool test, uint32_t depuisMs);
void logLine(Writer &w, uint32_t n, uint32_t ms, const char *src, const char *niv, const char *txt, uint32_t skipped);

// Message reponse (section 6.3).
struct Reply {
  enum Suite : uint8_t { SuiteNone, SuiteOrder, SuiteNothing };  // absent, ordre, aucune
  uint32_t id = 0;
  bool fin = true;              // false : etape debut
  const char *cmd = "";         // la commande sans le prefixe, tronquee a kCmdTextMax
  bool ok = true;
  const char *code = "ok";
  const char *msg = nullptr;    // nul : absent ; tronque a kMsgMax
  uint32_t durMs = 0;           // fin seulement
  Suite suite = SuiteNone;
  uint8_t lampe = 0;            // ordre d'une lampe (suite ordre) : son numero, 1..16 ; 0 : absent
  bool hasLease = false;        // bail_s, up_s (json 1, json ping)
  uint32_t leaseS = 0, upS = 0;
};
void reply(Writer &w, uint32_t n, uint32_t ms, const Reply &r);

// ---------------------------------------------------------------------------
//  Lignes de l'hote
// ---------------------------------------------------------------------------

// Prefixe "id=<n> " (n decimal 1..999999999) en tete de ligne, espaces de tete
// ignores. true : *id rempli et *rest pointe sur la commande (espaces sautes).
// false : pas de prefixe valide, *rest = line.
bool parseIdPrefix(char *line, uint32_t *id, char **rest);
// Copie la commande pour reponse.cmd : kCmdTextMax octets au plus.
void copyCmd(char out[kCmdTextMax + 1], const char *cmd);
// reponse.cmd ne renvoie jamais une cle : 'mesh cles <reseau> <application>'
// devient 'mesh cles'.
void maskCmd(char *shown);

// Assemblage des octets recus en lignes (tache de la console, mode machine).
// Octets de controle ignores, sauf LF, CR, Ctrl-U et retour arriere, pour
// qu'aucun RS ne revienne dans un message ; les octets hauts (UTF-8 des noms)
// sont gardes. Au-dela de kCmdMax octets, la ligne est marquee trop longue
// (refusee a son LF, rien n'est execute).
class LineAssembler {
 public:
  enum class Ev : uint8_t { None, Byte, Erase, Clear, Line };
  Ev feed(uint8_t c);
  char *text();  // ligne terminee par 0 (apres Ev::Line)
  bool tooLong() const { return tooLong_; }
  uint8_t length() const { return len_; }
  void reset() {
    len_ = 0;
    tooLong_ = false;
  }

 private:
  char buf_[kCmdMax + 1] = {};
  uint8_t len_ = 0;
  bool tooLong_ = false;
};

// ---------------------------------------------------------------------------
//  Debit
// ---------------------------------------------------------------------------

// Plafond par fenetre d'une seconde. Au-dela, l'evenement n'est pas produit
// (aucun n consomme) et le suivant du meme type porte 'sautes'.
class RateCap {
 public:
  explicit RateCap(uint16_t perSecond) : limit_(perSecond) {}
  bool available(uint32_t now);  // place dans la fenetre en cours
  void take() { count_++; }
  void skip() { skipped_++; }
  uint32_t takeSkipped() {
    const uint32_t s = skipped_;
    skipped_ = 0;
    return s;
  }

 private:
  uint16_t limit_, count_ = 0;
  bool started_ = false;
  uint32_t winAt_ = 0, skipped_ = 0;
};

// Au plus kLines lignes acceptees par kWindowMs glissantes (section 6.5).
class Cadence {
 public:
  static constexpr uint8_t kLines = 20;
  static constexpr uint32_t kWindowMs = 1000;
  bool allow(uint32_t now);  // true : ligne acceptee et comptee

 private:
  uint32_t at_[kLines] = {};
  uint8_t idx_ = 0, n_ = 0;
};

// ---------------------------------------------------------------------------
//  File des lignes periodiques (section 2.3)
// ---------------------------------------------------------------------------

constexpr uint32_t kLateMs = 500;  // ligne periodique perdue apres ce retard

// Une ligne a former a son tour. arg : la lampe (0..15) pour ConfigLampe et
// EtatLampe, la place de la reponse differee pour Reply.
enum class Item : uint8_t {
  HelloBase, HelloId, ConfigCatalogue, ConfigMesh, ConfigLampe, EtatPont, EtatLampe, EtatSante, CptMesh,
  NetMatter, NetThread, Heartbeat, Reply
};
struct Queued {
  Item item;
  uint8_t arg;
  bool session;  // periodique ou instantane de 'json 1' : retire a la fin du mode machine
  uint32_t at;   // mise en file (ou derniere demande explicite fondue dedans)
};

class Queue {
 public:
  static constexpr uint8_t kN = 48;  // un instantane complet a 16 lampes : 42 lignes
  // Ajoute en queue. Un element deja en file (meme item et meme arg, hors
  // Reply) n'est pas double ; une demande explicite (session faux) fondue
  // dedans le rend explicite et repart de maintenant (son retard ne compte
  // que depuis la demande). false : file pleine.
  bool push(Item item, uint32_t now, bool session, uint8_t arg = 0);
  const Queued *front() const { return n_ ? &q_[head_] : nullptr; }
  void pop();
  uint8_t size() const { return n_; }
  bool has(Item item, uint8_t arg = 0) const;
  // Retire de la tete les lignes en retard de plus de lateMs et rend leur
  // nombre (n consomme, json_perdus). Une reponse n'est jamais perdue pour
  // retard : elle arrete le balayage, les lignes derriere elle attendent.
  uint8_t dropLate(uint32_t now, uint32_t lateMs = kLateMs);
  // Retire les elements de session ; ceux qui restent gardent leur ordre.
  uint8_t dropSession();
  void clear() { head_ = n_ = 0; }

 private:
  Queued q_[kN] = {};
  uint8_t head_ = 0, n_ = 0;
};

// ---------------------------------------------------------------------------
//  Bail (section 3.5)
// ---------------------------------------------------------------------------

// Le bail court depuis le plus recent : dernier octet recu, ou fin de la
// derniere commande (une commande longue ne le fait pas expirer).
// leaseS nul : sans bail, jamais expire.
bool leaseExpired(uint32_t now, uint32_t lastRx, uint32_t lastCmd, uint16_t leaseS);

}  // namespace jsonp
