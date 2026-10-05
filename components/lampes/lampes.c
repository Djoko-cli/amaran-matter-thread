// Coeur du pont (voir lampes.h).
#include "lampes.h"

#include <string.h>

// maintenant a-t-il atteint echeance ? Horloge de 32 bits qui deborde : juste
// tant que les ecarts restent sous 2^31 ms (~24 jours).
static bool atteint(uint32_t maintenant, uint32_t echeance) { return (int32_t)(maintenant - echeance) >= 0; }

uint16_t lampes_niveau_vers_intensite(uint8_t niveau) {
  if (niveau < 1) niveau = 1;
  if (niveau > 254) niveau = 254;
  return (uint16_t)((2000u * niveau + 254u) / 508u);  // arrondi(niveau x 1000 / 254)
}

uint8_t lampes_intensite_vers_niveau(uint16_t intensite) {
  if (intensite > TELINK_INTENSITE_MAX) intensite = TELINK_INTENSITE_MAX;
  unsigned n = (508u * intensite + 1000u) / 2000u;  // arrondi(intensite x 254 / 1000)
  if (n < 1) n = 1;  // Matter n'a pas de niveau 0 ; pont_publier ne convertit jamais une intensite 0
  if (n > 254) n = 254;
  return (uint8_t)n;
}

void lampes_init(lampes_t *l, const uint16_t adresses[], int n, const lampes_sorties_t *sorties,
                 uint32_t maintenant_ms) {
  memset(l, 0, sizeof(*l));
  l->n = n < 0 ? 0 : (n > LAMPES_CAPACITE ? LAMPES_CAPACITE : n);
  for (int i = 0; i < l->n; i++) {
    l->lampes[i].adresse = adresses[i];
    l->lampes[i].joignable = true;         // 6.5 : pas de « Pas de reponse » fugace au demarrage
    l->lampes[i].montre_joignable = true;  // les endpoints naissent joignables
  }
  l->sorties = *sorties;
  l->periode_ms = LAMPES_RELEVE_DEFAUT_MS;
  l->prochaine_releve_ms = maintenant_ms;  // premiere relecture aussitot (6.5)
  l->fen_echeance_ms = maintenant_ms + LAMPES_ALERTE_TRANCHE_MS;
}

void lampes_regler_releve(lampes_t *l, uint32_t periode_ms) {
  if (periode_ms < LAMPES_RELEVE_MIN_MS) periode_ms = LAMPES_RELEVE_MIN_MS;
  if (periode_ms > LAMPES_RELEVE_MAX_MS) periode_ms = LAMPES_RELEVE_MAX_MS;
  l->periode_ms = periode_ms;
}

// Ce que Matter montre d'une lampe lue (spec 6.2, 6.3) : en marche a l'intensite 0
// (molette a 0 %), elle n'eclaire pas, donc eteinte pour Maison, au dernier niveau
// non nul lu (0 si aucun : le niveau de Matter reste ce qu'il est).
static lampe_etat_t vue(const lampe_t *p) {
  lampe_etat_t v = p->lu;
  if (v.intensite == 0) {
    v.marche = false;
    v.intensite = p->memoire;
  }
  return v;
}

// Publie ce que Matter doit montrer, s'il differe de ce qu'il montre deja (ou
// toujours, si forcer).
static void montrer(lampes_t *l, int i, bool forcer) {
  lampe_t *p = &l->lampes[i];
  const lampe_etat_t v = vue(p);
  const bool meme = p->montre_connu == p->connu && p->montre_joignable == p->joignable &&
                    (!p->connu || (p->montre.marche == v.marche && p->montre.intensite == v.intensite));
  if (meme && !forcer) return;
  p->montre_connu = p->connu;
  p->montre = v;
  p->montre_joignable = p->joignable;
  l->sorties.publier(l->sorties.ctx, i, p->connu ? &v : NULL, p->joignable);
}

static bool consigne_tenue(const lampe_t *p, const lampe_etat_t *e) {
  if (p->veut_marche && e->marche != p->consigne.marche) return false;
  if (p->veut_intensite && e->intensite != p->consigne.intensite) return false;
  return true;
}

// Trames de la consigne, dans l'ordre qui evite tout eclat : eteindre avant de
// changer le niveau ; regler le niveau avant d'allumer (R3 : la lampe retient un
// niveau recu eteinte, et s'allume ensuite directement a ce niveau). Une trame
// refusee par la file n'est pas rejouee ici : l'essai suivant la renverra.
static void envoyer_trames(lampes_t *l, const lampe_t *p) {
  uint8_t t[TELINK_TAILLE];
  if (p->veut_marche && !p->consigne.marche) {
    telink_marche(false, t);
    l->sorties.envoyer(l->sorties.ctx, p->adresse, t, LAMPES_REPETITIONS_ORDRE);
  }
  if (p->veut_intensite) {
    telink_intensite(p->consigne.intensite, t);
    l->sorties.envoyer(l->sorties.ctx, p->adresse, t, LAMPES_REPETITIONS_ORDRE);
  }
  if (p->veut_marche && p->consigne.marche) {
    telink_marche(true, t);
    l->sorties.envoyer(l->sorties.ctx, p->adresse, t, LAMPES_REPETITIONS_ORDRE);
  }
}

