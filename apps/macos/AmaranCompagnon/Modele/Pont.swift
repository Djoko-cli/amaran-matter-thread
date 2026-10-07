// Repris de Halo Compagnon (commit e114cd5) : sources (USB, demo, reseau Thread),
// reconnexion, session, console, trames et courbes. Les gestes des lampes, des cles
// Mesh et de l'acces reseau sont dans Pont+Lampes.swift, Pont+Cles.swift et
// Pont+Reseau.swift.
import AmaranProtocole
import AppKit
import Foundation
import Network
import Observation

/// Modele central de l'app : un transport, le recepteur, le moteur de session et tout
/// ce que les ecrans affichent. Tout se passe sur l'acteur principal ; la couche
/// protocole (AmaranProtocole) est du code pur appele d'ici.
@MainActor
@Observable
final class Pont {
    enum Source: Hashable, Sendable {
        case serie(chemin: String, serie: String?)
        case demo
        /// Pont joint par le reseau Thread (docs/PROTOCOLE-JSON.md 10) : son nom SRP, sans `.local`.
        case reseau(nom: String)

        var estDemo: Bool { self == .demo }
        var estReseau: Bool { if case .reseau = self { true } else { false } }
    }

    enum EtatTransport: Equatable, Sendable {
        case ferme
        case ouverture
        case ouvert
        /// Reouverture programmee (re-enumeration USB, silence...).
        case attente(prochain: Date, raison: String)
        /// "Liberer le port" : rien ne se rouvre avant un clic.
        case libere
        case erreur(String)
    }

    enum ResultatConsole: Equatable {
        case envoyee
        case confirmation(String)
        case refusee(String)
    }

    // MARK: Etat publie

    private(set) var source: Source?
    private(set) var ports: [PortUSB] = []
    private(set) var etatTransport: EtatTransport = .ferme
    /// Nom du transport ouvert (chemin du port, demo).
    private(set) var nomTransport = ""
    private(set) var phase: MoteurSession.Phase = .ferme
    private(set) var etat = EtatPont()
    private(set) var reception = CompteursReception()
    private(set) var statistiques = StatistiquesLien()
    private(set) var suivis: [SuiviCommande] = []
    private(set) var console = Borne<LigneConsole>(capacite: 4000)
    private(set) var rejets = Borne<Rejet>(capacite: 100)
    /// Trafic Bluetooth Mesh decode (`json trames 1`, 7.6).
    private(set) var trames = Borne<TrameRecue>(capacite: 5000)
    /// Dernier `json trames 1` envoye : a distance, le pont coupe le flux 60 s plus tard
    /// sans le dire (7.6), et ses reglages d'app gardent `trames` a vrai.
    private(set) var tramesDemandeesLe: Date?
    /// Series des graphiques (compteurs, relectures, ordres, tas), par segment de `boot`.
    private(set) var courbes = SeriesCourbes()
    /// Un bloc `compteurs` est arrive depuis que leur periode est non nulle : il est celui
    /// du releve en cours. Faux des que la periode retombe a 0 (session distante ouverte
    /// ou rouverte, `json compteurs 0`) : le dernier bloc garde alors des valeurs figees
    /// (CompteursMesh.swift).
    private(set) var compteursEnDirect = false
    /// Annonce grave (ancien firmware, aucune reponse...) montree en bandeau.
    private(set) var alerte: MoteurSession.Note?
    /// Alerte de la source reseau qui demande l'utilisateur (cle absente ou trousseau en
    /// erreur, reseau local refuse, pont sans cle, sessions pleines), montree en bandeau.
    /// Une cause qui se reprend seule (pas de route, pont introuvable...) n'en a pas :
    /// la console et le panneau de connexion la disent (sans route, l'etat de Thread Route
    /// et ce qu'il reste a faire), comme Halo.
    private(set) var alerteReseau: AlerteReseau?
    private(set) var derniereReception: Date?
    /// Commande de la console du pont de plus de 20 min : proposer de fermer le port.
    var propositionFermeture = false
    /// Numero de serie USB du dernier pont confirme (preferences) : titre `AMARAN · MAC` de sa carte dans les menus tant que le repertoire ne la connait pas.
    private(set) var dernierPont: String?
    /// Reglages de session en vigueur ; nil avant le `hello`.
    private(set) var reglages: HelloBase.ReglagesSession?
    /// Facteur de temps du mode demo (1 : temps reel ; les tests accelerent).
    @ObservationIgnored var vitesseDemo: Double = 1
    /// Faux (tests) : le pont simule n'annonce pas la capacite `logiciel`.
    @ObservationIgnored var demoAnnonceLogiciel = true

    // Acces reseau (Pont+Reseau.swift)
    /// Ponts dont ce Mac a la cle UDP (trousseau des ponts, jamais celui de la demo).
    var pontsConnus: [PontConnu] = []
    /// Ponts deja vus (modele et nom SRP par MAC) : titres des sources reseau, gardes
    /// dans les preferences (`RepertoirePonts.cleReglages`).
    var repertoire = RepertoirePonts()
    /// `json cle nouvelle` en cours : suivi et nom SRP du pont (Pont+Reseau.swift).
    @ObservationIgnored var creationCle: (id: UUID, nom: String)?

    // Cles (Pont+Cles.swift)
    /// Copie du trousseau (celui de la demo en mode demo), sans ses cles.
    var copie: ApercuReseau?
    /// Derniere lecture de la base d'amaran Desktop, sans ses cles.
    var base: ApercuReseau?
    var erreurBase: String?
    /// Dossier d'amaran Desktop autorise (signet).
    var dossierAmaran: URL?
    var chargement: EtatChargement = .repos
    var derniereSauvegarde: Date?
    @ObservationIgnored var charge: ChargementEnCours?
    /// `avancerChargement` est en cours : `envoyer` rappelle `synchroniser`, qui le rappellerait.
    @ObservationIgnored var chargementAvance = false

