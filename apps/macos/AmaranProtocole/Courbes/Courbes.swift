// Repris de Halo Compagnon (Courbes/Courbes.swift) : differences de compteurs cumulatifs
// par fenetre, segments ; adapte au pont amaran : compteurs du Bluetooth Mesh (5.4) et
// du bloc `etat` `pont` (5.3), jauges par lampe (part des relectures repondues), delais
// des ordres (7.1), tas libre (bloc `sante`). Pas de `raz` : seul un redemarrage (un
// autre `boot`) remet les compteurs a zero.
import Foundation

/// Compteurs cumulatifs suivis pour les courbes.
public enum Grandeur: String, CaseIterable, Sendable, Hashable {
    // bloc compteurs.mesh (5.4)
    case annonces, nidReconnu, nidInconnu, netmicFaux, accesDechiffres, etatsLampes, doublons
    case emis, echecsEmission, filePleine
    // bloc etat.pont (5.3)
    case releves, trames, ordres, confirmes, abandons, tenus, lents
}

/// Un bloc de compteurs date : les valeurs cumulatives presentes.
public struct Echantillon: Sendable, Equatable {
    public var date: Date
    public var boot: String?
    public var valeurs: [Grandeur: Int]

    public init(date: Date, boot: String?, valeurs: [Grandeur: Int]) {
        self.date = date
        self.boot = boot
        self.valeurs = valeurs
    }

    /// `compteurs` `mesh` (5.4).
    public static func mesh(_ c: CompteursMesh, date: Date, boot: String?) -> Echantillon {
        var v: [Grandeur: Int] = [:]
        v[.annonces] = c.annonces
        v[.nidReconnu] = c.nidReconnu
        v[.nidInconnu] = c.nidInconnu
        v[.netmicFaux] = c.netmicFaux
        v[.accesDechiffres] = c.accesDechiffres
        v[.etatsLampes] = c.etatsLampes
        v[.doublons] = c.doublons
        v[.emis] = c.emis
        v[.echecsEmission] = c.echecsEmission
        v[.filePleine] = c.filePleine
        return Echantillon(date: date, boot: boot, valeurs: v)
    }

    /// `etat` `pont` (5.3) : relectures envoyees, trames recues, ordres.
    public static func pont(_ p: BlocPont, date: Date, boot: String?) -> Echantillon {
        var v: [Grandeur: Int] = [:]
        v[.releves] = p.releves
        v[.trames] = p.trames
        v[.ordres] = p.ordres?.total
        v[.confirmes] = p.ordres?.confirmes
        v[.abandons] = p.ordres?.abandons
        v[.tenus] = p.ordres?.tenus
        v[.lents] = p.ordres?.lents
        return Echantillon(date: date, boot: boot ?? p.boot, valeurs: v)
    }
}

/// Differences entre deux echantillons d'un meme segment.
public struct Difference: Sendable, Equatable {
    public var debut: Date
    public var fin: Date
    public var segment: Int
    public var deltas: [Grandeur: Int]

    public init(debut: Date, fin: Date, segment: Int, deltas: [Grandeur: Int]) {
        self.debut = debut
        self.fin = fin
        self.segment = segment
        self.deltas = deltas
    }

    public var duree: TimeInterval { fin.timeIntervalSince(debut) }

    public subscript(_ g: Grandeur) -> Int? { deltas[g] }
}

/// Point d'une courbe cumulative (escalier).
public struct PointCumul: Sendable, Equatable {
    public var date: Date
    public var segment: Int
    public var valeur: Int
}

/// Point d'une jauge (valeur instantanee) ; `valeur` nil : inconnue (`part_10min` nul).
public struct PointMesure: Sendable, Equatable {
    public var date: Date
    /// Change a chaque redemarrage du pont : la courbe ne relie pas deux segments.
    public var segment: Int
    public var valeur: Double?

    public init(date: Date, segment: Int, valeur: Double?) {
        self.date = date
        self.segment = segment
        self.valeur = valeur
    }
}

/// Fin d'un ordre de lampe (evenement `ordre`, 7.1), pour la courbe des delais.
public struct PointOrdre: Sendable, Equatable {
    public var date: Date
    public var segment: Int
    public var lampe: Int
    public var issue: IssueOrdre?
    public var delaiMs: Int?
    public var essai: Int?

    public init(date: Date, segment: Int, lampe: Int, issue: IssueOrdre?, delaiMs: Int?, essai: Int?) {
        self.date = date
        self.segment = segment
        self.lampe = lampe
        self.issue = issue
        self.delaiMs = delaiMs
        self.essai = essai
    }
}

/// Differences par fenetre de 10 s ou 1 min ; une difference negative, un `boot`
/// qui change ou un trou dans les echantillons (app suspendue, veille du Mac, lien
/// perdu) ouvre un nouveau segment (pas de valeur aberrante).
public enum Courbes {
    /// Plus grand ecart tolere entre deux echantillons d'un meme segment.
    public static let ecartMaxDefaut: TimeInterval = 30