static void demarrer_essai(lampes_t *l, lampe_t *p, uint32_t maintenant_ms) {
  envoyer_trames(l, p);
  p->a_refaire = false;
  p->phase = LAMPE_TRAMES;
  p->echeance_ms = maintenant_ms + LAMPES_DELAI_ETAT_MS;
}

static void finir(lampes_t *l, int i, lampes_signal_t signal, uint32_t maintenant_ms) {
  lampe_t *p = &l->lampes[i];
  p->phase = LAMPE_REPOS;
  p->veut_marche = p->veut_intensite = false;
  p->a_refaire = false;
  const uint32_t delai = maintenant_ms - p->debut_ms;
  p->dernier_delai_ms = delai;
  if (signal == LAMPES_SIGNAL_CONFIRME) {
    l->confirmes++;
    l->delai_total_ms += delai;
    if (delai > l->delai_max_ms) l->delai_max_ms = delai;
    if (delai > 1000u) l->lents++;
  } else {
    l->abandons++;
  }
  l->sorties.signaler(l->sorties.ctx, i, signal);
  montrer(l, i, signal == LAMPES_SIGNAL_ABANDON);  // abandon : Maison revient au dernier etat lu (7.1)
}

void lampes_mesh_pret(lampes_t *l, bool pret, uint32_t maintenant_ms) {
  if (pret == l->mesh_pret) return;
  l->mesh_pret = pret;
  if (pret) {
    l->prochaine_releve_ms = maintenant_ms;  // relecture aussitot
    return;
  }
  for (int i = 0; i < l->n; i++) {
    l->lampes[i].releve_en_attente = false;  // la relecture partie n'aura pas d'issue a compter
    if (l->lampes[i].phase != LAMPE_REPOS) finir(l, i, LAMPES_SIGNAL_ABANDON, maintenant_ms);
  }
}

// Une lampe ne garde que le pour cent entier de l'intensite (banc C : une 60d
// relit 430 apres 433 comme apres 437). La consigne est donc arrondie au pour cent
// le plus proche, demi vers le haut, avant d'etre envoyee et comparee a l'etat
// relu ; sans cela, tout ordre qui n'est pas un multiple de 10 serait abandonne
// apres 3 essais alors que la lampe a obei. Au moins 1 % si elle n'est pas nulle
// (le niveau 1 de Matter, 4, ne doit pas tomber a 0), et 1000 au plus.
static uint16_t arrondir_pour_cent(uint16_t v) {
  if (v > TELINK_INTENSITE_MAX) v = TELINK_INTENSITE_MAX;
  uint16_t r = (uint16_t)((v + LAMPES_PAS_INTENSITE / 2) / LAMPES_PAS_INTENSITE * LAMPES_PAS_INTENSITE);
  if (v != 0 && r < LAMPES_PAS_INTENSITE) r = LAMPES_PAS_INTENSITE;
  return r;
}

