// Tests sur le Mac du socle repris du pont Halo (voyant et bouton BOOT) :
// testStatusLed et testBootButton de tools/host_tests/test_halo1.cpp du Halo
// (commit 3f82f76), inchanges. Lancer : sh tests/hote/lancer.sh
#include <initializer_list>
#include <stdio.h>
#include <string.h>

#include "boot_button.h"
#include "status_led.h"

static int gChecks = 0, gFails = 0;

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

// ---------------------------------------------------------------------------
//  LED d'etat (status_led.h) : motifs, priorites, intensite, rythme d'ecriture
// ---------------------------------------------------------------------------

static bool rgbIs(statusled::Rgb c, unsigned r, unsigned g, unsigned b) { return c.r == r && c.g == g && c.b == b; }
static bool dark(statusled::Rgb c) { return rgbIs(c, 0, 0, 0); }

// Changements de couleur vus par la LED sur [from, to[ en tours de 1 ms : ce
// que statusLedPoll() ecrirait (elle n'ecrit que les changements).
static unsigned writesOver(statusled::Logic &l, uint32_t from, uint32_t to) {
  unsigned n = 0;
  statusled::Rgb last = l.frame(from).c;
  for (uint32_t t = from + 1; t != to; t++) {
    const statusled::Rgb c = l.frame(t).c;
    if (c != last) n++;
    last = c;
  }
  return n;
}

