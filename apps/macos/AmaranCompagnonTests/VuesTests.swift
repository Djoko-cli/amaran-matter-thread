// Tests des ecrans du plan 3b-2 (chantier C) : filtres des trames, flux des trames a
// distance, trames du pont simule, etat de session des ponts connus, textes de l'acces
// reseau, et tests de fumee des vues (les monter ne plante pas). Le vrai trousseau et les
// vraies preferences ne servent jamais ; valeurs inventees.
import AmaranProtocole
import Foundation
import AppKit
import SwiftUI
import Testing
@testable import AmaranCompagnon

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

@Suite("Filtres des trames")
struct FiltreTramesTests {
    static let ordre = Trame(sens: .tx, quoi: .ordre, lampe: 1, marche: true, intensite: 500, essai: 1, sautes: 0)
    static let demande = Trame(sens: .tx, quoi: .demande, lampe: nil, sautes: 0)
    static let etat1 = Trame(sens: .rx, quoi: .etat, lampe: 1, marche: true, intensite: 500, sautes: 2)
    static let etat2 = Trame(sens: .rx, quoi: .etat, lampe: 2, marche: false, intensite: 0, sautes: 0)
    static let inconnue = Trame(sens: .inconnu, quoi: .inconnu, lampe: 3)

    static let journal: [TrameRecue] = [ordre, demande, etat1, etat2, inconnue].enumerated().map { i, t in
        TrameRecue(id: i, date: t0.addingTimeInterval(Double(i)), trame: t)
    }

    @Test func sansFiltreToutPasseDuPlusRecentAuPlusAncien() {
        let f = FiltreTrames()
        #expect(f.estNeutre)
        #expect(f.appliquer(Self.journal).map(\.id) == [4, 3, 2, 1, 0])
    }

    @Test func parSens() {
        var f = FiltreTrames()
        f.sens = .tx
        #expect(f.appliquer(Self.journal).map(\.id) == [1, 0])
        f.sens = .rx
        #expect(f.appliquer(Self.journal).map(\.id) == [3, 2])
        #expect(!f.estNeutre)
    }

    @Test func parLampeOuGroupe() {
        var f = FiltreTrames()
        f.cible = .lampe(1)
        #expect(f.appliquer(Self.journal).map(\.id) == [2, 0], "ordre et etat de la lampe 1, jamais la demande au groupe")
        f.cible = .groupe
        #expect(f.appliquer(Self.journal).map(\.id) == [1])
        f.cible = .lampe(9)
        #expect(f.appliquer(Self.journal).isEmpty)
    }

    @Test func parNature() {
        var f = FiltreTrames()
        f.quoi = [.etat]
        // L'inconnue n'est jamais cachee : une trace qu'on ne comprend pas ne se filtre pas.
        #expect(f.appliquer(Self.journal).map(\.id) == [4, 3, 2])
        f.quoi = []
        #expect(f.appliquer(Self.journal).map(\.id) == [4])
    }

    @Test func filtresCombines() {
        let f = FiltreTrames(sens: .rx, cible: .lampe(2), quoi: [.etat])
        #expect(f.appliquer(Self.journal).map(\.id) == [3])
    }

    @Test func libellesEtCibles() {
        #expect(FiltreTrames.libelleCible(Self.demande, noms: [:]) == "Groupe")
        #expect(FiltreTrames.libelleCible(Self.ordre, noms: [1: "Lampe bureau"]) == "1 · Lampe bureau")
        #expect(FiltreTrames.libelleCible(Self.ordre, noms: [:]) == "1")
        #expect(SensTrame.tx.fleche == "→" && SensTrame.rx.fleche == "←")
        #expect(QuoiTrame.demande.libelle == "Demande d'état")
    }
}

@Suite("Graphiques : segments")
struct GraphiquesSegmentsTests {
    @Test func unRedemarrageDuPontEstUneRupture() throws {
        var s = SeriesCourbes()
        func sante(_ boot: String, _ heap: Int, _ dt: Double) throws {
            let json = #"{"boot":"\#(boot)","sys":{"heap":\#(heap)}}"#
            let bloc = try JSONDecoder().decode(BlocSante.self, from: Data(json.utf8))
            s.ajouter(.etatSante(bloc), date: t0.addingTimeInterval(dt))
        }
        try sante("AAAA0001", 100, 0)
        try sante("AAAA0001", 90, 2)
        try sante("BBBB0002", 110, 10)
        try sante("BBBB0002", 105, 12)
        try sante("CCCC0003", 120, 20)
        #expect(s.redemarrages == [t0.addingTimeInterval(10), t0.addingTimeInterval(20)])
        #expect(SeriesCourbes().redemarrages.isEmpty)
    }
}

