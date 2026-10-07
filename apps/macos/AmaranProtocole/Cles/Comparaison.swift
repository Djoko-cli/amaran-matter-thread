// Comparer sans rien montrer (spec 3b, section 5) : les empreintes et les lampes de
// la base d'amaran Desktop, de la copie du trousseau et du pont. Le panneau « Cles »
// nomme l'ecart et propose le geste qui convient.
import Foundation

/// Ce qu'une source montre du reseau, sans ses cles.
public struct ApercuReseau: Codable, Sendable, Equatable {
    public var empreinteReseau: String
    public var empreinteApplication: String
    public var lampes: [LampeReseau]
    /// Copie ou sauvegarde : sa source et sa date ; nil pour le pont.
    public var source: ReseauMesh.Source?
    public var date: Date?

    public init(empreinteReseau: String, empreinteApplication: String, lampes: [LampeReseau],
                source: ReseauMesh.Source? = nil, date: Date? = nil) {
        self.empreinteReseau = empreinteReseau
        self.empreinteApplication = empreinteApplication
        self.lampes = lampes
        self.source = source
        self.date = date
    }

    /// Ce que le pont montre (`config`, blocs `mesh` et `lampe`) ; nil sans cles.
    public static func dePont(mesh: ConfigMesh?, lampes: [Int: ConfigLampe]) -> ApercuReseau? {
        guard let mesh, mesh.cles == true, let r = mesh.empreintes?.reseau, let a = mesh.empreintes?.application
        else { return nil }
        // Donnees venues du pont par l'USB : bornees, jamais de quoi faire tomber l'app.
        let n = min(max(mesh.lampes ?? lampes.count, 0), ReseauMesh.capacite)
        let liste = (0..<n).compactMap { k -> LampeReseau? in
            guard let c = lampes[k + 1], let ad = c.adresse.flatMap({ UInt16($0, radix: 16) }), let mac = c.mac,
                  mac.count == 12, Data(hex: mac) != nil else { return nil }
            let deux = stride(from: 0, to: 12, by: 2).map { i -> String in
                let d = mac.index(mac.startIndex, offsetBy: i)
                return String(mac[d..<mac.index(d, offsetBy: 2)])
            }
            return LampeReseau(adresse: ad, mac: deux.joined(separator: ":").uppercased(), nom: c.nom ?? "",
                               code: UInt32(clamping: c.code ?? 0),
                               logiciel: ReseauMesh.version(c.logiciel), ble: ReseauMesh.version(c.ble))
        }
        return ApercuReseau(empreinteReseau: r, empreinteApplication: a, lampes: liste)
    }

    /// Memes cles et memes lampes (adresse, MAC, nom, code, versions ; pas les capacites declarees).
    public func memeReseau(que autre: ApercuReseau) -> Bool {
        memesCles(que: autre) && memesLampes(que: autre) && memesVersions(que: autre)
    }

    /// Memes lampes, sans leurs versions (adresse, MAC, nom, code).
    public func memesLampes(que autre: ApercuReseau) -> Bool {
        Self.identites(lampes) == Self.identites(autre.lampes)
    }

    /// Memes versions, lampe par lampe. Une version inconnue d'un cote et connue de
    /// l'autre est un ecart ; la version du module Bluetooth seule ne compte pas sans
    /// celle du logiciel (le pont ne recoit rien dans ce cas).
    public func memesVersions(que autre: ApercuReseau) -> Bool {
        Self.versions(lampes) == Self.versions(autre.lampes)
    }

    public func memesCles(que autre: ApercuReseau) -> Bool {
        empreinteReseau == autre.empreinteReseau && empreinteApplication == autre.empreinteApplication
    }

    static func identites(_ l: [LampeReseau]) -> [String] {
        l.map { "\($0.adresse) \($0.mac.uppercased()) \($0.nom) \($0.code)" }
    }

    /// Ce que le pont garde des versions de chaque lampe : le jeton qu'il recoit.
    static func versions(_ l: [LampeReseau]) -> [String] {
        l.map { $0.jetonVersion ?? "inconnues" }
    }
}

extension ReseauMesh {
    public var apercu: ApercuReseau {
        ApercuReseau(empreinteReseau: empreinteReseau, empreinteApplication: empreinteApplication, lampes: lampes,
                     source: source, date: date)
    }
}

/// Un ecart entre les sources, et le geste qui le resout.
public enum EcartCles: Sendable, Equatable {
    /// Aucune copie dans le trousseau : copier depuis amaran Desktop.
    case pasDeCopie
    /// Le pont n'a pas de cles : le charger.
    case pontSansCles
    /// Le pont n'a pas ce que garde le trousseau : le recharger.
    case pontDifferent
    /// amaran Desktop a d'autres cles : reseau recree ? Mettre le trousseau a jour,
    /// puis recharger le pont.
    case reseauRecree
    /// amaran Desktop a d'autres lampes : mettre le trousseau a jour.
    case lampesChangees
    /// amaran Desktop a d'autres versions de lampes (mise a jour par Sidus) : mettre le
    /// trousseau a jour, puis recharger le pont.
    case versionsChangees
    /// La copie n'a aucune version (faite avant que l'app ne les lise) alors qu'amaran
    /// Desktop en a : memes gestes, autre explication.
    case copieSansVersions
    /// Le pont n'a pas les versions des lampes de la copie (inconnues ou differentes) :
    /// le recharger.
    case pontVersionsDifferentes
    /// Le pont ne prend pas la version des lampes (firmware ancien) alors que la copie en
    /// a : le recharger n'y changerait rien, il faut mettre son firmware a jour.
    case pontSansVersions

