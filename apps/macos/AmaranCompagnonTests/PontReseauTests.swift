// Repris de Halo Compagnon (commit e114cd5, PontReseauTests.swift) : la source reseau du
// modele (docs/PROTOCOLE-JSON.md 10). Un transport factice joue le pont joint par Thread
// (lignes de 10.6) ; la creation de cle passe par le pont simule du mode demo. Nom SRP,
// MAC, adresses et cles inventes ; trousseaux en memoire.
import AmaranProtocole
import Foundation
import Synchronization
import Testing
@testable import AmaranCompagnon

/// Transport factice d'une source reseau : garde les lignes envoyees, rend les lignes
/// injectees comme `TransportUDP` les rendrait (RS + JSON + LF). Chaque ouverture est
/// une nouvelle session.
final class TransportFactice: Transport {
    let genre: GenreTransport = .udp
    let nom: String
    private struct Etat {
        var suite: AsyncStream<EvenementTransport>.Continuation?
        var envoyees: [String] = []
        var ouvertures = 0
        var cles: [Data] = []
    }
    private let etat = Mutex(Etat())

    init(hote: String) { nom = hote }

    var envoyees: [String] { etat.withLock { $0.envoyees } }
    var ouvertures: Int { etat.withLock { $0.ouvertures } }
    var cles: [Data] { etat.withLock { $0.cles } }

    func noterCle(_ cle: Data) { etat.withLock { $0.cles.append(cle) } }

    func ouvrir() async throws -> AsyncStream<EvenementTransport> {
        let (flux, suite) = AsyncStream.makeStream(of: EvenementTransport.self, bufferingPolicy: .unbounded)
        etat.withLock { e in
            e.suite = suite
            e.ouvertures += 1
        }
        return flux
    }

    func envoyer(_ donnees: Data) throws {
        let lignes = String(decoding: donnees, as: UTF8.self).split(separator: "\n").map(String.init)
        etat.withLock { $0.envoyees += lignes }
    }

    func fermer() {
        let suite = etat.withLock { e -> AsyncStream<EvenementTransport>.Continuation? in
            let s = e.suite
            e.suite = nil
            return s
        }
        suite?.yield(.ferme(raison: "session réseau fermée par l'app"))
        suite?.finish()
    }

    /// Une ligne du pont.
    func injecter(_ json: String) {
        _ = etat.withLock { $0.suite?.yield(.donnees(Data(("\u{1E}" + json + "\n").utf8))) }
    }

    /// Numero de la derniere ligne envoyee qui contient `texte`.
    func numero(de texte: String) -> Int? {
        guard let l = envoyees.last(where: { $0.contains(texte) }), l.hasPrefix("id="),
              let espace = l.firstIndex(of: " ") else { return nil }
        return Int(l[l.index(l.startIndex, offsetBy: 3)..<espace])
    }
}

@Suite("Source reseau du modele", .serialized, .langue(.francais))
@MainActor
struct PontReseauTests {
    static let nom = "1A2B3C4D5E6F7081"
    static let cle = Data((0..<32).map { 0x40 &+ UInt8($0) })
    /// Nom SRP du pont simule du mode demo : jamais 16 hexa.
    static let nomDemo = SimulateurDemo.srpDemo

    /// Thread Route y est dans l'etat `route` (actif par defaut) : jamais l'etat reel du Mac.
    static func pont(cle: Data? = PontReseauTests.cle, trousseauPontsDemo: TrousseauPontsMemoire = TrousseauPontsMemoire(),
                     preferences: UserDefaults? = nil, route: EtatThreadRoute = .actif) throws -> (Pont, TrousseauPontsMemoire) {
        let t = TrousseauPontsMemoire()
        if let cle { try t.ranger(nom: nom, cle: cle, empreinte: H1.kid(cle: cle)) }
        let p = Pont(trousseau: TrousseauMemoire(), trousseauDemo: TrousseauMemoire(ReseauDemo.reseau),
                     trousseauPonts: t, trousseauPontsDemo: trousseauPontsDemo,
                     preferences: preferences ?? UserDefaults(suiteName: "amaran.tests.\(UUID().uuidString)")!,
                     etatThreadRoute: { route })
        p.vitesseDemo = 20
        return (p, t)
    }