    // MARK: Interne

    @ObservationIgnored var moteur = MoteurSession()
    @ObservationIgnored private var recepteur = RecepteurLignes()
    @ObservationIgnored private var transport: (any Transport)?
    @ObservationIgnored private var demo: TransportDemo?
    @ObservationIgnored private(set) var genreTransport: GenreTransport?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var tacheLecture: Task<Void, Never>?
    @ObservationIgnored private var tacheReconnexion: Task<Void, Never>?
    @ObservationIgnored private var tacheTic: Task<Void, Never>?
    @ObservationIgnored private var reconnexionAuto = false
    @ObservationIgnored private var essaisReconnexion = 0
    @ObservationIgnored private var compteur = 0
    @ObservationIgnored private var dernierCurseur: [String: TimeInterval] = [:]
    @ObservationIgnored private let origine = ContinuousClock.now
    @ObservationIgnored private let surveillant = SurveillantUSB()
    @ObservationIgnored let trousseau: any TrousseauReseau
    /// Trousseau isole de la demo : rien de la demo n'ecrase la vraie copie.
    @ObservationIgnored let trousseauDemo: any TrousseauReseau
    @ObservationIgnored let preferences: UserDefaults
    /// Cles UDP des ponts joints par Thread.
    @ObservationIgnored let trousseauPonts: any TrousseauPonts
    /// Trousseau des ponts isole de la demo : une cle creee en mode demo n'ecrase jamais
    /// celle d'un vrai pont et n'apparait jamais dans `pontsConnus`.
    @ObservationIgnored let trousseauPontsDemo: any TrousseauPonts
    /// Transport d'une source reseau (hote `<nom>.local`, cle) : `TransportUDP` ; les
    /// tests y mettent un transport factice.
    @ObservationIgnored var fabriqueReseau: @MainActor (_ hote: String, _ cle: Data) -> any Transport = { hote, cle in
        TransportUDP(hote: hote, cle: cle)
    }
    @ObservationIgnored private let cheminReseau = NWPathMonitor()
    /// Derniere cause reseau notee en console : une meme cause n'est notee qu'une fois
    /// tant qu'elle ne change pas.
    @ObservationIgnored private var derniereCauseReseau: String?
    @ObservationIgnored private var observateurReveil: (any NSObjectProtocol)?
    @ObservationIgnored private var observateurFin: (any NSObjectProtocol)?
    /// Session serie ouverte : pas de mise en sommeil de l'app (App Nap) qui
    /// retarderait le ping au-dela du bail de 30 s.
    @ObservationIgnored private var activite: (any NSObjectProtocol)?

    /// Delais de reouverture apres une fermeture : 300 ms, puis 1 s, 2 s, 5 s (3.1).
    static let delaisReconnexion: [Double] = [0.3, 1, 2, 5]
    /// L'etat de Thread Route, lu au moment d'un echec "pas de route" : les tests y mettent le leur.
    @ObservationIgnored private let etatThreadRoute: () -> EtatThreadRoute