static void testStatusLed() {
  using namespace statusled;
  using P = Pattern;

  // Motifs de l'etat du reseau.
  CHECK(rgbIs(render(P::Unpaired, 0), 0, 0, kMax), "bleu au depart");
  CHECK(dark(render(P::Unpaired, kUnpairedHalfMs)), "bleu eteint a la demi-periode");
  CHECK(rgbIs(render(P::Unpaired, 2 * kUnpairedHalfMs + 10), 0, 0, kMax), "bleu rallume");
  const Rgb orange = render(P::Offline, kOfflineHalfMs - 1);
  CHECK(orange.r == kMax && orange.g > 0 && orange.g < kMax / 2 && orange.b == 0, "orange %u %u %u", orange.r,
        orange.g, orange.b);
  CHECK(dark(render(P::Offline, kOfflineHalfMs)) && !dark(render(P::Offline, 2 * kOfflineHalfMs)), "orange lent");
  CHECK(dark(render(P::Online, 0)), "lueur : part du noir");
  CHECK(rgbIs(render(P::Online, kGlowMs / 2), kGlowMax, kGlowMax, kGlowMax), "lueur : sommet a 8");
  CHECK(dark(render(P::Online, kGlowMs)) && dark(render(P::Online, kGlowPeriodMs - 1)), "eteinte entre deux lueurs");
  CHECK(rgbIs(render(P::Online, kGlowPeriodMs + kGlowMs / 2), kGlowMax, kGlowMax, kGlowMax), "lueur suivante a 10 s");
  // Age de la phase (Frame.t, 'led.depuis_ms') : depuis le passage en ligne,
  // depuis le debut d'un evenement ; apres l'eclat vert, la lueur reprend sa
  // phase d'avant, elle ne repart pas de zero.
  {
    Logic l;
    l.setNet(Net::Online, 1000);
    CHECK(l.frame(13500).p == P::Online && l.frame(13500).t == 12500, "en ligne : age depuis le passage en ligne");
    l.delivered(14000);
    CHECK(l.frame(14100).p == P::Delivered && l.frame(14100).t == 100, "eclat vert : age depuis l'eclat");
    CHECK(l.frame(20000).p == P::Online && l.frame(20000).t == 19000, "retour en ligne : la phase d'avant continue");
  }

  // Evenements bornes : vert 150 ms, rouge trois fois, puis noir.
  CHECK(rgbIs(render(P::Delivered, 0), 0, kMax, 0) && rgbIs(render(P::Delivered, kDeliveredMs - 1), 0, kMax, 0),
        "eclat vert");
  CHECK(dark(render(P::Delivered, kDeliveredMs)), "vert fini");
  unsigned blinks = 0;
  bool was = false;
  for (uint32_t t = 0; t < 3 * kUnreachableMs; t++) {
    const Rgb c = render(P::Unreachable, t);
    CHECK(dark(c) || rgbIs(c, kMax, 0, 0), "rouge seulement, t %u", (unsigned)t);
    if (!dark(c) && !was) blinks++;
    was = !dark(c);
  }
  CHECK(blinks == kRedBlinks, "%u clignements rouges au lieu de 3", blinks);

  // Arc-en-ciel : intensite constante, un tour en kRainbowMs, par pas de 40 ms.
  unsigned distinct = 0;
  Rgb prev = render(P::Identify, 0);
  bool sawR = false, sawG = false, sawB = false;
  for (uint32_t t = 0; t < kRainbowMs; t++) {
    const Rgb c = render(P::Identify, t);
    CHECK(c.r + c.g + c.b == kMax, "arc-en-ciel t %u : %u %u %u", (unsigned)t, c.r, c.g, c.b);
    if (t % kStepMs) CHECK(c == prev, "arc-en-ciel change hors d'un pas, t %u", (unsigned)t);
    if (c != prev) distinct++;
    sawR |= c.r == kMax;
    sawG |= c.g == kMax;
    sawB |= c.b == kMax;
    prev = c;
  }
  CHECK(distinct >= 40 && sawR && sawG && sawB, "arc-en-ciel : %u couleurs, R%u V%u B%u", distinct, sawR, sawG, sawB);
  CHECK(render(P::Identify, kRainbowMs) == render(P::Identify, 0), "un tour en 2 s");

  // Bouton BOOT tenu 8 s : rouge, noir, violet, noir, 100 ms chacun, sans fin.
  for (uint32_t t = 0; t < 5000; t++) {
    const Rgb c = render(P::ButtonUnpair, t);
    switch ((t / kUnpairStepMs) % 4) {
      case 0: CHECK(rgbIs(c, kMax, 0, 0), "bouton tenu : rouge, t %u", (unsigned)t); break;
      case 2: CHECK(c.b == kMax && c.r > 0 && c.r < kMax && c.g == 0, "bouton tenu : violet, t %u", (unsigned)t); break;
      default: CHECK(dark(c), "bouton tenu : noir, t %u", (unsigned)t); break;
    }
    CHECK(renderMono(P::ButtonUnpair, t) == ((t / kUnpairMonoHalfMs) % 2 == 0), "LED simple : bouton tenu, t %u",
          (unsigned)t);
  }
  // Violet : different de toutes les couleurs des autres motifs.
  {
    const Rgb violet = render(P::ButtonUnpair, 2 * kUnpairStepMs);
    const P others[] = {P::Unreachable, P::RadioFault, P::Delivered, P::Unpaired, P::Offline, P::Online};
    for (P p : others)
      for (uint32_t t = 0; t < 25000; t += 7) CHECK(render(p, t) != violet, "violet dans %s", patternName(p));
    for (uint32_t t = 0; t < kRainbowMs; t++)
      CHECK(render(P::Identify, t) != violet, "violet dans l'arc-en-ciel, t %u", (unsigned)t);
  }
  // Appui court : eclat blanc de 150 ms, puis noir jusqu'au redemarrage.
  CHECK(rgbIs(render(P::ButtonReboot, 0), kMax, kMax, kMax) &&
            rgbIs(render(P::ButtonReboot, kRebootFlashMs - 1), kMax, kMax, kMax),
        "eclat blanc");
  CHECK(dark(render(P::ButtonReboot, kRebootFlashMs)) && dark(render(P::ButtonReboot, 60000)), "eclat blanc fini");
  CHECK(renderMono(P::ButtonReboot, 0) && !renderMono(P::ButtonReboot, kRebootFlashMs), "LED simple : eclat");
  CHECK(bootbtn::kRebootDelayMs >= kRebootFlashMs + 50, "redemarrage avant la fin de l'eclat");

  // Phase du bouton BOOT -> LED (statusLedPoll) : rouge/violet des l'armement
  // et jusqu'au desappairage, eclat blanc pour le redemarrage, rien sinon.
  {
    using bootbtn::Phase;
    const struct {
      Phase ph;
      Button b;
    } map[] = {{Phase::Idle, Button::None},     {Phase::Held, Button::None},     {Phase::Armed, Button::Unpair},
               {Phase::Reboot, Button::Reboot}, {Phase::Unpair, Button::Unpair}, {Phase::Locked, Button::None}};
    for (const auto &m : map)
      CHECK(buttonFor(m.ph) == m.b, "LED pour la phase %s : %u", bootbtn::phaseName(m.ph), (unsigned)buttonFor(m.ph));
    // Et de bout en bout : la phase choisit le motif, qui passe sur 'led test'
    // et sur le rouge fixe, pas sur Identify.
    Logic l;
    l.setNet(Net::Online, 0);
    l.setFault(true, 0);
    l.startTest(0);
    l.setButton(buttonFor(Phase::Armed), 10);
    CHECK(l.frame(20).p == P::ButtonUnpair, "phase armee : %s", patternName(l.frame(20).p));
    // Relache apres l'armement (Armed -> Unpair) : le motif continue sans
    // repartir du debut (a +110 ms du depart : noir ; repris a 30 : rouge).
    l.setButton(buttonFor(Phase::Unpair), 30);
    CHECK(l.frame(40).p == P::ButtonUnpair && dark(l.frame(120).c), "desappairage : meme motif, meme depart");
    l.setButton(buttonFor(Phase::Held), 130);
    CHECK(l.frame(140).p != P::ButtonUnpair && l.frame(140).p != P::ButtonReboot, "tenu : pas de motif du bouton");
    l.setButton(buttonFor(Phase::Reboot), 150);
    CHECK(l.frame(150).p == P::ButtonReboot && rgbIs(l.frame(150).c, kMax, kMax, kMax), "redemarrage : eclat blanc");
    l.setIdentify(true, 160);
    CHECK(l.frame(170).p == P::Identify, "Identify passe devant le bouton");
    l.setIdentify(false, 180);
    l.setButton(buttonFor(Phase::Locked), 180);
    CHECK(l.frame(190).p != P::ButtonUnpair && l.frame(190).p != P::ButtonReboot, "tenu au demarrage : rien");
  }

  // Intensite : jamais plus de 24 par canal, 8 pour la lueur.
  const P all[] = {P::Identify,   P::ButtonUnpair, P::ButtonReboot, P::Unreachable, P::RadioFault,
                   P::Delivered,  P::Unpaired,     P::Offline,      P::Online};
  for (P p : all) {
    const unsigned cap = p == P::Online ? kGlowMax : kMax;
    for (uint32_t t = 0; t < 25000; t += 7) {
      const Rgb c = render(p, t);
      CHECK(c.r <= cap && c.g <= cap && c.b <= cap, "%s t %u : %u %u %u", patternName(p), (unsigned)t, c.r, c.g, c.b);
    }
    CHECK(patternName(p) && *patternName(p), "nom du motif %u", (unsigned)p);
  }
  // Codes du protocole JSON (7.9), dans l'ordre des motifs : tous distincts.
  static const char *const kCodes[] = {"identification", "desappairage", "redemarrage",
                                       "injoignable",    "panne_radio",  "livree",
                                       "non_appaire",    "hors_reseau",  "operationnel"};
  static_assert(sizeof(kCodes) / sizeof(kCodes[0]) == sizeof(all) / sizeof(all[0]), "un code par motif");
  for (unsigned i = 0; i < sizeof(all) / sizeof(all[0]); i++) {
    CHECK(!strcmp(patternCode(all[i]), kCodes[i]), "code du motif %u : %s", i, patternCode(all[i]));
    for (unsigned j = 0; j < i; j++) CHECK(strcmp(kCodes[i], kCodes[j]), "codes %u et %u egaux", i, j);
  }

  // LED simple : pas de lueur, Identify clignote vite, le reste suit la couleur.
  for (uint32_t t = 0; t < 25000; t += 13) {
    CHECK(!renderMono(P::Online, t), "LED simple allumee en ligne, t %u", (unsigned)t);
    CHECK(renderMono(P::Unpaired, t) == !dark(render(P::Unpaired, t)), "LED simple, bleu t %u", (unsigned)t);
  }
  CHECK(renderMono(P::Identify, 0) && !renderMono(P::Identify, kIdentifyMonoHalfMs), "LED simple : Identify");

  // Module radio en panne : rouge fixe, sans fin (LED simple : allumee).
  for (uint32_t t = 0; t < 700000; t += 997)
    CHECK(rgbIs(render(P::RadioFault, t), kMax, 0, 0) && renderMono(P::RadioFault, t), "rouge fixe, t %u", (unsigned)t);

  // Priorites : Identify > rouge > vert > reseau.
  {
    Logic l;
    const uint32_t t0 = 5000;
    l.setNet(Net::Online, t0);
    CHECK(l.frame(t0).p == P::Online, "en ligne");
    l.delivered(t0 + 100);
    CHECK(l.frame(t0 + 100).p == P::Delivered, "vert par-dessus le reseau");
    l.unreachable(t0 + 120);
    CHECK(l.frame(t0 + 120).p == P::Unreachable, "rouge par-dessus le vert");
    l.setIdentify(true, t0 + 130);
    CHECK(l.frame(t0 + 130).p == P::Identify, "Identify par-dessus tout");
    CHECK(l.frame(t0 + 130).c == render(P::Identify, 0), "arc-en-ciel depuis son debut");
    l.setIdentify(true, t0 + 500);  // deja en cours : la roue ne repart pas
    CHECK(l.frame(t0 + 500).c == render(P::Identify, 370), "Identify continu");
    l.setIdentify(false, t0 + 600);
    CHECK(l.frame(t0 + 600).p == P::Unreachable, "rouge restant apres Identify");
    CHECK(l.frame(t0 + 120 + kUnreachableMs).p == P::Online, "rouge fini, vert deja fini : reseau");
    l.delivered(t0 + 2000);
    CHECK(l.frame(t0 + 2000).p == P::Delivered && l.frame(t0 + 2000 + kDeliveredMs).p == P::Online, "vert seul");
    l.unreachable(t0 + 3000);
    l.unreachable(t0 + 3900);  // nouvel abandon : trois clignements de plus
    CHECK(l.frame(t0 + 3000 + kUnreachableMs).p == P::Unreachable, "rouge relance");
    CHECK(l.frame(t0 + 3900 + kUnreachableMs).p == P::Online, "rouge relance fini");
  }

  // Panne du module radio : au-dessus du vert et du reseau, sous le rouge x3
  // (dont les noirs restent visibles) et Identify ; jusqu'a sa levee.
  {
    Logic l;
    const uint32_t t0 = 40000;
    l.setNet(Net::Unpaired, t0);
    l.setFault(true, t0 + 10);
    CHECK(l.frame(t0 + 10).p == P::RadioFault && rgbIs(l.frame(t0 + 10).c, kMax, 0, 0), "rouge fixe sur le bleu");
    CHECK(l.frame(t0 + 3600000).p == P::RadioFault, "rouge fixe une heure plus tard");
    l.delivered(t0 + 100);
    CHECK(l.frame(t0 + 100).p == P::RadioFault, "rouge fixe par-dessus le vert");
    l.unreachable(t0 + 200);
    CHECK(l.frame(t0 + 200).p == P::Unreachable && dark(l.frame(t0 + 200 + kRedHalfMs).c), "rouge x3 : noirs visibles");
    CHECK(l.frame(t0 + 200 + kUnreachableMs).p == P::RadioFault, "rouge x3 fini : rouge fixe");
    l.setIdentify(true, t0 + 5000);
    CHECK(l.frame(t0 + 5000).p == P::Identify, "Identify par-dessus le rouge fixe");
    l.setIdentify(false, t0 + 6000);
    l.setFault(true, t0 + 7000);  // deja en panne : rien ne change
    CHECK(l.frame(t0 + 7000).p == P::RadioFault, "panne continue");
    l.setFault(false, t0 + 8000);
    CHECK(l.frame(t0 + 8000).p == P::Unpaired, "panne levee : retour au reseau");
  }

  // Bouton BOOT : juste sous Identify, au-dessus de tout le reste (test
  // compris) ; son motif repart du debut a chaque changement de phase.
  {
    Logic l;
    const uint32_t t0 = 70000;
    l.setNet(Net::Online, t0);
    l.setFault(true, t0);
    l.unreachable(t0 + 10);
    l.delivered(t0 + 10);
    l.startTest(t0 + 10);
    l.setButton(Button::Unpair, t0 + 20);
    CHECK(l.frame(t0 + 20).p == P::ButtonUnpair && rgbIs(l.frame(t0 + 20).c, kMax, 0, 0),
          "bouton tenu 8 s par-dessus rouge, vert, panne et test, depuis son debut");
    l.setButton(Button::Unpair, t0 + 250);  // meme phase : le motif continue
    CHECK(l.frame(t0 + 250).c == render(P::ButtonUnpair, 230), "bouton tenu : motif continu");
    l.setIdentify(true, t0 + 300);
    CHECK(l.frame(t0 + 300).p == P::Identify, "Identify par-dessus le bouton");
    l.setIdentify(false, t0 + 400);
    CHECK(l.frame(t0 + 400).p == P::ButtonUnpair, "bouton apres Identify");
    l.setButton(Button::None, t0 + 500);
    CHECK(l.testing() && l.frame(t0 + 500).p == kTest[0].p, "bouton relache : le test continue");
    l.stopTest();
    CHECK(l.frame(t0 + 500).p == P::Unreachable, "test arrete : rouge x3 restant");
    l.setButton(Button::Reboot, t0 + 600);
    CHECK(l.frame(t0 + 600).p == P::ButtonReboot && rgbIs(l.frame(t0 + 600).c, kMax, kMax, kMax),
          "appui court : blanc des le relachement");
    CHECK(l.frame(t0 + 600 + kRebootFlashMs).p == P::ButtonReboot && dark(l.frame(t0 + 600 + kRebootFlashMs).c),
          "appui court : noir avant le redemarrage");
    l.setButton(Button::None, t0 + 900);
    l.setButton(Button::Reboot, t0 + 1000);  // nouvel appui court : nouvel eclat
    CHECK(rgbIs(l.frame(t0 + 1000).c, kMax, kMax, kMax), "nouvel eclat");
    l.setButton(Button::None, t0 + 1100);
    CHECK(l.frame(t0 + 5000).p == P::RadioFault, "bouton fini : panne");
  }

  // Phase du reseau : repart a chaque changement, pas quand l'etat se repete.
  {
    Logic l;
    l.setNet(Net::Offline, 1000);
    l.setNet(Net::Unpaired, 7000);
    CHECK(l.frame(7000).p == P::Unpaired && rgbIs(l.frame(7000).c, 0, 0, kMax), "bleu des le changement");
    l.setNet(Net::Unpaired, 7100);
    CHECK(dark(l.frame(7000 + kUnpairedHalfMs).c), "meme etat : phase gardee");
    l.setNet(Net::Online, 9000);
    CHECK(rgbIs(l.frame(9000 + kGlowMs / 2).c, kGlowMax, kGlowMax, kGlowMax), "lueur au passage en ligne");
  }

  // 'led test' : chaque motif a tour de role, puis retour a la normale.
  {
    Logic l;
    l.setNet(Net::Online, 0);
    const uint32_t t0 = 20000;
    l.startTest(t0);
    uint32_t at = t0, total = 0;
    for (const TestStep &s : kTest) {
      CHECK(s.ms >= 1000, "pas de test trop court");
      CHECK(l.frame(at).p == s.p && l.frame(at + s.ms - 1).p == s.p, "test : %s", patternName(s.p));
      CHECK(l.frame(at).c == render(s.p, 0), "test : %s depuis son debut", patternName(s.p));
      // Chaque pas finit sur du noir, sauf les motifs sans fin qui precedent un
      // noir ou un bleu (la lueur finit noire, le rouge fixe precede le vert).
      if (s.p == P::ButtonReboot || s.p == P::ButtonUnpair || s.p == P::Delivered || s.p == P::Unreachable)
        CHECK(dark(l.frame(at + s.ms - 1).c), "test : %s finit sur du noir", patternName(s.p));
      at += s.ms;
      total += s.ms;
    }
    CHECK(total == testTotalMs(), "duree du test");
    CHECK(total == 21000, "duree du test : %u ms (README : 21 s)", (unsigned)total);
    CHECK(l.testing() && l.frame(at).p == P::Online && !l.testing(), "fin du test");
    l.startTest(at + 10);
    l.setIdentify(true, at + 20);
    CHECK(l.frame(at + 20).p == P::Identify, "Identify pendant le test");
    l.setIdentify(false, at + 30);
    l.stopTest();
    CHECK(l.frame(at + 30).p == P::Online && !l.testing(), "led stop");
  }

  // Retour a zero de millis() : un evenement court le franchit, et un echu ne
  // revient pas 49,7 jours plus tard.
  {
    Logic l;
    l.setNet(Net::Online, 0xFFFFF000u);
    l.delivered(0xFFFFFFF0u);
    CHECK(l.frame(0x00000010u).p == P::Delivered, "vert a cheval sur le retour a zero");
    CHECK(l.frame(0x00000200u).p == P::Online, "vert fini apres le retour a zero");
    CHECK(l.frame(0xFFFFFFF0u + 20).p == P::Online, "vert echu ne revient pas");
  }

  // Rythme d'ecriture : seulement les changements de couleur, jamais a chaque
  // tour de loop() (1 kHz).
  {
    Logic l;
    l.setNet(Net::Online, 0);
    const unsigned online = writesOver(l, 0, 20000);
    CHECK(online >= 4 && online <= 2 * 2 * kGlowMax + 2, "en ligne : %u ecritures en 20 s", online);
    l.setNet(Net::Unpaired, 20000);
    const unsigned blue = writesOver(l, 20000, 22000);
    CHECK(blue == 2000 / kUnpairedHalfMs - 1, "bleu : %u ecritures en 2 s", blue);
    l.setIdentify(true, 30000);
    const unsigned rainbow = writesOver(l, 30000, 30000 + kRainbowMs);
    CHECK(rainbow <= kRainbowMs / kStepMs, "arc-en-ciel : %u ecritures en 2 s", rainbow);
  }

  // Identify par TriggerEffect : fin datee par endpoint (matter_bridge.cpp).
  {
    CHECK(!effectPending(0, 0) && !effectPending(0, 0x80000000u) && !effectPending(0, 0xFFFFFFFFu), "0 : aucun effet");
    CHECK(effectPending(5, 0xFFFFFFF0u), "fin juste apres le retour a zero de millis()");
    CHECK(!effectPending(5, 5) && !effectPending(5, 6), "fin atteinte");
    CHECK(effectPending(5, 4), "1 ms avant la fin");

    const uint32_t now = 1000;
    CHECK(effectEnd(0, kEffectBlink, now) == now + 2000 && effectEnd(0, kEffectOkay, now) == now + 2000,
          "Blink, Okay : 2 s");
    CHECK(effectEnd(0, kEffectBreathe, now) == now + 15000, "Breathe : 15 s");
    CHECK(effectEnd(0, kEffectChannelChange, now) == now + 8000, "ChannelChange : 8 s");
    CHECK(effectEnd(0, 0x42, now) == now + 2000, "effet inconnu : 2 s");
    CHECK(effectEnd(now + 500, kEffectBreathe, now) == now + 15000, "nouvel effet : remplace le precedent");
    CHECK(effectEnd(now + 9000, kEffectStop, now) == 0 && effectEnd(0, kEffectStop, now) == 0, "Stop : fin immediate");
    CHECK(effectEnd(now + 9000, kEffectFinish, now) == now + kEffectFinishMs, "Finish : cycle en cours acheve");
    CHECK(effectEnd(now + 300, kEffectFinish, now) == now + 300, "Finish : un effet presque fini garde sa fin");
    CHECK(effectEnd(0, kEffectFinish, now) == 0, "Finish sans effet : rien ne s'allume");
    CHECK(effectEnd(now - 10, kEffectFinish, now) == 0, "Finish apres un effet echu : rien ne s'allume");

    // A cheval sur le retour a zero, et jamais 0 pour un effet en cours.
    const uint32_t late = 0xFFFFF000u, end = effectEnd(0, kEffectBreathe, late);
    CHECK(effectPending(end, late) && effectPending(end, late + 14999) && !effectPending(end, late + 15000),
          "Breathe a cheval sur le retour a zero");
    CHECK(effectEnd(end, kEffectFinish, late + 100) == late + 100 + kEffectFinishMs, "Finish a cheval");
    CHECK(effectEnd(0, kEffectBlink, 0u - 2000) == 1 && effectPending(1, 0u - 2000), "fin a 0 : decalee a 1");
    CHECK(effectEnd(0x100u, kEffectFinish, 0u - kEffectFinishMs) == 1, "Finish a 0 : decalee a 1");
  }
}

