import AmaranProtocole
import Foundation
import Testing
@testable import AmaranCompagnon

/// Impose une langue aux textes du test (et de ses sous-taches), sans toucher
/// a la langue de l'app : les suites tournent en parallele.
struct LangueImposee: TestTrait, SuiteTrait, TestScoping {
    let langue: Langue
    var isRecursive: Bool { true }

    func provideScope(for test: Test, testCase: Test.Case?,
                      performing function: @Sendable () async throws -> Void) async throws {
        try await Localisation.$imposee.withValue(langue) { try await function() }
    }
}

extension Trait where Self == LangueImposee {
    static func langue(_ l: Langue) -> Self { LangueImposee(langue: l) }
}

@Suite("Langue de l'app", .serialized)
@MainActor
struct LangueAppTests {
    /// Preferences des tests, videes avant et apres : le choix de
    /// l'utilisateur n'est pas touche, et un seul fichier sert a chaque passage.
    static let nomDefauts = "fr.djoko.amaran.compagnon.tests.langue"

    static func defauts() throws -> UserDefaults {
        let d = try #require(UserDefaults(suiteName: nomDefauts))
        d.removePersistentDomain(forName: nomDefauts)
        return d
    }

    static func propre(_ d: UserDefaults, _ cle: String) -> Any? {
        d.persistentDomain(forName: nomDefauts)?[cle]
    }