    /// Le pont factice repond au json 1 comme un pont joint par Thread (10.6).
    static func repondreAuJson1(_ f: TransportFactice, boot: String = "3FA2C901") async throws {
        try #require(await attendre { f.numero(de: "json 1") != nil })
        let n = try #require(f.numero(de: "json 1"))
        f.injecter(#"{"v":1,"t":"hello","n":0,"ms":900120,"bloc":"base","rev":1,"fw":"0.1.0-d569f01","date":"Oct  5 2026","heure":"14:02:11","idf":"v5.5.4","puce":"esp32c6","boot":"\#(boot)","reset":"logiciel","reset_n":3,"up_s":900,"session":{"transport":"udp","periode_ms":2000,"lampes_ms":30000,"compteurs_ms":0,"reseau_ms":30000,"bail_s":60,"log":false,"trames":false},"limites":{"ligne_max":1024,"cmd_max":127}}"#)
        f.injecter(#"{"v":1,"t":"hello","n":1,"ms":900121,"bloc":"identite","boot":"\#(boot)","mac":"02000000DE01","id":{"fabricant":"TEST_VENDOR","produit":"TEST_PRODUCT","serie":"AMARAN-02000000DE01","nom":"Pont amaran"},"caps":["matter","thread","mesh","catalogue","ordres","led","log","trames","udp","cle","texte"]}"#)
        f.injecter(#"{"v":1,"t":"reponse","n":2,"ms":900130,"id":\#(n),"etape":"fin","cmd":"json 1 bail 60","ok":true,"code":"ok","duree_ms":10,"bail_s":60,"up_s":900}"#)
    }

    /// Ouverture par le reseau : cle lue dans le trousseau des ponts, hote `<nom>.local`,
    /// session distante (json 1 avec un bail, sans Ctrl-U, politique reseau), repertoire,
    /// liste blanche de la console, texte d'une commande, trames.
    @Test func ouvertureParLeReseau() async throws {
        let (pont, _) = try Self.pont()
        defer { pont.deconnecter() }
        var hotes: [String] = []
        let f = TransportFactice(hote: Self.nom + ".local")
        pont.fabriqueReseau = { hote, cle in
            hotes.append(hote)
            f.noterCle(cle)
            return f
        }
        pont.connecter(.reseau(nom: Self.nom))
        try await Self.repondreAuJson1(f)
        #expect(hotes == ["1A2B3C4D5E6F7081.local"])
        #expect(f.cles == [Self.cle], "la cle du trousseau des ponts ouvre la session")
        #expect(f.envoyees.first?.hasSuffix(" json 1 bail 60") == true)
        #expect(!f.envoyees.contains { $0.contains("\u{15}") }, "pas de Ctrl-U a distance")
        #expect(await attendre { pont.phase == .connecte })
        #expect(pont.aDistance)
        #expect(pont.moteur.genre == .udp)
        #expect(pont.moteur.correlateur.politique == .reseau)
        // La premiere ligne recue (le hello) n'est pas jetee comme a l'ouverture d'un port.
        #expect(pont.etat.helloBase?.valeur.rev == 1)
        #expect(pont.reglages?.transport == .udp)
        #expect(f.envoyees.filter { $0.contains("json 1") }.count == 1, "hello recu du premier coup : pas de renvoi")
        #expect(pont.console.elements.contains { $0.texte == "Session réseau ouverte : 1A2B3C4D5E6F7081.local." })
        #expect(pont.accesReseau == .inconnu, "l'acces reseau ne se gere que par l'USB")

        // Le bloc ip d'un vrai pont : le repertoire le retient, et titre la source.
        f.injecter(#"{"v":1,"t":"reseau","n":3,"ms":900200,"bloc":"ip","srp":"1A2B3C4D5E6F7081","adresses":[{"type":"omr","adresse":"fd12:34:5678:0:aaaa:bbbb:ccc:dddd"}],"udp":{"port":5480,"cle":true,"empreinte":"\#(H1.kid(cle: Self.cle))","ouvert":true,"sessions":1,"recus":4,"emis":9,"rejets":0,"perdus":0}}"#)
        #expect(await attendre { pont.etat.srp == Self.nom })
        #expect(pont.titre(reseau: Self.nom) == "AMARAN · 02:00:00:00:DE:01", "titre de la carte : modele puis MAC")
        #expect(pont.titre(reseau: "0000000000000000") == "0000000000000000.local", "pont inconnu : son nom SRP")
        let garde = try #require(pont.preferences.data(forKey: RepertoirePonts.cleReglages))
        #expect(RepertoirePonts(donnees: garde)?.mac(pourSrp: Self.nom) == "02000000DE01")

        // Compteurs : le profil distant les coupe ; l'IV Index vient alors de config mesh.
        #expect(pont.etatCompteursMesh == .nonReleves)
        #expect(pont.ivIndexMesh == nil)
        f.injecter(#"{"v":1,"t":"config","n":4,"ms":900210,"bloc":"mesh","cles":true,"empreintes":{"reseau":"1A2B3C4D","application":"5E6F7A8B"},"adresse":"7F38","iv_nvs":2,"balayage":{"fenetre_ms":20,"intervalle_ms":40},"lampes":2,"capacite":16,"releve_ms":2000,"groupe":"C000"}"#)
        #expect(await attendre { pont.etat.mesh != nil })
        #expect(pont.ivIndexMesh?.texte == "2 (mémoire du pont)")
        pont.activerCompteursMesh()
        #expect(f.envoyees.last?.hasSuffix(" json compteurs 5000") == true)
        // Les reglages ne suivent qu'a la reponse du pont.
        let nc = try #require(f.numero(de: "json compteurs 5000"))
        f.injecter(#"{"v":1,"t":"reponse","n":5,"ms":905000,"id":\#(nc),"etape":"fin","cmd":"json compteurs 5000","ok":true,"code":"ok","duree_ms":1}"#)
        #expect(await attendre { pont.etatCompteursMesh == .demandes })
        f.injecter(#"{"v":1,"t":"compteurs","n":6,"ms":905612,"bloc":"mesh","annonces":5120,"nid_reconnu":1630,"nid_inconnu":3402,"netmic_faux":0,"emis":64,"echecs_emission":0,"iv":3,"seq":1093,"plancher":1024}"#)
        #expect(await attendre { pont.etat.compteurs != nil })
        #expect(pont.etatCompteursMesh == .normal)
        #expect(pont.ivIndexMesh?.texte == "3", "les compteurs priment sur iv_nvs")

        // Liste blanche : une commande refusee n'est jamais envoyee, la console le dit.
        let avant = f.envoyees.count
        guard case .refusee(let raison) = pont.console("redemarre") else {
            Issue.record("redemarre doit etre refusee a distance")
            return
        }
        #expect(raison.contains("interdite a distance"))
        // La raison du pont citee une fois, telle quelle, dans une phrase qui ne la repete pas.
        #expect(pont.console.elements.last?.texte
                == "« redemarre » n'est pas envoyée : la liste blanche du pont la refuse (« interdite a distance : USB seulement »).")
        if case .refusee = pont.console("json cle efface") {} else { Issue.record("json cle efface : USB seulement") }
        #expect(pont.envoyer("mesh releve 5") == nil)
        #expect(pont.console.elements.last?.texte
                == "« mesh releve 5 » n'est pas envoyée : la liste blanche du pont la refuse (« interdite a distance : USB seulement »).")
        #expect(!pont.peutEnvoyer("mesh releve 5"))
        #expect(pont.peutEnvoyer("lampe 1 on"))
        // Une commande permise qui demande une confirmation la garde a distance.
        if case .confirmation = pont.console("mesh lampe 1 masquer") {} else { Issue.record("confirmation attendue") }
        #expect(f.envoyees.count == avant, "rien n'est parti")
        // Une commande permise part, avec un id, et sa sortie `texte` va dans la console.
        #expect(pont.console("lampe 1") == .envoyee)
        try #require(await attendre { f.numero(de: "lampe 1") != nil })
        let n = try #require(f.numero(de: "lampe 1"))
        f.injecter(#"{"v":1,"t":"reponse","n":4,"ms":913000,"id":\#(n),"etape":"debut","cmd":"lampe 1","ok":true,"code":"en_cours"}"#)
        f.injecter(#"{"v":1,"t":"texte","n":5,"ms":913004,"id":\#(n),"txt":"lampe 1 : Lampe bureau"}"#)
        f.injecter(#"{"v":1,"t":"reponse","n":6,"ms":913006,"id":\#(n),"etape":"fin","cmd":"lampe 1","ok":true,"code":"ok","duree_ms":6}"#)
        #expect(await attendre { pont.suivis.last { $0.numero == n }?.etat == .terminee })
        #expect(pont.console.elements.contains { $0.texte == "lampe 1 : Lampe bureau" && $0.numero == n })
        #expect(pont.suivis.last { $0.numero == n }?.texte == ["lampe 1 : Lampe bureau"])

        // Trames (7.6) : journal borne.
        f.injecter(#"{"v":1,"t":"trame","n":7,"ms":95012,"sens":"tx","quoi":"ordre","lampe":1,"marche":true,"intensite":500,"essai":1,"sautes":0}"#)
        #expect(await attendre { pont.trames.elements.count == 1 })
        #expect(pont.trames.elements.first?.trame == Trame(sens: .tx, quoi: .ordre, lampe: 1, marche: true, intensite: 500, essai: 1, sautes: 0))
        #expect(pont.derniereTrame != nil)
        pont.viderTrames()
        #expect(pont.trames.elements.isEmpty)

        // A distance, jamais de creation de cle.
        let lignes = f.envoyees.count
        pont.creerCle()
        #expect(f.envoyees.count == lignes)
        #expect(pont.creationCle == nil)

        // Fermer : json 0 scelle d'abord (une place de session rendue au pont).
        pont.deconnecter()
        #expect(await attendre { f.envoyees.last?.hasSuffix(" json 0") == true })
    }

    /// Les cadences demandees a distance restent dans la liste blanche.
    @Test func cadenceADistanceDansLaListeBlanche() async throws {
        let (pont, _) = try Self.pont()
        defer { pont.deconnecter() }
        let f = TransportFactice(hote: Self.nom + ".local")
        pont.fabriqueReseau = { _, _ in f }
        pont.connecter(.reseau(nom: Self.nom))
        try await Self.repondreAuJson1(f)
        #expect(await attendre { pont.phase == .connecte })
        pont.reglerCadence(.compteurs, ms: 1000)
        #expect(await attendre { f.envoyees.last?.hasSuffix(" json compteurs 5000") == true })
    }

    /// Aucun hello a distance (places de session prises) : bandeau sansHello, note une
    /// fois, puis nouvelle poignee de main a la relance de 30 s.
    @Test func sansHelloNouvellePoigneeDeMain() async throws {
        let (pont, _) = try Self.pont()
        defer { pont.deconnecter() }
        let f = TransportFactice(hote: Self.nom + ".local")
        pont.fabriqueReseau = { _, _ in f }
        pont.connecter(.reseau(nom: Self.nom))
        try #require(await attendre { f.numero(de: "json 1") != nil })
        // Renvois du json 1 (meme id a distance), puis l'abandon.
        for d in [2.1, 4.3, 6.5, 8.7] { pont.avancerPourUnTest(de: d) }
        #expect(pont.phase == .sansReponse)
        #expect(pont.alerteReseau == .sansHello)
        #expect(pont.alerte == nil, "a distance, le bandeau est celui de la source reseau")
        let numeros = Set(f.envoyees.filter { $0.contains("json 1") }.map { $0.split(separator: " ")[0] })
        #expect(numeros.count == 1, "a distance, le json 1 renvoye garde son id : \(f.envoyees)")
        func notes() -> Int { pont.console.elements.filter { $0.texte == AlerteReseau.sansHello.texte }.count }
        #expect(notes() == 1)
        // Relance de 30 s : nouvelle poignee de main (le transport se ferme et se rouvre).
        pont.avancerPourUnTest(de: 8.7 + 30.1)
        #expect(await attendre { f.ouvertures == 2 && f.numero(de: "json 1") != nil && pont.etatTransport == .ouvert })
        #expect(pont.alerteReseau == .sansHello, "le bandeau tient jusqu'au hello")
        #expect(pont.console.elements.contains { $0.texte == MoteurSession.Note.reseauSansHello.texte })
        try await Self.repondreAuJson1(f)
        #expect(await attendre { pont.phase == .connecte })
        #expect(pont.alerteReseau == nil)
        #expect(notes() == 1)
    }

    @Test func cleAbsenteArreteSansReessayer() throws {
        let (pont, _) = try Self.pont(cle: nil)
        var ouvertures = 0
        pont.fabriqueReseau = { hote, _ in
            ouvertures += 1
            return TransportFactice(hote: hote)
        }
        pont.connecter(.reseau(nom: Self.nom))
        #expect(pont.alerteReseau == .trousseau(.absente(Self.nom)))
        if case .erreur = pont.etatTransport {} else { Issue.record("etat \(pont.etatTransport)") }
        // Chemin reseau retrouve (ou reveil) : une cle absente n'est pas une cause que le
        // reseau puisse lever seul.
        pont.reseauChange()
        #expect(pont.alerteReseau == .trousseau(.absente(Self.nom)), "cle absente : pas de reprise seule")
        if case .erreur = pont.etatTransport {} else { Issue.record("aucune reprise attendue") }
        #expect(ouvertures == 0, "aucun transport sans cle")
        pont.deconnecter()
    }

    @Test func echecAvecRepriseAutomatiqueEffaceLAlerteEtReprogramme() throws {
        let (pont, _) = try Self.pont(cle: nil, route: .absent)
        pont.connecter(.reseau(nom: Self.nom))
        // L'echec d'un essai reseau ulterieur : « pas de route » reprend seul.
        pont.echecOuverture(ErreurTransportReseau.pasDeRoute)
        #expect(pont.alerteReseau == nil, "reprise automatique : pas de bandeau d'arret")
        if case .attente = pont.etatTransport {} else { Issue.record("reprise programmee attendue : \(pont.etatTransport)") }
        #expect(pont.console.elements.contains { $0.texte.contains("tools/macos/thread-route/installer.sh") },
                "Thread Route absent : la note dit comment l'installer")
        pont.deconnecter()
    }

    @Test func echecSansRepriseAutomatiqueGardeLAlerteEtArrete() throws {
        let (pont, _) = try Self.pont(cle: nil)
        pont.connecter(.reseau(nom: Self.nom))
        // « Port injoignable » (pont sans cle) : arret net, pas de reessai seul.
        pont.echecOuverture(ErreurTransportReseau.portInjoignable)
        #expect(pont.alerteReseau == .transport(.portInjoignable))
        if case .erreur = pont.etatTransport {} else { Issue.record("arret attendu : \(pont.etatTransport)") }
        pont.reseauChange()
        if case .erreur = pont.etatTransport {} else { Issue.record("pas de reprise sur un changement du reseau") }
        pont.deconnecter()
    }

    /// Reseau local refuse : bandeau, et la reconnexion reessaie quand meme (le refus se
    /// leve dans Reglages Systeme sans evenement pour l'app).
    @Test func reseauLocalRefuseMontreLeBandeauEtReessaie() throws {
        let (pont, _) = try Self.pont(cle: nil)
        pont.connecter(.reseau(nom: Self.nom))
        pont.echecOuverture(ErreurTransportReseau.reseauLocalRefuse)
        #expect(pont.alerteReseau == .transport(.reseauLocalRefuse))
        if case .attente = pont.etatTransport {} else { Issue.record("reprise programmee attendue : \(pont.etatTransport)") }
        // Une autre cause ensuite efface le bandeau perime.
        pont.echecOuverture(ErreurTransportReseau.nomIntrouvable(Self.nom + ".local"))
        #expect(pont.alerteReseau == nil)
        pont.deconnecter()
    }

    @Test func causeReseauNoteeUneFoisTantQuElleNeChangePas() throws {
        let (pont, _) = try Self.pont(cle: nil)
        pont.connecter(.reseau(nom: Self.nom))
        func occurrences(_ sousChaine: String) -> Int {
            pont.console.elements.filter { $0.texte.contains(sousChaine) }.count
        }
        #expect(occurrences("Clé absente") == 1)
        // Reessayer sur la meme cause n'ajoute pas de ligne.
        pont.reconnecter()
        #expect(occurrences("Clé absente") == 1, "meme cause : pas de nouvelle ligne")
        // Une cause differente, elle, est notee.
        pont.echecOuverture(ErreurTransportReseau.pasDeRoute)
        #expect(occurrences("Pas de route IPv6") == 1, "cause differente : nouvelle ligne")
        pont.deconnecter()
    }

    /// « Liberer le port » sur une source reseau : rien a flasher, la note parle de session.
    @Test func libererUneSourceReseauParleDeSession() throws {
        let (pont, _) = try Self.pont(cle: nil)
        pont.connecter(.reseau(nom: Self.nom))
        pont.libererPort()
        #expect(pont.etatTransport == .libere)
        #expect(pont.alerteReseau == nil)
        #expect(pont.console.elements.last?.texte == "Session réseau fermée. « Reconnecter » pour reprendre.")
        #expect(!pont.console.elements.contains { $0.texte.contains("Flasher") })
        pont.deconnecter()
    }

    @Test func pontsConnusEtOubli() async throws {
        let (pont, t) = try Self.pont()
        #expect(pont.pontsConnus == [PontConnu(nom: Self.nom, empreinte: H1.kid(cle: Self.cle))])
        let f = TransportFactice(hote: Self.nom + ".local")
        pont.fabriqueReseau = { _, _ in f }
        pont.connecter(.reseau(nom: Self.nom))
        #expect(await attendre { f.numero(de: "json 1") != nil })
        pont.oublierPont(Self.nom)
        #expect(pont.pontsConnus.isEmpty)
        #expect(t.lister().isEmpty)
        #expect(pont.etatTransport == .ferme, "la source oubliee est deconnectee")
    }

    /// Un echec "pas de route" : le texte de la console et de l'attente suit l'etat de Thread Route du pont,
    /// jamais celui du Mac.
    @Test func echecPasDeRouteUtiliseLEtatDuPont() throws {
        for (etat, fin) in [
            (EtatThreadRoute.absent, "sh tools/macos/thread-route/installer.sh"),
            (.aApprouver, "L'autoriser dans Réglages Système, Général, Ouverture et extensions."),
            (.actif, "Thread Route est actif : la route revient d'elle-même."),
            (.ancien, "Pour le remplacer, dans le dépôt du pont Halo"),
        ] {
            let (pont, _) = try Self.pont(cle: nil, route: etat)
            pont.connecter(.reseau(nom: Self.nom))
            pont.echecOuverture(ErreurTransportReseau.pasDeRoute)
            #expect(pont.console.elements.contains { $0.texte.contains(fin) }, "console, \(etat)")
            if case .attente(_, let raison) = pont.etatTransport {
                #expect(raison.contains(fin), "etat d'attente, \(etat)")
            } else {
                Issue.record("reprise programmee attendue : \(pont.etatTransport)")
            }
            pont.deconnecter()
        }
    }

    @Test func textes() {
        #expect(AlerteReseau.textePasDeRoute(.absent).contains("tools/macos/thread-route/installer.sh"))
        #expect(AlerteReseau.textePasDeRoute(.absent).contains("github.com/Djoko-cli/benq-screenbar-halo-matter"))
        #expect(AlerteReseau.textePasDeRoute(.ancien).contains("tools/macos/thread-route/installer.sh"))
        #expect(!AlerteReseau.textePasDeRoute(.actif).contains("installer.sh"))
        #expect(AlerteReseau.textePasDeRoute(.actif).hasSuffix("Thread Route est actif : la route revient d'elle-même."))
        #expect(!AlerteReseau.textePasDeRoute(.aApprouver).contains("installer.sh"))
        #expect(AlerteReseau.sansHello.texte.contains("30 s"))
        #expect(Pont.texteSansReponse(.reseau) == "sans réponse sous 6 s (2 renvois du même id)")
        #expect(Pont.texteSansReponse(.reseau, commande: "json etat") == "sans réponse sous 12 s (2 renvois du même id)",
                "la fin de json etat suit l'instantane")
        #expect(Pont.texteSansReponse(.usb) == "sans réponse sous 3 s (pas de réémission)")
        #expect(Pont.texteSansReponse(.usb, commande: "json etat") == "sans réponse sous 3 s (pas de réémission)")
    }

    /// Creation de la cle par l'USB (ici le pont simule) : rangee dans le trousseau isole
    /// de la demo, jamais dans le vrai ; la cle ne traine nulle part.
    @Test func creerLaCleParLUSB() async throws {
        let demo = TrousseauPontsMemoire()
        let (pont, reel) = try Self.pont(cle: nil, trousseauPontsDemo: demo)
        defer { pont.deconnecter() }
        pont.connecter(.demo)
        try #require(await attendre { pont.phase == .connecte && pont.accesReseau != .inconnu })
        #expect(pont.accesReseau == .sansCle(nom: Self.nomDemo))
        #expect(pont.repertoire == RepertoirePonts(), "le repertoire ne note jamais la demo")
        pont.creerCle()
        #expect(pont.creationCleEnCours)
        try #require(await attendre { !demo.lister().isEmpty })
        let connu = try #require(demo.lister().first)
        #expect(connu.nom == Self.nomDemo)
        let cle = try demo.lire(nom: connu.nom)
        #expect(H1.kid(cle: cle) == connu.empreinte)
        // Isolation de la demo : jamais dans le vrai trousseau, jamais dans pontsConnus.
        #expect(reel.lister().isEmpty, "le trousseau reel n'est jamais touche par la demo")
        #expect(pont.pontsConnus.isEmpty, "pontsConnus ne suit que le trousseau reel")
        // Ni la cle ni l'alea ne trainent : console, suivis, rejets.
        let hexa = H1.hexa(cle)
        func longHexa(_ s: String) -> Bool { s.contains(/[0-9A-Fa-f]{32,}/) }
        #expect(!pont.console.elements.contains { $0.texte.contains(hexa) || longHexa($0.texte) })
        #expect(pont.console.elements.contains { $0.texte.hasSuffix("json cle nouvelle ••••••••") }, "ligne envoyee masquee")
        #expect(!pont.suivis.contains { $0.fin?.cle != nil || longHexa($0.commande) })
        #expect(!pont.rejets.elements.contains { $0.brut.contains(hexa) })
        #expect(await attendre { pont.accesReseau == .cleConnue(nom: connu.nom, empreinte: connu.empreinte) })
        #expect(!pont.creationCleEnCours)
    }

    /// Une reconnexion ne laisse jamais une creation de cle perimee bloquer le prochain essai.
    @Test func laCreationDeCleReprendApresUneReconnexion() async throws {
        let demo = TrousseauPontsMemoire()
        let (pont, _) = try Self.pont(cle: nil, trousseauPontsDemo: demo)
        defer { pont.deconnecter() }
        pont.connecter(.demo)
        try #require(await attendre { pont.phase == .connecte && pont.accesReseau != .inconnu })
        pont.creerCle()
        pont.deconnecter()
        pont.connecter(.demo)
        // La reconnexion a coupe l'ancien essai : signale, pas bloque en silence.
        #expect(pont.console.elements.contains { $0.genre == .note(grave: true) && $0.texte.contains("interrompue") })
        try #require(await attendre { pont.phase == .connecte && pont.accesReseau != .inconnu })
        pont.creerCle()
        try #require(await attendre { !demo.lister().isEmpty })
        #expect(demo.lister().first?.nom == Self.nomDemo)
    }

    /// Un suivi de creation termine sans reponse ne bloque pas un second essai.
    @Test func laCreationDeCleReprendApresUnSuiviTermineSansReponse() async throws {
        let demo = TrousseauPontsMemoire()
        let (pont, _) = try Self.pont(cle: nil, trousseauPontsDemo: demo)
        defer { pont.deconnecter() }
        pont.connecter(.demo)
        try #require(await attendre { pont.phase == .connecte && pont.accesReseau != .inconnu })
        func demandes() -> Int {
            pont.console.elements.filter { $0.texte.contains("Nouvelle clé réseau demandée") }.count
        }
        pont.creerCle()
        #expect(demandes() == 1)
        pont.creerCle()
        #expect(demandes() == 1, "un essai en vol bloque le suivant")
        // Meme acteur, aucun `await` : la reponse simulee ne peut pas arriver avant.
        pont.avancerPourUnTest(de: 0.1)
        pont.avancerPourUnTest(de: 3.5)
        #expect(pont.console.elements.contains { $0.texte.contains("Pas encore de réponse à la création de clé") })
        pont.creerCle()
        #expect(demandes() == 2, "le suivi du premier essai est termine : un second essai part")
        try #require(await attendre { !demo.lister().isEmpty })
        #expect(demo.lister().first?.nom == Self.nomDemo)
    }

    /// En demo, le repertoire n'apprend rien et les vraies preferences ne bougent pas.
    @Test func laDemoNeNotePasLeRepertoire() async throws {
        let (pont, _) = try Self.pont(cle: nil)
        defer { pont.deconnecter() }
        pont.connecter(.demo)
        try #require(await attendre { pont.phase == .connecte && pont.etat.srp != nil })
        #expect(pont.repertoire.parMac.isEmpty)
        #expect(pont.preferences.data(forKey: RepertoirePonts.cleReglages) == nil)
        #expect(pont.etat.ip?.valeur.adresseOmr == "fd12:34:5678:0:aaaa:bbbb:ccc:dddd")
    }

    /// Titres des sources reseau comme Halo Compagnon : "MODELE · MAC" quand le repertoire connait
    /// la carte ; sinon « Pont amaran » dans les listes et `<nom>.local` pour la source choisie.
    @Test func titreDeLaSourceReseau() throws {
        let autre = "9F8E7D6C5B4A3921"
        let (pont, trousseau) = try Self.pont()
        let inconnu = PontConnu(nom: Self.nom, empreinte: "?")
        #expect(pont.titre(pont: inconnu) == "Pont amaran")
        #expect(pont.titre(reseau: Self.nom) == "\(Self.nom).local")
        // Un second pont dans le trousseau ne change rien : pas de discriminant.
        try trousseau.ranger(nom: autre, cle: Self.cle, empreinte: H1.kid(cle: Self.cle))
        pont.relirePontsConnus()
        #expect(pont.titre(pont: PontConnu(nom: autre, empreinte: "?")) == "Pont amaran")
        // MAC connue du repertoire, modele pas encore appris : ESP32.
        pont.repertoire.noter(mac: "02000000DE01", serie: nil, srp: Self.nom)
        #expect(pont.titre(reseau: Self.nom) == "ESP32 · 02:00:00:00:DE:01")
        // Modele appris au hello : AMARAN, dans la liste comme pour la source choisie.
        pont.repertoire.noter(mac: "02000000DE01", serie: "AMARAN-02000000DE01", srp: Self.nom)
        #expect(pont.titre(reseau: Self.nom) == "AMARAN · 02:00:00:00:DE:01")
        #expect(pont.titre(pont: inconnu) == "AMARAN · 02:00:00:00:DE:01")
        #expect(pont.titre(reseau: autre) == "\(autre).local")
    }

    /// Changer de source dit ce qui est fait : la console garde ses lignes (comme Halo).
    @Test func changementDeSourceGardeLaConsole() async throws {
        let (pont, _) = try Self.pont()
        defer { pont.deconnecter() }
        pont.connecter(.demo)
        #expect(await attendre { !pont.console.elements.isEmpty })
        let avant = pont.console.elements.count
        pont.connecter(.reseau(nom: Self.nom))
        let notes = pont.console.elements.filter { $0.texte.hasPrefix("Nouvelle source") }
        #expect(notes.last?.texte.contains("la console garde ses lignes") == true)
        #expect(notes.last?.texte.contains("console remis") == false)
        #expect(pont.console.elements.count >= avant, "aucune ligne de la source precedente n'est effacee")
    }

    /// « Oublier… » refuse par le trousseau (element cree par une autre signature, « Refuser »
    /// a l'invite) : la cle reste, la console dit l'erreur, rien n'est note comme oublie, et
    /// la session continue.
    @Test func oublierQuiEchoueNeDeconnectePas() async throws {
        let t = TrousseauPontsRefus()
        try t.ranger(nom: Self.nom, cle: Self.cle, empreinte: H1.kid(cle: Self.cle))
        let pont = Pont(trousseau: TrousseauMemoire(), trousseauDemo: TrousseauMemoire(ReseauDemo.reseau),
                        trousseauPonts: t, trousseauPontsDemo: TrousseauPontsMemoire(),
                        preferences: UserDefaults(suiteName: "amaran.tests.\(UUID().uuidString)")!)
        pont.vitesseDemo = 20
        defer { pont.deconnecter() }
        let f = TransportFactice(hote: Self.nom + ".local")
        pont.fabriqueReseau = { _, _ in f }
        pont.connecter(.reseau(nom: Self.nom))
        try await Self.repondreAuJson1(f)
        #expect(await attendre { pont.phase == .connecte })
        pont.oublierPont(Self.nom)
        #expect(pont.pontsConnus.map(\.nom) == [Self.nom], "la cle est toujours la")
        #expect(pont.console.elements.contains { $0.genre == .note(grave: true) && $0.texte.hasPrefix("Clé du pont \(Self.nom).local non oubliée : Trousseau") })
        #expect(!pont.console.elements.contains { $0.texte.contains("oubliée par ce Mac") })
        #expect(pont.etatTransport == .ouvert && pont.phase == .connecte, "la session continue")
    }

    /// Relecture M1 : compteurs actives, blocs recus, puis la session tombe et se rouvre. Le
    /// `json 1` de la nouvelle session remet `compteurs_ms` a 0 : l'ancien bloc n'est plus
    /// releve. La carte et les graphiques disent « non releves » (avec l'heure du dernier
    /// releve), jamais les compteurs figes comme actuels ; l'IV Index vient de la memoire
    /// du pont. Activer de nouveau : « demandes », puis le premier bloc du releve.
    @Test func compteursFigesApresReconnexion() async throws {
        let (pont, _) = try Self.pont()
        defer { pont.deconnecter() }
        let f = TransportFactice(hote: Self.nom + ".local")
        pont.fabriqueReseau = { _, _ in f }
        pont.connecter(.reseau(nom: Self.nom))
        try await Self.repondreAuJson1(f)
        #expect(await attendre { pont.phase == .connecte })
        f.injecter(#"{"v":1,"t":"config","n":4,"ms":900210,"bloc":"mesh","cles":true,"empreintes":{"reseau":"1A2B3C4D","application":"5E6F7A8B"},"adresse":"7F38","iv_nvs":2,"balayage":{"fenetre_ms":20,"intervalle_ms":40},"lampes":2,"capacite":16,"releve_ms":2000,"groupe":"C000"}"#)
        #expect(await attendre { pont.etat.mesh != nil })
        #expect(pont.etatCompteursMesh == .nonReleves)
        #expect(pont.texteCompteursMesh == "Compteurs du Mesh non relevés à distance", "rien de releve encore : pas d'heure")

        func activer(_ n: Int) async throws {
            pont.activerCompteursMesh()
            try #require(await attendre { f.envoyees.filter { $0.hasSuffix(" json compteurs 5000") }.count == n })
            let nc = try #require(f.numero(de: "json compteurs 5000"))
            f.injecter(#"{"v":1,"t":"reponse","n":5,"ms":905000,"id":\#(nc),"etape":"fin","cmd":"json compteurs 5000","ok":true,"code":"ok","duree_ms":1}"#)
            try #require(await attendre { pont.reglages?.compteursMs == 5000 })
        }
        try await activer(1)
        #expect(pont.etatCompteursMesh == .demandes)
        f.injecter(#"{"v":1,"t":"compteurs","n":6,"ms":905612,"bloc":"mesh","annonces":5120,"nid_reconnu":1630,"nid_inconnu":3402,"netmic_faux":0,"emis":64,"echecs_emission":0,"iv":3,"seq":1093,"plancher":1024}"#)
        #expect(await attendre { pont.etatCompteursMesh == .normal })
        #expect(pont.compteursMeshActuels?.annonces == 5120)
        #expect(pont.ivIndexMesh?.texte == "3")
        #expect(pont.texteCompteursMesh == nil)

        // La session tombe (chemin perdu, silence...) et se rouvre seule.
        f.fermer()
        try #require(await attendre { f.ouvertures == 2 && f.envoyees.filter { $0.contains(" json 1 ") }.count == 2 })
        try await Self.repondreAuJson1(f)
        #expect(await attendre { pont.phase == .connecte && pont.reglages?.compteursMs == 0 })
        #expect(pont.etat.compteurs?.valeur.annonces == 5120, "l'ancien bloc est toujours la...")
        #expect(pont.etatCompteursMesh == .nonReleves, "... mais il n'est plus releve")
        #expect(pont.compteursMeshActuels == nil, "la carte ne montre pas de compteurs figes")
        #expect(pont.texteCompteursMesh?.hasPrefix("Compteurs du Mesh non relevés à distance (dernier relevé à ") == true)
        #expect(pont.ivIndexMesh?.texte == "2 (mémoire du pont)", "l'IV Index des compteurs figes n'est plus montre")

        // De nouveau actives : demandes tant que le premier bloc du releve n'est pas la.
        try await activer(2)
        #expect(pont.etatCompteursMesh == .demandes, "l'ancien bloc ne vaut pas premier releve")
        #expect(pont.compteursMeshActuels == nil)
        f.injecter(#"{"v":1,"t":"compteurs","n":7,"ms":915612,"bloc":"mesh","annonces":6000,"nid_reconnu":1900,"nid_inconnu":4000,"netmic_faux":0,"emis":70,"echecs_emission":0,"iv":3,"seq":1200,"plancher":1024}"#)
        #expect(await attendre { pont.etatCompteursMesh == .normal })
        #expect(pont.compteursMeshActuels?.annonces == 6000)
    }

    /// Par l'USB (ici le pont simule), la console juge refus et confirmations sur la ligne
    /// decoupee comme le pont la decoupe : `re\xdemarre` est `redemarre`, et
    /// `js\xon cle nouvelle <alea>` ne part pas.
    @Test func consoleParLUSBJugeeCommeLePont() async throws {
        let p = pontDemo()
        defer { p.deconnecter() }
        #expect(await connecte(p))
        if case .confirmation = p.console(#"re\xdemarre"#) {} else { Issue.record("re\\xdemarre : confirmation attendue") }
        if case .confirmation = p.console(#"json c\xle efface"#) {} else { Issue.record("json c\\xle efface : confirmation attendue") }
        let avant = p.suivis.count
        guard case .refusee(let raison) = p.console(#"js\xon cle nouvelle "# + String(repeating: "AB", count: 32)) else {
            Issue.record("js\\xon cle nouvelle : refus attendu")
            return
        }
        #expect(raison.contains("Nouvelle clé"))
        #expect(p.suivis.count == avant, "rien n'est parti")
    }

    /// Cles du Mesh inventees, et les memes ecrites avec un `\x` tous les 4 hexa, que la
    /// console du pont oublie.
    static let k1 = "404142434445464748494A4B4C4D4E4F"
    static let k2 = "505152535455565758595A5B5C5D5E5F"
    static func echappee(_ k: String) -> String {
        stride(from: 0, to: k.count, by: 4).map { String(k.dropFirst($0).prefix(4)) }.joined(separator: #"\x"#)
    }

    /// Vrai si un morceau de 6 hexa d'une des deux cles se lit dans le texte, decoupe comme
    /// le pont le decoupe (echappements et guillemets retires).
    static func fuite(_ texte: String) -> Bool {
        let lu = LigneCommande.argv(texte, maxArguments: 10_000).joined().uppercased()
        return [k1, k2].contains { cle in
            let h = Array(cle)
            return (0...(h.count - 6)).contains { lu.contains(String(h[$0..<($0 + 6)])) }
        }
    }

    /// Reste du rapport : des cles tapees dans la console avec des echappements ou des
    /// guillemets que le pont retire n'apparaissent nulle part, par l'USB (ici le pont
    /// simule) : ni l'historique de saisie, ni la ligne envoyee du journal, ni le suivi.
    @Test func clesEcritesAutrementJamaisAffichees() async throws {
        let p = pontDemo()
        defer { p.deconnecter() }
        #expect(await connecte(p))
        for ligne in ["mesh cles \(Self.echappee(Self.k1)) \(Self.echappee(Self.k2))",
                      #"mesh cles "\#(Self.k1)" "\#(Self.echappee(Self.k2))""#] {
            // Historique de saisie : la vue n'y garde qu'une ligne que le masque laisse intacte.
            #expect(PolitiqueCommandes.masquerCle(ligne) != ligne, "\(ligne)")
            guard case .confirmation = p.console(ligne) else {
                Issue.record("mesh cles demande confirmation : \(ligne)")
                return
            }
            let avant = p.suivis.count
            #expect(p.console(ligne, confirme: true) == .envoyee)
            #expect(await attendre { p.suivis.count > avant })
        }
        // Les deux lignes parties (une seule en vol a la fois) et finies par le pont simule.
        #expect(await attendre { p.suivis.filter { $0.commande == "mesh cles •••••••• ••••••••" && $0.etat.estFinal }.count == 2 },
                "le suivi n'en garde que le masque")
        #expect(p.console.elements.filter { $0.texte.hasSuffix(" mesh cles •••••••• ••••••••") }.count == 2, "lignes envoyees masquees")
        #expect(!p.console.elements.contains { Self.fuite($0.texte) })
        #expect(!p.suivis.contains { Self.fuite($0.commande) })
    }

    /// A distance, la meme ligne est refusee par la liste blanche : la note qui la cite
    /// est masquee.
    @Test func clesEcritesAutrementCiteesMasquees() async throws {
        let (pont, _) = try Self.pont()
        defer { pont.deconnecter() }
        let f = TransportFactice(hote: Self.nom + ".local")
        pont.fabriqueReseau = { _, _ in f }
        pont.connecter(.reseau(nom: Self.nom))
        try await Self.repondreAuJson1(f)
        #expect(await attendre { pont.phase == .connecte })
        let ligne = #"mesh cles "\#(Self.echappee(Self.k1))" \#(Self.echappee(Self.k2))"#
        guard case .refusee = pont.console(ligne) else {
            Issue.record("mesh cles : USB seulement")
            return
        }
        #expect(pont.console.elements.last?.texte
                == "« mesh cles •••••••• •••••••• » n'est pas envoyée : la liste blanche du pont la refuse (« interdite a distance : USB seulement »).")
        #expect(!pont.console.elements.contains { Self.fuite($0.texte) })
        #expect(!f.envoyees.contains { Self.fuite($0) }, "rien n'est parti")
    }

    /// `json trames 1` reconnu comme le pont le lit : le compte a rebours des 60 s part
    /// aussi pour une ligne avec guillemets ou echappements.
    @Test func demandeDeTramesLueCommeLePont() async throws {
        let (pont, _) = try Self.pont()
        defer { pont.deconnecter() }
        let f = TransportFactice(hote: Self.nom + ".local")
        pont.fabriqueReseau = { _, _ in f }
        pont.connecter(.reseau(nom: Self.nom))
        try await Self.repondreAuJson1(f)
        #expect(await attendre { pont.phase == .connecte })
        #expect(pont.console(#"js\xon "trames" 1"#) == .envoyee)
        #expect(pont.tramesDemandeesLe != nil)
    }
}

/// Trousseau des ponts qui refuse toute suppression (`errSecAuthFailed`), comme un element
/// cree par une autre signature ; en memoire, isole du vrai.
final class TrousseauPontsRefus: TrousseauPonts {
    private let memoire = TrousseauPontsMemoire()

    func lister() -> [PontConnu] { memoire.lister() }
    func lire(nom: String) throws -> Data { try memoire.lire(nom: nom) }
    func ranger(nom: String, cle: Data, empreinte: String) throws { try memoire.ranger(nom: nom, cle: cle, empreinte: empreinte) }
    func oublier(nom: String) throws { throw ErreurTrousseauPonts.systeme(-25293) }

}
