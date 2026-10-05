// Tests sur le Mac du protocole JSON (components/protocole). Les briques reprises du
// pont Halo gardent ses tests (tools/host_tests/test_json.cpp, commit e114cd5) :
// ecrivain, prefixe id=, assemblage, debit, cadence, file, bail. Puis les
// messages du pont amaran : chaque exemple de docs/PROTOCOLE-JSON.md (ligne qui
// commence par <RS>) doit sortir tel quel d'ici, chaque message forme ici doit y
// figurer, et le pire cas de chacun tient dans le budget de 896 octets.
// Lancer : sh tests/hote/lancer.sh. Avec --exemples : imprime les lignes formees.
#include <stdio.h>
#include <string.h>

#include <fstream>
#include <set>
#include <string>

#include "catalogue.h"
#include "json_amaran.h"
#include "json_ligne.h"

using namespace jsonp;

static int gChecks = 0, gFails = 0;
static bool gImprimer = false;

#define CHECK(cond, ...)                                      \
  do {                                                        \
    gChecks++;                                                \
    if (!(cond)) {                                            \
      if (++gFails <= 40) {                                   \
        printf("ECHEC %s:%d : ", __FILE__, __LINE__);         \
        printf(__VA_ARGS__);                                  \
        printf("\n");                                         \
      }                                                       \
    }                                                         \
  } while (0)

static Writer gW;

// Ferme la ligne et la rend telle qu'elle partirait (RS ... LF).
static std::string finish(Writer &w, bool *ok = nullptr) {
  const bool good = w.finish();
  if (ok) *ok = good;
  return std::string((const char *)w.data(), w.size());
}

static std::string framed(const char *json) { return std::string("\x1e") + json + "\n"; }

static void expectLine(Writer &w, const char *json, const char *what) {
  bool ok = false;
  const std::string got = finish(w, &ok);
  const std::string want = framed(json);
  CHECK(ok && got == want, "%s :\n  obtenu  %s  attendu %s", what, got.c_str() + (got.empty() ? 0 : 1),
        want.c_str() + 1);
}

// ---------------------------------------------------------------------------
//  Ecrivain
// ---------------------------------------------------------------------------

static void testWriter() {
  gW.begin("x", 5, 7);
  expectLine(gW, "{\"v\":1,\"t\":\"x\",\"n\":5,\"ms\":7}", "enveloppe seule");

  // Ordre v, t, n, ms, puis bloc ; entiers extremes ; imbrication.
  gW.begin("etat", 4294967295u, 4294967295u);
  gW.str("bloc", "lampe");
  gW.i32("neg", -2147483647 - 1);
  gW.i32("pos", 2147483647);
  gW.u32("zero", 0);
  gW.obj("o");
  gW.arr("a");
  gW.u32(nullptr, 1);
  gW.str(nullptr, "b");
  gW.obj(nullptr);
  gW.boolean("t", true);
  gW.null("z");
  gW.end();
  gW.end();
  gW.boolean("f", false);
  gW.end();
  gW.arr("vide");
  gW.end();
  expectLine(gW,
             "{\"v\":1,\"t\":\"etat\",\"n\":4294967295,\"ms\":4294967295,\"bloc\":\"lampe\",\"neg\":-2147483648,"
             "\"pos\":2147483647,\"zero\":0,\"o\":{\"a\":[1,\"b\",{\"t\":true,\"z\":null}],\"f\":false},\"vide\":[]}",
             "imbrication et entiers extremes");

  // Echappement : '"' et '\', octets de controle -> '?', jamais de \u ; UTF-8 valide garde.
  gW.begin("log", 1, 2);
  gW.str("s", "a\"b\\c\x01\x1e\x7f\xc3\xa9 ~");
  gW.str("tronq", "abcdefgh", 3);
  gW.str("tronq_esc", "\"\"\"\"", 2);  // max compte les octets de la valeur, pas l'echappement
  gW.str("nul", nullptr);
  expectLine(gW,
             "{\"v\":1,\"t\":\"log\",\"n\":1,\"ms\":2,\"s\":\"a\\\"b\\\\c???\xc3\xa9 ~\",\"tronq\":\"abc\","
             "\"tronq_esc\":\"\\\"\\\"\",\"nul\":null}",
             "echappement");

  // Hexa.
  const uint8_t b[3] = {0x0A, 0xFF, 0x2E};
  gW.begin("h", 0, 0);
  gW.hex("b", b, 3);
  gW.hex("vide", b, 0);
  gW.hexU32("boot", 0x3FA2C901, 8);
  gW.hexU32("adresse", 0x7F38, 4);
  gW.hexU32("petit", 0x5, 4);
  expectLine(gW,
             "{\"v\":1,\"t\":\"h\",\"n\":0,\"ms\":0,\"b\":\"0AFF2E\",\"vide\":\"\",\"boot\":\"3FA2C901\","
             "\"adresse\":\"7F38\",\"petit\":\"0005\"}",
             "hexa");

  // Mal ferme : jamais emis.
  bool ok = true;
  gW.begin("x", 0, 0);
  gW.obj("o");
  finish(gW, &ok);
  CHECK(!ok, "objet non ferme accepte");
  gW.begin("x", 0, 0);
  gW.end();
  finish(gW, &ok);
  CHECK(!ok, "fermeture en trop acceptee");

  // Taille : exactement 1024 octets (RS et LF compris) passe, 1025 non.
  for (int extra = 0; extra < 2; extra++) {
    gW.begin("x", 0, 0);
    // enveloppe : RS {"v":1,"t":"x","n":0,"ms":0 = 1 + 27 ; ,"p":"..." = 7 + len ; } LF = 2
    const size_t head = 1 + strlen("{\"v\":1,\"t\":\"x\",\"n\":0,\"ms\":0");
    const size_t pad = kLineMax - head - 7 - 2 + (size_t)extra;
    std::string s(pad, 'a');
    gW.str("p", s.c_str(), pad);
    const bool good = gW.finish();
    CHECK(good == (extra == 0) && (!good || gW.size() == kLineMax), "limite de 1024 octets (extra %d, taille %zu)",
          extra, gW.size());
    CHECK(gW.size() <= kLineMax, "jamais plus de 1024 octets en tampon (%zu)", gW.size());
  }
  // Un depassement enorme reste borne et refuse.
  gW.begin("x", 0, 0);
  for (int i = 0; i < 300; i++) gW.u32("k", 4294967295u);
  CHECK(!gW.finish() && gW.overflow() && gW.size() <= kLineMax, "depassement borne");
}