@Suite("Etat de session des ponts", .serialized)
@MainActor
struct EtatSessionTests {
    @Test func libelles() {
        #expect(EtatSessionPont.aucune.libelle == "pas de session")
        #expect(EtatSessionPont.ouverte.libelle == "session ouverte")
        #expect(EtatSessionPont.enCours.libelle == "session en cours d'ouverture")
        #expect(EtatSessionPont.refusee("pas de route IPv6").libelle == "session refusée : pas de route IPv6")
        #expect(AlerteReseau.sansHello.raison.contains("sessions prises"))
        #expect(AlerteReseau.transport(.reseauLocalRefuse).raison == "accès au réseau local refusé")
    }

    /// Le trousseau qui refuse la lecture n'est pas une cle absente : la cle peut y etre
    /// (app recompilee ad hoc, « Refuser » a l'invite).
    @Test func trousseauInaccessibleNestPasUneCleAbsente() {
        #expect(AlerteReseau.trousseau(.absente(PontReseauTests.nom)).raison == "clé absente de ce Mac")
        #expect(AlerteReseau.trousseau(.systeme(-25293)).raison == "trousseau inaccessible")
        #expect(EtatSessionPont.refusee(AlerteReseau.trousseau(.systeme(-25293)).raison).libelle
                == "session refusée : trousseau inaccessible")
    }

    /// La cle absente de ce Mac : le pont en garde souvent une (« Nouvelle cle... ») ;
    /// « Activer l'acces reseau... » seulement s'il n'en a pas.
    @Test func cleAbsenteDitLeBonBouton() {
        let texte = ErreurTrousseauPonts.absente(PontReseauTests.nom).description
        #expect(texte.contains("puis « Nouvelle clé… » (« Activer l'accès réseau… » si le pont n'a pas de clé)"))
    }

    @Test func cleAbsenteEstUneSessionRefusee() throws {
        let (pont, _) = try PontReseauTests.pont(cle: nil)
        defer { pont.deconnecter() }
        #expect(pont.etatSession(pour: PontReseauTests.nom) == .aucune)
        pont.connecter(.reseau(nom: PontReseauTests.nom))
        #expect(pont.etatSession(pour: PontReseauTests.nom) == .refusee("clé absente de ce Mac"))
        #expect(pont.etatSession(pour: "0000000000000000") == .aucune, "un autre pont n'est pas la source")
    }

    @Test func sessionOuvertePuisFermee() async throws {
        let (pont, _) = try PontReseauTests.pont()
        defer { pont.deconnecter() }
        let f = TransportFactice(hote: PontReseauTests.nom + ".local")
        pont.fabriqueReseau = { _, _ in f }
        pont.connecter(.reseau(nom: PontReseauTests.nom))
        #expect(pont.etatSession(pour: PontReseauTests.nom) == .enCours)
        try await PontReseauTests.repondreAuJson1(f)
        #expect(await attendre { pont.phase == .connecte })
        #expect(pont.etatSession(pour: PontReseauTests.nom) == .ouverte)
        #expect(pont.etatSession(pour: "0000000000000000") == .aucune)
        pont.deconnecter()
        #expect(pont.etatSession(pour: PontReseauTests.nom) == .aucune)
    }
}

@Suite("Acces reseau Thread : textes", .serialized)
@MainActor
struct AccesReseauTextesTests {
    /// Relecture M6 : un pont connecte par l'USB sans nom SRP n'est pas « pas de pont ».
    @Test func sansAccesReseauDistingueLesCas() {
        let sansPont = Pont.texteSansAccesReseau(parUSB: false, udpAnnonce: true, ipRecu: true, srpConnu: true)
        #expect(sansPont.hasPrefix("Brancher le pont en USB"))
        let sansSrp = Pont.texteSansAccesReseau(parUSB: true, udpAnnonce: true, ipRecu: true, srpConnu: false)
        #expect(sansSrp.hasPrefix("Pont connecté par l'USB, nom SRP inconnu : le pont doit d'abord rejoindre le réseau Thread (être dans Maison)"))
        #expect(!sansSrp.contains("Brancher"))
        #expect(Pont.texteSansAccesReseau(parUSB: true, udpAnnonce: false, ipRecu: false, srpConnu: false).contains("capacité udp absente"))
        #expect(Pont.texteSansAccesReseau(parUSB: true, udpAnnonce: true, ipRecu: false, srpConnu: false).contains("bloc ip attendu"))
    }