    /// Ecart maximal pour une periode d'emission (`compteurs_ms`, `periode_ms`) :
    /// 3 periodes, 30 s au moins.
    public static func ecartMax(periodeMs: Int?) -> TimeInterval {
        guard let p = periodeMs, p > 0 else { return ecartMaxDefaut }
        return max(ecartMaxDefaut, 3 * Double(p) / 1000)
    }

    /// Decoupe en segments continus.
    public static func segmenter(_ echantillons: [Echantillon],
                                 ecartMax: TimeInterval = ecartMaxDefaut) -> [[Echantillon]] {
        var segments: [[Echantillon]] = []
        var courant: [Echantillon] = []
        for e in echantillons {
            if let p = courant.last, rupture(p, e, ecartMax: ecartMax) {
                segments.append(courant)
                courant = []
            }
            courant.append(e)
        }
        if !courant.isEmpty { segments.append(courant) }
        return segments
    }

    /// Vrai si `b` ne peut pas suivre `a` dans un meme segment. Un trou de plus de
    /// `ecartMax` en ferait une seule difference geante, tracee comme une valeur
    /// "par fenetre".
    public static func rupture(_ a: Echantillon, _ b: Echantillon, ecartMax: TimeInterval = ecartMaxDefaut) -> Bool {
        if a.boot != nil, b.boot != nil, a.boot != b.boot { return true }
        if b.date < a.date { return true }
        if b.date.timeIntervalSince(a.date) > ecartMax { return true }
        for (g, v) in b.valeurs {
            if let w = a.valeurs[g], v < w { return true }
        }
        return false
    }

    /// Differences par fenetre alignee sur l'horloge (`fenetre` secondes) : pour
    /// chaque fenetre, dernier echantillon de la fenetre moins dernier echantillon
    /// de la fenetre precedente du meme segment (ou le premier echantillon du segment).
    public static func differences(_ echantillons: [Echantillon], fenetre: TimeInterval,
                                   ecartMax: TimeInterval = ecartMaxDefaut) -> [Difference] {
        precondition(fenetre > 0)
        var sortie: [Difference] = []
        for (numero, segment) in segmenter(echantillons, ecartMax: ecartMax).enumerated() {
            guard var reference = segment.first else { continue }
            var i = 0
            while i < segment.count {
                let seau = floor(segment[i].date.timeIntervalSinceReferenceDate / fenetre)
                var dernier = segment[i]
                var j = i + 1
                while j < segment.count, floor(segment[j].date.timeIntervalSinceReferenceDate / fenetre) == seau {
                    dernier = segment[j]
                    j += 1
                }
                if dernier.date > reference.date {
                    sortie.append(Difference(debut: reference.date, fin: dernier.date, segment: numero,
                                             deltas: soustraire(dernier, reference)))
                }
                reference = dernier
                i = j
            }
        }
        return sortie
    }

    static func soustraire(_ b: Echantillon, _ a: Echantillon) -> [Grandeur: Int] {
        var d: [Grandeur: Int] = [:]
        for (g, v) in b.valeurs {
            if let w = a.valeurs[g] { d[g] = v - w }
        }
        return d
    }

    /// Valeurs cumulatives brutes, avec leur segment.
    public static func cumul(_ echantillons: [Echantillon], _ g: Grandeur,
                             ecartMax: TimeInterval = ecartMaxDefaut) -> [PointCumul] {
        var sortie: [PointCumul] = []
        for (numero, segment) in segmenter(echantillons, ecartMax: ecartMax).enumerated() {
            for e in segment {
                if let v = e.valeurs[g] { sortie.append(PointCumul(date: e.date, segment: numero, valeur: v)) }
            }
        }
        return sortie
    }

    // MARK: - Courbes du Bluetooth Mesh et des ordres

    /// Une grandeur ramenee a la minute.
    public static func parMinute(_ d: Difference, _ g: Grandeur) -> Double? {
        guard let v = d[g], d.duree > 0 else { return nil }
        return Double(v) * 60 / d.duree
    }

    /// Part des annonces de notre reseau dont le NetMIC est faux : `d netmic_faux /
    /// d nid_reconnu`, nil sans annonce de notre reseau dans la fenetre. Le pont ne
    /// verifie le NetMIC que d'un message qui porte notre NID (components/mesh/crochet.c) :
    /// un IV Index faux la fait monter vers 100 % ; des cles perimees (reseau recree) font
    /// tomber a zero les annonces de notre reseau, sans NetMIC faux. Bornee a 1 : pendant
    /// un renouvellement des cles, un message peut echouer avec l'ancienne et la nouvelle.
    public static func partNetmicFaux(_ d: Difference) -> Double? {
        guard let n = d[.nidReconnu], n > 0, let f = d[.netmicFaux] else { return nil }
        return min(1, Double(f) / Double(n))
    }