// Le nom d'une lampe vient d'amaran Desktop : de l'UTF-8 (accents), garde tel quel,
// sauf une sequence invalide ou coupee par la longueur maximale.
static void testUtf8() {
  const uint8_t e[] = {0xC3, 0xA9};               // e accent aigu
  const uint8_t euro[] = {0xE2, 0x82, 0xAC};      // euro
  const uint8_t emoji[] = {0xF0, 0x9F, 0x92, 0xA1};
  CHECK(utf8Seq(e, 2) == 2 && utf8Seq(euro, 3) == 3 && utf8Seq(emoji, 4) == 4, "2, 3 et 4 octets");
  CHECK(utf8Seq(e, 1) == 0 && utf8Seq(euro, 2) == 0, "sequence coupee");
  const uint8_t suite[] = {0xA9}, trop_longue[] = {0xC0, 0xAF}, e0[] = {0xE0, 0x80, 0xAF};
  const uint8_t surrogat[] = {0xED, 0xA0, 0x80}, haut[] = {0xF4, 0x90, 0x80, 0x80}, f5[] = {0xF5, 0x80, 0x80, 0x80};
  const uint8_t mauvaise_suite[] = {0xC3, 0x28};
  CHECK(!utf8Seq(suite, 1) && !utf8Seq(trop_longue, 2) && !utf8Seq(e0, 3) && !utf8Seq(surrogat, 3) &&
            !utf8Seq(haut, 4) && !utf8Seq(f5, 4) && !utf8Seq(mauvaise_suite, 2),
        "octet de suite isole, formes trop longues, surrogat, au-dela de U+10FFFF, mauvaise suite");
  gW.begin("x", 0, 0);
  gW.str("nom", "Lumi\xc3\xa8re fen\xc3\xaatre");
  gW.str("coupe", "ab\xc3\xa9", 3);   // max tombe au milieu du e accent
  gW.str("invalide", "a\xff\xc3(b");
  expectLine(gW,
             "{\"v\":1,\"t\":\"x\",\"n\":0,\"ms\":0,\"nom\":\"Lumi\xc3\xa8re fen\xc3\xaatre\",\"coupe\":\"ab?\","
             "\"invalide\":\"a?" "?(b\"}",  // "?" "?" : pas de trigraphe
             "UTF-8 garde, sequences invalides ou coupees remplacees");
}

// ---------------------------------------------------------------------------
//  Lignes de l'hote
// ---------------------------------------------------------------------------

static bool idOf(const char *line, uint32_t *id, std::string *rest) {
  char buf[256];
  snprintf(buf, sizeof(buf), "%s", line);
  char *r = nullptr;
  const bool ok = parseIdPrefix(buf, id, &r);
  *rest = r;
  return ok;
}

static void testIdPrefix() {
  uint32_t id = 0;
  std::string rest;
  CHECK(idOf("id=17 lampe 1 niveau 500", &id, &rest) && id == 17 && rest == "lampe 1 niveau 500", "id=17");
  CHECK(idOf("  id=1   json 1", &id, &rest) && id == 1 && rest == "json 1", "espaces");
  CHECK(idOf("id=999999999 json ping", &id, &rest) && id == 999999999 && rest == "json ping", "id maximal");
  CHECK(idOf("id=5", &id, &rest) && id == 5 && rest.empty(), "id seul");
  CHECK(idOf("id=007 x", &id, &rest) && id == 7, "zeros de tete");
  CHECK(!idOf("id=0 json 1", &id, &rest) && rest == "id=0 json 1", "id=0 refuse");
  CHECK(!idOf("id=1000000000 json 1", &id, &rest), "id trop grand");
  CHECK(!idOf("id=0000000001 x", &id, &rest), "plus de 9 chiffres");
  CHECK(!idOf("id= 5 x", &id, &rest), "sans chiffre");
  CHECK(!idOf("id=17lampe", &id, &rest), "sans espace apres le numero");
  CHECK(!idOf("id=-3 x", &id, &rest), "negatif");
  CHECK(!idOf("lampe id=3", &id, &rest), "pas en tete");
  CHECK(!idOf("ID=3 x", &id, &rest), "majuscules");
}

