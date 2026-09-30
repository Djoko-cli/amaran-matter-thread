// Socle repris du pont Halo : voyant WS2812 (IO8) et bouton BOOT (IO9), plus
// les commandes `led` et `cause` (spec 7.4 a 7.6).
#pragma once

#include <stdbool.h>

#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

// A demarrer tot, avant Matter : la garde du bouton passe alors en dernier avant
// chaque reset, et le voyant montre l'etat des le demarrage.
esp_err_t socle_demarrer(void);
// Bluetooth Mesh inoperant (spec 7.3) : rouge fixe une fois le pont appaire.
void socle_panne_mesh(bool oui);
// Commande `led [test|stop]`.
int socle_commande_led(int argc, char **argv);
// Commande `cause` : pourquoi la carte a redemarre la derniere fois.
int socle_commande_cause(int argc, char **argv);

#ifdef __cplusplus
}
#endif
