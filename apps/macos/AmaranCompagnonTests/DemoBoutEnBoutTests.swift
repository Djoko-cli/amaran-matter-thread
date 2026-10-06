// Bout en bout sans materiel (spec 3b, section 10) : le pont simule du mode demo, le
// tramage, la session, la correlation et le modele Pont, comme dans l'app. Le
// trousseau est en memoire : rien ne touche celui du Mac.
import AmaranProtocole
import Foundation
import Testing
@testable import AmaranCompagnon

/// Attend qu'une condition devienne vraie, au plus `delai` (repris de Halo Compagnon) :
/// pas de sommeil de duree fixe, qui casserait sur une machine chargee.
@MainActor
func attendre(_ delai: Duration = .seconds(15), _ condition: () -> Bool) async -> Bool {
    let fin = ContinuousClock.now + delai
    while ContinuousClock.now < fin {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return condition()
}

@MainActor
func pontDemo(copie: ReseauMesh? = ReseauDemo.reseau) -> Pont {
    let p = Pont(trousseau: TrousseauMemoire(), trousseauDemo: TrousseauMemoire(copie),
                 trousseauPonts: TrousseauPontsMemoire(), trousseauPontsDemo: TrousseauPontsMemoire(),
                 preferences: UserDefaults(suiteName: "amaran.tests.\(UUID().uuidString)")!)
    p.vitesseDemo = 20
    p.connecter(.demo)
    return p
}

@MainActor
func connecte(_ p: Pont) async -> Bool {
    await attendre { p.phase == .connecte && p.etat.configLampes.count == 3 && !p.moteur.instantaneEnCours }
}

@Suite("Mode demo, bout en bout", .serialized)
@MainActor
struct DemoBoutEnBoutTests {
    @Test func connexionEtLampes() async throws {
        let p = pontDemo()
        defer { p.deconnecter() }
        #expect(await connecte(p))
        #expect(p.lampes.map(\.nom) == ["Lampe bureau", "Lumière fenêtre", "Lampe du fond"])
        #expect(p.lampes[0].etat?.lue == EtatLu(marche: true, intensite: 500))
        #expect(p.etat.capacites.contains("ordres"))
        // La lampe jamais vue repond au bout de 15 s simulees : elle entre dans Maison.
        #expect(await attendre { p.lampes[2].etat?.maison?.endpoint == 5 })
        #expect(p.console.elements.contains { $0.texte == "Lampe 3 : entre dans Maison (EP5)." })
    }

    @Test func ordresConfirmeEtDejaTenu() async throws {
        let p = pontDemo()
        defer { p.deconnecter() }
        #expect(await connecte(p))
        p.allumer(lampe: 1, false)
        #expect(await attendre { p.suivis.last?.etat == .confirmee })
        #expect(await attendre { p.lampes[0].etat?.lue?.marche == false })
        #expect(p.lampes[0].dernierOrdre?.issue == .confirme)
        p.allumer(lampe: 2, false)  // deja eteinte
        #expect(await attendre { p.suivis.last?.etat == .tenue })
        p.niveau(lampe: 1, pourCent: 73, fini: true)
        #expect(await attendre { p.lampes[0].etat?.lue?.intensite == 730 })
    }

    @Test func remettrePuisRetirerDeMaison() async throws {
        let p = pontDemo()
        defer { p.deconnecter() }
        #expect(await connecte(p))
        #expect(p.lampes[1].etat?.maison?.masquee == true, "la lampe 2 de la demo est retiree de Maison")
        p.exposer(lampe: 2, dansMaison: true)
        #expect(await attendre { p.lampes[1].etat?.maison?.endpoint == 3 }, "remise avec son numero")
        #expect(p.console.elements.contains { $0.texte == "Lampe 2 : remise dans Maison (EP3)." })
        p.exposer(lampe: 1, dansMaison: false)
        #expect(await attendre { p.lampes[0].etat?.maison?.masquee == true && p.lampes[0].etat?.maison?.endpoint == nil })
        #expect(p.console.elements.contains { $0.texte == "Lampe 1 : retirée de Maison." })
    }

    /// Charger le pont depuis la copie : quatre controles, redemarrage, comparaison.
    /// Les cles ne restent ni dans les suivis, ni dans la console.
    @Test func chargementDuPont() async throws {
        let p = pontDemo()
        defer { p.deconnecter() }
        #expect(await connecte(p))
        #expect(p.ecartsCles.isEmpty, "le pont simule a deja les cles de la copie")
        p.chargerPont(depuis: .trousseau)
        #expect(await attendre(.seconds(30)) {
            if case .reussi = p.chargement { return true }
            return false
        }, "chargement : \(p.chargement)")
        let cleHexa = ReseauDemo.reseau.commandes()[0].dropFirst("mesh cles ".count).prefix(32)
        #expect(!p.suivis.contains { $0.commande.contains(cleHexa) })
        #expect(!p.console.elements.contains { $0.texte.contains(cleHexa) })
        #expect(p.suivis.contains { $0.commande == "mesh cles •••••••• ••••••••" && $0.etat == .terminee })
        #expect(p.ecartsCles.isEmpty)
    }

    /// Les lampes de la demo ont des versions inventees ; le pont simule les rend dans le bloc `config`
    /// `lampe`, annonce la capacite `logiciel`, et la carte de lampe en montre la ligne.
    @Test func versionsDesLampesDeLaDemo() async throws {
        let p = pontDemo()
        defer { p.deconnecter() }
        #expect(await connecte(p))
        #expect(p.etat.a(.logiciel))
        #expect(p.lampes.map { $0.config?.logiciel } == ["1.4", "1.4", "1.4"])
        #expect(p.lampes.map { $0.config?.ble } == ["1.69", "1.69", nil])
        #expect(p.lampes.compactMap { $0.config.map { Interpretation.logiciel($0, pontPrendLesVersions: true) } } == ["1.4 (BLE 1.69)", "1.4 (BLE 1.69)", "1.4"])
        #expect(p.ecartsCles.isEmpty, "le pont simule a deja les versions de la copie")
    }

    /// « Charger le pont » envoie le jeton de version quand le pont a la capacite `logiciel`, et la
    /// verification apres le redemarrage compare les versions rendues.
    @Test func chargementAvecLesVersions() async throws {
        let p = pontDemo()
        defer { p.deconnecter() }
        #expect(await connecte(p))
        p.chargerPont(depuis: .trousseau)
        #expect(await attendre(.seconds(30)) {
            if case .reussi = p.chargement { return true }
            return false
        }, "chargement : \(p.chargement)")
        let lignes = p.suivis.map(\.commande).filter { $0.hasPrefix("mesh lampe ") && !$0.hasPrefix("mesh lampe 1 afficher") }
        #expect(lignes == [
            "mesh lampe 1 0x0002 02:00:00:00:0D:01 40065 v1.4/1.69 \"Lampe bureau\"",
            "mesh lampe 2 0x0004 02:00:00:00:0D:02 40065 v1.4/1.69 \"Lumière fenêtre\"",
            "mesh lampe 3 0x0006 02:00:00:00:0D:03 40065 v1.4 \"Lampe du fond\"",
        ])
        #expect(!p.console.elements.contains { $0.texte.contains("firmware") })
        #expect(p.lampes.map { $0.config?.logiciel } == ["1.4", "1.4", "1.4"])
        #expect(p.ecartsCles.isEmpty)
    }

    /// Une copie sans versions (faite avant la fiche des lampes) : le pont simule, qui les connait,
    /// differe de la copie, et la verification apres chargement ne les attend pas.
    @Test func copieSansVersionsContreUnPontQuiLesA() async throws {
        var ancienne = ReseauDemo.reseau
        for i in ancienne.lampes.indices { ancienne.lampes[i].logiciel = nil; ancienne.lampes[i].ble = nil }
        let p = pontDemo(copie: ancienne)
        defer { p.deconnecter() }
        #expect(await connecte(p))
        #expect(p.ecartsCles == [.pontVersionsDifferentes])
        p.chargerPont(depuis: .trousseau)
        #expect(await attendre(.seconds(30)) {
            if case .reussi = p.chargement { return true }
            return false
        }, "chargement : \(p.chargement)")
        #expect(p.suivis.map(\.commande).contains("mesh lampe 1 0x0002 02:00:00:00:0D:01 40065 \"Lampe bureau\""))
        // Sans jeton, le pont simule a perdu les versions : la copie n'en a pas non plus.
        #expect(await attendre { p.lampes.map { $0.config?.logiciel } == [nil, nil, nil] })
        #expect(p.ecartsCles.isEmpty)
    }

    /// Un pont qui n'annonce pas `logiciel` (firmware d'avant) lirait le jeton comme le debut du nom :
    /// l'app charge sans versions, le dit, et ne boucle pas sur l'ecart des versions.
    @Test func pontSansLaCapaciteLogiciel() async throws {
        let p = Pont(trousseau: TrousseauMemoire(), trousseauDemo: TrousseauMemoire(ReseauDemo.reseau),
                     trousseauPonts: TrousseauPontsMemoire(), trousseauPontsDemo: TrousseauPontsMemoire(),
                     preferences: UserDefaults(suiteName: "amaran.tests.\(UUID().uuidString)")!)
        p.vitesseDemo = 20
        p.demoAnnonceLogiciel = false
        p.connecter(.demo)
        defer { p.deconnecter() }
        #expect(await connecte(p))
        #expect(!p.etat.a(.logiciel))
        #expect(p.lampes.map { $0.config?.logiciel } == [nil, nil, nil])
        #expect(p.ecartsCles == [.pontSansVersions], "a mettre a jour, pas a recharger")
        p.chargerPont(depuis: .trousseau)
        #expect(p.console.elements.contains { $0.texte.contains("Ce pont ne prend pas la version des lampes : mettre à jour son firmware.") })
        #expect(await attendre(.seconds(30)) {
            if case .reussi = p.chargement { return true }
            return false
        }, "chargement : \(p.chargement)")
        let lignes = p.suivis.map(\.commande).filter { $0.hasPrefix("mesh lampe ") }
        #expect(lignes.count == 3 && !lignes.contains { $0.contains(" v1.") }, "\(lignes)")
        #expect(p.ecartsCles == [.pontSansVersions])
        // Le nom rendu est intact, et la ligne « Logiciel » dit le geste qui convient.
        #expect(p.lampes.map { $0.config?.nom } == ["Lampe bureau", "Lumière fenêtre", "Lampe du fond"])
        #expect(p.lampes.compactMap { $0.config.map { Interpretation.logiciel($0, pontPrendLesVersions: p.etat.a(.logiciel)) } }
                == Array(repeating: "inconnu (firmware du pont à mettre à jour)", count: 3))
        // Un jeton envoye a la main n'est pas reconnu : tout est le nom, et la reponse ne parle pas de version.
        p.envoyer("mesh lampes 1")
        #expect(await attendre { p.suivis.last?.commande == "mesh lampes 1" && p.suivis.last?.etat.estFinal == true })
        #expect(p.suivis.last?.texte == ["ok liste de 1 lampe(s) : envoyer mesh lampe 1 a 1"])
        p.envoyer("mesh lampe 1 0x0002 02:00:00:00:0D:01 40065 v1.4/1.69 \"A\"")
        #expect(await attendre { p.suivis.last?.commande.contains("v1.4/1.69") == true && p.suivis.last?.etat.estFinal == true })
        #expect(p.suivis.last?.texte.first == "ok lampe 1 0x0002 modele 40065 amaran COB 60d [intensite] : v1.4/1.69 A"
                    + " ; liste de 1 lampe(s) enregistree (redemarrer pour l'appliquer)", "\(p.suivis.last?.texte ?? [])")
        p.envoyer("mesh lampe 9 0x0002 02:00:00:00:0D:01 40065 \"A\"")
        #expect(await attendre { p.suivis.last?.commande.hasPrefix("mesh lampe 9") == true && p.suivis.last?.etat.estFinal == true })
        #expect(p.suivis.last?.texte == ["erreur : mesh lampe <1-1> <adresse> <mac> <code> <nom>"])
    }

    /// Comme le pont : `argv[6]` est un jeton seulement s'il reste un mot apres lui et s'il a la forme
    /// `v<x.y>[/<x.y>]` ; sinon tout est le nom, sans erreur.
    @Test func lePontSimuleLitLeJetonCommeLeFirmware() async throws {
        let p = pontDemo()
        defer { p.deconnecter() }
        #expect(await connecte(p))
        p.envoyer("mesh lampes 1")
        #expect(await attendre { p.suivis.last?.etat == .terminee })
        #expect(p.suivis.last?.texte == ["ok liste de 1 lampe(s) : envoyer mesh lampe 1 a 1 [v<x.y>[/<x.y>]]"])
        let tete = "mesh lampe 1 0x0002 02:00:00:00:0D:01 40065"
        var vu = Set<String>()
        func envoyer(_ fin: String, _ attendu: String, _ n: Int = #line) async {
            let ligne = "\(tete) \(fin)"
            p.envoyer(ligne)
            #expect(await attendre { p.suivis.last?.commande == ligne && p.suivis.last?.etat.estFinal == true }, "ligne \(n) : \(ligne)")
            #expect(p.suivis.last?.fin?.ok == true, "ligne \(n) : \(p.suivis.last?.texte ?? [])")
            #expect(p.suivis.last?.texte.contains { $0.contains(attendu) } == true, "ligne \(n) : \(p.suivis.last?.texte ?? [])")
            vu.insert(ligne)
        }
        // Nom entre guillemets sans jeton, meme s'il a la forme d'une version : le nom reste intact.
        await envoyer("\"v2\"", "logiciel inconnu : v2 ;")
        await envoyer("\"v2 bureau\"", "logiciel inconnu : v2 bureau ;")
        await envoyer("\"v1.4 bureau\"", "logiciel inconnu : v1.4 bureau ;")
        // Un seul mot de la forme d'un jeton, sans rien apres : c'est le nom.
        await envoyer("v1.4", "logiciel inconnu : v1.4 ;")
        // Jeton puis nom : version et nom.
        await envoyer("v1.4/1.69 \"A\"", "logiciel 1.4 (BLE 1.69) : A ;")
        await envoyer("v1.4 \"v2 bureau\"", "logiciel 1.4 : v2 bureau ;")
        // Jeton mal forme suivi d'un nom : tout est le nom, sans erreur.
        for mot in ["v1.4.2", "v1", "v1.4/", "v1.4/1", "v1234.5"] {
            await envoyer("\(mot) \"A\"", "logiciel inconnu : \(mot) A ;")
        }
        // Un nom ordinaire, un mot qui commence par v sans chiffre.
        p.envoyer("mesh lampe 9 0x0002 02:00:00:00:0D:01 40065 \"A\"")
        #expect(await attendre { p.suivis.last?.commande.hasPrefix("mesh lampe 9") == true && p.suivis.last?.etat.estFinal == true })
        #expect(p.suivis.last?.texte == ["erreur : mesh lampe <1-1> <adresse> <mac> <code> [v<x.y>[/<x.y>]] <nom>"])
        await envoyer("\"Vase\"", "logiciel inconnu : Vase ;")
        await envoyer("vente \"A\"", "logiciel inconnu : vente A ;")
        #expect(vu.count == 13)
    }

    @Test func chargementRefuseParLesPreControles() async throws {
        var faux = ReseauDemo.reseau
        faux.lampes[1].adresse = 0x7F38
        let p = pontDemo(copie: faux)
        defer { p.deconnecter() }
        #expect(await connecte(p))
        let avant = p.suivis.count
        p.chargerPont(depuis: .trousseau)
        #expect(p.chargement == .echec(ErreurReseau.adresseDuPont(lampe: 2, 0x7F38).description))
        #expect(p.suivis.count == avant, "rien n'est envoye au pont")
    }

    @Test func sauvegardeExporteePuisImportee() async throws {
        let p = pontDemo()
        defer { p.deconnecter() }
        let fichier = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).sauvegarde")
        defer { try? FileManager.default.removeItem(at: fichier) }
        let phrase = "phrase de passe de test"
        #expect(throws: ErreurSauvegarde.phrasesDifferentes) {
            try p.exporterSauvegarde(vers: fichier, phrase: phrase, confirmation: phrase + ".")
        }
        try p.exporterSauvegarde(vers: fichier, phrase: phrase, confirmation: phrase)
        #expect(p.derniereSauvegarde == nil, "la demo n'ecrit pas dans les preferences")
        #expect(p.preferences.object(forKey: Pont.cleSauvegarde) == nil)
        var lue = try p.lireSauvegarde(fichier, phrase: phrase)
        #expect(lue.source == .sauvegarde)
        lue.source = .amaranDesktop
        #expect(lue == ReseauDemo.reseau)
        #expect(throws: ErreurSauvegarde.ouvertureImpossible) { try p.lireSauvegarde(fichier, phrase: "une autre phrase") }
        try p.trousseauDemo.oublier()
        p.rafraichirCopie()
        #expect(p.copie == nil)
        try p.remplacerCopie(par: lue)
        #expect(p.copie?.memeReseau(que: ReseauDemo.reseau.apercu) == true)
    }
}

