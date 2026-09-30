# Protocole des amaran COB 60d, relevé au banc

Relevé le 30/09/2026 (bancs R1 à R6, [BANC.md](BANC.md)), avec le firmware `ecoute`, sur les deux 60d de 1re génération. amaran Desktop 1.1.03 était ouvert. Ce document complète la spec, section 3.2.

**Confirmé par le banc (spec 3.3) :**
- **Les ordres d'amaran Desktop sont visibles, sauf ceux de sa lampe proxy.** Pendant les deux sessions `mesh ecoute on` (environ 3 min), on a capté de l'app 17 messages distincts pour la lampe 1 (`0x0002`), 9 pour le groupe « All » (`0xC000`, 15 copies captées), aucun pour la lampe 2 (`0x0004`). Pourtant la lampe 2 répond, comme la lampe 1, aux sondages par lampe de l'app (état `0x0E`, alimentation `0x0A`) : ses réponses arrivent, sans que la demande correspondante ait été captée. L'app passait donc très probablement par la lampe 2 comme proxy GATT : ce qu'elle lui envoie ne sort pas en radio, alors que ce qu'elle envoie à la lampe 1 et au groupe passe par le proxy, qui le réémet.

**Écarts avec la spec (3.2 et 3.3) :**
- **Aucun accusé.** Les lampes ne répondent jamais à un ordre (`0x8C`, `0x8F`), ni au nôtre ni à celui de l'app. Seule une demande d'état (`0x0E`) obtient une réponse.
- **Aucun état spontané.** Ni la molette, ni son bouton, ni une coupure ne font parler une lampe. Pour suivre un réglage fait à la main, il faut relire la lampe (spec 5.7).
- **Commandes physiques inertes.** Une lampe éteinte par l'app (ou par le pont) ignore sa molette et le bouton de molette (+20 %). Seule une coupure au bouton d'alimentation la rallume.
- **Retour de coupure.** Coupée puis remise au bouton, la lampe revient **allumée vers 40 %** (41 % et 40 % au banc). Deux cas seulement, une fois par lampe, chacune éteinte avant la coupure (à 93 % et à 6 % de niveau retenu) : une lampe allumée avant la coupure n'a pas été essayée.
- **Trames et opcodes absents de la spec :** type `0x0A` (alimentation), type `0x00` (produit), et les opcodes à un octet `0x33` / `0x31`.

## Réseau

- **IV Index 0.** Les lampes émettent des balises réseau sécurisées avec IV 0 et drapeaux 0 : environ une toutes les 5 s au total. Une balise ne porte pas de source : on ne sait pas de quelle lampe vient chacune.
- **Destination.** Toutes les réponses des lampes vont à `0x0001` (amaran Desktop), y compris celles qui répondent à notre adresse (`0x7F38`) ou au groupe « All » (`0xC000`).
- **Copies.** Chaque réponse arrive une à trois fois, à 4 à 76 ms d'écart (médiane 25 ms) : très probablement les copies réseau de la lampe. C'est déduit de cet écart : le numéro de séquence n'est pas journalisé, donc non vérifié. Le pont devra ignorer les doublons.

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

**Alimentation (`0x0A`).** Les octets 7 et 8, pris en petit-boutiste, valent de 18 696 à 19 256 sur l'ensemble des bancs. Pour chaque lampe, la valeur est la plus haute éteinte et la plus basse allumée, mais les deux lampes ne se recouvrent pas (la lampe 1 lit environ 0,3 V de plus) : ne pas les mélanger.

| lampe | éteinte | allumée |
|---|---|---|
| 1 | environ 19,25 V (19 233 à 19 256) | environ 19,0 V (18 992 à 19 015) |
| 2 | environ 18,91 V (18 875 à 18 914) | environ 18,70 V (18 696 à 18 812) |

C'est très probablement la tension d'alimentation en millivolts : hypothèse, non vérifiée au voltmètre.

**Produit (`0x00`).** La réponse est la même pour les deux lampes ; elle n'est pas décodée.

## Opcodes à un octet `0x33` / `0x31`

L'app envoie au groupe l'opcode `0x33` avec l'octet `07`. Chaque lampe répond à `0x0001` par l'opcode `0x31` et la charge `33 76 31 36 39 52 07`, soit `33`, « v169R » en ASCII, puis `07`. « v169 » correspond au firmware Bluetooth 1.69 de la spec (3.1) ; le reste (`33`, `R`, `07`) n'est pas décodé.

## Ce que fait amaran Desktop

- **Relevé périodique.** Il demande l'alimentation (`0x0A`) au groupe « All » à intervalles réguliers. Déjà vu dans ses journaux : environ toutes les 60 s.
- **Redécouverte.** Quand une lampe revient après une coupure, il enchaîne, au groupe « All » :
  1. `0x00` (produit) ;
  2. `0x33 07` ;
  3. `0x0E` (état) ;
  4. `0x0A` (alimentation).

  Puis, lampe par lampe, seuls `0x0E` et `0x0A` sont vus (les quatre étapes vont au groupe), et seulement pour la lampe 1 : rien n'est capté pour la lampe 2, très probablement le proxy de l'app.
- **Curseur d'intensité.** Chaque mouvement du curseur envoie un ordre `0x8F`, sans répétition ni accusé : 11 ordres en 4 s au banc.
- **Il ne suit pas le pont (R6).** Nos ordres, même suivis d'une relecture dont la réponse lui est adressée, ne changent pas son affichage.

## Enchaînement « intensité puis marche » (R3)

- `niveau` sur une lampe éteinte : le niveau est retenu, la lampe reste éteinte.
- `on` ensuite : elle s'allume directement au niveau retenu (30 % au banc), sans passer par l'ancien.
