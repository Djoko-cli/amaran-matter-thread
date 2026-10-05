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
        #expect(p.derniereSauvegarde != nil)
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
}
