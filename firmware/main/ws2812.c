// La WS2812 de la C6 SuperMini, d'apres l'exemple d'ESP-IDF
// peripherals/rmt/led_strip_simple_encoder : un pixel, ordre G, R, B (verifie
// sur la carte avec 'led test' pour le Halo).
#include "ws2812.h"

#include "driver/rmt_encoder.h"
#include "driver/rmt_tx.h"

#define RESOLUTION_HZ 10000000  // 1 pas = 0,1 us

static const rmt_symbol_word_t SYMBOLE_0 = {.level0 = 1, .duration0 = 3, .level1 = 0, .duration1 = 9};  // 0,3 us / 0,9 us
static const rmt_symbol_word_t SYMBOLE_1 = {.level0 = 1, .duration0 = 9, .level1 = 0, .duration1 = 3};  // 0,9 us / 0,3 us
static const rmt_symbol_word_t SYMBOLE_RAZ = {.level0 = 0, .duration0 = 250, .level1 = 0, .duration1 = 250};  // 50 us

static rmt_channel_handle_t s_canal;
static rmt_encoder_handle_t s_encodeur;

static size_t encoder(const void *donnees, size_t taille, size_t ecrits, size_t libres, rmt_symbol_word_t *symboles,
                      bool *fini, void *arg) {
  (void)arg;
  if (libres < 8) return 0;
  const size_t pos = ecrits / 8;
  const uint8_t *octets = donnees;
  if (pos < taille) {
    for (int i = 0; i < 8; i++) symboles[i] = (octets[pos] & (0x80 >> i)) ? SYMBOLE_1 : SYMBOLE_0;
    return 8;
  }
  symboles[0] = SYMBOLE_RAZ;
  *fini = true;
  return 1;
}

esp_err_t ws2812_demarrer(int gpio) {
  const rmt_tx_channel_config_t canal = {
      .gpio_num = gpio,
      .clk_src = RMT_CLK_SRC_DEFAULT,
      .resolution_hz = RESOLUTION_HZ,
      .mem_block_symbols = 48,
      .trans_queue_depth = 2,
  };
  esp_err_t err = rmt_new_tx_channel(&canal, &s_canal);
  if (err != ESP_OK) return err;
  const rmt_simple_encoder_config_t codeur = {.callback = encoder};
  err = rmt_new_simple_encoder(&codeur, &s_encodeur);
  if (err == ESP_OK) err = rmt_enable(s_canal);
  if (err == ESP_OK) err = ws2812_ecrire(0, 0, 0);  // elle garde sa couleur a travers un reset
  return err;
}

esp_err_t ws2812_ecrire(uint8_t r, uint8_t g, uint8_t b) {
  if (!s_canal) return ESP_ERR_INVALID_STATE;
  static uint8_t grb[3];  // lu par le RMT pendant l'envoi
  grb[0] = g;
  grb[1] = r;
  grb[2] = b;
  const rmt_transmit_config_t envoi = {.loop_count = 0};
  esp_err_t err = rmt_transmit(s_canal, s_encodeur, grb, sizeof(grb), &envoi);
  if (err == ESP_OK) err = rmt_tx_wait_all_done(s_canal, 10);
  return err;
}