void lampes_ordre(lampes_t *l, int lampe, const bool *marche, const uint16_t *intensite, bool depuis_matter,
                  uint32_t maintenant_ms) {
  if (lampe < 0 || lampe >= l->n || (!marche && !intensite)) return;
  lampe_t *p = &l->lampes[lampe];
  l->ordres++;
  // Le controleur montre deja sa consigne : la prochaine publication part d'office.
  if (depuis_matter) p->montre_connu = false;
  if (marche) {
    p->veut_marche = true;
    p->consigne.marche = *marche;
  }
  if (intensite) {
    p->veut_intensite = true;
    p->consigne.intensite = arrondir_pour_cent(*intensite);
  }
  // Allumer une lampe noire (lue a l'intensite 0, en marche ou non) : sans intensite,
  // l'ordre serait deja tenu (6.4), ou la rallumerait a 0. Elle reprend sa derniere
  // intensite non nulle ; une ecriture de niveau qui suit (effet de LevelControl a
  // l'allumage) la remplace pendant le regroupement.
  if (p->veut_marche && p->consigne.marche && !p->veut_intensite && p->connu && p->lu.intensite == 0) {
    p->veut_intensite = true;
    p->consigne.intensite = arrondir_pour_cent(p->memoire ? p->memoire : LAMPES_INTENSITE_RALLUMAGE);
  }
  if (!l->mesh_pret) {
    p->debut_ms = maintenant_ms;  // rien n'est emis : ni delai ni essai
    p->essai = 0;
    finir(l, lampe, LAMPES_SIGNAL_ABANDON, maintenant_ms);
    return;
  }
  // Une seule consigne en attente par lampe : la nouvelle valeur remplace
  // l'ancienne, et part au plus tot a la prochaine etape (5.6).
  if (p->phase != LAMPE_REPOS) {
    p->a_refaire = true;
    p->debut_ms = maintenant_ms;  // delai mesure depuis la derniere valeur (regle 5.8)
    return;
  }
  // Une valeur egale au dernier etat lu ne fait jamais emettre (6.4).
  if (p->connu && consigne_tenue(p, &p->lu)) {
    p->veut_marche = p->veut_intensite = false;
    p->dernier_delai_ms = 0;
    l->tenus++;
    l->sorties.signaler(l->sorties.ctx, lampe, LAMPES_SIGNAL_TENU);
    montrer(l, lampe, false);
    return;
  }
  // Les trames partent apres LAMPES_REGROUPEMENT_MS : une commande Matter ecrit
  // souvent plusieurs attributs a la suite (l'arret avec effet : CurrentLevel au
  // minimum, OnOff faux, puis CurrentLevel restaure), et tout part en une salve,
  // avec la consigne finale.
  p->essai = 1;
  p->a_refaire = true;
  p->phase = LAMPE_TRAMES;
  p->echeance_ms = maintenant_ms + LAMPES_REGROUPEMENT_MS;
  p->debut_ms = maintenant_ms;
}

void lampes_trame_recue(lampes_t *l, uint16_t src, const uint8_t trame[TELINK_TAILLE], uint32_t maintenant_ms) {
  int i = -1;
  for (int k = 0; k < l->n; k++) {
    if (l->lampes[k].adresse == src) {
      i = k;
      break;
    }
  }
  if (i < 0) return;
  lampe_t *p = &l->lampes[i];
  l->trames_recues++;
  // Toute trame de la lampe prouve qu'elle vit, y compris celles que l'on ne lit
  // pas (0x0A, reponses aux questions d'amaran Desktop).
  p->entendue = true;
  p->reponse_ms = maintenant_ms;
  p->releves_sans_reponse = 0;
  p->joignable = true;
  if (!p->repondu) {
    p->repondu = true;
    p->releves_repondues++;
  }
  telink_etat_t e;
  const bool etat = telink_lire_etat(trame, &e);
  if (etat) {
    p->connu = true;
    p->lu.marche = e.marche;
    p->lu.intensite = e.intensite;
    if (e.intensite) p->memoire = e.intensite;
  }
  if (p->phase == LAMPE_REPOS) {
    montrer(l, i, false);
    return;
  }
  // Ordre en cours : seul un etat recu apres notre demande et egal a la
  // consigne compte. Les autres peuvent etre perimes : on ne les montre pas (5.6).
  if (etat && p->phase == LAMPE_ATTENTE && !p->a_refaire && consigne_tenue(p, &p->lu)) {
    finir(l, i, LAMPES_SIGNAL_CONFIRME, maintenant_ms);
  }
}

// Relectures et reponses de la fenetre de 10 min.
static void fenetre_sommes(const lampe_t *p, uint32_t *releves, uint32_t *repondues) {
  *releves = *repondues = 0;
  for (unsigned t = 0; t < LAMPES_ALERTE_TRANCHES; t++) {
    *releves += p->fen_releves[t];
    *repondues += p->fen_repondues[t];
  }
}

// Tronque : sous le seuil, jamais affiche au seuil.
static uint8_t pour_cent(uint32_t part, uint32_t total) { return (uint8_t)(part * 100u / total); }

// Issue de la relecture precedente, dans la tranche courante.
static void compter_releve(const lampes_t *l, lampe_t *p) {
  if (p->fen_releves[l->fen_tranche] < UINT16_MAX) p->fen_releves[l->fen_tranche]++;
  if (p->repondu && p->fen_repondues[l->fen_tranche] < UINT16_MAX) p->fen_repondues[l->fen_tranche]++;
}

