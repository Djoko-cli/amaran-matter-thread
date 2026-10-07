// Repris de Halo Compagnon (commit e114cd5) : par l'USB et par Thread (cas UDP de Halo),
// avec les blocs et l'evenement ordre du pont amaran (docs/PROTOCOLE-JSON.md 3, 6 et 10).
import Foundation

/// Compteurs de sante du lien, cote app.
public struct StatistiquesLien: Sendable, Equatable {
    /// Lignes perdues d'apres les trous de `n` (2.4).
    public var pertes = 0
    /// `n` qui recule sans changement de `boot` (lignes anciennes).
    public var reculs = 0
    public var redemarrages = 0
    public var sansReponse = 0
    public var silences = 0
    public var reouvertures = 0
    public var connexions = 0

    public init() {}
}

/// Machine d'etat de la session (section 3), independante du transport.
///
/// Code pur : chaque entree renvoie des effets que l'appelant execute
/// (envoyer des octets, rouvrir le transport...). Le temps est passe en
/// argument (secondes d'une horloge monotone), ce qui la rend testable.
public struct MoteurSession: Sendable {
    public struct Parametres: Sendable, Equatable {
        /// Sans `hello` 2 s apres `json 1` : renvoyer...
        public var delaiHello: TimeInterval = 2
        /// ... 3 fois.
        public var renvoisHello = 3
        /// Puis `\x15\n` et `json 1` toutes les 30 s, pas plus souvent. A
        /// distance, une nouvelle poignee de main a la place (voir `tic`).
        public var relanceLente: TimeInterval = 30
        /// `json ping` apres 10 s sans autre commande (bail de 30 s) ; plus tot
        /// si le bail est plus court (`json 1 bail 10` : au tiers du bail).
        public var pingApres: TimeInterval = 10
        /// Reponse `fin` au `json 1` attendue au plus 3 s apres le `hello`
        /// (un instantane a 16 lampes part en moins d'une demi-seconde) ; au-dela
        /// elle est tenue pour perdue et la file repart.
        public var delaiFinJson1: TimeInterval = 3
        /// A distance : l'instantane de `json 1` (42 lignes, ~11 Ko a 16 lampes) passe a
        /// 3 000 octets par seconde au plus sur Thread, partages entre deux sessions
        /// (10.3) : 3,6 s seul, un peu plus de 8 s a deux ; sa `fin` est attendue 12 s,
        /// comme celle de `json etat` et `json hello` (`PolitiqueDelais.delaiInstantane`).
        public var delaiFinJson1Reseau: TimeInterval = PolitiqueDelais.reseau.delaiInstantane
        /// Bail demande a distance (`json 1 bail <s>`, 10 a 120 s permis, 10.5) : plus
        /// long que par l'USB, Thread perd des datagrammes ; le ping part au plus tard
        /// toutes les 10 s.
        public var bailDistantS = 60
        /// Silence : aucune ligne depuis 3 x max(periode, 2 s).
        public var facteurSilence: Double = 3
        public var silenceMin: TimeInterval = 2
        /// Sans `hello` sous 5 s apres le `json 1` du silence : rouvrir le port.
        public var delaiResynchro: TimeInterval = 5
        /// Commande de la console du pont de plus de 20 min : proposer de fermer le port.
        public var bancLong: TimeInterval = 20 * 60

        public init() {}
    }

    public enum Phase: Sendable, Equatable {
        case ferme
        /// `json 1` envoye, `hello` attendu (essai 1 a 4).
        case attenteHello(essai: Int)
        /// Mode machine etabli.
        case connecte
        /// Silence du pont : `json 1` renvoye, `hello` attendu sous 5 s.
        case resynchro
        /// `Unrecognized command` : firmware sans mode JSON.
        case ancienFirmware
        /// Aucune reponse : ecoute, `json 1` toutes les 30 s (a distance :
        /// nouvelle poignee de main toutes les 30 s).
        case sansReponse
        /// `hello` d'une version majeure non geree : console seule.
        case versionInconnue(Int)
        /// `json 0` : le pont est revenu a la console texte.
        case modeHumain

