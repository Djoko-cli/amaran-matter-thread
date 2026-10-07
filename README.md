**English** · [Français](README.fr.md)

# amaran COB 60d -> Matter

Control **amaran** (Aputure) lights, currently two **COB 60d** (1st
generation), from Apple Home, Siri and automations, over **Matter over
Thread**, with an ESP32-C6, while keeping the **amaran Desktop** app usable.
Up to 16 lights per bridge.

The other documents in this repository (specs, bench results, protocol notes, the companion app README) are in French.

Sister projects:
- [benq-screenbar-halo-matter](https://github.com/Djoko-cli/benq-screenbar-halo-matter):
  the foundation (LED, BOOT button, console) and the lessons learned on the Apple side;
- [maillage-thread](https://github.com/Djoko-cli/maillage-thread).

## Status

**The bridge works: both lights are in Apple Home, on a single C6.** The full design is in
[docs/superpowers/specs/2026-09-28-pont-amaran-design.md](docs/superpowers/specs/2026-09-28-pont-amaran-design.md).

| Phase | Contents | Status |
|---|---|---|
| P0 | Reconnaissance. A listening firmware joins the lights' network and checks: IV Index, captured replies, commands, dial, group, coexistence with amaran Desktop | done (2026-09-30): 62 commands out of 62 confirmed by status read, every state request got its reply; no spontaneous state (no dial, no button, no power cut) |
| P1 | Matter on the same board, and bench test of the radio shared between Thread and Bluetooth: one or two C6 | done (2026-09-30): a single C6 is enough, with Mesh listening at 50%, rounding to the percent and the state request doubled; 96.9% and 98.3% of status reads answered, 47 bursts of commands from Apple Home without failure |
| P2 | Product: LED, button, console, product sheet; bench tests, then 24 h endurance | done (2026-10-02): T1 to T10 (T5 partial, T7 not done); 24 h without a reboot, 97.9% and 98.3% of status reads answered, 41 bursts of commands without failure; dark light (dial at 0%) fixed and verified |
| P3a | N lights: list, model catalog, stable endpoint numbers, exposure at first reply | done (2026-10-05): bench tests 1 to 4; migration without loss in Apple Home; 16 lights held (heap at its lowest 103 KB); a light hidden then restored is forgotten by Apple Home, so no automatic hiding |
| P3b-1 | Companion app over USB: JSON mode of the bridge; amaran Desktop keys (keychain, encrypted backup, loading the bridge); dashboard, commands and console, demo | done (2026-10-05): bench tests A and B; JSON mode without echo, commands tracked by their `id` until their outcome; the app reads the amaran Desktop database through a bookmark, keeps a copy in the keychain, loads the bridge and compares it, exports an encrypted backup; reconnects on its own after a USB unplug; heap at its lowest 144 KB |
| P3b-2 | Companion app over Thread: signed UDP channel (H1) and the bridge's allowlist, UDP key created over USB and stored in the Mac's keychain; Network source, graphs, decoded frames, "Thread Network Access" settings | done (2026-10-05): bench tests A and B; key created and erased over USB without ever being displayed; console, commands and frames remotely, commands outside the allowlist refused; one hour remotely, the bridge on mains power, without a session resumption; heap at its lowest 106 KB |
| P3b-3 | Lights' sheet in Apple Home: manufacturer, model, serial number; lights' software version, from the amaran Desktop database to the bridge and the app; `ConfigurationVersion` | done (2026-10-06): prototype bench test; Apple Home re-reads the sheet without re-pairing, but does not display the version of a bridged Matter accessory; versions under a separate NVS key (rollback without loss); heap at its lowest 102 KB |

Bench results: [docs/BANC.md](docs/BANC.md). Captured protocol: [docs/PROTOCOLE.md](docs/PROTOCOLE.md). Machine protocol of the bridge, for the app: [docs/PROTOCOLE-JSON.md](docs/PROTOCOLE-JSON.md).

## What the bridge does

- It shows each light in Apple Home as a dimmable light, with
  on/off and brightness.
- It follows the actual state of the lights, whether they are set in Apple Home,
  in amaran Desktop or with the dial.
- It lets amaran Desktop keep working at the same time.

## How

**Lights side.** The lights form a **Bluetooth Mesh** network, created by amaran
Desktop.
- The ESP32 becomes a member of it with **its own address**, using the
  network keys that a script reads from the app's local database.
- Nothing is modified, neither in the lights nor in the app.
- The ESP32 speaks the lights' real language: a proprietary Telink opcode,
  `0x26`.
- It reads their state in passing: the lights address their replies to amaran
  Desktop, and it captures them.

**Apple Home side.** It is a Matter over Thread bridge (ESP-IDF + esp-matter): an
aggregator, and one "bridged" light per light.

## Install

You need ESP-IDF v5.5.4 and esp-matter (commit `c5b9ea8`) in `~/esp`, an ESP32-C6 SuperMini, and a Thread border router (HomePod mini, Apple TV).

1. Build and flash. The port is always given explicitly:

   ```bash
   source ~/esp/esp-idf/export.sh && source ~/esp/esp-matter/export.sh
   cd firmware && idf.py build && idf.py -p /dev/cu.usbmodemXXXX erase-flash flash
   ```

   To update a bridge that is already paired: `flash` without `erase-flash` (otherwise Apple Home loses everything), and delete `firmware/sdkconfig` first so that the settings in `sdkconfig.defaults` apply. The first update to N lights converts the list of lights and erases the old format: back up before the full flash (`esptool.py read_flash 0 0x400000 <fichier>`, kept out of the repository: it contains the keys).

2. Load the lights' network keys, read from the amaran Desktop database: with the companion app ("Keys" card, "Load Bridge"), or on the command line:

   ```bash
   python3 outils/cles_amaran.py --port /dev/cu.usbmodemXXXX
   ```

3. Pair. `python3 outils/console.py --port /dev/cu.usbmodemXXXX matter` prints the manual code. In Apple Home: "+", "Add Accessory", "More options…", then this code. The bridge uses the Matter SDK's test codes: Apple Home warns that it is not certified, "Add Anyway".

Once paired, the bridge joins the lights' network. Each light appears in Apple Home, under its amaran Desktop name, at its first reply: a light declared in amaran Desktop but absent from here does not appear there.

Board already used: `erase-flash` makes the bridge draw a new random Mesh address (`0x7F00` to `0x7F7F`). In about 1 case in 128 per address already in use, it lands on an address the lights know, and they then ignore the bridge, without any error message. If all the lights stay silent (`lampes`: "lue jamais") with no other alert in the console, type `mesh adresse suivante`: the bridge takes the neighboring address, starts again from zero and reboots.

## The companion app

Amaran Compagnon (`apps/macos`) monitors and controls the bridge over USB, or remotely over the home's Thread network: one card per light, the Bluetooth Mesh, Matter, the LED, the bridge's console, graphs and the decoded Bluetooth Mesh frames. It also manages the lights' network keys, in place of `outils/cles_amaran.py`:
- it reads the amaran Desktop database, never writing to it (Settings, "Change…": point once to the `amaran Desktop` folder in `~/Library/Containers/com.sidus.amaran-desktop/Data/Library/Application Support`);
- it keeps a copy in this Mac's keychain, and exports it on request as a backup encrypted with a passphrase (iCloud Drive recommended);
- it loads the bridge over USB, checks its fingerprints and its list, then reboots it;
- it compares the fingerprints of the database, the copy and the bridge, without ever showing a key.

**Remotely, over Thread.** The bridge listens on UDP (port 5480) on the Thread network, once a UDP key exists. This key is created over USB only (Settings › Thread Network Access › "Enable Network Access…"): the bridge keeps it, the app stores it in this Mac's keychain. After that, the bridge appears in the Source menu, under "Network". Each message is signed with this key, but nothing is encrypted: no secret goes over Thread. Remotely, reads, commands to the lights, `mesh lampe <n> masquer|afficher` and `led` are allowed; the keys, the list of lights, the Mesh network configuration, Matter commissioning and rebooting remain reserved to USB (the state of Matter and of the Mesh can also be read remotely). `json cle efface`, `decommission` and BOOT held for 8 s erase the UDP key.

macOS sometimes loses the IPv6 route to the Thread network: Thread Route, the system helper of the Halo bridge ([tools/macos/thread-route](https://github.com/Djoko-cli/benq-screenbar-halo-matter/tree/main/tools/macos/thread-route)), restores it and is used here as is (same Thread network). It is installed once, from the Halo bridge repository, with `sh tools/macos/thread-route/installer.sh`; the app shows its state (Settings, General).

Demo mode (sidebar menu, or File › Demo Mode, ⇧⌘D) simulates a bridge with three lights, without hardware. To build: see [apps/macos/README.md](apps/macos/README.md).

## LED and button

| LED | Meaning |
|---|---|
| blinking blue | not paired with Apple Home |
| slow orange | Thread network absent |
| off, brief white glow every 10 s | all is well |
| solid red | Bluetooth Mesh not working: the console says why |
| green flash | command confirmed by the light |
| red ×3 | command abandoned after 3 tries |
| rainbow | a controller is asking for identification |
| red, black, purple, black, fast | BOOT held for 8 s: release to unpair |
| white flash | short BOOT press: reboot |

BOOT button: short press, reboot; from 2 to 8 s, nothing; 8 s or more, unpairing from Apple Home. The lights' network keys stay; the UDP key for access over Thread is erased.

## Console

Over USB, in French (`python3 outils/console.py --port <port> "<commande>"`, or any serial terminal):
- `lampes`: one line per light (its place in Apple Home: `EP<n>`, "jamais vue", "masquee" or "hors de Maison"; state read, reachability, status reads answered), then the commands;
- `lampe <n>`: the details of one light (address, MAC, model and capabilities, its software version, setpoint, status reads over 10 min);
- `lampe <n> on|off|niveau <0-1000>|releve`: the level is rounded to the percent (the light does not keep anything finer);
- `mesh lampe <n> masquer|afficher`: remove the light from Apple Home, which then forgets it (see "Good to know"), or put it back, with the same number (`afficher` also brings in a light never seen);
- `mesh`: network, key fingerprints, counters; `mesh releve <s>`, `mesh balayage`, `mesh ecoute on|off`, `mesh autotest`, etc.;
- `mesh lampes <N>`, then `mesh lampe <n> <adresse> <mac> <code> [v<logiciel>[/<ble>]] "<nom>"`: the list of lights, all or nothing, with each light's software version if known (this is what `outils/cles_amaran.py` sends); the version is only read when followed by the name, and a quoted name stays a name; a copy of `outils/cles_amaran.py` from before plan 3b-3 no longer reads this firmware's reply to `mesh lampe`: take the one from the repository;
- `matter`: commissioning, Thread, subscriptions, codes, identity, `ConfigurationVersion` (incremented when what Apple Home sees of the lights changes, so that it re-reads their sheet);
- `led [test|stop]`, `cause`, `taches`, `redemarre`;
- `decommission`: removes the bridge from Apple Home (all Matter fabrics) and erases the UDP key, then reboots;
- `json …`: the companion app's machine mode ([docs/PROTOCOLE-JSON.md](docs/PROTOCOLE-JSON.md)). The bridge always starts in text console; `json 1` switches to machine mode, `json 0` (or 30 s without anything from the app) returns to text. `json cle nouvelle <64 hexa>` creates the UDP key for access over Thread (the reply shows it only in machine mode, only once; the text console shows only its fingerprint), `json cle efface` erases it; `json trames 1|0` turns the decoded Bluetooth Mesh frames on or off.

An unknown command replies `Commande inconnue : "<nom>" (help)`.

## Good to know

- In Apple Home, each light's sheet shows its manufacturer (`Aputure`), its model and its serial number (`AMARAN-<MAC of the light>`). The software version is also exposed over Matter, but Apple Home does not display it for a bridged Matter accessory (observed in the bench test of 2026-10-06): the companion app shows it.
- A light turned off from Apple Home, or from amaran Desktop, ignores its dial and its dial button. To turn it back on by hand: cut then restore its power. Its state on return varies: on at about 40%, on at its remembered level, or off.
- A light whose dial is at 0% stays on, but gives no light: Apple Home shows it off, at its last level. Touching it in Apple Home turns it back on at that level (at 40% only on a fresh installation, when Apple Home has no level yet for it). The bridge never turns it off by itself: its dial stays live. But right after the dial is turned to 0, Apple Home still shows it on for a few seconds: turning it off at that moment turns it off "by the app", and its dial no longer responds.
- Apple Home follows the dial and amaran Desktop within about 2 s: the lights report nothing on their own, and the bridge reads them all every 2 s (`mesh releve <s>` to change).
- amaran Desktop, for its part, does not follow the commands coming from Apple Home.
- Apple Home shows a light as "No Response", and then its return, only after its tile has been touched. The bridge nevertheless publishes every change.
- For brightness, tapping the Apple Home slider is smoother than dragging it: a drag sends a value every 150 to 300 ms.
- A light enters Apple Home only at its first reply, then stays there: when absent, it shows as "No Response" there, and keeps its tile, its room and its scenes. To remove it from Apple Home: `mesh lampe <n> masquer`. Apple Home then forgets the light: put back (`afficher`, with the same number), it returns as a new accessory, under its amaran Desktop name, without the name given in Apple Home, nor group, nor scenes, nor automations (bench test of 2026-10-05). Apple Home has been seen afterwards refusing to change the icon of the returned light ("This setting can't be changed"): removing the bridge from Apple Home and then re-pairing it fixed it (2026-10-06).
- Removing a light in amaran Desktop, then reloading the list (`outils/cles_amaran.py`), makes it lose its number: put back later, it returns as a new light.
- `mesh oublie` erases the keys, but keeps the list of lights: their tiles stay, as "No Response", until the keys are reloaded. `mesh lampes 0` empties the list.
- A model the bridge does not know yet is controlled for on/off and intensity only. `outils/cles_amaran.py` flags a light that declares color temperature or color: model to be cataloged.
- If a reachable light misses more than 5% of its status reads over 10 minutes, the console says so (`!! lampe <n> : relectures manquees, <p> % repondues sur 10 min`): lengthen the period (`mesh releve`). The first verdict comes at the earliest 10 minutes after startup; after a late Mesh startup, or a light absent for 10 minutes or more, it waits for 5 minutes of status reads.
- BOOT button: right after a canceled press (held from 2 to 8 s, so with no effect), release cleanly; a brush reboots the bridge, with no consequence (the keys and the pairing stay).
- An accented light name: the text console (and therefore `outils/cles_amaran.py`) strips the non-ASCII characters from it. The companion app, which loads the bridge in machine mode, keeps them.

## Network keys

Whoever holds the Bluetooth Mesh network keys controls the lights.
- They **never** go in this repository.
- The companion app, or a script, reads them from the amaran Desktop database and
  loads them into the ESP32 over USB, never over the network.

## amaran Desktop on macOS 27

amaran Desktop 1.1.03 crashes at startup on macOS 27: matplotlib, which it
bundles, can no longer read the system's font list. The script
[outils/polices_amaran_desktop.py](outils/polices_amaran_desktop.py) places for it
the font cache it looks for, without touching the application:

```bash
python3 outils/polices_amaran_desktop.py
```

To undo, delete the file the script indicates.

## Credits

The lights' protocol was decoded by two free projects, under the MIT
license:
- [amaran-bridge](https://github.com/kevinschaich/amaran-bridge), by Kevin
  Schaich. This bridge reuses code from it: the encoding of Telink frames
  (`components/telink/telink.c`) and the sequence for joining the network
  (`components/mesh/mesh_amaran.c`). Each of these files keeps, at the top, the
  author's MIT license notice;
- [amaran-BLE-control](https://github.com/wesbos/amaran-BLE-control), by Wes
  Bos. This bridge owes him its knowledge of the protocol (the `0x26` opcode), but
  reuses none of his code.

The amaran Desktop repair script
([outils/polices_amaran_desktop.py](outils/polices_amaran_desktop.py)) reuses
from [matplotlib](https://matplotlib.org) 3.10.8 (`font_manager.py`) the function
`ttfFontProperty` and the `_weight_regexes` table, under the
[matplotlib license](https://matplotlib.org/stable/project/license.html)
(Copyright (c) 2012- Matplotlib Development Team). Its notice is at the top of the
script, and the license text is in
[outils/LICENCE-matplotlib.txt](outils/LICENCE-matplotlib.txt).

The LED and the BOOT button reuse the logic of the Halo bridge
([benq-screenbar-halo-matter](https://github.com/Djoko-cli/benq-screenbar-halo-matter),
by the same author): `components/socle`, with its tests. The JSON mode
(`components/protocole`), the H1 envelope for access over Thread
(`components/h1`, with its tests) and the companion app (`apps/macos`) are an
adapted copy of its protocol and of Halo Compagnon.

Personal project, with no connection to Aputure. It neither opens nor modifies the lights.