// Fin d'une tranche d'une minute : une fois 10 tranches achevees, verdict sur les 10
// dernieres minutes (alerte, spec N lampes 8) ; puis la plus ancienne repart a zero.
static void tourner_fenetre(lampes_t *l, uint32_t maintenant_ms) {
  if (l->fen_pleines < LAMPES_ALERTE_TRANCHES) l->fen_pleines++;
  if (l->fen_pleines >= LAMPES_ALERTE_TRANCHES) {
    // Relectures attendues sur la fenetre, a la periode courante (10 a 600).
    const uint32_t attendues = LAMPES_ALERTE_TRANCHES * LAMPES_ALERTE_TRANCHE_MS / l->periode_ms;
    for (int i = 0; i < l->n; i++) {
      lampe_t *p = &l->lampes[i];
      if (!p->joignable) continue;  // une lampe muette releve de 7.2, pas de cette alerte
      uint32_t releves, repondues;
      fenetre_sommes(p, &releves, &repondues);
      if (!releves || releves * 100u < LAMPES_ALERTE_ECHANTILLON_PC * attendues) continue;
      const bool manque = repondues * 100u < LAMPES_ALERTE_SEUIL_PC * releves;
      if (manque == p->alerte) continue;
      p->alerte = manque;
      if (l->sorties.alerter) l->sorties.alerter(l->sorties.ctx, i, manque, pour_cent(repondues, releves));
    }
  }
  l->fen_tranche = (uint8_t)((l->fen_tranche + 1u) % LAMPES_ALERTE_TRANCHES);
  for (int i = 0; i < l->n; i++) {
    l->lampes[i].fen_releves[l->fen_tranche] = 0;
    l->lampes[i].fen_repondues[l->fen_tranche] = 0;
  }
  l->fen_echeance_ms = maintenant_ms + LAMPES_ALERTE_TRANCHE_MS;
}

void lampes_forcer_publication(lampes_t *l, int lampe) {
  if (lampe < 0 || lampe >= l->n) return;
  montrer(l, lampe, true);
}

int lampes_part_repondue(const lampes_t *l, int lampe) {
  if (lampe < 0 || lampe >= l->n) return -1;
  uint32_t releves, repondues;
  fenetre_sommes(&l->lampes[lampe], &releves, &repondues);
  return releves ? (int)pour_cent(repondues, releves) : -1;
}

void lampes_tic(lampes_t *l, uint32_t maintenant_ms) {
  if (atteint(maintenant_ms, l->fen_echeance_ms)) tourner_fenetre(l, maintenant_ms);
  for (int i = 0; i < l->n; i++) {
    lampe_t *p = &l->lampes[i];
    if (p->phase == LAMPE_TRAMES) {
      if (!atteint(maintenant_ms, p->echeance_ms)) continue;
      if (p->a_refaire) {  // au plus une salve de trames par lampe toutes les 200 ms
        p->essai = 1;
        demarrer_essai(l, p, maintenant_ms);
        continue;
      }
      uint8_t t[TELINK_TAILLE];
      telink_demande_etat(t);
      l->sorties.envoyer(l->sorties.ctx, p->adresse, t, LAMPES_REPETITIONS_ETAT);
      p->demande_ms = maintenant_ms;
      p->phase = LAMPE_ATTENTE;
      p->echeance_ms = maintenant_ms + LAMPES_FENETRE_MS;
    } else if (p->phase == LAMPE_ATTENTE) {
      if (p->a_refaire) {
        p->essai = 1;
        demarrer_essai(l, p, maintenant_ms);
        continue;
      }
      if (!atteint(maintenant_ms, p->echeance_ms)) continue;
      if (p->essai < LAMPES_ESSAIS) {
        p->essai++;
        demarrer_essai(l, p, maintenant_ms);
      } else {
        finir(l, i, LAMPES_SIGNAL_ABANDON, maintenant_ms);
      }
    }
  }
  // Relecture periodique au groupe « All » (5.7).
  if (!atteint(maintenant_ms, l->prochaine_releve_ms)) return;
  l->prochaine_releve_ms = maintenant_ms + l->periode_ms;
  for (int i = 0; i < l->n; i++) {
    lampe_t *p = &l->lampes[i];
    if (p->releves_sans_reponse >= LAMPES_RELEVES_MUETTE && p->joignable) {
      p->joignable = false;  // 3 relectures sans reponse : « Pas de reponse » (7.2)
      if (p->phase == LAMPE_REPOS) montrer(l, i, false);
    }
    if (p->releves_sans_reponse < 255) p->releves_sans_reponse++;
    if (l->mesh_pret) {
      // Issue de la relecture precedente, comptee si la lampe est joignable (alerte, spec
      // N lampes 8), puis la relecture qui part attend sa reponse.
      if (p->releve_en_attente && p->joignable) compter_releve(l, p);
      p->repondu = false;
      p->releve_en_attente = true;
    }
  }
  // Mesh pas pret : rien ne part, mais les periodes comptent, et les lampes
  // deviennent muettes au bout de trois (7.3).
  if (!l->mesh_pret) return;
  uint8_t t[TELINK_TAILLE];
  telink_demande_etat(t);
  l->sorties.envoyer(l->sorties.ctx, LAMPES_GROUPE, t, LAMPES_REPETITIONS_ETAT);
  l->releves++;
}