// ---------------------------------------------------------------------------
//  Bouton BOOT (boot_button.h) : seuils, anti-rebond, garde de la broche de
//  strapping, tenu au demarrage, trous de releves, retour a zero de millis()
// ---------------------------------------------------------------------------

namespace {

// Releves simules de la broche : un appel a update() toutes les 'step' ms.
struct Btn {
  bootbtn::Machine m;
  uint32_t now;
  bootbtn::Event ev[32];
  uint32_t at[32];
  unsigned n = 0;
  explicit Btn(uint32_t t0, bool lowAtBoot = false) : now(t0) {
    record(m.update(lowAtBoot, now));  // premier releve : begin()
    now++;
  }
  void record(bootbtn::Event e) {
    if (e == bootbtn::Event::None || n >= 32) return;
    ev[n] = e;
    at[n] = now;
    n++;
  }
  // 'ms' ms au niveau 'low' : releves a now, now + step... (step divise ms).
  void level(bool low, uint32_t ms, uint32_t step = 1) {
    for (uint32_t e = 0; e < ms; e += step) {
      record(m.update(low, now));
      now += step;
    }
  }
  void skip(uint32_t ms) { now += ms; }  // loop() bloquee : aucun releve
  bool only(bootbtn::Event e) const { return n == 1 && ev[0] == e; }
  void clear() { n = 0; }
};

}  // namespace