@Suite("Trousseau du reseau")
struct TrousseauTests {
    static func exercer(_ t: any TrousseauReseau) throws {
        try? t.oublier()
        #expect(try t.apercu() == nil)
        #expect(throws: ErreurTrousseau.absente) { try t.lire() }
        try t.ranger(ReseauDemo.reseau)
        #expect(try t.apercu() == ReseauDemo.reseau.apercu)
        #expect(try t.lire() == ReseauDemo.reseau)
        var autre = ReseauDemo.reseau
        autre.lampes.removeLast()
        try t.ranger(autre)
        #expect(try t.lire().lampes.count == 2, "remplacee, pas doublee")
        try t.oublier()
        #expect(try t.apercu() == nil)
        try t.oublier()  // deja oublie : sans erreur
    }

    @Test func enMemoire() throws {
        try Self.exercer(TrousseauMemoire())
    }

    /// Le trousseau rend les versions des lampes comme il les a rangees.
    @Test func gardeLesVersions() throws {
        let t = TrousseauMemoire()
        try t.ranger(ReseauDemo.reseau)
        let r = try t.lire()
        #expect(r.lampes.map(\.logiciel) == ["1.4", "1.4", "1.4"] && r.lampes.map(\.ble) == ["1.69", "1.69", nil])
        #expect(try t.apercu()?.lampes.map(\.jetonVersion) == ["v1.4/1.69", "v1.4/1.69", "v1.4"])
    }