    /// Le pont simule (USB) annonce son nom SRP : la section gere la cle, aucun de ces textes.
    @Test func demoAvecUnNomSRP() async throws {
        let p = pontDemo()
        defer { p.deconnecter() }
        #expect(await connecte(p))
        #expect(await attendre { p.etat.ip != nil })
        #expect(p.accesReseau != .inconnu)
    }

    /// Relecture M4 : sans cle, rien ne tombe ; le texte de « Nouvelle cle... » ne change pas.
    @Test func confirmationsDeLaCle() {
        let sans = AccesReseau.texteConfirmation(sansCle: true)
        #expect(sans == "Le pont crée sa clé et ouvre le port 5480 ; la clé est rangée dans le trousseau de ce Mac.")
        #expect(!sans.contains("tombent"))
        #expect(AccesReseau.texteConfirmation(sansCle: false).hasPrefix("Le pont remplace sa clé : les sessions réseau en cours tombent"))
    }
}

@Suite("Flux des trames a distance", .serialized)
@MainActor
struct FluxTramesDistantTests {
    /// Le pont coupe `json trames 1` seul 60 s apres la demande, sans le dire : l'app le
    /// deduit de l'horloge, un nouveau `json trames 1` repart pour 60 s, et un `hello` qui
    /// dit `trames` faux ramene l'etat a coupe.
    @Test func coupureAu60sEtRelance() async throws {
        let (pont, _) = try PontReseauTests.pont()
        defer { pont.deconnecter() }
        let f = TransportFactice(hote: PontReseauTests.nom + ".local")
        pont.fabriqueReseau = { _, _ in f }
        pont.connecter(.reseau(nom: PontReseauTests.nom))
        try await PontReseauTests.repondreAuJson1(f)
        #expect(await attendre { pont.phase == .connecte })
        #expect(!pont.tramesActives)
        #expect(!pont.tramesCoupeesParLePont())
        #expect(pont.secondesAvantCoupureDesTrames() == nil)

        pont.activerTrames(true)
        try #require(await attendre { f.numero(de: "json trames 1") != nil })
        let n = try #require(f.numero(de: "json trames 1"))
        f.injecter(#"{"v":1,"t":"reponse","n":3,"ms":901000,"id":\#(n),"etape":"fin","cmd":"json trames 1","ok":true,"code":"ok","duree_ms":1}"#)
        try #require(await attendre { pont.tramesActives })
        let demande = try #require(pont.tramesDemandeesLe)
        #expect(!pont.tramesCoupeesParLePont(a: demande.addingTimeInterval(59)))
        #expect(pont.secondesAvantCoupureDesTrames(a: demande.addingTimeInterval(20)) == 40)
        #expect(pont.tramesCoupeesParLePont(a: demande.addingTimeInterval(60)))
        #expect(pont.secondesAvantCoupureDesTrames(a: demande.addingTimeInterval(61)) == nil, "deja coupe")

        // « Relancer » : un nouveau json trames 1 repart pour 60 s.
        try await Task.sleep(for: .milliseconds(10))
        pont.activerTrames(true)
        let relance = try #require(pont.tramesDemandeesLe)
        #expect(relance > demande)
        #expect(!pont.tramesCoupeesParLePont(a: relance.addingTimeInterval(30)))

        // Un hello qui dit `trames` faux : le flux n'est plus demande.
        f.injecter(#"{"v":1,"t":"hello","n":4,"ms":960000,"bloc":"base","rev":1,"fw":"0.1.0-d569f01","boot":"3FA2C901","up_s":960,"session":{"transport":"udp","periode_ms":2000,"lampes_ms":30000,"compteurs_ms":0,"reseau_ms":30000,"bail_s":60,"log":false,"trames":false}}"#)
        #expect(await attendre { !pont.tramesActives })
        #expect(!pont.tramesCoupeesParLePont(a: relance.addingTimeInterval(500)), "plus rien a couper")
    }

    @Test func parLUsbLeFluxNeSeCoupePas() async throws {
        let p = pontDemo()
        defer { p.deconnecter() }
        #expect(await connecte(p))
        p.activerTrames(true)
        #expect(await attendre { p.tramesActives })
        #expect(p.tramesDemandeesLe != nil)
        #expect(!p.tramesCoupeesParLePont(a: .distantFuture))
        #expect(p.secondesAvantCoupureDesTrames() == nil)
    }
}

@Suite("Trames du pont simule", .serialized)
@MainActor
struct TramesDeLaDemoTests {
    /// Rien sans `json trames 1` ; avec : la demande d'etat au groupe, l'ordre vers la
    /// lampe, l'etat qu'elle renvoie ; plus rien apres `json trames 0`.
    @Test func ordreDemandeEtEtat() async throws {
        let p = pontDemo()
        defer { p.deconnecter() }
        #expect(await connecte(p))
        #expect(!p.tramesActives)
        #expect(p.trames.elements.isEmpty)
        p.activerTrames(true)
        #expect(await attendre { p.tramesActives })
        #expect(await attendre { p.trames.elements.contains { $0.trame.quoi == .demande && $0.trame.lampe == nil } },
                "relecture periodique : demande au groupe")
        #expect(await attendre { p.trames.elements.contains { $0.trame.sens == .rx && $0.trame.quoi == .etat } })

        p.allumer(lampe: 1, false)
        #expect(await attendre {
            p.trames.elements.contains { $0.trame == Trame(sens: .tx, quoi: .ordre, lampe: 1, marche: false, intensite: nil, essai: 1, sautes: 0) }
        })
        #expect(await attendre {
            p.trames.elements.contains { $0.trame == Trame(sens: .rx, quoi: .etat, lampe: 1, marche: false, intensite: 500, sautes: 0) }
        }, "la lampe renvoie son etat, coherent avec l'ordre")
        #expect(await attendre { p.lampes[0].dernierOrdre?.issue == .confirme })

        // L'ordre precede l'etat qui le confirme.
        let ordre = try #require(p.trames.elements.firstIndex { $0.trame.quoi == .ordre && $0.trame.lampe == 1 })
        let etat = try #require(p.trames.elements.lastIndex { $0.trame.quoi == .etat && $0.trame.lampe == 1 && $0.trame.marche == false })
        #expect(ordre < etat)
        #expect(Interpretation.trame(p.trames.elements[ordre].trame) == "→ lampe 1 : ordre éteinte (essai 1)")

        // `lampe 2 releve` : demande, puis l'etat de cette lampe seulement.
        let avant = p.trames.elements.count
        p.relire(lampe: 2)
        #expect(await attendre { p.trames.elements.dropFirst(avant).contains { $0.trame.sens == .rx && $0.trame.lampe == 2 } })

        // Plus de flux apres json trames 0 : un ordre de plus, aucune trame de plus.
        p.activerTrames(false)
        #expect(await attendre { !p.tramesActives })
        let figees = p.trames.elements.count
        p.allumer(lampe: 1, true)
        #expect(await attendre { p.lampes[0].dernierOrdre?.issue == .confirme && p.lampes[0].etat?.lue?.marche == true })
        #expect(p.trames.elements.count == figees)
    }

    /// Un ordre « deja tenu » n'envoie rien a la lampe : aucune trame.
    @Test func ordreDejaTenuSansTrame() async throws {
        let p = pontDemo()
        defer { p.deconnecter() }
        #expect(await connecte(p))
        p.activerTrames(true)
        #expect(await attendre { p.tramesActives })
        p.allumer(lampe: 2, false)  // deja eteinte
        #expect(await attendre { p.suivis.last?.etat == .tenue })
        #expect(!p.trames.elements.contains { $0.trame.quoi == .ordre })
    }

    /// Lampe jamais entendue : l'ordre part aux essais 1, 2 et 3, puis l'abandon. Temps
    /// reel (la lampe ne repond qu'apres 15 s simulees).
    @Test func ordreSansReponseTroisEssais() async throws {
        let p = Pont(trousseau: TrousseauMemoire(), trousseauDemo: TrousseauMemoire(ReseauDemo.reseau),
                     trousseauPonts: TrousseauPontsMemoire(), trousseauPontsDemo: TrousseauPontsMemoire(),
                     preferences: UserDefaults(suiteName: "amaran.tests.\(UUID().uuidString)")!)
        p.vitesseDemo = 1
        p.connecter(.demo)
        defer { p.deconnecter() }
        #expect(await connecte(p))
        p.activerTrames(true)
        #expect(await attendre { p.tramesActives })
        p.allumer(lampe: 3, true)
        #expect(await attendre(.seconds(20)) { p.lampes[2].dernierOrdre?.issue == .abandon })
        let essais = p.trames.elements.filter { $0.trame.quoi == .ordre && $0.trame.lampe == 3 }.map(\.trame.essai)
        #expect(essais == [1, 2, 3])
        #expect(!p.trames.elements.contains { $0.trame.sens == .rx && $0.trame.lampe == 3 }, "la lampe ne repond pas")
    }
}