        /// Les commandes portent un `id` et suivent la correlation.
        public var modeMachine: Bool {
            switch self {
            case .connecte, .resynchro: true
            default: false
            }
        }
    }

    /// Annonce de la session a l'utilisateur.
    public enum Note: Sendable, Equatable {
        /// `Unrecognized command` (grave).
        case ancienFirmware
        /// Banniere de demarrage recue en texte.
        case texteDemarrage
        /// `hello` d'une version majeure non geree (grave).
        case versionInconnue(Int)
        /// Aucun `hello` apres les renvois de `json 1` (grave).
        case aucuneReponse
        case reponseJson1Perdue
        /// Silence du pont depuis tant de secondes : `json 1` renvoye.
        case silence(secondes: Int)
        /// Pas de `hello` sous 5 s apres le `json 1` du silence : le port est rouvert.
        case resynchroSansReponse
        /// `fin` `bail` : `json 1` renvoye.
        case bailEchu
        /// A distance, toujours aucun `hello` (relance de 30 s ou "Reessayer") :
        /// nouvelle poignee de main. Le pont a oublie la session H1 provisoire (30 s
        /// sans premier message, 10.3) : un `json 1` scelle pour elle serait ecarte
        /// sans bruit.
        case reseauSansHello

        /// Montree en bandeau (echec de la connexion).
        public var grave: Bool {
            switch self {
            case .ancienFirmware, .versionInconnue, .aucuneReponse: true
            default: false
            }
        }

        public var texte: String {
            switch self {
            case .ancienFirmware:
                tr("Firmware sans mode JSON : flasher un firmware du pont avec le mode JSON. L'app reste en console seule.")
            case .texteDemarrage:
                tr("Texte de démarrage reçu : le pont a peut-être redémarré.")
            case .versionInconnue(let v):
                tr("Protocole v\(String(v)) non géré par cette app (v1) : console seule.")
            case .aucuneReponse:
                tr("Aucune réponse : mauvais port, pont en mode téléchargement, ou commande longue en cours ? Nouvel essai toutes les 30 s.")
            case .reponseJson1Perdue:
                tr("Réponse au json 1 perdue : les commandes reprennent.")
            case .silence(let s):
                tr("Silence du pont depuis \(s) s : json 1 renvoyé.")
            case .resynchroSansReponse:
                tr("Pas de réponse à json 1 sous 5 s : fermeture et réouverture du port.")
            case .bailEchu:
                tr("Le pont a quitté le mode machine (bail échu) : json 1 renvoyé.")
            case .reseauSansHello:
                tr("Aucune réponse au json 1 par le réseau : nouvelle poignée de main.")
            }
        }
    }

    public enum Effet: Sendable, Equatable {
        case envoyer(Data)
        /// Fermer puis rouvrir le transport.
        case rouvrir(Note)
        /// Redemarrage du pont : vider les etats derives.
        case redemarrage(ancien: String?, nouveau: String?)
        case note(Note)
        case commandeSansReponse(UUID)
        /// Ordre accepte sans evenement `ordre` sous 10 s.
        case ordrePerdu(UUID)
        /// Commande de la console du pont de plus de 20 min.
        case proposerFermeture
    }

    public var parametres = Parametres()
    /// Transport de la connexion en cours (regles du reseau, 10.4).
    public private(set) var genre: GenreTransport = .usb
    public private(set) var phase: Phase = .ferme
    public private(set) var correlateur = Correlateur()
    public private(set) var statistiques = StatistiquesLien()
    /// Reglages de session en vigueur : ceux du `hello`, puis ceux des
    /// commandes `json periode|lampes|compteurs|reseau|log|trames` acceptees (3.3).
    /// Valeurs par defaut de `json 1` (profil USB ou distant) tant qu'aucun `hello`
    /// n'est arrive.
    public private(set) var reglages = Self.reglagesParDefaut(.usb, bailDistantS: 60)
    public var periodeMs: Int { reglages.periodeMs ?? 1000 }
    public var bailS: Int? { reglages.bailS }
    public private(set) var boot: String?
    public private(set) var dernierUpS: Int?
    /// Vrai tant que le `hello` de cette connexion n'est pas arrive : les
    /// lignes recues sont des lignes anciennes, restees dans le tampon (3.1).
    public private(set) var historique = true
    /// `json 1` envoye, sa `reponse fin` pas encore recue : aucune commande
    /// de la file ne part avant (une seule commande en vol, 6.5).
    public var instantaneEnCours: Bool { json1 != nil }