    /// Vrai trousseau (service de test, nettoye) : seulement sur demande,
    /// `TEST_RUNNER_AMARAN_TEST_TROUSSEAU=1 xcodebuild ... test`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["AMARAN_TEST_TROUSSEAU"] == "1"))
    func trousseauDuMac() throws {
        try Self.exercer(TrousseauSysteme(service: "fr.djoko.amaran.reseau.tests"))
    }
}

/// Les tests heberges tournent dans l'app, donc dans sa sandbox.
@Suite("Sandbox")
struct SandboxTests {
    /// Dans une app sandboxee, homeDirectoryForCurrentUser est le conteneur de l'app :
    /// le panneau d'ouverture doit proposer le vrai dossier d'amaran Desktop.
    @Test func dossierHabituelHorsDuConteneur() {
        let chemin = BaseAmaranDesktop.dossierHabituel.path
        #expect(!chemin.contains("/Containers/fr.djoko.amaran.compagnon"), "\(chemin)")
        #expect(chemin.hasSuffix("/Library/Containers/com.sidus.amaran-desktop/Data/Library/Application Support/amaran Desktop"))
    }
}

@Suite("Port du pont")
@MainActor
struct PortDuPontTests {
    @Test func seulLePontEspressifEstRetenu() {
        func port(_ chemin: String, vid: Int, serie: String?) -> PortUSB {
            PortUSB(chemin: chemin, vid: vid, pid: 0x1001, serie: serie, produit: nil)
        }
        let pont = "02:00:00:00:00:AA"
        // Meme numero de serie sous un autre nom : ce port.
        let ailleurs = [port("/dev/cu.usbmodem1101", vid: 0x303A, serie: "02:00:00:00:00:BB"),
                        port("/dev/cu.usbmodem2201", vid: 0x303A, serie: pont)]
        #expect(Pont.portDuPont(ailleurs, chemin: "/dev/cu.usbmodem1101", serie: pont)?.chemin == "/dev/cu.usbmodem2201")
        // Numero connu mais absent : jamais un autre port Espressif de meme nom.
        let autre = [port("/dev/cu.usbmodem1101", vid: 0x303A, serie: "02:00:00:00:00:BB")]
        #expect(Pont.portDuPont(autre, chemin: "/dev/cu.usbmodem1101", serie: pont) == nil)
        // Sans numero connu, un port qui n'est pas Espressif n'est jamais retenu.
        let ecran = [port("/dev/cu.usbmodem1101", vid: 0x043E, serie: nil)]
        #expect(Pont.portDuPont(ecran, chemin: "/dev/cu.usbmodem1101", serie: nil) == nil)
        // Sans numero connu : le port Espressif de meme chemin.
        let memeChemin = ecran + [port("/dev/cu.usbmodem1101", vid: 0x303A, serie: nil),
                                  port("/dev/cu.usbmodem3301", vid: 0x303A, serie: nil)]
        #expect(Pont.portDuPont(memeChemin, chemin: "/dev/cu.usbmodem1101", serie: nil)?.vid == 0x303A)
        #expect(Pont.portDuPont(memeChemin, chemin: "/dev/cu.usbmodem1101", serie: nil)?.chemin == "/dev/cu.usbmodem1101")
    }