    init(trousseau: any TrousseauReseau = TrousseauSysteme(), trousseauDemo: any TrousseauReseau = TrousseauMemoire(ReseauDemo.reseau),
         trousseauPonts: any TrousseauPonts = TrousseauPontsSysteme(),
         trousseauPontsDemo: any TrousseauPonts = TrousseauPontsMemoire(),
         preferences: UserDefaults = .standard,
         etatThreadRoute: @escaping () -> EtatThreadRoute = { EtatThreadRoute.lire() }) {
        self.etatThreadRoute = etatThreadRoute
        self.trousseau = trousseau
        self.trousseauDemo = trousseauDemo
        self.trousseauPonts = trousseauPonts
        self.trousseauPontsDemo = trousseauPontsDemo
        self.preferences = preferences
        dernierPont = preferences.string(forKey: Self.cleDernierPont)
        pontsConnus = trousseauPonts.lister()
        if let d = preferences.data(forKey: RepertoirePonts.cleReglages), let r = RepertoirePonts(donnees: d) {
            repertoire = r
        }
        ports = Self.portsVisibles(SurveillantUSB.lister())
        surveillant.changement = { [weak self] ports in self?.portsChanges(ports) }
        surveillant.demarrer()
        cheminReseau.pathUpdateHandler = { [weak self] chemin in
            guard chemin.status == .satisfied else { return }
            Task { @MainActor [weak self] in self?.reseauChange() }
        }
        cheminReseau.start(queue: .main)
        observateurReveil = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // Pause de lecture : la premiere ligne lue ensuite peut etre un fragment (2.4).
                self?.recepteur.signalerPause()
                self?.reseauChange()
            }
        }
        observateurFin = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // Rendre la console texte au pont avant de partir (sinon JSON jusqu'a la fin du bail).
                self?.fermerProprement(synchrone: true)
            }
        }
        tacheTic = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self else { return }
                self.tic()
            }
        }
        chargerPreferencesCles()
    }

    func maintenant() -> TimeInterval {
        (ContinuousClock.now - origine) / .seconds(1)
    }

    private func prochainId() -> Int {
        compteur += 1
        return compteur
    }

    // MARK: - Connexion

    /// Cle des preferences : numero de serie USB du dernier pont confirme (le `hello` a
    /// montre un pont amaran), jamais d'un port seulement choisi dans le menu.
    static let cleDernierPont = "dernierPont"

    /// Source proposee par "Connecter" : seulement le dernier pont confirme, reconnu a son
    /// numero de serie USB. Jamais "le premier port Espressif" (la C6 BenQ en est un aussi).
    var sourceParDefaut: Source? {
        Self.sourceParDefaut(ports: ports, dernierPont: dernierPont)
    }

    /// Vrai si l'identite du `hello` est celle d'un pont amaran : la capacite `mesh`, ou un
    /// numero de serie `AMARAN-...`.
    static func estPontAmaran(_ identite: HelloIdentite?) -> Bool {
        guard let identite else { return false }
        return (identite.caps ?? []).contains("mesh") || (identite.id?.serie?.hasPrefix("AMARAN-") ?? false)
    }

    /// Une carte USB deja confirmee comme pont est retenue pour "Connecter".
    private func confirmerPont() {
        guard case .serie(_, let serie?)? = source, serie != dernierPont,
              Self.estPontAmaran(etat.identite?.valeur) else { return }
        dernierPont = serie
        preferences.set(serie, forKey: Self.cleDernierPont)
    }

    /// Titre d'un port (comme Halo Compagnon) : "AMARAN · F0:F5:BD:0A:0B:0C", le modele puis la
    /// MAC (le numero de serie USB de la carte est sa MAC). Le modele vient du repertoire (appris
    /// au `hello` d'un vrai pont, par l'USB ou le reseau) ; carte encore inconnue du repertoire
    /// mais dernier pont confirme : `AMARAN` ; sinon "ESP32". Sans MAC lisible, le nom court du port.
    func titre(port p: PortUSB) -> String { titre(serie: p.serie, chemin: p.chemin) }

    /// Titre d'une carte USB par son numero de serie (sa MAC) et son chemin : celui d'un port
    /// branche comme celui de la source serie choisie (branchee ou non).
    func titre(serie: String?, chemin: String) -> String {
        guard let mac = RepertoirePonts.mac(serie) else {
            return chemin.replacingOccurrences(of: "/dev/cu.", with: "")
        }
        if repertoire.parMac[mac]?.modele == nil, serie == dernierPont {
            return "\(Self.modelePont) · \(RepertoirePonts.macLisible(mac))"
        }
        return repertoire.titre(mac: mac)
    }

    /// Modele d'un pont amaran (le numero de serie du `hello` est `AMARAN-<MAC>`).
    static let modelePont = "AMARAN"

    static func sourceParDefaut(ports: [PortUSB], dernierPont: String?) -> Source? {
        guard let dernierPont,
              let p = ports.first(where: { $0.estEspressif && $0.serie == dernierPont }) else { return nil }
        return .serie(chemin: p.chemin, serie: p.serie)
    }

    func connecter(_ s: Source) {
        let changement = s != source
        if changement {
            // Autre pont ou demo : le pont quitte retrouve la console texte, et rien de
            // l'ancienne source ne reste (ni etat, ni boot).
            fermerProprement()
            oublierSource()
        } else if s.estReseau {
            // Meme pont reseau choisi de nouveau : json 0 scelle d'abord, sinon l'ancienne
            // session H1 garderait l'une des deux places du pont jusqu'a son oubli (10.3).
            fermerProprement()
        } else {
            fermerTransport()
        }
        source = s
        alerte = nil
        alerteReseau = nil
        derniereCauseReseau = nil
        reconnexionAuto = true
        essaisReconnexion = 0
        if changement, let nom = nomSource {
            // Comme Halo : la console garde ses lignes (l'historique de la session), seuls les
            // etats, trames et courbes repartent de zero.
            note(tr("Nouvelle source : \(nom). États, trames et courbes remis à zéro ; la console garde ses lignes."))
        }
        rafraichirCopie()
        ouvrir()
    }

    func deconnecter() {
        reconnexionAuto = false
        alerteReseau = nil
        fermerProprement()
        etatTransport = .ferme
    }

    /// "Liberer le port" (3.1) : `json 0`, fermeture, pas de reouverture avant un clic.
    /// Source reseau : la session H1 se ferme de meme (`json 0` scelle), rien a flasher.
    func libererPort() {
        reconnexionAuto = false
        let modeMachine = rendModeTexte
        let reseau = source?.estReseau == true
        fermerProprement()
        etatTransport = .libere
        // Plus aucune relance : un bandeau reseau qui en promettait une ne vaut plus.
        alerteReseau = nil
        if reseau {
            note(modeMachine
                 ? tr("Session réseau fermée : json 0 envoyé. « Reconnecter » pour reprendre.")
                 : tr("Session réseau fermée. « Reconnecter » pour reprendre."))
        } else {
            note(modeMachine
                 ? tr("Port libéré : json 0 envoyé, port fermé. Flasher est possible ; « Reconnecter » pour reprendre.")
                 : tr("Port libéré : port fermé. Flasher est possible ; « Reconnecter » pour reprendre."))
        }
    }

    /// Vrai si fermer doit d'abord rendre la console texte au pont (`json 0`) : session
    /// machine ou tentative en cours, et pas de commande en cours (la console du pont
    /// ne lit plus).
    private var rendModeTexte: Bool {
        guard transport != nil, moteur.correlateur.commandeDeBanc == nil else { return false }
        switch moteur.phase {
        case .ferme, .ancienFirmware, .versionInconnue, .modeHumain: return false
        default: return true
        }
    }

    /// `json 0` si besoin, puis fermeture apres vidage de la file de sortie.
    private func fermerProprement(synchrone: Bool = false) {
        tacheReconnexion?.cancel()
        guard let t = transport else {
            fermerTransport()
            return
        }
        if rendModeTexte {
            executer(moteur.liberer(maintenant: maintenant()))
        } else if moteur.phase != .ferme {
            moteur.ferme(maintenant: maintenant())
        }
        transport = nil
        // La boucle de lecture se detache (generation) ; l'annuler fermerait le port
        // tout de suite, avant que json 0 soit parti.
        generation += 1
        tacheLecture = nil
        t.fermerApresVidage(synchrone: synchrone)
        finActivite()
        synchroniser()
    }

    /// Nouvelle source : moteur, recepteur et etats repartent de zero.
    private func oublierSource() {
        moteur = MoteurSession()
        recepteur = RecepteurLignes()
        etat = EtatPont()
        demo = nil
        rejets.vider()
        trames.vider()
        tramesDemandeesLe = nil
        courbes.vider()
        compteursEnDirect = false
        dernierCurseur = [:]
        propositionFermeture = false
        derniereReception = nil
        interrompreChargement(tr("source changée"))
        interrompreCreationCle()
        synchroniser()
    }

    private var nomSource: String? {
        switch source {
        case .serie(let chemin, let serie): titre(serie: serie, chemin: chemin)
        case .demo: tr("démo")
        case .reseau(let nom): repertoire.mac(pourSrp: nom) == nil ? "\(nom).local" : "\(titre(reseau: nom)) (\(nom).local)"
        case nil: nil
        }
    }

    func reconnecter() {
        guard source != nil else { return }
        reconnexionAuto = true
        essaisReconnexion = 0
        alerte = nil
        // La cause n'est PAS oubliee (derniereCauseReseau) : reessayer sur la meme cause
        // ne redouble pas la ligne de console.
        alerteReseau = nil
        ouvrir()
    }

    /// Nouvel essai de `json 1` (apres un flash du firmware, par exemple).
    func reessayer() {
        alerte = nil
        executer(moteur.reessayer(maintenant: maintenant()))
    }

    private func ouvrir() {
        guard let source else { return }
        tacheReconnexion?.cancel()
        fermerTransport()
        let t: any Transport
        switch source {
        case .demo:
            if demo == nil { demo = TransportDemo(vitesse: vitesseDemo, annonceLogiciel: demoAnnonceLogiciel) }
            t = demo!
        case .serie(let chemin, let serie):
            // Le meme pont (meme numero de serie USB) peut revenir sous un autre nom ;
            // jamais un autre appareil, meme sous le nom d'avant.
            guard let port = Self.portDuPont(ports, chemin: chemin, serie: serie) else {
                echecOuverture(ErreurTransport(tr("Pont absent : aucune carte Espressif reconnue")))
                return
            }
            t = TransportSerie(chemin: port.chemin)
        case .reseau(let nom):
            do {
                // La cle quitte le trousseau pour la session seulement.
                t = fabriqueReseau("\(nom).local", try trousseauPonts.lire(nom: nom))
            } catch {
                let a = AlerteReseau.trousseau(error as? ErreurTrousseauPonts ?? .absente(nom))
                alerteReseau = a
                etatTransport = .erreur(a.texte)
                noterCauseReseau(a.texte, grave: true)
                return
            }
        }
        transport = t
        genreTransport = t.genre
        nomTransport = t.nom
        etatTransport = .ouverture
        generation += 1
        let g = generation
        tacheLecture = Task { [weak self] in
            do {
                let flux = try await t.ouvrir()
                guard let self, self.generation == g else {
                    t.fermer()
                    return
                }
                self.transportOuvert()
                var raison = tr("flux terminé")
                for await ev in flux {
                    guard self.generation == g else { break }
                    if case .ferme(let r) = ev { raison = r }
                    self.recevoir(ev)
                }
                if self.generation == g { self.transportFerme(raison) }
            } catch {
                guard let self, self.generation == g else { return }
                self.echecOuverture(error)
            }
        }
    }

    private func fermerTransport() {
        generation += 1
        tacheLecture?.cancel()
        tacheLecture = nil
        transport?.fermer()
        transport = nil
        finActivite()
        if moteur.phase != .ferme {
            moteur.ferme(maintenant: maintenant())
            synchroniser()
        }
        interrompreCreationCle()
    }

    private func debutActivite() {
        guard activite == nil else { return }
        activite = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                         reason: "Session du pont amaran : ping du bail")
    }

    private func finActivite() {
        guard let a = activite else { return }
        ProcessInfo.processInfo.endActivity(a)
        activite = nil
    }

    private func transportOuvert() {
        etatTransport = .ouvert
        // Une poignee de main reussie leve les causes d'echec d'ouverture, pas « aucune
        // reponse au json 1 » (sansHello) : elle reussissait deja. Ce bandeau tient
        // jusqu'au hello (synchroniser), sans etre redit a chaque relance.
        if alerteReseau != .sansHello {
            alerteReseau = nil
            derniereCauseReseau = nil
        }
        debutActivite()
        // Port serie : jeter ce qui precede le premier LF (3.1). Reseau : chaque datagramme
        // est une ligne entiere, et la premiere est le hello du json 1 : rien a jeter.
        if genreTransport != .udp { recepteur.resynchroniser() }
        switch genreTransport {
        case .demo: note(tr("Pont de démonstration ouvert."))
        case .udp: note(tr("Session réseau ouverte : \(nomTransport)."))
        default: note(tr("Port ouvert : \(nomTransport) (DTR = RTS = 0)."))
        }
        executer(moteur.ouvert(maintenant: maintenant(), genre: genreTransport ?? .usb))
    }

    private func transportFerme(_ raison: String) {
        transport = nil
        finActivite()
        moteur.ferme(maintenant: maintenant())
        synchroniser()
        note(tr("Transport fermé : \(raison)"))
        interrompreCreationCle()
        if reconnexionAuto { planifierReconnexion(raison) } else { etatTransport = .ferme }
    }

    func echecOuverture(_ erreur: any Error) {
        transport = nil
        if let e = erreur as? ErreurTransportReseau {
            let texte = AlerteReseau.transport(e).texte(etatThreadRoute: etatThreadRoute)
            // Bandeau tant que l'utilisateur doit agir (reseau local refuse, pont sans
            // cle), essais en cours ou non ; une autre cause efface un bandeau perime.
            alerteReseau = e.bandeau ? .transport(e) : nil
            noterCauseReseau(texte, grave: e.bandeau)
            if !e.repriseAutomatique {
                etatTransport = .erreur(texte)
            } else if reconnexionAuto, essaisReconnexion < 40 {
                planifierReconnexion(texte)
            } else {
                etatTransport = .erreur(tr("\(texte) — en attente d'un changement du réseau"))
            }
            return
        }
        let texte = String(describing: erreur)
        if reconnexionAuto, essaisReconnexion < 40 {
            planifierReconnexion(texte)
        } else if reconnexionAuto {
            // Plus d'essais minutes (~3 min), mais le retour du port (IOKit) rouvre encore.
            etatTransport = .erreur(tr("\(texte) — en attente du retour du port"))
        } else {
            etatTransport = .erreur(texte)
        }
    }

    private func planifierReconnexion(_ raison: String) {
        let delai = Self.delaisReconnexion[min(essaisReconnexion, Self.delaisReconnexion.count - 1)]
        essaisReconnexion += 1
        etatTransport = .attente(prochain: Date().addingTimeInterval(delai), raison: raison)
        tacheReconnexion?.cancel()
        tacheReconnexion = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delai / (self?.vitesseDemo ?? 1)))
            guard !Task.isCancelled else { return }
            self?.ouvrir()
        }
    }

    /// Le port du pont parmi `ports` : Espressif seulement. Avec un numero de serie USB
    /// connu, c'est lui qui decide (le pont peut changer de nom, jamais de numero) ;
    /// sans numero, le port de meme chemin.
    static func portDuPont(_ ports: [PortUSB], chemin: String, serie: String?) -> PortUSB? {
        let cartes = ports.filter(\.estEspressif)
        if let serie { return cartes.first { $0.serie == serie } }
        return cartes.first { $0.chemin == chemin }
    }

    /// Ports du menu Source : les cartes Espressif seulement (USB Serial/JTAG du C6,
    /// VID 303A) ; ni Bluetooth, ni console de debogage, ni ecrans.
    static func portsVisibles(_ tous: [PortUSB]) -> [PortUSB] { tous.filter(\.estEspressif) }

    /// Arrivee ou depart d'un port (IOKit) : on rouvre des que le pont revient, meme
    /// apres l'abandon des essais minutes (etat `.erreur`).
    private func portsChanges(_ nouveaux: [PortUSB]) {
        ports = Self.portsVisibles(nouveaux)
        guard reconnexionAuto, case .serie(let chemin, let serie)? = source else { return }
        switch etatTransport {
        case .attente, .erreur: break
        default: return
        }
        if Self.portDuPont(nouveaux, chemin: chemin, serie: serie) != nil {
            essaisReconnexion = 0
            planifierReconnexion(tr("port revenu"))
        }
    }

    /// Chemin reseau retrouve ou reveil du Mac : une source reseau en attente ou en
    /// echec repart (la ou l'USB attend le retour du port). Les arrets qui exigent
    /// l'utilisateur (cle absente ou trousseau en erreur, pont sans cle) ne
    /// reessaient pas seuls. « Reseau local refuse » reessaie seul, bandeau tenu, et
    /// repart aussi d'ici apres ses 40 essais.
    func reseauChange() {
        guard reconnexionAuto, source?.estReseau == true else { return }
        if case .trousseau = alerteReseau { return }
        if case .transport(.portInjoignable) = alerteReseau { return }
        switch etatTransport {
        case .attente, .erreur:
            essaisReconnexion = 0
            planifierReconnexion(tr("réseau changé"))
        default:
            break
        }
    }

    // MARK: - Boucle

    private func tic() {
        if moteur.phase != .ferme { executer(moteur.tic(maintenant: maintenant())) }
        avancerChargement()
    }

    /// Seul un test appelle ceci : avance l'horloge de la session de `secondes` sans
    /// attendre, comme le ferait `tic()` a l'echeance reelle.
    func avancerPourUnTest(de secondes: TimeInterval) {
        executer(moteur.tic(maintenant: maintenant() + secondes))
    }

    private func recevoir(_ ev: EvenementTransport) {
        guard case .donnees(let d) = ev else { return }
        derniereReception = Date()
        for element in recepteur.alimenter(d) { traiter(element) }
        synchroniser()
    }

    private func traiter(_ brut: ElementRecu) {
        // La reponse a `json cle nouvelle` porte la cle UDP : elle ne sert qu'ici, a la
        // ranger. Tout le reste (moteur, etats, console, rejets, trames) ne voit que
        // l'element sans cle (masque strict pour les lignes abimees et les fragments).
        let suiviCle = reponseACreationCle(brut)
        let element = brut.sansCle
        let effets = moteur.recu(element, maintenant: maintenant())
        let historique = moteur.historique
        // Un redemarrage vide les etats derives AVANT d'appliquer la ligne qui l'a revele
        // (le hello du nouveau demarrage doit rester).
        let (redemarrages, autres) = effets.reduce(into: ([MoteurSession.Effet](), [MoteurSession.Effet]())) { r, e in
            if case .redemarrage = e { r.0.append(e) } else { r.1.append(e) }
        }
        executer(redemarrages)
        if let c = suiviCle { terminerCreationCle(c.0, nom: c.1) }
        switch element {
        case .machine(let l):
            traiterMachine(l, historique: historique)
        case .texte(let t):
            if t.classe != .invite {
                ajouterConsole(.texte(t.classe), t.texte, numero: moteur.correlateur.commandeDeBanc?.numero)
            }
        case .fragment(let s):
            ajouterConsole(.fragment, s)
        case .abimee(let raison, let brut):
            rejets.ajouter(Rejet(id: prochainId(), date: Date(), raison: tr("abîmée : \(raison)"), brut: brut))
        case .versionInconnue(let v, let t):
            rejets.ajouter(Rejet(id: prochainId(), date: Date(), raison: tr("version \(String(v)) inconnue"),
                                  brut: PolitiqueCommandes.masquerCle(t)))
        case .invalide(let t, let raison):
            rejets.ajouter(Rejet(id: prochainId(), date: Date(), raison: tr("\(t) invalide : \(raison)"), brut: ""))
        case .debordement(let s):
            ajouterConsole(.texte(.commande), s)
        }
        executer(autres)
    }

    /// `l` est deja sans cle (`LigneMachine.sansCle`).
    private func traiterMachine(_ l: LigneMachine, historique: Bool) {
        let recueA = Date()
        let date = historique ? etat.dater(ms: l.enveloppe.ms, recueA: recueA) : etat.appliquer(l, recueA: recueA)
        if !historique {
            courbes.ajouter(l.message, date: date)
            switch l.message {
            case .helloIdentite, .reseauIp: noterRepertoire()
            case .compteursMesh where (moteur.reglages.compteursMs ?? 0) > 0 && !compteursEnDirect: compteursEnDirect = true
            default: break
            }
        }
        switch l.message {
        case .texte(let t):
            // A distance, la sortie d'une commande a texte (10.4) : comme le texte de la
            // console par l'USB, rattachee a son id.
            ajouterConsole(.texte(.commande), t.txt ?? "", numero: t.id)
        case .trame(let t):
            trames.ajouter(TrameRecue(id: prochainId(), date: date, trame: t))
        case .ordre(let o):
            for id in o.ids ?? [] {
                guard let s = moteur.correlateur.suivi(numero: id) else { continue }
                ajouterConsole(.retour(ok: o.issue != .abandon, session: s.origine == .session),
                               tr("‹ id=\(String(id)) « \(s.commande) » : \(Interpretation.ordre(o))"), numero: id)
            }
        case .reponse(let r):
            let s = moteur.correlateur.suivi(numero: r.id)
            ajouterConsole(.retour(ok: r.ok, session: (s?.origine ?? .session) == .session),
                           "‹ " + Interpretation.reponse(r), numero: r.id)
        case .log(let lg):
            ajouterConsole(.log, lg.txt ?? "")
        case .lampe(let e):
            let ep = e.endpoint ?? 0
            let quoi = switch e.quoi {
            case .entree: tr("entre dans Maison (EP\(ep))")
            case .masquee: tr("retirée de Maison")
            case .remise: tr("remise dans Maison (EP\(ep))")
            case .echec: tr("endpoint Matter non créé")
            case .inconnu, nil: tr("changement inconnu")
            }
            note(tr("Lampe \(e.lampe) : \(quoi)."))
        case .alerte(let a):
            switch a.quoi {
            case .releves:
                let (lampe, part) = (a.lampe ?? 0, a.part ?? 0)
                note(a.manque == true
                     ? tr("Lampe \(lampe) : relectures manquées, \(part) % répondues sur 10 min.")
                     : tr("Lampe \(lampe) : relectures de nouveau répondues (\(part) %)."),
                     grave: a.manque == true)
            case .mesh:
                note(tr("Bluetooth Mesh : \(Interpretation.diag(a.diag))."), grave: a.diag != .ok)
            case .inconnu, nil:
                break
            }
        default:
            break
        }
    }

    func executer(_ effets: [MoteurSession.Effet]) {
        for e in effets {
            switch e {
            case .envoyer(let d):
                do {
                    try transport?.envoyer(d)
                } catch {
                    note(tr("Envoi impossible : \(String(describing: error))"))
                }
                journaliserEnvoi(d)
            case .rouvrir(let n):
                note(n.texte)
                // Relance prevue a distance (toujours aucun hello), pas un echec de plus :
                // le nouvel essai part des la fermeture, le bandeau « nouvel essai toutes
                // les 30 s » reste vrai, et ces relances n'usent pas les 40 essais.
                if n == .reseauSansHello { essaisReconnexion = 0 }
                // Reseau : .ferme, transportFerme, puis reconnexion (nouvelle resolution du
                // nom, nouvelle poignee de main).
                transport?.fermer()
            case .redemarrage(let ancien, let nouveau):
                etat.viderDerives()
                let (av, ap) = (ancien ?? "?", nouveau ?? "?")
                note(tr("Redémarrage du pont détecté (boot \(av) → \(ap)) : états vidés."))
            case .note(let n):
                if n == .aucuneReponse, genreTransport == .udp {
                    alerteReseau = .sansHello
                    // Redite a chaque relance (nouvelle poignee de main toutes les 30 s) :
                    // notee une fois tant que la cause ne change pas.
                    noterCauseReseau(AlerteReseau.sansHello.texte, grave: true)
                } else {
                    note(n.texte, grave: n.grave)
                    if n.grave { alerte = n }
                }
            case .commandeSansReponse(let id):
                if creationCle?.id == id {
                    // `creationCle` reste arme : une reponse tardive doit encore etre rangee.
                    note(tr("Pas encore de réponse à la création de clé : une réponse tardive sera quand même rangée ; sinon l'accès réseau affichera « clé inconnue de ce Mac »."))
                }
                if let s = moteur.correlateur.suivi(id) {
                    let sansReponse = Self.texteSansReponse(moteur.correlateur.politique, commande: s.commande)
                    ajouterConsole(.retour(ok: false, session: s.origine == .session),
                                   tr("‹ id=\(String(s.numero ?? 0)) « \(s.commande) » : \(sansReponse)"),
                                   numero: s.numero)
                }
            case .ordrePerdu(let id):
                if let s = moteur.correlateur.suivi(id) {
                    ajouterConsole(.retour(ok: false, session: s.origine == .session),
                                   tr("‹ id=\(String(s.numero ?? 0)) « \(s.commande) » : aucune issue sous 10 s (ligne perdue ?)"),
                                   numero: s.numero)
                }
            case .proposerFermeture:
                propositionFermeture = true
            }
        }
        synchroniser()
    }

    private func journaliserEnvoi(_ d: Data) {
        let texte = String(decoding: d, as: UTF8.self).trimmingCharacters(in: .newlines)
        guard !texte.isEmpty, texte != "\u{15}" else { return }
        var numero: Int?
        var origine = OrigineCommande.session
        if texte.hasPrefix("id="), let espace = texte.firstIndex(of: " ") {
            numero = Int(texte[texte.index(texte.startIndex, offsetBy: 3)..<espace])
            if let n = numero, let s = moteur.correlateur.suivi(numero: n) { origine = s.origine }
        } else {
            origine = .console
        }
        ajouterConsole(.envoi(origine), "› " + texte, numero: numero)
    }

    func synchroniser() {
        if phase != moteur.phase {
            phase = moteur.phase
            if phase == .connecte {
                essaisReconnexion = 0
                // Session retablie : l'alerte d'un echec passe ne vaut plus, et une cause
                // reseau qui reviendrait ensuite sera notee de nouveau.
                alerte = nil
                alerteReseau = nil
                derniereCauseReseau = nil
            }
        }
        let r = etat.helloBase != nil ? moteur.reglages : nil
        if reglages != r { reglages = r }
        // Periode des compteurs a 0 (ou pas de session) : le dernier bloc n'est plus releve.
        if compteursEnDirect, (r?.compteursMs ?? 0) == 0 { compteursEnDirect = false }
        if suivis != moteur.correlateur.suivis { suivis = moteur.correlateur.suivis }
        if statistiques != moteur.statistiques { statistiques = moteur.statistiques }
        if reception != recepteur.compteurs { reception = recepteur.compteurs }
        confirmerPont()
        avancerChargement()
    }

    /// Toute ligne de la console passe par le masque des cles : texte recu,
    /// fragments, retours qui citent la commande, notes.
    private func ajouterConsole(_ genre: LigneConsole.Genre, _ texte: String, numero: Int? = nil) {
        console.ajouter(LigneConsole(id: prochainId(), date: Date(), genre: genre,
                                     texte: PolitiqueCommandes.masquerCle(texte), numero: numero))
    }

    /// Annonce de l'app dans la console.
    func note(_ texte: String, grave: Bool = false) {
        ajouterConsole(.note(grave: grave), texte)
    }

    /// Cause d'un arret ou d'une reprise reseau : un meme message n'est note qu'une
    /// fois dans la console tant que la cause ne change pas.
    private func noterCauseReseau(_ texte: String, grave: Bool) {
        guard derniereCauseReseau != texte else { return }
        derniereCauseReseau = texte
        note(texte, grave: grave)
    }

    /// Fin d'une commande sans reponse : par l'USB, 3 s sans renvoi ; a distance, le
    /// meme id renvoye avant le verdict (politique du correlateur), 6 s, ou 12 s pour une
    /// commande dont la `fin` suit un instantane (`json etat`, `json hello`, `json 1`).
    static func texteSansReponse(_ p: PolitiqueDelais, commande: String = "") -> String {
        let delai = Int(p.delaiReponse(pour: commande))
        return p.renvois > 0
            ? tr("sans réponse sous \(delai) s (\(p.renvois) renvois du même id)")
            : tr("sans réponse sous \(delai) s (pas de réémission)")
    }

    // MARK: - Commandes

    var peutCommander: Bool { phase.modeMachine && transport != nil }

    /// Source reseau ouverte : la liste blanche du pont s'applique (10.5).
    var aDistance: Bool { genreTransport == .udp }

    /// La commande peut partir par la source en vigueur (boutons des ecrans).
    func peutEnvoyer(_ commande: String) -> Bool {
        peutCommander && (!aDistance || PolitiqueCommandes.autoriseeADistance(commande) == nil)
    }

    /// La console envoie avec un `id` : session machine, ou `json 1` en attente de
    /// son `hello`. Sinon (ancien firmware, console texte...) : ligne brute. A distance,
    /// toujours avec un `id` (le pont ignore une ligne sans id).
    var consoleAvecId: Bool {
        if aDistance { return true }
        if phase.modeMachine { return true }
        if case .attenteHello = phase { return true }
        return false
    }

    /// Commande d'un bouton ou d'un curseur, avec `id` et correlation. `secret` : la
    /// commande porte des cles (jamais gardee ni affichee).
    @discardableResult
    func envoyer(_ commande: String, fusion: String? = nil, secret: Bool = false) -> UUID? {
        guard peutCommander else {
            note(tr("Pas de session machine : « \(PolitiqueCommandes.masquerCle(commande)) » n'est pas envoyée."))
            return nil
        }
        if aDistance, let raison = PolitiqueCommandes.autoriseeADistance(commande) {
            note(Self.texteNonEnvoyee(commande, raison: raison))
            return nil
        }
        let (id, effets) = moteur.soumettre(commande, origine: .interface, fusion: fusion, secret: secret,
                                            maintenant: maintenant())
        noterDemandeTrames(commande)
        executer(effets)
        return id
    }

    /// Curseurs : une commande toutes les 150 ms au plus pendant le glissement,
    /// toujours la valeur finale au relachement (6.4).
    func curseur(_ commande: String, cle: String, fini: Bool) {
        let t = maintenant()
        guard fini || t - (dernierCurseur[cle] ?? -1) >= 0.15 else { return }
        dernierCurseur[cle] = t
        envoyer(commande, fusion: cle)
    }

    /// Note d'une commande que la liste blanche du pont refuse : rien ne part. La raison
    /// du pont n'y est citee qu'une fois, telle quelle ; la commande, masquee.
    static func texteNonEnvoyee(_ commande: String, raison: String) -> String {
        let masquee = PolitiqueCommandes.masquerCle(commande.trimmingCharacters(in: .whitespaces))
        return tr("« \(masquee) » n'est pas envoyée : \(PolitiqueCommandes.refusDistant(raison)).")
    }

    /// Console brute : regles de 2.5, confirmations et interdits de 6.4.
    func console(_ ligne: String, confirme: Bool = false) -> ResultatConsole {
        switch PolitiqueCommandes.verdictConsole(ligne, transport: genreTransport ?? .usb) {
        case .interdite(let raison):
            if aDistance, let refus = PolitiqueCommandes.autoriseeADistance(ligne) {
                // Rien ne part : la console le dit aussi, la ligne tapee masquee.
                note(Self.texteNonEnvoyee(ligne, raison: refus))
            }
            return .refusee(raison)
        case .confirmation(let raison) where !confirme:
            return .confirmation(raison)
        default:
            break
        }
        guard let transport else { return .refusee(tr("Aucun pont connecté.")) }
        let propre = ligne.trimmingCharacters(in: .whitespaces)
        let secret = PolitiqueCommandes.masquerCle(propre) != propre
        if consoleAvecId {
            let (_, effets) = moteur.soumettre(propre, origine: .console, secret: secret, maintenant: maintenant())
            noterDemandeTrames(propre)
            executer(effets)
        } else {
            // Ancien firmware, console texte... : ligne brute, sans id.
            switch moteur.ligneBrute(propre) {
            case .success(let d):
                do { try transport.envoyer(d) } catch {
                    return .refusee(tr("Envoi impossible : \(String(describing: error))"))
                }
                journaliserEnvoi(d)
            case .failure(let e):
                return .refusee(e.description)
            }
        }
        if PolitiqueCommandes.attendReenumeration(propre) {
            note(tr("Attente de la ré-énumération USB (le pont redémarre)."))
        }
        return .envoyee
    }

    func rafraichir() { envoyer("json etat") }

    func viderConsole() { console.vider() }

    /// `json trames 1` ou `0` (7.6). Les reglages suivent la reponse du pont ; a
    /// distance, le pont les coupe seul au bout de 60 s.
    func activerTrames(_ actives: Bool) {
        envoyer("json trames \(actives ? 1 : 0)")
    }

    /// Flux `trame` demande (reglages de la session : `hello`, puis `json trames`).
    var tramesActives: Bool { reglages?.trames == true }

    /// Duree du flux des trames a distance : le pont le coupe seul (7.6).
    static let dureeTramesADistance: TimeInterval = 60

    /// A distance, le flux demande est coupe par le pont 60 s apres le dernier
    /// `json trames 1` : il ne le signale pas, l'app le deduit de l'horloge (un `hello`
    /// qui dirait `trames` faux ramene de toute facon `tramesActives` a faux).
    func tramesCoupeesParLePont(a maintenant: Date = Date()) -> Bool {
        guard aDistance, tramesActives, let d = tramesDemandeesLe else { return false }
        return maintenant.timeIntervalSince(d) >= Self.dureeTramesADistance
    }

    /// Secondes avant la coupure du flux a distance ; nil : pas de coupure a attendre
    /// (USB, flux non demande, ou deja coupe).
    func secondesAvantCoupureDesTrames(a maintenant: Date = Date()) -> Int? {
        guard aDistance, tramesActives, let d = tramesDemandeesLe, !tramesCoupeesParLePont(a: maintenant) else { return nil }
        return Int((Self.dureeTramesADistance - maintenant.timeIntervalSince(d)).rounded(.up))
    }

    /// `json trames 1` lu comme la console du pont le decoupe (`LigneCommande.argv`,
    /// sensible a la casse) : la ligne que le pont executera, guillemets ou echappements compris.
    private func noterDemandeTrames(_ commande: String) {
        let a = LigneCommande.argv(commande.trimmingCharacters(in: .whitespaces))
        if a == ["json", "trames", "1"] { tramesDemandeesLe = Date() }
    }

    /// Derniere trame recue (a distance, son absence dit que le pont a coupe le flux).
    var derniereTrame: Date? { trames.elements.last?.date }

    func viderTrames() { trames.vider() }

    func viderCourbes() { courbes.vider() }

    /// `json periode|lampes|compteurs|reseau <ms>`, ramenee dans les bornes du transport
    /// (a distance, celles de la liste blanche) : par exemple les `compteurs` des courbes
    /// Mesh, coupes par le profil distant.
    func reglerCadence(_ c: MoteurSession.Cadence, ms: Int) {
        envoyer(moteur.ligneCadence(c, ms: ms))
    }

    // MARK: - Lectures pour les ecrans

    var estDemo: Bool { source?.estDemo ?? false }

    /// Commande de la console du pont en cours (`reponse debut` recue, pas de `fin`).
    var commandeDeBanc: SuiviCommande? {
        suivis.last { $0.etat == .enCours }
    }
}