    /// `json 1` en attente de sa `reponse` `fin` ; `repondu` : une `fin` est arrivee
    /// sans le `hello` de cette tentative, ou `deja_traite` (reponse oubliee) : le renvoi
    /// prend alors un id neuf.
    private var json1: (numero: Int, envoyeA: TimeInterval, repondu: Bool)?
    private var dernierEssaiA: TimeInterval = 0
    private var dernierRecuA: TimeInterval = 0
    private var ouvertA: TimeInterval = 0
    private var resynchroDepuis: TimeInterval?
    private var dernierN: UInt32?
    private var bancSignale = false

    public init() {}

    // MARK: - Entrees

    /// Reglages qu'annonce `json 1` (3.3) : profil de l'USB, ou profil distant (10.5).
    public static func reglagesParDefaut(_ genre: GenreTransport, bailDistantS: Int) -> HelloBase.ReglagesSession {
        genre == .udp
            ? HelloBase.ReglagesSession(transport: .udp, periodeMs: 2000, lampesMs: 30000, compteursMs: 0, reseauMs: 30000,
                                        bailS: bailDistantS, log: false, trames: false)
            : HelloBase.ReglagesSession(transport: .usb, periodeMs: 1000, lampesMs: 10000, compteursMs: 1000,
                                        reseauMs: 5000, bailS: 30, log: false, trames: false)
    }

    /// Transport ouvert : `\x15\n` puis `id=1 json 1` (3.2). A distance, pas de
    /// Ctrl-U (pas de ligne en cours a effacer ; le pont ignore une ligne sans id),
    /// la politique reseau du correlateur, et un bail permis a distance.
    public mutating func ouvert(maintenant: TimeInterval, genre: GenreTransport = .usb) -> [Effet] {
        self.genre = genre
        correlateur.politique = .pour(genre)
        reglages = Self.reglagesParDefaut(genre, bailDistantS: parametres.bailDistantS)
        correlateur.reinitialiser(maintenant: maintenant)
        statistiques.connexions += 1
        phase = .attenteHello(essai: 1)
        historique = true
        dernierN = nil
        ouvertA = maintenant
        dernierRecuA = maintenant
        resynchroDepuis = nil
        bancSignale = false
        return effacement + envoyerJson1(maintenant: maintenant)
    }

    private var effacement: [Effet] { genre == .udp ? [] : [.envoyer(LigneCommande.effacement)] }

    /// Transport ferme (cable, re-enumeration, liberation du port).
    public mutating func ferme(maintenant: TimeInterval) {
        correlateur.reinitialiser(maintenant: maintenant)
        phase = .ferme
        json1 = nil
        resynchroDepuis = nil
    }

    public mutating func soumettre(_ commande: String, origine: OrigineCommande, fusion: String? = nil,
                                   secret: Bool = false, maintenant: TimeInterval) -> (UUID, [Effet]) {
        let id = correlateur.soumettre(commande, origine: origine, fusion: fusion, secret: secret, maintenant: maintenant)
        return (id, pomper(maintenant: maintenant))
    }

    /// Hors mode machine (ancien firmware, mode humain...) : ligne brute, sans `id`.
    public func ligneBrute(_ commande: String) -> Result<Data, ErreurLigne> {
        LigneCommande.octets(commande, id: nil)
    }