static void testMask() {
  char a[] = "mesh cles 000102030405060708090A0B0C0D0E0F 101112131415161718191A1B1C1D1E1F";
  maskCmd(a);
  CHECK(!strcmp(a, "mesh cles"), "mesh cles : les cles ne reviennent jamais ('%s')", a);
  char b[] = "  mesh   cles 0011";
  maskCmd(b);
  CHECK(!strcmp(b, "mesh cles"), "espaces en trop ('%s')", b);
  char c[] = "mesh lampe 1 masquer";
  maskCmd(c);
  CHECK(!strcmp(c, "mesh lampe 1 masquer"), "le reste passe tel quel");
  char d[] = "mesh clesX 00";
  maskCmd(d);
  CHECK(!strcmp(d, "mesh clesX 00"), "seulement le mot cles");
  // Une ligne trop longue n'est jamais executee, mais sa reponse cite la commande :
  // masquee avant d'etre tronquee.
  char cmd[kCmdTextMax + 1];
  char e[] = "mesh cles 000102030405060708090A0B0C0D0E0F 101112131415161718191A1B1C1D1E1F 2021222324";
  maskCmd(e);
  copyCmd(cmd, e);
  CHECK(!strcmp(cmd, "mesh cles"), "masquee puis tronquee");
  copyCmd(cmd, "lampe 1 niveau 500 et encore des mots pour depasser");
  CHECK(strlen(cmd) == kCmdTextMax && !strncmp(cmd, "lampe 1 niveau 500 et encore des mots po", kCmdTextMax),
        "copyCmd : '%s'", cmd);
}

static std::string feedAll(LineAssembler &a, const char *bytes, size_t n, int *lines) {
  std::string last;
  for (size_t i = 0; i < n; i++) {
    if (a.feed((uint8_t)bytes[i]) == LineAssembler::Ev::Line) {
      last = a.text();
      last += a.tooLong() ? "|trop long" : "";
      (*lines)++;
      a.reset();
    }
  }
  return last;
}

static void testAssembler() {
  LineAssembler a;
  int lines = 0;
  const char in1[] = "id=1 json 1\r\n";
  CHECK(feedAll(a, in1, sizeof(in1) - 1, &lines) == "id=1 json 1" && lines == 1, "ligne simple, CR ignore");
  // RS, echappement et autres octets de controle ignores ; octets hauts gardes (UTF-8).
  lines = 0;
  const char in2[] = "le\x1e" "d\x1b\x01 test\n";
  CHECK(feedAll(a, in2, sizeof(in2) - 1, &lines) == "led test" && lines == 1, "octets de controle filtres");
  lines = 0;
  const char in3[] = "mesh lampe 2 0x0004 02:00:00:00:00:02 40065 Lumi\xc3\xa8re\n";
  CHECK(feedAll(a, in3, sizeof(in3) - 1, &lines) == "mesh lampe 2 0x0004 02:00:00:00:00:02 40065 Lumi\xc3\xa8re" &&
            lines == 1,
        "nom en UTF-8 garde");
  // Ctrl-U vide la ligne ; retour arriere.
  lines = 0;
  const char in4[] = "reste d'une session\x15" "\nid=2 json pinh\x08g\n";
  a.reset();
  std::string last = feedAll(a, in4, sizeof(in4) - 1, &lines);
  CHECK(lines == 2 && last == "id=2 json ping", "Ctrl-U puis retour arriere : %d ligne(s), '%s'", lines, last.c_str());
  a.reset();
  a.feed('a');
  a.feed('b');
  CHECK(a.feed(kCtrlU) == LineAssembler::Ev::Clear && a.length() == 0, "Ctrl-U");
  CHECK(a.feed(8) == LineAssembler::Ev::None, "retour arriere sur ligne vide");
  // 127 octets passent, 128 marquent la ligne trop longue ; la suivante repart.
  for (int extra = 0; extra < 2; extra++) {
    a.reset();
    lines = 0;
    std::string s(kCmdMax + (size_t)extra, 'x');
    s += "\n";
    last = feedAll(a, s.c_str(), s.size(), &lines);
    CHECK(lines == 1 && (extra ? last.size() == kCmdMax + strlen("|trop long") : last.size() == kCmdMax),
          "limite de 127 (extra %d) : %zu", extra, last.size());
  }
  lines = 0;
  last = feedAll(a, "ok\n", 3, &lines);
  CHECK(last == "ok", "apres une ligne trop longue");
  // Ctrl-U efface aussi le depassement.
  a.reset();
  std::string s(200, 'y');
  s += "\x15" "json\n";
  lines = 0;
  last = feedAll(a, s.c_str(), s.size(), &lines);
  CHECK(last == "json", "Ctrl-U apres depassement : '%s'", last.c_str());
}

// ---------------------------------------------------------------------------
//  Debit, cadence, file, bail
// ---------------------------------------------------------------------------

static void testRate() {
  RateCap cap(20);
  uint32_t t = 0u - 300;  // a travers le retour a zero de l'horloge
  unsigned passed = 0;
  for (int i = 0; i < 50; i++) {
    if (cap.available(t)) {
      cap.take();
      passed++;
    } else {
      cap.skip();
    }
    t += 10;  // 50 evenements en 500 ms
  }
  CHECK(passed == 20 && cap.takeSkipped() == 30 && cap.takeSkipped() == 0, "20 par seconde : %u", passed);
  t += 1000;
  CHECK(cap.available(t), "nouvelle fenetre");
  // Cadence : 20 lignes par seconde glissante.
  Cadence c;
  uint32_t now = 1000;
  int ok = 0;
  for (int i = 0; i < 25; i++) ok += c.allow(now + (uint32_t)i * 10);  // 25 lignes en 250 ms
  CHECK(ok == 20, "cadence : %d lignes acceptees sur 25", ok);
  CHECK(!c.allow(now + 999), "21e ligne dans la seconde");
  CHECK(c.allow(now + 1000), "la plus ancienne sort de la fenetre");
  CHECK(!c.allow(now + 1001), "une seule place liberee");
  CHECK(c.allow(now + 1010), "la suivante sort a son tour");
}