    @Test(.langue(.anglais)) func textesDeLAppEnAnglais() {
        #expect(Ecran.allCases.map(\.titre) == ["Dashboard", "Charts", "Frames", "Controls & Console"])
        #expect(QuoiTrame.demande.libelle == "State request")
        #expect(SensTrame.tx.libelle == "Sent")
        #expect(Format.oui(true) == "yes")
        #expect(Format.duree(secondes: 90_061) == "1 d 1 h 1 min")
        #expect(TransportDemo.nomLisible == "Demo (simulated bridge with three lamps)")
        #expect(MoteurSession.Phase.attenteHello(essai: 2).libelle == "waiting for hello")
        #expect(MotifLed.injoignable.libelle == "lamp unreachable (red ×3)")
        #expect(EtatCommande.tenue.libelle == "already satisfied")
        #expect(EtatSessionPont.ouverte.libelle == "session open")
        #expect(Pont.avertissementRetrait.hasPrefix("Apple Home removes the lamp's tile."))
        #expect(VueLampe(numero: 3, config: nil, etat: nil, dernierOrdre: nil).nom == "Lamp 3")
        #expect(AlerteReseau.sansHello.texte.hasPrefix("No answer to json 1 over the network: two other sessions"))
        #expect(CompteursMesh.texte(.demandes, dernierReleve: nil) == "Mesh counters requested, waiting for the first readout")
        #expect(Pont.texteSansReponse(.usb) == "no reply within 3 s (not resent)")
        #expect(Pont.texteSansAccesReseau(parUSB: false, udpAnnonce: true, ipRecu: true, srpConnu: true)
                == "Plug the bridge in over USB and connect to it (Source menu) to create or renew its key.")
    }

    @Test(.langue(.francais)) func textesDeLAppEnFrancais() {
        #expect(Ecran.allCases.map(\.titre) == ["Tableau de bord", "Graphiques", "Trames", "Commandes et console"])
        #expect(QuoiTrame.demande.libelle == "Demande d'état")
        #expect(SensTrame.tx.libelle == "Émise")
        #expect(Format.oui(true) == "oui")
        #expect(Format.duree(secondes: 90_061) == "1 j 1 h 1 min")
        #expect(TransportDemo.nomLisible == "Démo (pont simulé à trois lampes)")
        #expect(MoteurSession.Phase.attenteHello(essai: 2).libelle == "attente du hello")
        #expect(Pont.avertissementRetrait.hasPrefix("Maison retire la tuile de la lampe."))
        #expect(VueLampe(numero: 3, config: nil, etat: nil, dernierOrdre: nil).nom == "Lampe 3")
        #expect(Pont.texteSansReponse(.usb) == "sans réponse sous 3 s (pas de réémission)")
    }

    /// Les notes du modele dans la console sont ecrites dans la langue en vigueur ; ce que dit
    /// le pont (le pont simule du mode demo ici) reste tel quel.
    @Test(.langue(.anglais)) func notesDeLaConsoleEnAnglais() async throws {
        let p = pontDemo()
        defer { p.deconnecter() }
        #expect(await connecte(p))
        #expect(p.console.elements.contains { $0.texte == "Demo bridge open." })
        #expect(await attendre { p.lampes[2].etat?.maison?.endpoint == 5 })
        #expect(p.console.elements.contains { $0.texte == "Lamp 3: enters Apple Home (EP5)." })
        #expect(p.lampes.map(\.nom) == ["Lampe bureau", "Lumière fenêtre", "Lampe du fond"], "les noms de lampes viennent du pont")
        p.allumer(lampe: 1, false)
        #expect(await attendre { p.suivis.last?.etat == .confirmee })
        #expect(p.console.elements.contains { $0.texte.hasPrefix("‹ id=") && $0.texte.contains(": confirmed in ") })
    }

    /// Les formats suivent la langue choisie (avec la region de l'utilisateur,
    /// qui depend de la machine : on ne compare que ce que la langue change).
    @Test func formatsSelonLaLangue() {
        let midi = Date(timeIntervalSince1970: 43_200.5)
        for l in Langue.allCases {
            let h = Localisation.$imposee.withValue(l) { Format.heure(midi) }
            #expect(h.contains("00.500") || h.contains("00,500"), "heure a la milliseconde : \(h)")
        }
        // Unites d'octets : "ko" en francais, "kB" en anglais.
        let octetsEn = Localisation.$imposee.withValue(.anglais) { Format.octets(1536) }
        let octetsFr = Localisation.$imposee.withValue(.francais) { Format.octets(1536) }
        #expect(octetsEn != octetsFr, "\(octetsEn) / \(octetsFr)")
        // L'intensite a la decimale : « 43,5 % » en francais, « 43.5% » en anglais (separateur selon la region).
        #expect(Localisation.$imposee.withValue(.francais) { Interpretation.intensite(435) }.hasSuffix("5 %"))
        #expect(Localisation.$imposee.withValue(.anglais) { Interpretation.intensite(435) }.hasSuffix("5%"))
    }

    @Test func choixPersisteEtApplique() throws {
        let d = try Self.defauts()
        defer { d.removePersistentDomain(forName: Self.nomDefauts) }
        let nom = Self.nomDefauts
        let l = Localisation(langue: .francais)
        #expect(ReglageLangue.choix(d) == .systeme, "par defaut : la langue du systeme")

        ReglageLangue.appliquer(.anglais, defauts: d, domaine: nom, localisation: l)
        #expect(ReglageLangue.choix(d) == .anglais)
        #expect(Self.propre(d, ReglageLangue.cleAppleLanguages) as? [String] == ["en"],
                "les menus de macOS suivront au prochain lancement")
        #expect(l.langue == .anglais)
        #expect(l.locale.language.languageCode == .english)

        ReglageLangue.appliquer(.francais, defauts: d, domaine: nom, localisation: l)
        #expect(l.langue == .francais)
        #expect(Self.propre(d, ReglageLangue.cleAppleLanguages) as? [String] == ["fr"])

        ReglageLangue.appliquer(.systeme, defauts: d, domaine: nom, localisation: l)
        #expect(ReglageLangue.choix(d) == .systeme)
        #expect(Self.propre(d, ReglageLangue.cleAppleLanguages) == nil, "la langue du systeme reprend la main")
        #expect(Self.propre(d, ReglageLangue.cleAppleLanguagesAvantChoix) == nil)
        #expect(l.langue == Langue.preferee(parmi: ReglageLangue.languesSysteme(d)))
    }

    /// Une langue choisie pour l'app dans Reglages Systeme (son `AppleLanguages`)
    /// revient avec « Langue du systeme », apres un passage par English/Francais.
    @Test func langueDeReglagesSystemeRendue() throws {
        let d = try Self.defauts()
        defer { d.removePersistentDomain(forName: Self.nomDefauts) }
        let nom = Self.nomDefauts
        let l = Localisation(langue: .francais)
        d.set(["en-GB"], forKey: ReglageLangue.cleAppleLanguages)

        // Au lancement, "Langue du systeme" la garde.
        ReglageLangue.appliquer(.systeme, defauts: d, domaine: nom, lancement: true, localisation: l)
        #expect(Self.propre(d, ReglageLangue.cleAppleLanguages) as? [String] == ["en-GB"])
        // (-AppleLanguages de la ligne de commande, `-testLanguage`, passe devant.)
        #expect(l.langue == Langue.preferee(parmi: ReglageLangue.languesSysteme(d)))

        ReglageLangue.appliquer(.francais, defauts: d, domaine: nom, localisation: l)
        ReglageLangue.appliquer(.anglais, defauts: d, domaine: nom, localisation: l)
        ReglageLangue.appliquer(.francais, defauts: d, domaine: nom, lancement: true, localisation: l)
        #expect(Self.propre(d, ReglageLangue.cleAppleLanguages) as? [String] == ["fr"])
        #expect(Self.propre(d, ReglageLangue.cleAppleLanguagesAvantChoix) as? [String] == ["en-GB"],
                "gardee a travers les choix et les lancements")

        ReglageLangue.appliquer(.systeme, defauts: d, domaine: nom, localisation: l)
        #expect(Self.propre(d, ReglageLangue.cleAppleLanguages) as? [String] == ["en-GB"])
        #expect(Self.propre(d, ReglageLangue.cleAppleLanguagesAvantChoix) == nil)
        #expect(l.langue == Langue.preferee(parmi: ReglageLangue.languesSysteme(d)))
    }
}
