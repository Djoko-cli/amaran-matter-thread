# Protocole des amaran COB 60d, relevé au banc

Relevé le 30/09/2026 (bancs R1 à R6, [BANC.md](BANC.md)), avec le firmware `ecoute`, sur les deux 60d de 1re génération. amaran Desktop 1.1.03 était ouvert. Ce document complète la spec, section 3.2.

**Écarts avec la spec (3.2 et 3.3) :**
- **Les ordres d'amaran Desktop sont visibles.** La spec (3.3) prévoyait que les ordres envoyés à la lampe qui sert de proxy à l'app n'apparaîtraient pas dans les annonces. Au banc, tous les ordres de l'app à la lampe 1 ont été captés. Deux explications possibles : l'app passait par la lampe 2, ou la lampe proxy réémet ces ordres. Ce n'est pas tranché.
- **Aucun accusé.** Les lampes ne répondent jamais à un ordre (`0x8C`, `0x8F`), ni au nôtre ni à celui de l'app. Seule une demande d'état (`0x0E`) obtient une réponse.
- **Aucun état spontané.** Ni la molette, ni son bouton, ni une coupure ne font parler une lampe. Pour suivre un réglage fait à la main, il faut relire la lampe (spec 5.7).
- **Commandes physiques inertes.** Une lampe éteinte par l'app (ou par le pont) ignore sa molette et le bouton de molette (+20 %). Seule une coupure au bouton d'alimentation la rallume.
- **Retour de coupure.** Coupée puis remise au bouton, la lampe revient **allumée vers 40 %** (41 % et 40 % au banc), quel que soit le niveau d'avant.
- **Trames et opcodes absents de la spec :** type `0x0A` (alimentation), type `0x00` (produit), et les opcodes à un octet `0x33` / `0x31`.

## Réseau

- **IV Index 0.** Les lampes émettent des balises réseau sécurisées avec IV 0 et drapeaux 0, chacune environ toutes les 10 s.
- **Destination.** Toutes les réponses des lampes vont à `0x0001` (amaran Desktop), y compris celles qui répondent à notre adresse (`0x7F38`) ou au groupe « All » (`0xC000`).
- **Copies.** Chaque réponse arrive une à trois fois : ce sont les copies réseau de la lampe. Le pont devra ignorer les doublons.

## Trames `0x26` (10 octets, octet 0 = somme des octets 1 à 9)

| octet 9 | sens | exemple relevé | vu au banc |
|---|---|---|---|
| `0x0E` | demande d'état | `0E 00 00 00 00 00 00 00 00 0E` | 30/09/2026, du pont et de l'app |
| `0x8C` | marche (octet 8 = 1) / arrêt (0) | `8D 00 00 00 00 00 00 00 01 8C`, `8C 00 00 00 00 00 00 00 00 8C` | 30/09/2026, du pont et de l'app, trames identiques octet pour octet |
| `0x8F` | intensité *v* (0 à 1000) | `3E 00 00 00 00 00 00 00 AF 8F` (*v* = 700) | 30/09/2026, du pont et de l'app |
| `0x02` | état en mode CCT (réponse à `0x0E`) | voir plus bas | 30/09/2026 |
| `0x01` | état en mode HSI | — | jamais (une 60d reste en CCT) |
| `0x0A` | alimentation (demande, puis réponse) | demande `0A 00 00 00 00 00 00 00 00 0A`, réponse `86 00 00 00 00 00 00 31 4B 0A` | 30/09/2026, de l'app seulement |
| `0x00` | produit (demande, puis réponse) | demande `00 00 00 00 00 00 00 00 00 00`, réponse `B4 03 80 A3 7C 08 6E 00 9C 00` | 30/09/2026, de l'app seulement |

**États reçus.** Lecture de la spec : marche = bit 0 de l'octet 1 ; intensité = ((octet 8 << 2) | (octet 7 >> 6)) & 0x3FF. Chaque lecture a été confirmée par la relecture après nos ordres (R3 : 62 sur 62).

| lampe | trame | lecture |
|---|---|---|
| 1 | `CE 00 00 00 00 40 01 A3 E8 02` | arrêt, 930 (93 %), CCT |
| 1 | `4D 01 00 00 00 40 01 A3 66 02` | marche, 410 (41 %), CCT |
| 2 | `75 00 00 00 00 40 01 23 0F 02` | arrêt, 60 (6 %), CCT |
| 2 | `B2 01 00 00 00 40 01 23 4B 02` | marche, 300 (30 %), CCT |

Les octets 5 et 6 (`40 01`) et les 6 bits bas de l'octet 7 (`0x23`) sont identiques sur les deux lampes. C'est la zone température/G-M de la spec, sans usage pour une 60d.

**Alimentation (`0x0A`).** Les octets 7 et 8, pris en petit-boutiste, valent de 18 696 à 19 249. Le plus haut quand la lampe est éteinte, le plus bas quand elle éclaire. C'est très probablement la tension d'alimentation en millivolts (19,2 V au repos, 18,7 V sous charge) : hypothèse, non vérifiée au voltmètre.

**Produit (`0x00`).** La réponse est la même pour les deux lampes ; elle n'est pas décodée.

## Opcodes à un octet `0x33` / `0x31`

L'app envoie au groupe l'opcode `0x33` avec l'octet `07`. Chaque lampe répond à `0x0001` par `31 33 76 31 36 39 52 07`, qui se lit en ASCII « 13v169R » suivi de `07`. C'est peut-être une version de firmware ; non décodé.

## Ce que fait amaran Desktop

- **Relevé périodique.** Il demande l'alimentation (`0x0A`) au groupe « All » à intervalles réguliers. Déjà vu dans ses journaux : environ toutes les 60 s.
- **Redécouverte.** Quand une lampe revient après une coupure, il enchaîne, au groupe puis à chaque lampe :
  1. `0x00` (produit) ;
  2. `0x33 07` ;
  3. `0x0E` (état) ;
  4. `0x0A` (alimentation).
- **Curseur d'intensité.** Chaque mouvement du curseur envoie un ordre `0x8F`, sans répétition ni accusé : 11 ordres en 4 s au banc.
- **Il ne suit pas le pont (R6).** Nos ordres, même suivis d'une relecture dont la réponse lui est adressée, ne changent pas son affichage.

## Enchaînement « intensité puis marche » (R3)

- `niveau` sur une lampe éteinte : le niveau est retenu, la lampe reste éteinte.
- `on` ensuite : elle s'allume directement au niveau retenu (30 % au banc), sans passer par l'ancien.