static void testBootButton() {
  using namespace bootbtn;

  // Appui court : relache a 1999 ms -> redemarrage, 250 ms apres le
  // relachement confirme (30 ms apres le premier releve haut). Aussi a cheval
  // sur le retour a zero de millis().
  for (uint32_t t0 : {1000u, 0xFFFFFFFFu - 1500u, 0xFFFFFFFFu - 1u}) {
    Btn b(t0);
    b.level(false, 500);
    b.level(true, 1999);
    CHECK(b.m.phase() == Phase::Held && b.n == 0, "court : tenu, t0 %08X", (unsigned)t0);
    const uint32_t up = b.now;  // premier releve haut
    b.level(false, kDebounceMs);
    CHECK(b.m.phase() == Phase::Held, "court : relachement pas encore confirme, t0 %08X", (unsigned)t0);
    b.level(false, 1);
    CHECK(b.m.phase() == Phase::Reboot && b.n == 0, "court : redemarrage en attente, t0 %08X", (unsigned)t0);
    CHECK(b.m.lastPressMs() == 1999, "court : %u ms", (unsigned)b.m.lastPressMs());
    b.level(false, 1000);
    CHECK(b.only(Event::Reboot), "court : %u evenement(s), t0 %08X", b.n, (unsigned)t0);
    CHECK(b.n && b.at[0] == up + kDebounceMs + kRebootDelayMs, "court : redemarrage a +%u ms",
          (unsigned)(b.at[0] - up));
    CHECK(b.m.phase() == Phase::Idle, "court : fini");
  }

  // 2000 ms tout juste, et jusqu'a 7999 ms : annule, jamais arme.
  for (uint32_t d : {2000u, 2001u, 5000u, 7998u, 7999u}) {
    Btn b(50000);
    b.level(false, 100);
    b.level(true, d);
    CHECK(b.n == 0 && b.m.phase() == Phase::Held, "%u ms : arme", (unsigned)d);
    b.level(false, 20000);
    CHECK(b.only(Event::Cancelled) && b.m.lastPressMs() == d, "%u ms : %u evenement(s), mesure %u ms", (unsigned)d,
          b.n, (unsigned)b.m.lastPressMs());
    CHECK(b.m.phase() == Phase::Idle, "%u ms : fini", (unsigned)d);
  }

  // Appui long : arme au releve de +7999 ms (8000 ms d'appui), une seule fois ;
  // desappairage 100 ms apres le premier releve haut, pas avant.
  for (uint32_t d : {8000u, 8001u, 60000u}) {
    for (uint32_t t0 : {5000u, 0xFFFFFFFFu - 4000u}) {
      Btn b(t0);
      b.level(false, 100);
      const uint32_t down = b.now;
      b.level(true, d);
      CHECK(b.only(Event::Armed) && b.at[0] == down + kLongMs - 1, "%u ms : arme a +%u ms (%u evenement(s))",
            (unsigned)d, (unsigned)(b.at[0] - down), b.n);
      CHECK(b.m.phase() == Phase::Armed, "%u ms : phase armee", (unsigned)d);
      const uint32_t up = b.now;
      b.level(false, kDebounceMs + 1);
      CHECK(b.m.phase() == Phase::Unpair && b.n == 1, "%u ms : desappairage en attente", (unsigned)d);
      b.level(false, 1000);
      CHECK(b.n == 2 && b.ev[1] == Event::Unpair && b.at[1] == up + kSettleMs,
            "%u ms : desappairage a +%u ms apres le relachement", (unsigned)d, (unsigned)(b.at[1] - up));
      CHECK(b.m.lastPressMs() == d && b.m.phase() == Phase::Idle, "%u ms : mesure %u", (unsigned)d,
            (unsigned)b.m.lastPressMs());
    }
  }

  // Parasites de 30 ms au plus : rien. 31 releves bas : un appui (court).
  {
    Btn b(1000);
    for (int i = 0; i < 50; i++) {
      b.level(true, kDebounceMs);
      b.level(false, 5);
    }
    b.level(false, 1000);
    CHECK(b.n == 0 && b.m.phase() == Phase::Idle, "parasites : %u evenement(s)", b.n);
    b.level(true, kDebounceMs + 1);
    b.level(false, 1000);
    CHECK(b.only(Event::Reboot) && b.m.lastPressMs() == kDebounceMs + 1, "31 ms : appui court");
  }

  // Rebonds a l'appui, pendant l'appui et au relachement : une seule mesure,
  // du premier releve bas du niveau qui tient au premier releve haut du
  // niveau qui tient.
  {
    Btn b(1000);
    b.level(false, 100);
    b.level(true, 3);
    b.level(false, 2);
    b.level(true, 4);
    b.level(false, 1);
    const uint32_t down = b.now;
    b.level(true, 1500);
    b.level(false, 10);
    b.level(true, 400);
    b.level(false, 5);
    b.level(true, 3);
    b.level(false, 2);
    b.level(true, 1);
    const uint32_t up = b.now;
    b.level(false, 1000);
    CHECK(b.only(Event::Reboot), "rebonds : %u evenement(s)", b.n);
    CHECK(b.m.lastPressMs() == up - down, "rebonds : %u ms au lieu de %u", (unsigned)b.m.lastPressMs(),
          (unsigned)(up - down));
    CHECK(b.n && b.at[0] == up + kDebounceMs + kRebootDelayMs, "rebonds : redemarrage a +%u",
          (unsigned)(b.at[0] - up));
  }
  {
    // Rebond pendant un appui long, et juste au releve de +7999 ms : arme au
    // premier releve bas suivant, jamais annule.
    Btn b(1000);
    b.level(false, 100);
    const uint32_t down = b.now;
    b.level(true, 5000);
    b.level(false, 20);
    b.level(true, 2979);
    b.level(false, 5);
    CHECK(b.n == 0, "rebond a +7999 : pas arme");
    b.level(true, 100);
    CHECK(b.only(Event::Armed) && b.at[0] == down + kLongMs + 4, "rebond a +7999 : arme a +%u",
          (unsigned)(b.at[0] - down));
    b.level(false, 1000);
    CHECK(b.n == 2 && b.ev[1] == Event::Unpair, "rebond a +7999 : desappairage");
  }

  // Garde de la broche de strapping : un rebond bas pendant l'attente
  // repousse l'action a 100 ms de releves hauts sans interruption.
  {
    Btn b(1000);
    b.level(false, 100);
    b.level(true, 500);
    b.level(false, 200);
    b.level(true, 10);  // moins de 30 ms : pas un nouvel appui
    const uint32_t last = b.now;
    b.level(false, 1000);
    CHECK(b.only(Event::Reboot) && b.at[0] == last + kSettleMs, "rebond pendant l'attente : redemarrage a +%u",
          (unsigned)(b.at[0] - last));
  }
  {
    Btn b(1000);
    b.level(false, 100);
    b.level(true, 9000);
    for (int i = 0; i < 20; i++) {
      b.level(false, kSettleMs - 1);
      b.level(true, 1);
    }
    CHECK(b.only(Event::Armed) && b.m.phase() == Phase::Unpair, "rebonds apres un appui long : toujours en attente");
    const uint32_t last = b.now;
    b.level(false, 1000);
    CHECK(b.n == 2 && b.ev[1] == Event::Unpair && b.at[1] == last + kSettleMs, "rebonds : desappairage a +%u",
          (unsigned)(b.at[1] - last));
  }

  // Nouvel appui pendant l'attente : l'action est abandonnee, le nouvel appui
  // compte seul.
  {
    Btn b(1000);
    b.level(false, 100);
    b.level(true, 500);
    b.level(false, 60);
    CHECK(b.m.phase() == Phase::Reboot, "attente du redemarrage");
    b.level(true, 3000);
    b.level(false, 1000);
    CHECK(b.n == 2 && b.ev[0] == Event::Dropped && b.ev[1] == Event::Cancelled, "nouvel appui : abandon puis annule");
    b.clear();
    b.level(true, 9000);
    b.level(false, 50);
    CHECK(b.m.phase() == Phase::Unpair, "attente du desappairage");
    b.level(true, 100);
    b.level(false, 1000);
    CHECK(b.n == 3 && b.ev[1] == Event::Dropped && b.ev[2] == Event::Reboot, "nouvel appui court apres un long");
  }

  // Tenu au demarrage : ignore jusqu'a son relachement, meme 20 s ; ensuite,
  // un appui court redemarre normalement.
  {
    Btn b(1000, true);
    CHECK(b.m.phase() == Phase::Locked && b.n == 0, "tenu au demarrage");
    b.level(true, 20000);
    CHECK(b.n == 0 && b.m.phase() == Phase::Locked, "tenu au demarrage : jamais arme");
    b.level(false, 5);
    b.level(true, 5);
    CHECK(b.m.phase() == Phase::Locked, "tenu au demarrage : un rebond ne le libere pas");
    b.level(false, 1000);
    CHECK(b.only(Event::BootReleased) && b.m.phase() == Phase::Idle, "tenu au demarrage : relache, rien fait");
    b.clear();
    b.level(true, 300);
    b.level(false, 1000);
    CHECK(b.only(Event::Reboot), "apres le demarrage : appui court normal");
  }
  {
    Btn b(1000, true);
    b.level(true, 500);
    b.level(false, 2000);
    CHECK(b.only(Event::BootReleased), "tenu brievement au demarrage : rien fait");
  }

  // Derniere garde ratee (bouton rappuye pendant pinSettled()) : la carte
  // relance la machine avec begin(broche basse). Action en attente oubliee,
  // appui en cours ignore jusqu'au relachement, jamais d'action.
  for (bool longPress : {false, true}) {
    Btn b(1000);
    b.level(false, 100);
    b.level(true, longPress ? 9000 : 500);
    b.level(false, kDebounceMs + 1);
    CHECK(b.m.phase() == (longPress ? Phase::Unpair : Phase::Reboot), "garde ratee : action en attente");
    b.clear();
    b.m.begin(true, b.now);
    CHECK(b.m.phase() == Phase::Locked, "garde ratee : verrouille");
    b.level(true, 12000);
    CHECK(b.n == 0 && b.m.phase() == Phase::Locked, "garde ratee : tenu, rien (%u evenement(s))", b.n);
    b.level(false, 5000);
    CHECK(b.only(Event::BootReleased) && b.m.phase() == Phase::Idle, "garde ratee (%s) : relache, rien fait",
          longPress ? "long" : "court");
  }
  {
    // Relance avec la broche deja haute : simplement au repos.
    Btn b(1000);
    b.level(false, 100);
    b.level(true, 500);
    b.level(false, kDebounceMs + 1);
    b.clear();
    b.m.begin(false, b.now);
    b.level(false, 5000);
    CHECK(b.n == 0 && b.m.phase() == Phase::Idle, "relance broche haute : rien en attente");
  }

  // Trous de releves (loop() bloquee) : un front date a plus de kMaxGapMs
  // pres rend la duree incertaine, l'appui est ignore.
  {
    Btn b(1000);
    b.level(false, 100);
    b.level(true, 1000);
    b.skip(kMaxGapMs + 1);  // bloquee au relachement
    b.level(false, 1000);
    CHECK(b.only(Event::Unsure) && b.m.lastGapMs() == kMaxGapMs + 2, "trou au relachement : %u evenement(s), %u ms",
          b.n, (unsigned)b.m.lastGapMs());
  }
  {
    // Trou avant le premier releve bas : un appui court est ignore...
    Btn b(1000);
    b.level(false, 100);
    b.skip(500);
    b.level(true, 1000);
    b.level(false, 1000);
    CHECK(b.only(Event::Unsure), "trou a l'appui : appui court ignore");
  }
  {
    // ... un appui long reste arme : le trou ne pouvait que l'allonger.
    Btn b(1000);
    b.level(false, 100);
    b.skip(500);
    const uint32_t down = b.now;
    b.level(true, 9000);
    b.level(false, 1000);
    CHECK(b.n == 2 && b.ev[0] == Event::Armed && b.at[0] == down + kLongMs - 1 && b.ev[1] == Event::Unpair,
          "trou a l'appui : appui long arme");
  }
  {
    // Trou pendant l'appui (un relachement et un nouvel appui ont pu s'y
    // cacher) : jamais arme, ignore.
    Btn b(1000);
    b.level(false, 100);
    b.level(true, 3000);
    b.skip(2000);
    b.level(true, 10000);
    b.level(false, 1000);
    CHECK(b.only(Event::Unsure), "trou pendant l'appui : %u evenement(s)", b.n);
  }
  {
    // Releves toutes les kMaxGapMs tout juste : acceptes.
    Btn b(1000);
    b.level(false, 1000, kMaxGapMs);
    b.level(true, 1500, kMaxGapMs);
    b.level(false, 2000, kMaxGapMs);
    CHECK(b.only(Event::Reboot) && b.m.lastPressMs() == 1500, "releves espaces de %u ms : appui court",
          (unsigned)kMaxGapMs);
    b.clear();
    b.level(true, 9000, kMaxGapMs);
    b.level(false, 2000, kMaxGapMs);
    CHECK(b.n == 2 && b.ev[0] == Event::Armed && b.ev[1] == Event::Unpair, "releves espaces : appui long");
  }
  {
    // Trou pendant l'attente : 100 ms de releves hauts apres lui.
    Btn b(1000);
    b.level(false, 100);
    b.level(true, 500);
    b.level(false, 50);
    b.skip(5000);
    const uint32_t back = b.now;
    b.level(false, 1000);
    CHECK(b.only(Event::Reboot) && b.at[0] == back + kSettleMs, "trou pendant l'attente : redemarrage a +%u",
          (unsigned)(b.at[0] - back));
  }

  // Proprietes sur des releves aleatoires (rebonds, appuis de toutes durees,
  // trous, tenu au demarrage, retour a zero de millis()) : une action ne part
  // que broche relevee haute, sans trou, depuis kSettleMs au moins ; un
  // redemarrage suit un appui mesure sous 2 s et jamais arme ; un
  // desappairage, un appui arme.
  {
    uint32_t seed = 0x1234567u;
    auto rnd = [&seed](uint32_t n) {
      seed = seed * 1103515245u + 12345u;
      return (seed >> 8) % n;
    };
    struct Obs {
      uint32_t t;
      bool low;
    };
    static Obs hist[1024];
    unsigned reboots = 0, unpairs = 0, unsure = 0, cancelled = 0, bad = 0;
    for (int round = 0; round < 24; round++) {
      Machine m;
      uint32_t now = round % 2 ? 0xFFFFFFFFu - rnd(300000) : rnd(100000);
      bool low = rnd(4) == 0, armed = false;
      Phase before = Phase::Idle;
      unsigned hn = 0;
      for (int run = 0; run < 300; run++) {
        uint32_t len;
        switch (rnd(6)) {
          case 0:
          case 1: len = 1 + rnd(40); break;
          case 2: len = 40 + rnd(400); break;
          case 3: len = 400 + rnd(2500); break;
          case 4: len = 1500 + rnd(1000); break;
          default: len = 6000 + rnd(4000); break;
        }
        const uint32_t end = now + len;
        while ((int32_t)(end - now) > 0) {
          const Event e = m.update(low, now);
          hist[hn % 1024] = Obs{now, low};
          hn++;
          if (m.phase() == Phase::Held && before != Phase::Held) armed = false;
          before = m.phase();
          if (e == Event::Armed) armed = true;
          if (e == Event::Unsure) unsure++;
          if (e == Event::Cancelled) cancelled++;
          if (e == Event::Reboot || e == Event::Unpair) {
            bool ok = false;
            uint32_t prevT = now;
            for (unsigned k = 0; k < hn && k < 1024; k++) {
              const Obs &o = hist[(hn - 1 - k) % 1024];
              if (o.low || prevT - o.t > kMaxGapMs) break;
              prevT = o.t;
              if (now - o.t >= kSettleMs) {
                ok = true;
                break;
              }
            }
            if (!ok && ++bad <= 5) CHECK(ok, "aleatoire : action sans broche haute stable, tour %d t %u", round, now);
            if (e == Event::Reboot) {
              reboots++;
              CHECK(m.lastPressMs() < kShortMaxMs && !armed, "aleatoire : redemarrage apres %u ms (arme %d)",
                    (unsigned)m.lastPressMs(), armed);
            } else {
              unpairs++;
              CHECK(armed && m.lastPressMs() >= kLongMs, "aleatoire : desappairage sans armement (%u ms)",
                    (unsigned)m.lastPressMs());
            }
          }
          // Surtout 1 ms, parfois quelques-unes, rarement un trou de 50 a 400 ms.
          const uint32_t r = rnd(100000);
          now += r < 97000 ? 1 : r < 99995 ? 2 + rnd(20) : 50 + rnd(350);
        }
        low = !low;
      }
    }
    CHECK(bad == 0, "aleatoire : %u action(s) sans broche haute stable", bad);
    CHECK(reboots >= 200 && unpairs >= 50 && unsure >= 50 && cancelled >= 200,
          "aleatoire : %u redemarrage(s), %u desappairage(s), %u incertain(s), %u annule(s)", reboots, unpairs, unsure,
          cancelled);
  }

  // Noms (messages de la console).
  for (int p = 0; p <= (int)Phase::Locked; p++) CHECK(*phaseName((Phase)p) != '?', "nom de phase %d", p);
  for (int e = 0; e <= (int)Event::Unpair; e++) CHECK(*eventName((Event)e) != '?', "nom d'evenement %d", e);
}

// ---------------------------------------------------------------------------


int main() {
  testStatusLed();
  testBootButton();
  printf("socle : %d verifications, %d echecs\n", gChecks, gFails);
  return gFails ? 1 : 0;
}
