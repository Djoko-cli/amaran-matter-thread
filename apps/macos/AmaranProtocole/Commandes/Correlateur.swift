// Repris de Halo Compagnon (commit e114cd5) : l'evenement ordre du pont amaran remplace
// la livraison, et le bloc sante dit la commande en cours (docs/PROTOCOLE-JSON.md 6.2).
import Foundation

/// Qui a demande la commande.
public enum OrigineCommande: String, Sendable, Equatable {
    /// Boutons et curseurs de l'ecran Commandes, tableau de bord.
    case interface
    /// Console brute.
    case console
    /// Commandes de service de l'app (`json ping`, `json etat` apres un silence).
    case session
}

/// Ou en est une commande envoyee avec un `id` (6.2 a 6.4).
public enum EtatCommande: Sendable, Equatable {
    case enFile
    case envoyee
    /// `reponse` `debut` recue : commande historique en cours (peut bloquer).
    case enCours
    /// `reponse` `fin` recue, rien d'autre a attendre.
    case terminee
    /// `accepte`, `suite` `ordre` : un evenement `ordre` suivra (7.1).
    case attenteOrdre
    /// Issues de l'ordre : confirme, abandonne, deja tenu (rien n'est parti).
    case confirmee
    case abandonnee
    case tenue
    /// Aucun evenement `ordre` sous le delai de la politique : il s'est perdu.
    case ordrePerdu
    /// Pas de `reponse` sous 3 s, sans `debut` (pas de reemission).
    case sansReponse
    /// `debut` recu, puis un bloc `sante` (ou un `hb`) qui ne porte plus son id :
    /// la commande est finie, sa `fin` s'est perdue (6.2).
    case finPerdue
    /// Remplacee dans la file par une valeur plus recente (curseurs).
    case remplacee
    /// Connexion perdue avant la fin.
    case perdue

    public var estFinal: Bool {
        switch self {
        case .enFile, .envoyee, .enCours, .attenteOrdre: false
        default: true
        }
    }
}

/// Suivi d'une commande, de la file a l'evenement `ordre`.
public struct SuiviCommande: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let commande: String
    public let origine: OrigineCommande
    /// Cle de fusion : une commande en file de meme cle est remplacee.
    public let fusion: String?
    public internal(set) var numero: Int?
    public internal(set) var etat: EtatCommande
    public internal(set) var fin: Reponse?
    /// Ordre de lampe : son numero (`reponse.lampe`), et l'evenement qui l'a fini.
    public internal(set) var lampe: Int?
    public internal(set) var ordre: EvenementOrdre?
    /// Texte recu entre `reponse debut` et `reponse fin` (au mieux).
    public internal(set) var texte: [String]
    public let soumiseA: TimeInterval
    public internal(set) var envoyeeA: TimeInterval?
    public internal(set) var debutA: TimeInterval?
    public internal(set) var termineeA: TimeInterval?
}

/// Delais de la correlation par l'USB (6.4) : "sans reponse" a 3 s, pas de
/// renvoi ; un ordre accepte sans evenement `ordre` sous 10 s (un abandon prend
/// moins de 4 s) est tenu pour perdu. Thread viendra au plan 3b-2.
public struct PolitiqueDelais: Sendable, Equatable {
    public var delaiReponse: TimeInterval
    public var delaiOrdre: TimeInterval

    public static let usb = PolitiqueDelais(delaiReponse: 3, delaiOrdre: 10)
}

/// Correlation des commandes par `id`, une seule en vol a la fois (6.4).
///
/// Code pur : le temps est passe en argument (secondes monotones).
public struct Correlateur: Sendable {
    public static let historiqueMax = 300
    /// Au plus 20 lignes par seconde vers le pont (6.3, refus `cadence`).
    public static let intervalleMin: TimeInterval = 0.05

    public var politique = PolitiqueDelais.usb

    public private(set) var suivis: [SuiviCommande] = []
    private var file: [UUID] = []
    /// Commandes secretes (`mesh cles`), en attente d'envoi : le suivi n'en garde
    /// que la forme masquee, et la ligne est oubliee des son envoi (spec 3b, 5).
    private var secrets: [UUID: String] = [:]
    public private(set) var enVol: UUID?
    private var prochainNumero = 1
    public private(set) var dernierEnvoiA: TimeInterval?

    public init() {}

    /// Nouvelle connexion : tout ce qui attendait est perdu. Les numeros ne
    /// repartent PAS a 1 : les id en attente du pont (4 par lampe) survivent a une
    /// reconnexion de l'app, et un `ordre` tardif ne doit pas tomber sur une
    /// commande neuve de meme numero (6.1 : croissant).
    public mutating func reinitialiser(maintenant: TimeInterval) {
        for i in suivis.indices where !suivis[i].etat.estFinal {
            suivis[i].etat = .perdue
            suivis[i].termineeA = maintenant
        }
        file.removeAll()
        secrets.removeAll()
        enVol = nil
        dernierEnvoiA = nil
    }

