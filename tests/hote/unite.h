// Mini cadre de tests sur le Mac (meme esprit que tools/host_tests du Halo).
#pragma once

#include <stdio.h>

static int g_verifs = 0;
static int g_echecs = 0;

#define VERIFIE(cond, ...)                          \
  do {                                              \
    g_verifs++;                                     \
    if (!(cond)) {                                  \
      g_echecs++;                                   \
      printf("ECHEC %s:%d : ", __FILE__, __LINE__); \
      printf(__VA_ARGS__);                          \
      printf("\n");                                 \
    }                                               \
  } while (0)

static inline int bilan(const char *nom) {
  printf("%s : %d verifications, %d echecs\n", nom, g_verifs, g_echecs);
  return g_echecs ? 1 : 0;
}