    @Test func sourceParDefautVisaSeulementLeDernierPontChoisi() {
        func port(_ chemin: String, vid: Int, serie: String?) -> PortUSB {
            PortUSB(chemin: chemin, vid: vid, pid: 0x1001, serie: serie, produit: nil)
        }
        let pont = "02:00:00:00:00:AA"
        let autre = "02:00:00:00:00:BB"
        // Numero retenu present sur un port Espressif : ce port, sous son nom actuel.
        let deux = [port("/dev/cu.usbmodem1101", vid: 0x303A, serie: autre),
                    port("/dev/cu.usbmodem2201", vid: 0x303A, serie: pont)]
        #expect(Pont.sourceParDefaut(ports: deux, dernierPont: pont) == .serie(chemin: "/dev/cu.usbmodem2201", serie: pont))
        // Numero retenu absent alors qu'un autre port Espressif est branche : rien.
        #expect(Pont.sourceParDefaut(ports: [deux[0]], dernierPont: pont) == nil)
        // Aucun numero retenu, meme avec un seul port Espressif : rien.
        #expect(Pont.sourceParDefaut(ports: [deux[1]], dernierPont: nil) == nil)
        // Un port qui n'est pas Espressif ne convient jamais, meme avec le numero retenu.
        #expect(Pont.sourceParDefaut(ports: [port("/dev/cu.usbmodem3301", vid: 0x043E, serie: pont)], dernierPont: pont) == nil)
    }

