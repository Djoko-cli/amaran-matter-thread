// Repris de Halo Compagnon (commit e114cd5) : sources, reconnexion, session, console.
// Par l'USB seulement (Thread au plan 3b-2) ; les gestes des lampes et des cles sont
// dans Pont+Lampes.swift et Pont+Cles.swift.
import AmaranProtocole
import AppKit
import Foundation
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

        var estDemo: Bool { self == .demo }
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
    /// Annonce grave (ancien firmware, aucune reponse...) montree en bandeau.
    private(set) var alerte: MoteurSession.Note?
    private(set) var derniereReception: Date?
    /// Commande de la console du pont de plus de 20 min : proposer de fermer le port.
    var propositionFermeture = false
    /// Numero de serie USB du dernier pont confirme (preferences) : "Pont amaran" dans les menus.
    private(set) var dernierPont: String?
    /// Reglages de session en vigueur ; nil avant le `hello`.
    private(set) var reglages: HelloBase.ReglagesSession?
    /// Facteur de temps du mode demo (1 : temps reel ; les tests accelerent).
    @ObservationIgnored var vitesseDemo: Double = 1

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
    @ObservationIgnored private var genreTransport: GenreTransport?
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
    @ObservationIgnored private var observateurReveil: (any NSObjectProtocol)?
    @ObservationIgnored private var observateurFin: (any NSObjectProtocol)?
    /// Session serie ouverte : pas de mise en sommeil de l'app (App Nap) qui
    /// retarderait le ping au-dela du bail de 30 s.
    @ObservationIgnored private var activite: (any NSObjectProtocol)?

    /// Delais de reouverture apres une fermeture : 300 ms, puis 1 s, 2 s, 5 s (3.1).
    static let delaisReconnexion: [Double] = [0.3, 1, 2, 5]

    init(trousseau: any TrousseauReseau = TrousseauSysteme(), trousseauDemo: any TrousseauReseau = TrousseauMemoire(ReseauDemo.reseau),
         preferences: UserDefaults = .standard) {
        self.trousseau = trousseau
        self.trousseauDemo = trousseauDemo
        self.preferences = preferences
        dernierPont = preferences.string(forKey: Self.cleDernierPont)
        ports = Self.portsVisibles(SurveillantUSB.lister())
        surveillant.changement = { [weak self] ports in self?.portsChanges(ports) }
        surveillant.demarrer()
        observateurReveil = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // Pause de lecture : la premiere ligne lue ensuite peut etre un fragment (2.4).
                self?.recepteur.signalerPause()
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

    /// Nom d'un port montre a l'utilisateur : le pont confirme, une autre carte Espressif
    /// (la C6 BenQ, par exemple), ou le nom court du port sans numero de serie.
    static func libellePort(_ port: PortUSB, dernierPont: String?) -> String {
        let court = port.chemin.replacingOccurrences(of: "/dev/cu.", with: "")
        guard let serie = port.serie, !serie.isEmpty else { return court }
        let fin = "…" + serie.suffix(5)
        if serie == dernierPont { return "Pont amaran (\(fin))" }
        return port.estEspressif ? "Autre carte Espressif (\(fin))" : court
    }

    /// Nom montre pour le port d'une source serie : celui du port branche s'il l'est encore.
    func libelleSource(chemin: String, serie: String?) -> String {
        if let p = Self.portDuPont(ports, chemin: chemin, serie: serie) { return Self.libellePort(p, dernierPont: dernierPont) }
        return chemin.replacingOccurrences(of: "/dev/cu.", with: "")
    }

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
        } else {
            fermerTransport()
        }
        source = s
        alerte = nil
        reconnexionAuto = true
        essaisReconnexion = 0
        if changement, let nom = nomSource {
            note("Nouvelle source : \(nom). États et console remis à zéro.")
        }
        rafraichirCopie()
        ouvrir()
    }

    func deconnecter() {
        reconnexionAuto = false
        fermerProprement()
        etatTransport = .ferme
    }

    /// "Liberer le port" (3.1) : `json 0`, fermeture, pas de reouverture avant un clic.
    func libererPort() {
        reconnexionAuto = false
        let modeMachine = rendModeTexte
        fermerProprement()
        etatTransport = .libere
        note(modeMachine
             ? "Port libéré : json 0 envoyé, port fermé. Flasher est possible ; « Reconnecter » pour reprendre."
             : "Port libéré : port fermé. Flasher est possible ; « Reconnecter » pour reprendre.")
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
        dernierCurseur = [:]
        propositionFermeture = false
        derniereReception = nil
        interrompreChargement("source changée")
        synchroniser()
    }

    private var nomSource: String? {
        switch source {
        case .serie(let chemin, let serie): libelleSource(chemin: chemin, serie: serie)
        case .demo: "démo"
        case nil: nil
        }
    }

    func reconnecter() {
        guard source != nil else { return }
        reconnexionAuto = true
        essaisReconnexion = 0
        alerte = nil
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
            if demo == nil { demo = TransportDemo(vitesse: vitesseDemo) }
            t = demo!
        case .serie(let chemin, let serie):
            // Le meme pont (meme numero de serie USB) peut revenir sous un autre nom ;
            // jamais un autre appareil, meme sous le nom d'avant.
            guard let port = Self.portDuPont(ports, chemin: chemin, serie: serie) else {
                echecOuverture(ErreurTransport("Pont absent : aucune carte Espressif reconnue"))
                return
            }
            t = TransportSerie(chemin: port.chemin)
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
                var raison = "flux terminé"
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
    }

    private func debutActivite() {
        guard activite == nil else { return }
        activite = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                         reason: "Session série du pont amaran : ping du bail")
    }

    private func finActivite() {
        guard let a = activite else { return }
        ProcessInfo.processInfo.endActivity(a)
        activite = nil
    }

    private func transportOuvert() {
        etatTransport = .ouvert
        debutActivite()
        recepteur.resynchroniser()
        note(genreTransport == .demo ? "Pont de démonstration ouvert." : "Port ouvert : \(nomTransport) (DTR = RTS = 0).")
        executer(moteur.ouvert(maintenant: maintenant()))
    }

    private func transportFerme(_ raison: String) {
        transport = nil
        finActivite()
        moteur.ferme(maintenant: maintenant())
        synchroniser()
        note("Transport fermé : \(raison)")
        if reconnexionAuto { planifierReconnexion(raison) } else { etatTransport = .ferme }
    }

    func echecOuverture(_ erreur: any Error) {
        transport = nil
        let texte = String(describing: erreur)
        if reconnexionAuto, essaisReconnexion < 40 {
            planifierReconnexion(texte)
        } else if reconnexionAuto {
            // Plus d'essais minutes (~3 min), mais le retour du port (IOKit) rouvre encore.
            etatTransport = .erreur("\(texte) — en attente du retour du port")
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
            planifierReconnexion("port revenu")
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

    private func traiter(_ element: ElementRecu) {
        let effets = moteur.recu(element, maintenant: maintenant())
        let historique = moteur.historique
        // Un redemarrage vide les etats derives AVANT d'appliquer la ligne qui l'a revele
        // (le hello du nouveau demarrage doit rester).
        let (redemarrages, autres) = effets.reduce(into: ([MoteurSession.Effet](), [MoteurSession.Effet]())) { r, e in
            if case .redemarrage = e { r.0.append(e) } else { r.1.append(e) }
        }
        executer(redemarrages)
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
            rejets.ajouter(Rejet(id: prochainId(), date: Date(), raison: "abîmée : \(raison)",
                                  brut: PolitiqueCommandes.masquerCle(brut)))
        case .versionInconnue(let v, let t):
            rejets.ajouter(Rejet(id: prochainId(), date: Date(), raison: "version \(v) inconnue",
                                  brut: PolitiqueCommandes.masquerCle(t)))
        case .invalide(let t, let raison):
            rejets.ajouter(Rejet(id: prochainId(), date: Date(), raison: "\(t) invalide : \(raison)", brut: ""))
        case .debordement(let s):
            ajouterConsole(.texte(.commande), s)
        }
        executer(autres)
    }

    private func traiterMachine(_ l: LigneMachine, historique: Bool) {
        if !historique { etat.appliquer(l, recueA: Date()) }
        switch l.message {
        case .ordre(let o):
            for id in o.ids ?? [] {
                guard let s = moteur.correlateur.suivi(numero: id) else { continue }
                ajouterConsole(.retour(ok: o.issue != .abandon, session: s.origine == .session),
                               "‹ id=\(id) « \(s.commande) » : \(Interpretation.ordre(o))", numero: id)
            }
        case .reponse(let r):
            let s = moteur.correlateur.suivi(numero: r.id)
            ajouterConsole(.retour(ok: r.ok, session: (s?.origine ?? .session) == .session),
                           "‹ " + Interpretation.reponse(r), numero: r.id)
        case .log(let lg):
            ajouterConsole(.log, lg.txt ?? "")
        case .lampe(let e):
            let quoi = switch e.quoi {
            case .entree: "entre dans Maison (EP\(e.endpoint ?? 0))"
            case .masquee: "retirée de Maison"
            case .remise: "remise dans Maison (EP\(e.endpoint ?? 0))"
            case .echec: "endpoint Matter non créé"
            case .inconnu, nil: "changement inconnu"
            }
            note("Lampe \(e.lampe) : \(quoi).")
        case .alerte(let a):
            switch a.quoi {
            case .releves:
                note(a.manque == true
                     ? "Lampe \(a.lampe ?? 0) : relectures manquées, \(a.part ?? 0) % répondues sur 10 min."
                     : "Lampe \(a.lampe ?? 0) : relectures de nouveau répondues (\(a.part ?? 0) %).",
                     grave: a.manque == true)
            case .mesh:
                note("Bluetooth Mesh : \(Interpretation.diag(a.diag)).", grave: a.diag != .ok)
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
                    note("Envoi impossible : \(String(describing: error))")
                }
                journaliserEnvoi(d)
            case .rouvrir(let n):
                note(n.texte)
                transport?.fermer()
            case .redemarrage(let ancien, let nouveau):
                etat.viderDerives()
                note("Redémarrage du pont détecté (boot \(ancien ?? "?") → \(nouveau ?? "?")) : états vidés.")
            case .note(let n):
                note(n.texte, grave: n.grave)
                if n.grave { alerte = n }
            case .commandeSansReponse(let id):
                if let s = moteur.correlateur.suivi(id) {
                    ajouterConsole(.retour(ok: false, session: s.origine == .session),
                                   "‹ id=\(s.numero ?? 0) « \(s.commande) » : sans réponse sous 3 s (pas de réémission)",
                                   numero: s.numero)
                }
            case .ordrePerdu(let id):
                if let s = moteur.correlateur.suivi(id) {
                    ajouterConsole(.retour(ok: false, session: s.origine == .session),
                                   "‹ id=\(s.numero ?? 0) « \(s.commande) » : aucune issue sous 10 s (ligne perdue ?)",
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
                // Session retablie : l'alerte d'un echec passe ne vaut plus.
                alerte = nil
            }
        }
        let r = etat.helloBase != nil ? moteur.reglages : nil
        if reglages != r { reglages = r }
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

    // MARK: - Commandes

    var peutCommander: Bool { phase.modeMachine && transport != nil }

    /// La console envoie avec un `id` : session machine, ou `json 1` en attente de
    /// son `hello`. Sinon (ancien firmware, console texte...) : ligne brute.
    var consoleAvecId: Bool {
        if phase.modeMachine { return true }
        if case .attenteHello = phase { return true }
        return false
    }

    /// Commande d'un bouton ou d'un curseur, avec `id` et correlation. `secret` : la
    /// commande porte des cles (jamais gardee ni affichee).
    @discardableResult
    func envoyer(_ commande: String, fusion: String? = nil, secret: Bool = false) -> UUID? {
        guard peutCommander else {
            note("Pas de session machine : « \(PolitiqueCommandes.masquerCle(commande)) » n'est pas envoyée.")
            return nil
        }
        let (id, effets) = moteur.soumettre(commande, origine: .interface, fusion: fusion, secret: secret,
                                            maintenant: maintenant())
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

    /// Console brute : regles de 2.5, confirmations et interdits de 6.4.
    func console(_ ligne: String, confirme: Bool = false) -> ResultatConsole {
        switch PolitiqueCommandes.verdictConsole(ligne) {
        case .interdite(let raison):
            return .refusee(raison)
        case .confirmation(let raison) where !confirme:
            return .confirmation(raison)
        default:
            break
        }
        guard let transport else { return .refusee("Aucun pont connecté.") }
        let propre = ligne.trimmingCharacters(in: .whitespaces)
        let secret = PolitiqueCommandes.masquerCle(propre) != propre
        if consoleAvecId {
            let (_, effets) = moteur.soumettre(propre, origine: .console, secret: secret, maintenant: maintenant())
            executer(effets)
        } else {
            // Ancien firmware, console texte... : ligne brute, sans id.
            switch moteur.ligneBrute(propre) {
            case .success(let d):
                do { try transport.envoyer(d) } catch {
                    return .refusee("Envoi impossible : \(String(describing: error))")
                }
                journaliserEnvoi(d)
            case .failure(let e):
                return .refusee(e.description)
            }
        }
        if PolitiqueCommandes.attendReenumeration(propre) {
            note("Attente de la ré-énumération USB (le pont redémarre).")
        }
        return .envoyee
    }

    func rafraichir() { envoyer("json etat") }

    func viderConsole() { console.vider() }

    // MARK: - Lectures pour les ecrans

    var estDemo: Bool { source?.estDemo ?? false }

    /// Commande de la console du pont en cours (`reponse debut` recue, pas de `fin`).
    var commandeDeBanc: SuiviCommande? {
        suivis.last { $0.etat == .enCours }
    }
}