    /// "Liberer le port" : `json 0`, puis l'appelant ferme sans rouvrir (3.1).
    public mutating func liberer(maintenant: TimeInterval) -> [Effet] {
        var effets: [Effet] = []
        if phase != .ferme {
            let n = correlateur.reserverNumero()
            effets.append(.envoyer(Data("id=\(n) json 0\n".utf8)))
        }
        ferme(maintenant: maintenant)
        return effets
    }

    /// Relance manuelle apres un echec (firmware flashe depuis, bouton "Reessayer").
    /// A distance : nouvelle poignee de main, comme la relance de 30 s.
    public mutating func reessayer(maintenant: TimeInterval) -> [Effet] {
        guard phase != .ferme else { return [] }
        if genre == .udp { return rouvrirADistance(maintenant: maintenant) }
        phase = .attenteHello(essai: 1)
        return effacement + envoyerJson1(maintenant: maintenant)
    }

    public mutating func recu(_ element: ElementRecu, maintenant: TimeInterval) -> [Effet] {
        dernierRecuA = maintenant
        var effets: [Effet] = []
        switch element {
        case .texte(let t):
            if ClasseurTexte.estRefusIdAncienFirmware(t.texte), !phase.modeMachine, phase != .ancienFirmware {
                phase = .ancienFirmware
                json1 = nil
                correlateur.reinitialiser(maintenant: maintenant)
                effets.append(.note(.ancienFirmware))
            } else if t.classe == .commande || t.classe == .annonce {
                correlateur.texte(t.texte)
            }
            if t.classe == .demarrage {
                effets.append(.note(.texteDemarrage))
            }
        case .machine(let l):
            continuite(l.enveloppe.n)
            effets += traiter(l, maintenant: maintenant)
        case .versionInconnue(let v, let t) where t == "hello":
            phase = .versionInconnue(v)
            json1 = nil
            correlateur.reinitialiser(maintenant: maintenant)
            effets.append(.note(.versionInconnue(v)))
        default:
            break
        }
        return effets + pomper(maintenant: maintenant)
    }

    public mutating func tic(maintenant: TimeInterval) -> [Effet] {
        var effets: [Effet] = []
        switch phase {
        case .attenteHello(let essai):
            if let j = json1, maintenant - j.envoyeA >= parametres.delaiHello {
                if essai <= parametres.renvoisHello {
                    phase = .attenteHello(essai: essai + 1)
                    effets += envoyerJson1(maintenant: maintenant, renvoi: true)
                } else {
                    phase = .sansReponse
                    json1 = nil
                    // Pas de session : ce qui attendait en file ne partira pas plus tard, a l'insu.
                    correlateur.reinitialiser(maintenant: maintenant)
                    statistiques.sansReponse += 1
                    effets.append(.note(.aucuneReponse))
                }
            }
        case .sansReponse:
            if maintenant - dernierEssaiA >= parametres.relanceLente {
                if genre == .udp {
                    effets += rouvrirADistance(maintenant: maintenant)
                } else {
                    effets += effacement
                    effets += envoyerJson1(maintenant: maintenant)
                }
            }
        case .connecte:
            let delaiFin = genre == .udp ? parametres.delaiFinJson1Reseau : parametres.delaiFinJson1
            if let j = json1, maintenant - j.envoyeA >= delaiFin {
                // hello recu mais pas la reponse fin (ligne perdue ou abimee) : la file repart.
                json1 = nil
                statistiques.sansReponse += 1
                effets.append(.note(.reponseJson1Perdue))
            }
            let limite = parametres.facteurSilence * max(Double(periodeMs) / 1000, parametres.silenceMin)
            if correlateur.commandeDeBanc == nil, maintenant - dernierRecuA >= limite {
                phase = .resynchro
                resynchroDepuis = maintenant
                statistiques.silences += 1
                effets.append(.note(.silence(secondes: Int(limite))))
                correlateur.perdreEnVol(maintenant: maintenant)
                effets += envoyerJson1(maintenant: maintenant)
            }
        case .resynchro:
            if let d = resynchroDepuis, maintenant - d >= parametres.delaiResynchro {
                resynchroDepuis = nil
                statistiques.reouvertures += 1
                effets.append(.rouvrir(.resynchroSansReponse))
            }
        default:
            break
        }

        if phase.modeMachine {
            for d in correlateur.renvoisDus(maintenant: maintenant) { effets.append(.envoyer(d)) }
            for s in correlateur.verifierOrdres(maintenant: maintenant) { effets.append(.ordrePerdu(s.id)) }
            for s in correlateur.verifierDelais(maintenant: maintenant) {
                statistiques.sansReponse += 1
                effets.append(.commandeSansReponse(s.id))
                if s.origine != .session {
                    correlateur.soumettre("json etat", origine: .session, maintenant: maintenant)
                }
            }
            if let banc = correlateur.commandeDeBanc, let d = banc.debutA {
                if maintenant - d >= parametres.bancLong, !bancSignale {
                    bancSignale = true
                    effets.append(.proposerFermeture)
                }
            } else {
                bancSignale = false
            }
            if phase == .connecte, json1 == nil, !correlateur.occupe,
               maintenant - (correlateur.dernierEnvoiA ?? ouvertA) >= intervallePing {
                correlateur.soumettre("json ping", origine: .session, maintenant: maintenant)
            }
        }
        return effets + pomper(maintenant: maintenant)
    }