static void testQueue() {
  Queue q;
  CHECK(q.push(Item::EtatPont, 0, true) && q.push(Item::EtatSante, 1, true) && q.size() == 2, "deux elements");
  CHECK(q.push(Item::EtatPont, 2, true) && q.size() == 2, "doublon ignore");
  CHECK(q.push(Item::EtatLampe, 2, true, 0) && q.push(Item::EtatLampe, 2, true, 1) && q.size() == 4,
        "une ligne par lampe : l'argument distingue");
  CHECK(q.push(Item::EtatLampe, 3, true, 1) && q.size() == 4 && q.has(Item::EtatLampe, 1) &&
            !q.has(Item::EtatLampe, 2),
        "meme lampe : fondue");
  CHECK(q.push(Item::Reply, 3, false, 1) && q.push(Item::Reply, 3, false, 2) && q.size() == 6, "reponses jamais fondues");
  CHECK(q.push(Item::EtatSante, 4, false) && q.size() == 6, "doublon explicite");
  CHECK(q.dropSession() == 3 && q.size() == 3, "fin de session : %u restent", q.size());
  const Queued *f = q.front();
  CHECK(f && f->item == Item::EtatSante && !f->session && f->at == 4, "sante promue, gardee a sa place, retard depuis la demande");
  q.pop();
  f = q.front();
  CHECK(f && f->item == Item::Reply && f->arg == 1, "ordre garde");
  q.clear();
  int pushed = 0;
  for (int i = 0; i < 60; i++) pushed += q.push(Item::Reply, (uint32_t)i, false, (uint8_t)i);
  CHECK(pushed == Queue::kN && q.size() == Queue::kN, "file pleine a %u", q.size());
  CHECK(!q.push(Item::ConfigMesh, 50, false), "rien de plus");
  for (int i = 0; i < 5; i++) q.pop();
  CHECK(q.push(Item::ConfigMesh, 51, false) && q.has(Item::ConfigMesh), "place rendue");
  uint8_t prev = 4;
  bool order = true;
  while (const Queued *e = q.front()) {
    if (e->item == Item::Reply) {
      order &= e->arg == prev + 1;
      prev = e->arg;
    }
    q.pop();
  }
  CHECK(order, "ordre FIFO a travers le tour de l'anneau");
  // Un instantane complet a 16 lampes tient dans la file : hello (2), catalogue,
  // mesh, 16 config, pont, 16 etat, sante, compteurs, reseau (2), reponse.
  q.clear();
  int n = 0;
  n += q.push(Item::HelloBase, 0, true) + q.push(Item::HelloId, 0, true) + q.push(Item::ConfigCatalogue, 0, true) +
       q.push(Item::ConfigMesh, 0, true);
  for (uint8_t i = 0; i < LISTE_CAPACITE; i++) n += q.push(Item::ConfigLampe, 0, true, i);
  n += q.push(Item::EtatPont, 0, true);
  for (uint8_t i = 0; i < LISTE_CAPACITE; i++) n += q.push(Item::EtatLampe, 0, true, i);
  n += q.push(Item::EtatSante, 0, true) + q.push(Item::CptMesh, 0, true) + q.push(Item::NetMatter, 0, true) +
       q.push(Item::NetThread, 0, true) + q.push(Item::Reply, 0, false, 0);
  CHECK(n == 42 && q.size() == 42, "instantane a 16 lampes : %d lignes en file", n);
}

// Retard (500 ms) : la garde de la tache json.
static void testQueueDrain() {
  Queue q;
  CHECK(!q.front() && q.dropLate(1000) == 0, "file vide");
  q.push(Item::EtatPont, 0, true);
  q.push(Item::EtatSante, 100, true);
  q.push(Item::Reply, 200, false, 0);
  q.push(Item::CptMesh, 250, true);
  CHECK(q.dropLate(500) == 0 && q.size() == 4, "500 ms tout juste : rien de perdu");
  CHECK(q.dropLate(700) == 2 && q.front()->item == Item::Reply, "deux periodiques perdues, la reponse arrete le balayage");
  CHECK(q.dropLate(1000000) == 0 && q.size() == 2, "une reponse n'est jamais perdue pour retard");
  q.pop();
  CHECK(q.front()->item == Item::CptMesh && q.dropLate(1000000) == 1 && !q.size(),
        "derriere la reponse, la periodique en retard est perdue a son tour");
  // Fusion : une demande explicite repart de maintenant, pas une periodique.
  q.push(Item::EtatSante, 0, true);
  q.push(Item::EtatSante, 450, false);
  CHECK(q.size() == 1 && !q.front()->session && q.front()->at == 450, "json etat fondu dans une periodique");
  CHECK(q.dropLate(950) == 0 && q.dropLate(951) == 1, "retard compte depuis la demande explicite");
  q.push(Item::EtatPont, 0, true);
  q.push(Item::EtatPont, 400, true);
  CHECK(q.front()->at == 0 && q.dropLate(501) == 1, "periodique fondue : garde son retard");
  q.clear();
  q.push(Item::HelloBase, 0, false);
  q.push(Item::HelloBase, 300, true);
  CHECK(!q.front()->session && q.front()->at == 0, "periodique fondue dans une demande explicite : ni session, ni retard remis");
}