/// Tests de fumee : monter la vue ne plante pas. Chaque vue est hebergee dans une fenetre
/// hors ecran et mise en page, avec les donnees du pont simule, d'une session distante ou
/// sans rien recu (ni bloc `ip`, ni trame, ni point manquant ne doit l'arreter). Ils ne
/// verifient rien du contenu ni du dessin : la taille d'une vue cadree est toujours celle
/// du cadre, et `ImageRenderer` ne sait pas rendre les tables d'AppKit.
@Suite("Fumee : monter les vues ne plante pas", .serialized)
@MainActor
struct FumeeVuesTests {
    /// Monter la vue ne plante pas : fenetre hors ecran, mise en page forcee.
    private func monter<V: View>(_ vue: V, _ pont: Pont) {
        let h = NSHostingView(rootView: vue.environment(pont).frame(width: 900, height: 700))
        let fenetre = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled], backing: .buffered, defer: true)
        fenetre.contentView = h
        h.layoutSubtreeIfNeeded()
        fenetre.contentView = nil
    }

    @Test func monterGraphiquesNePlantePas() async throws {
        let p = pontDemo()
        defer { p.deconnecter() }
        try #require(await connecte(p))
        p.allumer(lampe: 1, false)
        try #require(await attendre { !p.courbes.tas.isEmpty && !p.courbes.ordres.isEmpty })
        monter(Graphiques(), p)
    }

    @Test func monterTramesNePlantePas() async throws {
        let p = pontDemo()
        defer { p.deconnecter() }
        try #require(await connecte(p))
        p.activerTrames(true)
        try #require(await attendre { p.trames.elements.contains { $0.trame.quoi == .etat } })
        monter(Trames(), p)
    }

    @Test func monterTableauEtReglagesNePlantePas() async throws {
        let p = pontDemo()
        defer { p.deconnecter() }
        try #require(await connecte(p))
        try #require(await attendre { p.etat.ip?.valeur.srp == SimulateurDemo.srpDemo })
        monter(TableauDeBord(), p)
        monter(ReglagesAccesReseau(), p)
        monter(FenetreReglages(), p)
    }

    /// Session distante : compteurs non releves, pont hors service sans codes d'appairage
    /// (`code_manuel` et `qr` a null a distance).
    @Test func monterLesVuesADistanceNePlantePas() async throws {
        let (p, _) = try PontReseauTests.pont()
        defer { p.deconnecter() }
        let f = TransportFactice(hote: PontReseauTests.nom + ".local")
        p.fabriqueReseau = { _, _ in f }
        p.connecter(.reseau(nom: PontReseauTests.nom))
        try await PontReseauTests.repondreAuJson1(f)
        try #require(await attendre { p.phase == .connecte })
        f.injecter(#"{"v":1,"t":"reseau","n":3,"ms":900200,"bloc":"matter","demarre":true,"fabriques":0,"ble":false,"identifie":false,"abonnements":{"demandes":0,"plafonnes":0,"etablis":0,"termines":0,"plafond_s":20},"code_manuel":null,"qr":null}"#)
        try #require(await attendre { p.etat.enService == false })
        monter(TableauDeBord(), p)
        monter(Graphiques(), p)
        monter(ReglagesAccesReseau(), p)
    }

    @Test func monterSansRienRecuNePlantePas() throws {
        let (p, _) = try PontReseauTests.pont()
        monter(Graphiques(), p)
        monter(Trames(), p)
        monter(ReglagesAccesReseau(), p)
        monter(ContenuPrincipal(), p)
    }
}