    // MARK: - Interne

    /// Ping au plus tard au tiers du bail : `json 1 bail 10` (permis depuis la
    /// console) laisserait sinon le ping de 10 s perdre la course (3.5).
    var intervallePing: TimeInterval {
        guard let b = bailS, b > 0 else { return parametres.pingApres }
        return min(parametres.pingApres, Double(b) / 3)
    }

    /// Ligne `json 1` : par l'USB, le bail par defaut (30 s) ; a distance, `json 1
    /// bail <bailDistantS>`, ramene dans les bornes permises (10 a 120 s, 10.5).
    public var ligneJson1: String {
        genre == .udp ? "json 1 bail \(min(max(parametres.bailDistantS, 10), 120))" : "json 1"
    }

    /// `json 1`, idempotent : par l'USB, chaque renvoi a son propre `id`. A distance,
    /// un renvoi garde son `id` (10.4) : si le premier est arrive, le pont ne refait
    /// pas l'instantane (il ignore le renvoi tant qu'il l'envoie, puis rend sa
    /// reponse gardee) ; mais un `json 1` dont la `fin` est arrivee sans `hello`
    /// (hello perdu), ou dont la reponse est oubliee (`deja_traite`), repart avec un
    /// id neuf, pour un nouvel instantane.
    private mutating func envoyerJson1(maintenant: TimeInterval, renvoi: Bool = false) -> [Effet] {
        let n: Int
        if renvoi, genre == .udp, let j = json1, !j.repondu { n = j.numero } else { n = correlateur.reserverNumero() }
        json1 = (n, maintenant, false)
        dernierEssaiA = maintenant
        correlateur.noterEnvoiHorsFile(maintenant: maintenant)
        return [.envoyer(Data("id=\(n) \(ligneJson1)\n".utf8))]
    }

    /// A distance, relancer c'est refaire la poignee de main : le pont oublie la
    /// session H1 provisoire 30 s apres son SALUT (10.3). `dernierEssaiA` repousse la
    /// relance suivante : pas de second `.rouvrir` avant que la fermeture ne remette
    /// le moteur a `.ferme` (puis `ouvert` au transport suivant).
    private mutating func rouvrirADistance(maintenant: TimeInterval) -> [Effet] {
        dernierEssaiA = maintenant
        statistiques.reouvertures += 1
        return [.rouvrir(.reseauSansHello)]
    }

    private mutating func pomper(maintenant: TimeInterval) -> [Effet] {
        guard phase == .connecte, json1 == nil, let e = correlateur.prochainEnvoi(maintenant: maintenant)
        else { return [] }
        return [.envoyer(e.octets)]
    }