static void testLease() {
  CHECK(!leaseExpired(1000000, 0, 0, 0), "sans bail : jamais");
  CHECK(!leaseExpired(30999, 1000, 500, 30) && leaseExpired(31000, 1000, 500, 30), "30 s apres le dernier octet");
  // Commande longue de 60 s : le bail part de sa fin.
  CHECK(!leaseExpired(90000, 1000, 70000, 30) && leaseExpired(100000, 1000, 70000, 30), "30 s apres la fin de la commande");
  const uint32_t rx = 0xFFFFF000u;
  CHECK(!leaseExpired(rx + 29999u, rx, rx - 0x1000u, 30) && leaseExpired(rx + 30000u, rx, rx - 0x1000u, 30),
        "a travers le retour a zero de l'horloge");
  CHECK(!leaseExpired(9999, 0, 0, 10) && leaseExpired(600000, 0, 0, 600), "bornes 10 et 600 s");
}

// ---------------------------------------------------------------------------
//  Messages du pont amaran, et exemples du document
// ---------------------------------------------------------------------------

static std::set<std::string> gDoc;   // lignes <RS> du document, sans RS ni LF
static std::set<std::string> gVues;  // lignes formees par les exemples ci-dessous

static void lireDocument() {
  std::ifstream f("docs/PROTOCOLE-JSON.md");
  CHECK(f.good(), "docs/PROTOCOLE-JSON.md introuvable (lancer depuis la racine du depot)");
  std::string l;
  while (std::getline(f, l)) {
    if (l.compare(0, 4, "<RS>") == 0) gDoc.insert(l.substr(4));
  }
}

// La ligne formee est un exemple du document : elle doit y figurer telle quelle.
static void exemple(Writer &w, const char *what) {
  bool ok = false;
  const std::string got = finish(w, &ok);
  CHECK(ok && got.size() >= 2 && got[0] == '\x1e' && got.back() == '\n', "%s : ligne mal formee", what);
  CHECK(got.size() <= kBudget, "%s : %zu octets, au-dela du budget de %zu", what, got.size(), kBudget);
  const std::string json = got.substr(1, got.size() - 2);
  gVues.insert(json);
  if (gImprimer) printf("%s\t<RS>%s\n", what, json.c_str());
  CHECK(gDoc.count(json), "%s : absente du document :\n  <RS>%s", what, json.c_str());
}

// Deux lampes de demonstration (MAC inventees, adresses de la base d'amaran Desktop).
static liste_lampe_t lampeListe(uint16_t adresse, uint8_t dernier, const char *nom, uint16_t ep) {
  liste_lampe_t l;
  memset(&l, 0, sizeof(l));
  l.adresse = adresse;
  const uint8_t mac[6] = {0x02, 0x00, 0x00, 0x00, 0x00, dernier};
  memcpy(l.mac, mac, 6);
  snprintf(l.nom, sizeof(l.nom), "%s", nom);
  l.code = CATALOGUE_CODE_COB_60D;
  l.endpoint = ep;
  l.drapeaux = LISTE_VUE;
  return l;
}

static lampe_t lampeLue(uint16_t adresse, bool marche, uint16_t intensite, uint32_t reponse, uint32_t repondues) {
  lampe_t p;
  memset(&p, 0, sizeof(p));
  p.adresse = adresse;
  p.entendue = p.connu = p.joignable = true;
  p.lu.marche = marche;
  p.lu.intensite = intensite;
  p.memoire = intensite;
  p.reponse_ms = reponse;
  p.releves_repondues = repondues;
  return p;
}

static const uint32_t kBoot = 0x3FA2C901;
static const Pile kPiles[] = {{"lampes", 2104}, {"json", 1460},       {"console", 2876},
                              {"socle", 1180},  {"CHIP", 1872},       {"ot_task", 1536},
                              {"nimble_host", 1712}, {"mesh_adv_task", 980}, {"amaran_tx", 1290}};

static EtatSante sante(uint32_t ms) {
  EtatSante e;
  e.boot = kBoot;
  e.upS = ms / 1000;
  e.motif = "operationnel";
  e.depuisMs = 62160;
  e.enService = e.threadAttache = true;
  e.heap = 112640;
  e.heapMin = 103424;
  e.heapBloc = 45056;
  e.piles = kPiles;
  e.nPiles = sizeof(kPiles) / sizeof(kPiles[0]);
  return e;
}

