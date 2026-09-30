#include "status_led.h"

// ===========================================================================
//  Logique pure (compilee aussi sur l'hote, sans ARDUINO)
// ===========================================================================

namespace statusled {

// Orange : le vert d'une WS2812 parait bien plus fort que son rouge.
static constexpr Rgb kBlue{0, 0, kMax}, kOrange{kMax, kMax / 4, 0}, kGreen{0, kMax, 0}, kRed{kMax, 0, 0};
// Violet : bleu plein, moitie de rouge (le magenta pur se confond avec le rouge
// a cette intensite). Blanc de l'eclat : bien plus vif que la lueur (8).
static constexpr Rgb kViolet{kMax / 2, 0, kMax}, kWhite{kMax, kMax, kMax};

// Ordre du tableau du README ; les motifs bornes (vert, rouge x3, eclat blanc)
// finissent sur du noir, qui separe les pas. Le rouge fixe suit la lueur (noir
// a sa fin) et precede le vert : colle au rouge x3 ou au rouge de depart de
// l'arc-en-ciel, il ne s'en distinguerait pas. Le motif du bouton tenu 8 s
// dure 2000 ms, un multiple de son tour (400 ms) : il finit sur un noir.
const TestStep kTest[kTestSteps] = {
    {Pattern::Unpaired, 3000},    {Pattern::Offline, 4000},      {Pattern::Online, 2000},
    {Pattern::RadioFault, 2000},  {Pattern::Delivered, 1000},    {Pattern::Unreachable, 2000},
    {Pattern::ButtonReboot, 1000}, {Pattern::ButtonUnpair, 2000}, {Pattern::Identify, 4000},
};

uint32_t testTotalMs() {
  uint32_t total = 0;
  for (const TestStep &s : kTest) total += s.ms;
  return total;
}

Rgb wheel(uint16_t hue) {
  hue %= 768;
  const uint8_t up = (uint8_t)((hue % 256) * kMax / 255), down = (uint8_t)(kMax - up);
  switch (hue / 256) {
    case 0: return Rgb{down, up, 0};
    case 1: return Rgb{0, down, up};
    default: return Rgb{up, 0, down};
  }
}

Rgb render(Pattern p, uint32_t t) {
  switch (p) {
    case Pattern::Identify: {
      // Par pas de kStepMs : la couleur ne change que 25 fois par seconde.
      const uint32_t phase = t / kStepMs * kStepMs % kRainbowMs;
      return wheel((uint16_t)(phase * 768 / kRainbowMs));
    }
    case Pattern::ButtonUnpair:
      switch ((t / kUnpairStepMs) % 4) {
        case 0: return kRed;
        case 2: return kViolet;
        default: return Rgb{};
      }
    case Pattern::ButtonReboot: return t < kRebootFlashMs ? kWhite : Rgb{};
    case Pattern::Unreachable: return t < kUnreachableMs && (t / kRedHalfMs) % 2 == 0 ? kRed : Rgb{};
    case Pattern::RadioFault: return kRed;  // fixe : le seul motif qui ne clignote pas
    case Pattern::Delivered: return t < kDeliveredMs ? kGreen : Rgb{};
    case Pattern::Unpaired: return (t / kUnpairedHalfMs) % 2 == 0 ? kBlue : Rgb{};
    case Pattern::Offline: return (t / kOfflineHalfMs) % 2 == 0 ? kOrange : Rgb{};
    case Pattern::Online: {
      // Triangle 0 -> kGlowMax -> 0 sur kGlowMs, en tete de chaque periode :
      // une lueur des le passage en ligne, puis toutes les 10 s.
      const uint32_t ph = t % kGlowPeriodMs, half = kGlowMs / 2;
      if (ph >= kGlowMs) return Rgb{};
      const uint32_t x = ph < half ? ph : kGlowMs - ph;
      const uint8_t v = (uint8_t)((kGlowMax * x + half / 2) / half);
      return Rgb{v, v, v};
    }
  }
  return Rgb{};
}

bool renderMono(Pattern p, uint32_t t) {
  if (p == Pattern::Online) return false;  // une LED simple ne sait pas luire doucement
  if (p == Pattern::Identify) return (t / kIdentifyMonoHalfMs) % 2 == 0;
  if (p == Pattern::ButtonUnpair) return (t / kUnpairMonoHalfMs) % 2 == 0;
  return render(p, t) != Rgb{};
}

const char *patternName(Pattern p) {
  switch (p) {
    case Pattern::Identify: return "identification (arc-en-ciel)";
    case Pattern::ButtonUnpair: return "bouton tenu 8 s : relacher pour desappairer (rouge/violet rapide)";
    case Pattern::ButtonReboot: return "bouton, appui court : redemarrage (eclat blanc)";
    case Pattern::Unreachable: return "ordre abandonne apres 3 essais (rouge x3)";
    case Pattern::RadioFault: return "Bluetooth Mesh inoperant (rouge fixe)";
    case Pattern::Delivered: return "ordre confirme par la lampe (eclat vert)";
    case Pattern::Unpaired: return "pas mis en service (bleu clignotant)";
    case Pattern::Offline: return "reseau absent (orange lent)";
    case Pattern::Online: return "operationnel (lueur blanche toutes les 10 s)";
  }
  return "?";
}

const char *patternCode(Pattern p) {
  switch (p) {
    case Pattern::Identify: return "identification";
    case Pattern::ButtonUnpair: return "desappairage";
    case Pattern::ButtonReboot: return "redemarrage";
    case Pattern::Unreachable: return "injoignable";
    case Pattern::RadioFault: return "panne_radio";
    case Pattern::Delivered: return "livree";
    case Pattern::Unpaired: return "non_appaire";
    case Pattern::Offline: return "hors_reseau";
    case Pattern::Online: return "operationnel";
  }
  return "operationnel";
}

void Logic::setNet(Net n, uint32_t now) {
  if (n == net_) return;
  net_ = n;
  netAt_ = now;
}

void Logic::setIdentify(bool on, uint32_t now) {
  if (on && !identify_) identAt_ = now;
  identify_ = on;
}

void Logic::delivered(uint32_t now) {
  green_ = true;
  greenAt_ = now;
}

void Logic::unreachable(uint32_t now) {
  red_ = true;
  redAt_ = now;
}

void Logic::setFault(bool on, uint32_t now) {
  if (on && !fault_) faultAt_ = now;
  fault_ = on;
}

Button buttonFor(bootbtn::Phase p) {
  switch (p) {
    case bootbtn::Phase::Armed:
    case bootbtn::Phase::Unpair: return Button::Unpair;
    case bootbtn::Phase::Reboot: return Button::Reboot;
    case bootbtn::Phase::Idle:
    case bootbtn::Phase::Held:
    case bootbtn::Phase::Locked: break;
  }
  return Button::None;
}

void Logic::setButton(Button b, uint32_t now) {
  if (b == button_) return;
  button_ = b;
  buttonAt_ = now;
}

void Logic::startTest(uint32_t now) {
  testing_ = true;
  testAt_ = now;
}

Pattern Logic::pick(uint32_t now, uint32_t &t) {
  // Echeances d'abord, quel que soit le motif affiche : un evenement masque
  // par un plus prioritaire s'oublie quand meme a l'heure.
  if (red_ && now - redAt_ >= kUnreachableMs) red_ = false;
  if (green_ && now - greenAt_ >= kDeliveredMs) green_ = false;
  if (testing_ && now - testAt_ >= testTotalMs()) testing_ = false;

  if (identify_) {
    t = now - identAt_;
    return Pattern::Identify;
  }
  // Le bouton passe avant 'led test' : c'est une action de l'utilisateur.
  if (button_ != Button::None) {
    t = now - buttonAt_;
    return button_ == Button::Unpair ? Pattern::ButtonUnpair : Pattern::ButtonReboot;
  }
  if (testing_) {
    uint32_t e = now - testAt_;
    for (const TestStep &s : kTest) {
      if (e < s.ms) {
        t = e;
        return s.p;
      }
      e -= s.ms;
    }
  }
  if (red_) {
    t = now - redAt_;
    return Pattern::Unreachable;
  }
  if (fault_) {
    t = now - faultAt_;
    return Pattern::RadioFault;
  }
  if (green_) {
    t = now - greenAt_;
    return Pattern::Delivered;
  }
  t = now - netAt_;
  switch (net_) {
    case Net::Unpaired: return Pattern::Unpaired;
    case Net::Offline: return Pattern::Offline;
    case Net::Online: break;
  }
  return Pattern::Online;
}

Frame Logic::frame(uint32_t now) {
  uint32_t t = 0;
  const Pattern p = pick(now, t);
  return Frame{p, render(p, t), renderMono(p, t), t};
}

uint32_t effectEnd(uint32_t end, uint8_t effect, uint32_t now) {
  uint32_t ms = 2000;  // Blink, Okay, et tout effet inconnu
  switch (effect) {
    case kEffectStop: return 0;
    case kEffectFinish: {
      if (!effectPending(end, now)) return 0;
      const uint32_t soon = now + kEffectFinishMs;
      return effectPending(end, soon) ? (soon ? soon : 1) : end;
    }
    case kEffectBreathe: ms = 15000; break;
    case kEffectChannelChange: ms = 8000; break;
    default: break;
  }
  const uint32_t e = now + ms;
  return e ? e : 1;  // 0 veut dire "aucun effet"
}

}  // namespace statusled