    /// Controle de continuite de `n` (2.4).
    private mutating func continuite(_ n: UInt32) {
        defer { dernierN = n }
        guard let d = dernierN else { return }
        let attendu = d &+ 1
        let ecart = n &- attendu
        if ecart == 0 { return }
        if ecart < 0x8000_0000 {
            statistiques.pertes += Int(ecart)
        } else {
            statistiques.reculs += 1
        }
    }

    /// Redemarrage : `boot` change, ou `up_s` recule (3.5).
    private mutating func verifierDemarrage(boot b: String?, upS: Int?) -> Effet? {
        var redemarre = false
        let ancien = boot
        if let b {
            if let ancien, ancien != b { redemarre = true }
            boot = b
        }
        if let u = upS {
            if !redemarre, let d = dernierUpS, u < d { redemarre = true }
            dernierUpS = u
        }
        guard redemarre else { return nil }
        statistiques.redemarrages += 1
        // Le pont a oublie la commande en vol et ses ordres en cours.
        correlateur.perdreEnVol(maintenant: dernierRecuA, redemarrage: true)
        return .redemarrage(ancien: ancien, nouveau: boot)
    }

    private mutating func traiter(_ l: LigneMachine, maintenant: TimeInterval) -> [Effet] {
        var effets: [Effet] = []
        switch l.message {
        case .helloBase(let h):
            if let e = verifierDemarrage(boot: h.boot, upS: h.upS) { effets.append(e) }
            if let s = h.session { adopterReglages(s) }
            recevoirHello(maintenant: maintenant)
        case .helloIdentite(let h):
            if let e = verifierDemarrage(boot: h.boot, upS: nil) { effets.append(e) }
            recevoirHello(maintenant: maintenant)
        case .etatPont(let b):
            effets += demarrageHorsHello(boot: b.boot, upS: b.upS, maintenant: maintenant)
        case .etatSante(let b):
            correlateur.periodiqueRecu(commande: b.commande, maintenant: maintenant)
            effets += demarrageHorsHello(boot: b.boot, upS: b.upS, maintenant: maintenant)
        case .battement(let b):
            correlateur.periodiqueRecu(commande: b.commande, maintenant: maintenant)
            effets += demarrageHorsHello(boot: b.boot, upS: b.upS, maintenant: maintenant)
        case .reponse(let r):
            if let b = r.bailS { reglages.bailS = b }
            if let j = json1, r.id == j.numero {
                // La session ne s'etablit qu'avec le hello de cette tentative : une
                // reponse sans hello (hello perdu, coupe par un log, ok:false,
                // cadence) laisse json1 pose et le minuteur renvoie json 1
                // (idempotent ; a distance, avec un id neuf). Apres le hello, la reponse
                // fin libere la file. `deja_traite` (10.4) est une fin comme les autres :
                // la reponse est oubliee, aucune autre ne viendra pour cet id.
                if r.etape == .fin {
                    if phase == .connecte { json1 = nil } else { json1?.repondu = true }
                }
            } else if case .fin(let id, _) = correlateur.recevoir(r, maintenant: maintenant) {
                if r.ok, let s = correlateur.suivi(id) { appliquerReglage(s.commande) }
                // A distance, `deja_traite` : le pont a oublie la reponse (10.4), l'etat a
                // pu changer sans que l'app le sache : instantane, comme Halo.
                if r.code == .dejaTraite { correlateur.soumettre("json etat", origine: .session, maintenant: maintenant) }
            }
        case .texte(let t):
            correlateur.texte(t.txt ?? "", id: t.id, maintenant: maintenant)
        case .ordre(let o):
            correlateur.recevoir(o, maintenant: maintenant)
        case .fin(let f):
            if f.cause == .bail, phase.modeMachine {
                effets.append(.note(.bailEchu))
                historique = true
                phase = .attenteHello(essai: 1)
                correlateur.perdreEnVol(maintenant: maintenant)
                effets += envoyerJson1(maintenant: maintenant)
            } else if f.cause == .commande {
                phase = .modeHumain
                json1 = nil
            }
        default:
            break
        }
        return effets
    }