static void testExemples() {
  const liste_lampe_t l1 = lampeListe(0x0002, 0x01, "Lampe bureau", 2);
  liste_lampe_t l2 = lampeListe(0x0004, 0x02, "Lumi\xc3\xa8re fen\xc3\xaatre", 3);
  lampe_t p1 = lampeLue(0x0002, true, 430, 83390, 40);
  lampe_t p2 = lampeLue(0x0004, false, 600, 83398, 41);

  // 9.1 Connexion : instantane de 'json 1'.
  HelloBase hb;
  hb.fw = "0.1.0-d569f01";
  hb.date = "Oct  5 2026";
  hb.heure = "14:02:11";
  hb.idf = "v5.5.4";
  hb.puce = "esp32c6";
  hb.boot = kBoot;
  hb.reset = "logiciel";
  hb.resetN = 3;
  hb.upS = 83;
  helloBase(gW, 0, 83512, hb);
  exemple(gW, "hello base");
  HelloId hi;
  hi.boot = kBoot;
  const uint8_t mac[6] = {0xF0, 0xF5, 0xBD, 0x0A, 0x0B, 0x0C};
  memcpy(hi.mac, mac, 6);
  hi.fabricant = "TEST_VENDOR";
  hi.produit = "TEST_PRODUCT";
  hi.serie = "AMARAN-F0F5BD0A0B0C";
  hi.nom = "Pont amaran";
  helloId(gW, 1, 83522, hi);
  exemple(gW, "hello identite");
  configCatalogue(gW, 2, 83532);
  exemple(gW, "config catalogue");
  ConfigMesh cm;
  cm.cles = true;
  cm.empReseau = "1A2B3C4D";
  cm.empApp = "5E6F7A8B";
  cm.adresse = 0x7F38;
  cm.fenetreMs = 20;
  cm.intervalleMs = 40;
  cm.lampes = 2;
  cm.releveMs = 2000;
  configMesh(gW, 3, 83542, cm);
  exemple(gW, "config mesh");
  configLampe(gW, 4, 83552, 0, l1);
  exemple(gW, "config lampe 1");
  configLampe(gW, 5, 83562, 1, l2);
  exemple(gW, "config lampe 2 (UTF-8)");
  EtatPont ep;
  ep.boot = kBoot;
  ep.upS = 83;
  ep.meshPret = true;
  ep.ordres = 6;
  ep.confirmes = 5;
  ep.tenus = 1;
  ep.delaiTotalMs = 2150;
  ep.delaiMaxMs = 620;
  ep.releves = 41;
  ep.trames = 80;
  etatPont(gW, 6, 83572, ep);
  exemple(gW, "etat pont");
  etatLampe(gW, 7, 83582, 0, p1, l1, 2, 97);
  exemple(gW, "etat lampe 1");
  etatLampe(gW, 8, 83592, 1, p2, l2, 3, 100);
  exemple(gW, "etat lampe 2");
  etatSante(gW, 9, 83602, sante(83602));
  exemple(gW, "etat sante");
  CompteursMesh c;
  c.annonces = 5120;
  c.nidReconnu = 1630;
  c.nidInconnu = 3402;
  c.accesDechiffres = 1500;
  c.etatsLampes = 81;
  c.doublons = 77;
  c.balisesNotres = 17;
  c.baliseVue = true;
  c.baliseMs = 81870;
  c.emis = 64;
  c.seq = 1093;
  c.plancher = 1024;
  compteursMesh(gW, 10, 83612, c);
  exemple(gW, "compteurs mesh");
  ReseauMatter rm;
  rm.demarre = true;
  rm.fabriques = 1;
  rm.demandes = rm.plafonnes = rm.etablis = 2;
  rm.termines = 1;
  rm.plafondS = 20;
  rm.codeManuel = "34970112332";
  rm.qr = "MT:Y.K9042C00KA0648G00";
  reseauMatter(gW, 11, 83622, rm);
  exemple(gW, "reseau matter");
  reseauThread(gW, 12, 83632, "child", true);
  exemple(gW, "reseau thread");
  Reply r;
  r.id = 1;
  r.cmd = "json 1";
  r.durMs = 130;
  r.hasLease = true;
  r.leaseS = 30;
  r.upS = 83;
  reply(gW, 13, 83642, r);
  exemple(gW, "reponse json 1");

  // 9.2 Ordre : accepte, en cours, confirme, voyant.
  r = Reply();
  r.id = 2;
  r.cmd = "lampe 1 niveau 500";
  r.code = "accepte";
  r.suite = Reply::SuiteOrder;
  r.lampe = 1;
  reply(gW, 31, 95002, r);
  exemple(gW, "reponse accepte");
  p1.phase = LAMPE_TRAMES;
  p1.essai = 1;
  p1.veut_intensite = true;
  p1.consigne.intensite = 500;
  etatLampe(gW, 32, 95010, 0, p1, l1, 2, 97);
  exemple(gW, "etat lampe, ordre en cours");
  Ordre o;
  o.lampe = 0;
  o.delaiMs = 410;
  o.essai = 1;
  o.ids[0] = 2;
  o.nIds = 1;
  ordre(gW, 33, 95412, o);
  exemple(gW, "ordre confirme");
  led(gW, 34, 95413, "livree", "operationnel", false, 0);
  exemple(gW, "led livree");
  p1.phase = LAMPE_REPOS;
  p1.veut_intensite = false;
  p1.lu.intensite = 500;
  p1.reponse_ms = 95410;
  p1.releves_repondues = 46;
  etatLampe(gW, 35, 95420, 0, p1, l1, 2, 97);
  exemple(gW, "etat lampe, confirmee");
  led(gW, 36, 95563, "operationnel", "livree", false, 74000);
  exemple(gW, "led operationnel");

  // 9.3 Deja tenu, abandon, alerte.
  r = Reply();
  r.id = 3;
  r.cmd = "lampe 2 off";
  r.code = "accepte";
  r.suite = Reply::SuiteOrder;
  r.lampe = 2;
  reply(gW, 40, 101002, r);
  exemple(gW, "reponse accepte, lampe 2");
  o = Ordre();
  o.lampe = 1;
  o.issue = "tenu";
  o.ids[0] = 3;
  o.nIds = 1;
  ordre(gW, 41, 101003, o);
  exemple(gW, "ordre tenu");
  o = Ordre();
  o.lampe = 1;
  o.issue = "abandon";
  o.delaiMs = 3700;
  o.essai = 3;
  o.ids[0] = 4;
  o.nIds = 1;
  ordre(gW, 52, 108705, o);
  exemple(gW, "ordre abandon");
  led(gW, 53, 108706, "injoignable", "operationnel", false, 0);
  exemple(gW, "led injoignable");
  alerteReleves(gW, 210, 603000, 1, true, 82);
  exemple(gW, "alerte releves");

  // 9.4 Maison : retirer, remettre, premiere reponse.
  r = Reply();
  r.id = 5;
  r.fin = false;
  r.cmd = "mesh lampe 2 masquer";
  r.code = "en_cours";
  reply(gW, 220, 640001, r);
  exemple(gW, "reponse debut masquer");
  r.fin = true;
  r.code = "ok";
  r.durMs = 38;
  reply(gW, 221, 640039, r);
  exemple(gW, "reponse fin masquer");
  lampe(gW, 222, 640040, 1, "masquee", 0);
  exemple(gW, "lampe masquee");
  lampe(gW, 230, 652100, 1, "remise", 3);
  exemple(gW, "lampe remise");
  lampe(gW, 12, 21402, 2, "entree", 4);
  exemple(gW, "lampe entree");

  // 9.5 Bluetooth Mesh inoperant.
  alerteMesh(gW, 40, 125030, "cles_perimees");
  exemple(gW, "alerte mesh");
  alerteMesh(gW, 61, 133210, "ok");
  exemple(gW, "alerte mesh ok");

  // 9.6 Console : commande, usage, inconnue, trop longue, cadence, cles masquees.
  r = Reply();
  r.id = 7;
  r.fin = false;
  r.cmd = "mesh";
  r.code = "en_cours";
  reply(gW, 300, 700002, r);
  exemple(gW, "reponse debut mesh");
  EtatSante es = sante(700003);
  es.cmdId = 7;
  etatSante(gW, 301, 700003, es);
  exemple(gW, "etat sante, commande en cours");
  r.fin = true;
  r.code = "ok";
  r.durMs = 6;
  reply(gW, 302, 700008, r);
  exemple(gW, "reponse fin mesh");
  r = Reply();
  r.id = 8;
  r.cmd = "lampe 9 on";
  r.ok = false;
  r.code = "usage";
  r.msg = "lampe <1-2> on|off|niveau <0-1000>";
  reply(gW, 303, 701000, r);
  exemple(gW, "reponse usage");
  r = Reply();
  r.id = 9;
  r.fin = false;
  r.cmd = "bonjour";
  r.code = "en_cours";
  reply(gW, 304, 702000, r);
  exemple(gW, "reponse debut inconnue");
  r.fin = true;
  r.ok = false;
  r.code = "inconnue";
  reply(gW, 305, 702001, r);
  exemple(gW, "reponse inconnue");
  r = Reply();
  r.id = 10;
  r.cmd = "mesh lampe 1 0x0002 02:00:00:00:00:01 40";
  r.ok = false;
  r.code = "trop_long";
  r.msg = "ligne de plus de 127 octets : rien n'est execute";
  reply(gW, 306, 703000, r);
  exemple(gW, "reponse trop longue");
  r = Reply();
  r.id = 31;
  r.cmd = "json ping";
  r.ok = false;
  r.code = "cadence";
  r.msg = "plus de 20 lignes par seconde : rien n'est execute";
  reply(gW, 307, 704000, r);
  exemple(gW, "reponse cadence");
  r = Reply();
  r.id = 32;
  r.fin = false;
  r.cmd = "mesh cles";
  r.code = "en_cours";
  reply(gW, 310, 710001, r);
  exemple(gW, "reponse debut mesh cles");
  r.fin = true;
  r.code = "ok";
  r.durMs = 21;
  reply(gW, 311, 710022, r);
  exemple(gW, "reponse fin mesh cles");
  r = Reply();
  r.id = 33;
  r.fin = false;
  r.cmd = "mesh lampe 3 masquer";
  r.code = "en_cours";
  reply(gW, 312, 711001, r);
  exemple(gW, "reponse debut erreur");
  r.fin = true;
  r.ok = false;
  r.code = "erreur";
  r.durMs = 1;
  reply(gW, 313, 711002, r);
  exemple(gW, "reponse erreur");

  // 9.7 Journal, battement, fin de session.
  logLine(gW, 400, 720100, "lampes", "alerte",
          "!! lampe 2 : relectures manquees, 82 % repondues sur 10 min : allonger la periode (mesh releve)", 0);
  exemple(gW, "log");
  heartbeat(gW, 401, 722000, kBoot, 722, 0, 0);
  exemple(gW, "hb");
  sessionEnd(gW, 415, 751400, "bail");
  exemple(gW, "fin");

  // Chaque exemple du document a ete forme ici.
  for (const std::string &d : gDoc) CHECK(gVues.count(d), "exemple du document jamais forme :\n  <RS>%s", d.c_str());
}