    /// Part des emissions refusees : `d echecs_emission / (d emis + d echecs_emission)`.
    public static func partRefusEmission(_ d: Difference) -> Double? {
        guard let e = d[.emis], let r = d[.echecsEmission], e + r > 0 else { return nil }
        return Double(r) / Double(e + r)
    }

    /// Part des ordres abandonnes parmi ceux qui ont fini par confirme ou abandon.
    public static func partAbandons(_ d: Difference) -> Double? {
        guard let c = d[.confirmes], let a = d[.abandons], c + a > 0 else { return nil }
        return Double(a) / Double(c + a)
    }
}

/// Series tirees des messages successifs du pont, pour les graphiques : compteurs du
/// Mesh et du bloc `pont` (differences par `Courbes`), part des relectures repondues
/// et delais des ordres par lampe, tas libre. Chaque serie est bornee ; un changement
/// de `boot` ouvre un nouveau segment (`segment`).
///
/// Code pur : la date de chaque message est passee en argument (celle d'`EtatPont`).
public struct SeriesCourbes: Sendable, Equatable {
    /// Points gardes par serie : 2 h a une ligne par seconde.
    public static let capaciteDefaut = 7200

    public var capacite: Int
    /// `compteurs` `mesh` (absents a distance tant que `json compteurs` vaut 0).
    public private(set) var mesh: [Echantillon] = []
    /// `etat` `pont` : relectures, trames, ordres.
    public private(set) var pont: [Echantillon] = []
    /// Par lampe : part des relectures repondues sur 10 min, en pour cent (`part_10min`).
    public private(set) var parts: [Int: [PointMesure]] = [:]
    /// Par lampe : fin de chaque ordre (`ordre` : issue, delai, essai).
    public private(set) var ordres: [Int: [PointOrdre]] = [:]
    /// Tas libre, en octets (`sante.sys.heap`).
    public private(set) var tas: [PointMesure] = []
    /// Plus bas du tas depuis le demarrage (`sante.sys.heap_min`).
    public private(set) var tasMin: [PointMesure] = []
    /// Segment en cours : augmente a chaque nouveau `boot`.
    public private(set) var segment = 0
    public private(set) var boot: String?

    public init(capacite: Int = SeriesCourbes.capaciteDefaut) {
        self.capacite = max(1, capacite)
    }

    /// Ajoute ce qu'un message apporte aux series. `date` : date de la ligne (ancre du
    /// `hello`). Les lignes anciennes (avant le `hello` de la connexion) n'y vont pas.
    public mutating func ajouter(_ m: MessageCarte, date: Date) {
        switch m {
        case .helloBase(let h): noterBoot(h.boot)
        case .helloIdentite(let h): noterBoot(h.boot)
        case .battement(let b): noterBoot(b.boot)
        case .etatPont(let p):
            noterBoot(p.boot)
            Self.borner(&pont, Echantillon.pont(p, date: date, boot: boot), capacite)
        case .etatSante(let s):
            noterBoot(s.boot)
            if let h = s.sys?.heap { Self.borner(&tas, PointMesure(date: date, segment: segment, valeur: Double(h)), capacite) }
            if let h = s.sys?.heapMin { Self.borner(&tasMin, PointMesure(date: date, segment: segment, valeur: Double(h)), capacite) }
        case .compteursMesh(let c):
            Self.borner(&mesh, Echantillon.mesh(c, date: date, boot: boot), capacite)
        case .etatLampe(let l):
            Self.borner(&parts[l.lampe, default: []],
                   PointMesure(date: date, segment: segment, valeur: l.part10Min.map(Double.init)), capacite)
        case .ordre(let o):
            Self.borner(&ordres[o.lampe, default: []],
                   PointOrdre(date: date, segment: segment, lampe: o.lampe, issue: o.issue, delaiMs: o.delaiMs,
                              essai: o.essai), capacite)
        default:
            break
        }
    }

    /// Tout oublier (bouton "Effacer les courbes").
    public mutating func vider() {
        self = SeriesCourbes(capacite: capacite)
    }

    /// Numeros des lampes presentes dans les series.
    public var lampes: [Int] { Set(parts.keys).union(ordres.keys).sorted() }

    /// Delais des ordres confirmes d'une lampe, en millisecondes.
    public func delaisConfirmes(lampe: Int) -> [PointMesure] {
        (ordres[lampe] ?? []).compactMap { o in
            guard o.issue == .confirme, let d = o.delaiMs else { return nil }
            return PointMesure(date: o.date, segment: o.segment, valeur: Double(d))
        }
    }

    private mutating func noterBoot(_ b: String?) {
        guard let b else { return }
        if let boot, boot != b { segment += 1 }
        boot = b
    }

    private static func borner<T>(_ serie: inout [T], _ x: T, _ capacite: Int) {
        serie.append(x)
        if serie.count > capacite { serie.removeFirst(serie.count - capacite) }
    }
}