    /// Avant un `json 1` en cours de session (silence, bail echu,
    /// redemarrage) : la commande en vol ne recevra plus sa `reponse` dans
    /// cette session ; la file reste et repartira apres la reponse au `json 1`.
    /// `redemarrage` : le pont a aussi oublie ses ordres en cours.
    public mutating func perdreEnVol(maintenant: TimeInterval, redemarrage: Bool = false) {
        for i in suivis.indices {
            let e = suivis[i].etat
            guard e == .envoyee || e == .enCours || (redemarrage && e == .attenteOrdre) else { continue }
            suivis[i].etat = .perdue
            suivis[i].termineeA = maintenant
        }
        enVol = nil
    }

    /// Reserve un numero hors file (json 1, json 0 envoyes par la session).
    public mutating func reserverNumero() -> Int {
        let n = prochainNumero
        prochainNumero = LigneCommande.suivant(n)
        return n
    }

    public func suivi(_ id: UUID) -> SuiviCommande? {
        suivis.first { $0.id == id }
    }

    public func suivi(numero: Int) -> SuiviCommande? {
        suivis.last { $0.numero == numero }
    }

    public var enFile: Int { file.count }
    public var occupe: Bool { enVol != nil || !file.isEmpty || commandeDeBanc != nil }

    /// Commande de la console du pont en cours (`debut` recu, pas encore `fin`),
    /// y compris un `debut` tardif, arrive apres le verdict "sans reponse" : la
    /// console du pont ne lit plus rien, rien d'autre ne part.
    public var commandeDeBanc: SuiviCommande? {
        suivis.last { $0.etat == .enCours }
    }

    /// `secret` : la commande porte des cles ; seul son masque reste dans le suivi.
    @discardableResult
    public mutating func soumettre(_ commande: String, origine: OrigineCommande, fusion: String? = nil,
                                   secret: Bool = false, maintenant: TimeInterval) -> UUID {
        if let fusion {
            var gardees: [UUID] = []
            for id in file {
                if let i = index(id), suivis[i].fusion == fusion {
                    suivis[i].etat = .remplacee
                    suivis[i].termineeA = maintenant
                } else {
                    gardees.append(id)
                }
            }
            file = gardees
        }
        let s = SuiviCommande(id: UUID(), commande: secret ? PolitiqueCommandes.masquerCle(commande) : commande,
                              origine: origine, fusion: fusion, numero: nil,
                              etat: .enFile, fin: nil, lampe: nil, ordre: nil, texte: [], soumiseA: maintenant,
                              envoyeeA: nil, debutA: nil, termineeA: nil)
        suivis.append(s)
        file.append(s.id)
        if secret { secrets[s.id] = commande }
        elaguer()
        return s.id
    }

    /// Prochaine ligne a envoyer si rien n'est en vol ni en cours, et pas
    /// plus d'une ligne toutes les 50 ms (20 par seconde). Une ligne invalide
    /// (trop longue...) est retiree et marquee terminee.
    public mutating func prochainEnvoi(maintenant: TimeInterval) -> (id: UUID, numero: Int, octets: Data)? {
        if let d = dernierEnvoiA, maintenant - d < Self.intervalleMin { return nil }
        while enVol == nil, commandeDeBanc == nil, !file.isEmpty {
            let id = file.removeFirst()
            guard let i = index(id) else { continue }
            let numero = prochainNumero
            switch LigneCommande.octets(secrets.removeValue(forKey: id) ?? suivis[i].commande, id: numero) {
            case .failure:
                suivis[i].etat = .terminee
                suivis[i].termineeA = maintenant
                continue
            case .success(let octets):
                prochainNumero = LigneCommande.suivant(numero)
                suivis[i].numero = numero
                suivis[i].etat = .envoyee
                suivis[i].envoyeeA = maintenant
                enVol = id
                dernierEnvoiA = maintenant
                return (id, numero, octets)
            }
        }
        return nil
    }

    /// Note un envoi fait hors file (json 1) pour le calcul du ping.
    public mutating func noterEnvoiHorsFile(maintenant: TimeInterval) {
        dernierEnvoiA = maintenant
    }

    public enum Correlation: Sendable, Equatable {
        /// `id` inconnu (autre connexion, humain au banc) : ignore.
        case inattendue
        case debut(UUID)
        /// `fin` : `ordreAttendu` si `suite` vaut `ordre`.
        case fin(UUID, ordreAttendu: Bool)
    }