// Pire cas de chaque message : 16 lampes, noms de 31 octets, compteurs au maximum.
static void testPiresCas() {
  const uint32_t M = 4294967295u;
  bool ok = false;
  liste_lampe_t l;
  memset(&l, 0xFF, sizeof(l));
  memset(l.nom, '"', LISTE_NOM_MAX - 1);  // 31 guillemets : 62 octets echappes
  l.nom[LISTE_NOM_MAX - 1] = 0;
  l.code = M;
  configLampe(gW, M, M, LISTE_CAPACITE - 1, l);
  std::string s = finish(gW, &ok);
  CHECK(ok && s.size() <= kBudget, "config lampe : %zu octets", s.size());
  lampe_t p;
  memset(&p, 0xFF, sizeof(p));
  p.phase = LAMPE_ATTENTE;
  p.veut_marche = p.veut_intensite = true;
  p.consigne.intensite = 65535;
  p.lu.intensite = 65535;
  p.essai = 255;
  etatLampe(gW, M, M, LISTE_CAPACITE - 1, p, l, 65535, 100);
  s = finish(gW, &ok);
  CHECK(ok && s.size() <= kBudget, "etat lampe : %zu octets", s.size());
  HelloBase hb;
  std::string longue(64, 'x');
  hb.fw = hb.date = hb.heure = hb.idf = hb.puce = hb.reset = longue.c_str();
  hb.boot = hb.upS = M;
  hb.resetN = 255;
  hb.session.periodeMs = hb.session.lampesMs = hb.session.compteursMs = hb.session.reseauMs = M;
  hb.session.bailS = 65535;
  helloBase(gW, M, M, hb);
  s = finish(gW, &ok);
  CHECK(ok && s.size() <= kBudget, "hello base : %zu octets", s.size());
  HelloId hi;
  hi.boot = M;
  hi.fabricant = hi.produit = hi.serie = hi.nom = longue.c_str();
  helloId(gW, M, M, hi);
  s = finish(gW, &ok);
  CHECK(ok && s.size() <= kBudget, "hello identite : %zu octets", s.size());
  configCatalogue(gW, M, M);
  s = finish(gW, &ok);
  CHECK(ok && s.size() <= kBudget, "config catalogue : %zu octets (une ligne par modele au-dela)", s.size());
  ConfigMesh cm;
  cm.cles = true;
  cm.empReseau = cm.empApp = longue.c_str();
  cm.adresse = 65535;
  cm.ivNvs = cm.releveMs = M;
  cm.fenetreMs = cm.intervalleMs = 65535;
  cm.lampes = 255;
  configMesh(gW, M, M, cm);
  s = finish(gW, &ok);
  CHECK(ok && s.size() <= kBudget, "config mesh : %zu octets", s.size());
  EtatPont ep;
  ep.boot = ep.upS = ep.ordres = ep.confirmes = ep.abandons = ep.tenus = M;
  ep.delaiTotalMs = ep.delaiMaxMs = ep.lents = ep.releves = ep.trames = M;
  ep.diag = "cles_absentes";
  etatPont(gW, M, M, ep);
  s = finish(gW, &ok);
  CHECK(ok && s.size() <= kBudget, "etat pont : %zu octets", s.size());
  Pile piles[9];
  const char *noms[9] = {"lampes", "json", "console", "socle", "CHIP", "ot_task", "nimble_host", "mesh_adv_task",
                         "amaran_tx"};
  for (int i = 0; i < 9; i++) piles[i] = Pile{noms[i], 2147483647};
  EtatSante e;
  e.boot = e.upS = e.depuisMs = e.heap = e.heapMin = e.heapBloc = e.perdus = e.tropLongs = e.rejets = M;
  e.cmdId = kIdMax;
  e.motif = "identification";
  e.piles = piles;
  e.nPiles = 9;
  etatSante(gW, M, M, e);
  s = finish(gW, &ok);
  CHECK(ok && s.size() <= kBudget, "etat sante : %zu octets", s.size());
  CompteursMesh c;
  c.annonces = c.nidReconnu = c.nidInconnu = c.netmicFaux = c.accesDechiffres = c.etatsLampes = c.doublons = M;
  c.balisesNotres = c.balisesAutres = c.balisesFausses = c.baliseIv = c.baliseMs = M;
  c.baliseVue = true;
  c.baliseDrapeaux = 255;
  c.emis = c.echecsEmission = c.filePleine = c.iv = c.seq = c.plancher = M;
  compteursMesh(gW, M, M, c);
  s = finish(gW, &ok);
  CHECK(ok && s.size() <= kBudget, "compteurs mesh : %zu octets", s.size());
  ReseauMatter rm;
  rm.fabriques = 255;
  rm.demandes = rm.plafonnes = rm.etablis = rm.termines = M;
  rm.plafondS = 65535;
  rm.codeManuel = rm.qr = longue.c_str();
  reseauMatter(gW, M, M, rm);
  s = finish(gW, &ok);
  CHECK(ok && s.size() <= kBudget, "reseau matter : %zu octets", s.size());
  Ordre o;
  o.lampe = LISTE_CAPACITE - 1;
  o.delaiMs = o.idsPerdus = M;
  o.essai = 255;
  for (uint8_t i = 0; i < kIdsMax; i++) o.ids[i] = kIdMax;
  o.nIds = kIdsMax;
  ordre(gW, M, M, o);
  s = finish(gW, &ok);
  CHECK(ok && s.size() <= kBudget, "ordre : %zu octets", s.size());
  Reply r;
  r.id = kIdMax;
  r.fin = true;
  std::string cmd(200, '"');
  r.cmd = cmd.c_str();
  r.ok = false;
  r.code = "deja_traite";
  r.msg = cmd.c_str();
  r.durMs = M;
  r.suite = Reply::SuiteOrder;
  r.lampe = 255;
  r.hasLease = true;
  r.leaseS = r.upS = M;
  reply(gW, M, M, r);
  s = finish(gW, &ok);
  CHECK(ok && s.size() <= kBudget, "reponse : %zu octets", s.size());
  std::string txt(300, '"');
  logLine(gW, M, M, "lampes", "alerte", txt.c_str(), M);
  s = finish(gW, &ok);
  CHECK(ok && s.size() <= kBudget, "log : %zu octets", s.size());
}

int main(int argc, char **argv) {
  gImprimer = argc > 1 && !strcmp(argv[1], "--exemples");
  lireDocument();
  testWriter();
  testUtf8();
  testIdPrefix();
  testMask();
  testAssembler();
  testRate();
  testQueue();
  testQueueDrain();
  testLease();
  testExemples();
  testPiresCas();
  printf("json : %d verifications, %d echecs\n", gChecks, gFails);
  return gFails ? 1 : 0;
}