    private mutating func recevoirHello(maintenant: TimeInterval) {
        historique = false
        switch phase {
        case .attenteHello, .resynchro, .sansReponse, .ancienFirmware, .modeHumain:
            phase = .connecte
            resynchroDepuis = nil
        default:
            break
        }
    }

    /// Redemarrage vu hors `hello` (etat, hb) : le mode machine est retombe,
    /// renvoyer `json 1` (3.5).
    private mutating func demarrageHorsHello(boot b: String?, upS: Int?, maintenant: TimeInterval) -> [Effet] {
        guard let e = verifierDemarrage(boot: b, upS: upS) else { return [] }
        guard phase.modeMachine else { return [e] }
        historique = true
        phase = .attenteHello(essai: 1)
        return [e] + envoyerJson1(maintenant: maintenant)
    }

    /// Reglages annonces par un `hello` (les champs absents gardent leur valeur).
    private mutating func adopterReglages(_ s: HelloBase.ReglagesSession) {
        if let v = s.transport { reglages.transport = v }
        if let v = s.periodeMs { reglages.periodeMs = v }
        if let v = s.lampesMs { reglages.lampesMs = v }
        if let v = s.compteursMs { reglages.compteursMs = v }
        if let v = s.reseauMs { reglages.reseauMs = v }
        if let v = s.bailS { reglages.bailS = v }
        if let v = s.log { reglages.log = v }
        if let v = s.trames { reglages.trames = v }
    }

    /// `json periode|lampes|compteurs|reseau <ms>`, `json log|trames 0|1` acceptes (y
    /// compris tapes dans la console) : les reglages suivent, et le seuil de
    /// silence avec la periode. La commande est lue comme la console du pont la
    /// decoupe (`LigneCommande.argv`, sensible a la casse) : `js\xon compteurs 5000`,
    /// que le pont execute comme `json compteurs 5000`, regle bien les compteurs.
    private mutating func appliquerReglage(_ commande: String) {
        let a = LigneCommande.argv(commande.trimmingCharacters(in: .whitespaces))
        guard a.count == 3, a[0] == "json" else { return }
        switch a[1] {
        case "periode": if let v = Int(a[2]) { reglages.periodeMs = v }
        case "lampes": if let v = Int(a[2]) { reglages.lampesMs = v }
        case "compteurs": if let v = Int(a[2]) { reglages.compteursMs = v }
        case "reseau": if let v = Int(a[2]) { reglages.reseauMs = v }
        case "log" where a[2] == "0" || a[2] == "1": reglages.log = a[2] == "1"
        case "trames" where a[2] == "0" || a[2] == "1": reglages.trames = a[2] == "1"
        default: break
        }
    }

    // MARK: - Cadences (3.3, 10.5)

    /// Les cadences de session que l'app peut demander.
    public enum Cadence: String, Sendable, CaseIterable {
        /// Blocs `etat` `pont` et `sante`.
        case periode
        /// Toutes les lignes `etat` `lampe`.
        case lampes
        case compteurs
        case reseau
    }

    /// Bornes d'une cadence non nulle (0 la coupe) : celles de la commande `json`
    /// (3.3) par l'USB, celles de la liste blanche (10.5) a distance.
    public static func bornes(_ c: Cadence, genre: GenreTransport) -> ClosedRange<Int> {
        if genre == .udp, let min = PolitiqueCommandes.bornesDistantes.first(where: { $0.0 == c.rawValue })?.1 {
            return min...60_000
        }
        switch c {
        case .periode, .compteurs: return 200...60_000
        case .lampes, .reseau: return 1_000...60_000
        }
    }

    /// Ligne `json <cadence> <ms>` ramenee dans les bornes du transport en cours :
    /// le moteur ne demande jamais a distance une cadence que la liste blanche
    /// refuserait (0 reste 0 : coupe).
    public func ligneCadence(_ c: Cadence, ms: Int) -> String {
        let b = Self.bornes(c, genre: genre)
        let v = ms <= 0 ? 0 : min(max(ms, b.lowerBound), b.upperBound)
        return "json \(c.rawValue) \(v)"
    }
}
