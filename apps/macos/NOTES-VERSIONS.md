# Release notes · Notes de version

Amaran Compagnon: one section per published version, in English then in French. `apps/macos/Outils/publier.sh`
takes from it the notes of the GitHub release and those of the update window.

Amaran Compagnon : une section par version publiée, en anglais puis en français. `apps/macos/Outils/publier.sh` en
tire les notes de la version publiée sur GitHub et celles de la fenêtre de mise à jour.

## 1.0.0

**English**

- First published version: the app that supervises and drives the amaran bridge, over USB or over the Thread
  network (dashboard, controls and console, charts, decoded Bluetooth Mesh frames), loads the Bluetooth Mesh keys
  and lamps of amaran Desktop into the bridge, and keeps a copy of them in this Mac's keychain, with an encrypted
  backup; in French and English, with its demo mode.
- Automatic updates (Sparkle 2): a check at launch and then every 24 hours, download, and installation when the
  app quits, or right away with "Install and Relaunch". "Check for Updates…" is in the Amaran Compagnon menu;
  Settings, General, "Updates", can turn them off.
- Thread Route, the system helper that keeps the Mac's route to the Thread network (formerly halo-routes): its
  status is in Settings, General; it installs from the Halo bridge repository with
  `sh tools/macos/thread-route/installer.sh`.

**Français**

- Première version publiée : l'app qui supervise et pilote le pont amaran, par l'USB ou par le réseau Thread
  (tableau de bord, commandes et console, graphiques, trames du Bluetooth Mesh décodées), charge dans le pont les
  clés et les lampes du Bluetooth Mesh d'amaran Desktop, et en garde une copie dans le trousseau de ce Mac, avec une
  sauvegarde chiffrée ; en français et en anglais, avec son mode démo.
- Mises à jour automatiques (Sparkle 2) : recherche au démarrage puis toutes les 24 heures, téléchargement et
  installation à la fermeture de l'app, ou tout de suite par « Installer et relancer ». « Rechercher les mises à
  jour… » est dans le menu Amaran Compagnon ; Réglages, Général, « Mises à jour », permet de les arrêter.
- Thread Route, l'assistant système qui garde la route du Mac vers le réseau Thread (anciennement halo-routes) :
  son état est dans Réglages, Général ; il s'installe depuis le dépôt du pont Halo par
  `sh tools/macos/thread-route/installer.sh`.