    public mutating func recevoir(_ r: Reponse, maintenant: TimeInterval) -> Correlation {
        // Une reponse tardive (apres "sans reponse") met encore le suivi a jour.
        guard let i = suivis.lastIndex(where: {
            $0.numero == r.id && (!$0.etat.estFinal || $0.etat == .sansReponse)
        }) else {
            return .inattendue
        }
        let id = suivis[i].id
        switch r.etape {
        case .inconnu:
            // Etape future (progression...) : ne clot rien, ne libere pas la place en vol.
            return .inattendue
        case .debut:
            suivis[i].etat = .enCours
            suivis[i].debutA = maintenant
            return .debut(id)
        case .fin:
            suivis[i].fin = r
            suivis[i].termineeA = maintenant
            suivis[i].lampe = r.lampe
            let attend = r.ok && r.code == .accepte && r.suite == .ordre
            suivis[i].etat = attend ? .attenteOrdre : .terminee
            if enVol == id { enVol = nil }
            return .fin(id, ordreAttendu: attend)
        }
    }

    /// Un evenement `ordre` finit les ordres de sa lampe que porte `ids` ; un
    /// ordre arrive pendant un autre s'y est fondu (6.2). Les ordres plus anciens
    /// de la meme lampe, encore en attente, sont sortis de la liste du pont
    /// (`ids_perdus`) : ils prennent la meme issue.
    @discardableResult
    public mutating func recevoir(_ o: EvenementOrdre, maintenant: TimeInterval) -> [UUID] {
        guard let ids = o.ids, let plusGrand = ids.max() else { return [] }
        let etat: EtatCommande = switch o.issue {
        case .confirme: .confirmee
        case .abandon: .abandonnee
        case .tenu: .tenue
        case .inconnu, nil: .terminee
        }
        var touches: [UUID] = []
        for i in suivis.indices where suivis[i].etat == .attenteOrdre && suivis[i].lampe == o.lampe {
            guard let n = suivis[i].numero, n <= plusGrand else { continue }
            suivis[i].etat = etat
            suivis[i].ordre = o
            suivis[i].termineeA = maintenant
            touches.append(suivis[i].id)
        }
        return touches
    }

    /// Texte recu : rattache a la commande de banc en cours (meme apres un
    /// `debut` tardif), sinon a la commande en vol.
    @discardableResult
    public mutating func texte(_ ligne: String) -> UUID? {
        guard let id = commandeDeBanc?.id ?? enVol, let i = index(id),
              suivis[i].etat == .enCours || suivis[i].etat == .envoyee
        else { return nil }
        suivis[i].texte.append(ligne)
        if suivis[i].texte.count > 400 { suivis[i].texte.removeFirst() }
        return id
    }

    /// Bloc `sante` ou `hb` recu, avec l'id de la commande que la console du pont
    /// execute (`commande`, nil : aucune). Une commande encore "en cours" qui
    /// n'est pas celle-la est finie, et sa `reponse fin` s'est perdue (6.2).
    /// Sans cela, la place en vol resterait prise et plus rien ne partirait.
    @discardableResult
    public mutating func periodiqueRecu(commande: Int?, maintenant: TimeInterval) -> [UUID] {
        var touches: [UUID] = []
        for i in suivis.indices where suivis[i].etat == .enCours && suivis[i].numero != commande {
            suivis[i].etat = .finPerdue
            suivis[i].termineeA = maintenant
            if enVol == suivis[i].id { enVol = nil }
            touches.append(suivis[i].id)
        }
        return touches
    }

    /// Commandes sans `reponse` sous le delai de la politique (et sans `debut`) : marquees, pas reemises ici.
    public mutating func verifierDelais(maintenant: TimeInterval) -> [SuiviCommande] {
        guard let id = enVol, let i = index(id), suivis[i].etat == .envoyee,
              let t = suivis[i].envoyeeA, maintenant - t >= politique.delaiReponse else { return [] }
        suivis[i].etat = .sansReponse
        suivis[i].termineeA = maintenant
        enVol = nil
        return [suivis[i]]
    }

    /// Ordres acceptes sans evenement `ordre` sous le delai de la politique.
    public mutating func verifierOrdres(maintenant: TimeInterval) -> [SuiviCommande] {
        var perdus: [SuiviCommande] = []
        for i in suivis.indices where suivis[i].etat == .attenteOrdre {
            guard let t = suivis[i].termineeA, maintenant - t >= politique.delaiOrdre else { continue }
            suivis[i].etat = .ordrePerdu
            suivis[i].termineeA = maintenant
            perdus.append(suivis[i])
        }
        return perdus
    }

    private func index(_ id: UUID) -> Int? {
        suivis.lastIndex { $0.id == id }
    }

    private mutating func elaguer() {
        guard suivis.count > Self.historiqueMax else { return }
        var aRetirer = suivis.count - Self.historiqueMax
        suivis.removeAll { s in
            guard aRetirer > 0, s.etat.estFinal else { return false }
            aRetirer -= 1
            return true
        }
    }
}
