#include "boot_button.h"

// ===========================================================================
//  Logique pure (compilee aussi sur l'hote, sans ARDUINO)
// ===========================================================================

namespace bootbtn {

const char *phaseName(Phase p) {
  switch (p) {
    case Phase::Idle: return "relache";
    case Phase::Held: return "tenu";
    case Phase::Armed: return "tenu 8 s (relacher = desappairer)";
    case Phase::Reboot: return "redemarrage en attente";
    case Phase::Unpair: return "desappairage en attente";
    case Phase::Locked: return "tenu au demarrage (ignore)";
  }
  return "?";
}

const char *eventName(Event e) {
  switch (e) {
    case Event::None: return "aucun";
    case Event::Armed: return "arme";
    case Event::Cancelled: return "annule";
    case Event::Unsure: return "incertain";
    case Event::Dropped: return "abandonne";
    case Event::BootReleased: return "relache apres le demarrage";
    case Event::Reboot: return "redemarrage";
    case Event::Unpair: return "desappairage";
  }
  return "?";
}

void Machine::begin(bool low, uint32_t now) {
  started_ = true;
  raw_ = stable_ = low;
  highValid_ = !low;
  lastNow_ = rawAt_ = highSince_ = pressAt_ = now;
  edgeGap_ = runGap_ = startGap_ = holdGap_ = 0;
  enter(low ? Phase::Locked : Phase::Idle, now);
}

Event Machine::update(bool low, uint32_t now) {
  if (!started_) {
    begin(low, now);
    return Event::None;
  }
  const uint32_t gap = now - lastNow_;
  lastNow_ = now;

  // Trous de releves (loop() bloquee). Un front est date a edgeGap_ pres ;
  // pendant un appui, tout trou a pu cacher un relachement et un nouvel appui.
  if (low != raw_) {
    raw_ = low;
    rawAt_ = now;
    edgeGap_ = gap;
    runGap_ = 0;
  } else if (gap > runGap_) {
    runGap_ = gap;
  }
  if (stable_ && gap > holdGap_) holdGap_ = gap;
  // Broche haute sans interruption, et sans trou de releves, depuis highSince_.
  if (low)
    highValid_ = false;
  else if (!highValid_ || gap > kMaxGapMs) {
    highValid_ = true;
    highSince_ = now;
  }

  // Anti-rebond : un nouveau niveau compte s'il a tenu kDebounceMs.
  if (raw_ != stable_ && now - rawAt_ >= kDebounceMs) {
    stable_ = raw_;
    return stable_ ? pressed(now) : released(now);
  }

  const bool settled = highValid_ && now - highSince_ >= kSettleMs;
  switch (phase_) {
    case Phase::Held:
      // Encore bas au releve de pressAt_ + kLongMs - 1, sans trou depuis le
      // premier releve bas : l'appui a dure au moins kLongMs (un releve couvre
      // sa milliseconde, comme dans lastPressMs_), c'est certain ; un trou
      // avant le premier releve bas ne ferait que l'allonger. Relache juste
      // apres, il mesure donc kLongMs ou plus.
      if (raw_ && holdGap_ <= kMaxGapMs && now - pressAt_ >= kLongMs - 1) {
        enter(Phase::Armed, now);
        return Event::Armed;
      }
      break;
    case Phase::Reboot:
      if (settled && now - phaseAt_ >= kRebootDelayMs) {
        enter(Phase::Idle, now);
        return Event::Reboot;
      }
      break;
    case Phase::Unpair:
      if (settled) {
        enter(Phase::Idle, now);
        return Event::Unpair;
      }
      break;
    default: break;
  }
  return Event::None;
}

Event Machine::pressed(uint32_t now) {
  pressAt_ = rawAt_;
  startGap_ = edgeGap_;
  holdGap_ = runGap_;
  const bool pending = phase_ == Phase::Reboot || phase_ == Phase::Unpair;
  enter(Phase::Held, now);
  return pending ? Event::Dropped : Event::None;
}

Event Machine::released(uint32_t now) {
  lastPressMs_ = rawAt_ - pressAt_;
  // Le trou du front de relachement et de son anti-rebond est dans holdGap_.
  lastGapMs_ = startGap_ > holdGap_ ? startGap_ : holdGap_;
  switch (phase_) {
    case Phase::Locked:
      enter(Phase::Idle, now);
      return Event::BootReleased;
    case Phase::Armed:  // tenu kLongMs, prouve a l'armement
      enter(Phase::Unpair, now);
      return Event::None;
    default: break;
  }
  if (lastGapMs_ > kMaxGapMs) {
    enter(Phase::Idle, now);
    return Event::Unsure;
  }
  if (lastPressMs_ < kShortMaxMs) {
    enter(Phase::Reboot, now);
    return Event::None;
  }
  // De 2000 a 7999 ms ; ou 8000 ms et plus sans releve bas assez tardif pour
  // armer (releves espaces, sans trou au-dela de kMaxGapMs) : annule.
  enter(Phase::Idle, now);
  return Event::Cancelled;
}

}  // namespace bootbtn