    /// Titres des ports comme Halo Compagnon : "MODELE · MAC" (modele du repertoire ; `AMARAN`
    /// pour le dernier pont confirme pas encore note ; sinon "ESP32"), le nom court sans MAC.
    @Test func titresDesPortsEtConfirmationDuPont() {
        func port(_ chemin: String, vid: Int, serie: String?) -> PortUSB {
            PortUSB(chemin: chemin, vid: vid, pid: 0x1001, serie: serie, produit: nil)
        }
        let pont = "02:00:00:00:00:AA"
        let autre = "02:00:00:00:00:BB"
        let prefs = UserDefaults(suiteName: "amaran.tests.\(UUID().uuidString)")!
        prefs.set(pont, forKey: Pont.cleDernierPont)
        let p = Pont(trousseau: TrousseauMemoire(), trousseauDemo: TrousseauMemoire(),
                     trousseauPonts: TrousseauPontsMemoire(), trousseauPontsDemo: TrousseauPontsMemoire(),
                     preferences: prefs)
        // Dernier pont confirme, repertoire encore vide : le modele AMARAN ; l'autre carte : ESP32.
        #expect(p.titre(port: port("/dev/cu.usbmodem2201", vid: 0x303A, serie: pont)) == "AMARAN · 02:00:00:00:00:AA")
        #expect(p.titre(port: port("/dev/cu.usbmodem1101", vid: 0x303A, serie: autre)) == "ESP32 · 02:00:00:00:00:BB")
        // Le repertoire fait foi des qu'il connait la carte (modele appris au hello).
        p.repertoire.noter(mac: autre, serie: "AMARAN-0200000000BB", srp: nil)
        #expect(p.titre(port: port("/dev/cu.usbmodem1101", vid: 0x303A, serie: autre)) == "AMARAN · 02:00:00:00:00:BB")
        p.repertoire.noter(mac: pont, serie: "BANC-0200000000AA", srp: nil)
        #expect(p.titre(port: port("/dev/cu.usbmodem2201", vid: 0x303A, serie: pont)) == "BANC · 02:00:00:00:00:AA")
        // Sans numero de serie lisible : le nom court du port.
        #expect(p.titre(port: port("/dev/cu.usbmodem1101", vid: 0x303A, serie: nil)) == "usbmodem1101")
        #expect(p.titre(port: port("/dev/cu.usbmodem1101", vid: 0x303A, serie: "")) == "usbmodem1101")
        #expect(p.titre(port: port("/dev/cu.usbmodem1101", vid: 0x303A, serie: "pas-une-mac")) == "usbmodem1101")
        // La source serie choisie, debranchee ou non, porte le meme titre.
        #expect(p.titre(serie: autre, chemin: "/dev/cu.usbmodem1101") == "AMARAN · 02:00:00:00:00:BB")
        #expect(p.titre(serie: nil, chemin: "/dev/cu.usbmodem1101") == "usbmodem1101")
        // Aucun pont confirme : toute carte inconnue est ESP32.
        let vierge = Pont(trousseau: TrousseauMemoire(), trousseauDemo: TrousseauMemoire(),
                          trousseauPonts: TrousseauPontsMemoire(), trousseauPontsDemo: TrousseauPontsMemoire(),
                          preferences: UserDefaults(suiteName: "amaran.tests.\(UUID().uuidString)")!)
        #expect(vierge.titre(port: port("/dev/cu.usbmodem1101", vid: 0x303A, serie: pont)) == "ESP32 · 02:00:00:00:00:AA")

        // Un pont est confirme par la capacite `mesh` ou par un numero de serie AMARAN-.
        func identite(caps: [String]?, serie: String?) -> HelloIdentite? {
            var champs: [String: Any] = [:]
            if let caps { champs["caps"] = caps }
            if let serie { champs["id"] = ["serie": serie] }
            return try? JSONDecoder().decode(HelloIdentite.self, from: JSONSerialization.data(withJSONObject: champs))
        }
        #expect(Pont.estPontAmaran(identite(caps: ["ordres", "mesh"], serie: nil)))
        #expect(Pont.estPontAmaran(identite(caps: nil, serie: "AMARAN-0000")))
        #expect(!Pont.estPontAmaran(identite(caps: ["ordres"], serie: "BENQ-0000")))
        #expect(!Pont.estPontAmaran(identite(caps: nil, serie: nil)))
        #expect(!Pont.estPontAmaran(nil))
    }
}