    public var texte: String {
        switch self {
        case .pasDeCopie: tr("Aucune copie des clés sur ce Mac : « Copier depuis amaran Desktop ».")
        case .pontSansCles: tr("Le pont n'a pas de clés : « Charger le pont ».")
        case .pontDifferent: tr("Le pont n'a pas les clés ou les lampes de la copie : « Charger le pont ».")
        case .reseauRecree:
            tr("amaran Desktop a d'autres clés : réseau recréé ? « Copier depuis amaran Desktop », puis « Charger le pont ».")
        case .lampesChangees:
            tr("amaran Desktop a d'autres lampes : « Copier depuis amaran Desktop », puis « Charger le pont ».")
        case .versionsChangees:
            tr("amaran Desktop a d'autres versions de lampes (mise à jour ?) : « Copier depuis amaran Desktop », puis « Charger le pont ».")
        case .copieSansVersions:
            tr("La copie de ce Mac n'a pas encore les versions des lampes : « Copier depuis amaran Desktop », puis « Charger le pont ».")
        case .pontSansVersions:
            tr("Ce pont ne prend pas la version des lampes : mettre à jour son firmware.")
        case .pontVersionsDifferentes:
            tr("Les versions des lampes du pont diffèrent de la copie (inconnues ou changées) : « Charger le pont ».")
        }
    }
}

public enum ComparaisonCles {
    /// Les ecarts, du plus urgent au moins urgent. `pont` nil : pont sans cles ;
    /// `pontConnu` faux : aucun pont en mode machine (rien a dire de lui).
    /// `pontPrendLesVersions` faux : le pont n'annonce pas la capacite `logiciel` ; ses
    /// versions ne sont pas comparees (« Charger le pont » ne les lui donnerait pas).
    public static func ecarts(base: ApercuReseau?, copie: ApercuReseau?, pont: ApercuReseau?,
                              pontConnu: Bool, pontPrendLesVersions: Bool = true) -> [EcartCles] {
        var e: [EcartCles] = []
        if let base, let copie {
            if !base.memesCles(que: copie) {
                e.append(.reseauRecree)
            } else if !base.memesLampes(que: copie) {
                e.append(.lampesChangees)
            } else if !base.memesVersions(que: copie) {
                let copieSans = !copie.lampes.contains(where: { $0.jetonVersion != nil })
                e.append(copieSans ? .copieSansVersions : .versionsChangees)
            }
        }
        guard let copie else { return [.pasDeCopie] + e }
        if pontConnu {
            if let pont {
                if !pont.memesCles(que: copie) || !pont.memesLampes(que: copie) {
                    e.append(.pontDifferent)
                } else if !pontPrendLesVersions {
                    if copie.lampes.contains(where: { $0.jetonVersion != nil }) { e.append(.pontSansVersions) }
                } else if !pont.memesVersions(que: copie) {
                    e.append(.pontVersionsDifferentes)
                }
            } else {
                e.append(.pontSansCles)
            }
        }
        return e
    }

    /// Les lampes du pont (reconnues a leur MAC dans la base) dont une capacite
    /// declaree manque a celles que le pont leur connait, comme le signale
    /// outils/cles_amaran.py.
    public static func modelesACataloguer(base: ApercuReseau?, pont: [Int: ConfigLampe]) -> [ModeleACataloguer] {
        guard let base else { return [] }
        func cle(_ mac: String) -> String { mac.replacingOccurrences(of: ":", with: "").uppercased() }
        var r: [ModeleACataloguer] = []
        for (n, c) in pont.sorted(by: { $0.key < $1.key }) {
            guard let mac = c.mac, let l = base.lampes.first(where: { cle($0.mac) == cle(mac) }) else { continue }
            let connues = Set((c.capacites ?? []).map(\.rawValue))
            for capacite in ["cct", "couleur"] where l.declarees.contains(capacite) && !connues.contains(capacite) {
                r.append(ModeleACataloguer(lampe: n, nom: l.nom, code: l.code, capacite: capacite))
            }
        }
        return r
    }
}

/// Une lampe capable de plus que ce que le pont lui connait : pilotee en marche et
/// intensite seulement, tant que son modele n'est pas au catalogue du pont.
public struct ModeleACataloguer: Sendable, Equatable {
    public var lampe: Int
    public var nom: String
    public var code: UInt32
    /// `cct` ou `couleur`.
    public var capacite: String

    public init(lampe: Int, nom: String, code: UInt32, capacite: String) {
        self.lampe = lampe
        self.nom = nom
        self.code = code
        self.capacite = capacite
    }

    public var texte: String {
        let quoi = capacite == "cct" ? tr("la température de couleur") : tr("la couleur")
        let (l, c) = (String(lampe), String(code))
        return tr("Lampe \(l) (\(nom), code \(c)) : déclare \(quoi), que le pont ne lui connaît pas : marche et intensité seulement, modèle à cataloguer.")
    }
}
