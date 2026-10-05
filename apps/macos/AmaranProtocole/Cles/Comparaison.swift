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
        let n = mesh.lampes ?? lampes.count
        let liste = (1...max(n, 1)).prefix(n).compactMap { i -> LampeReseau? in
            guard let c = lampes[i], let ad = c.adresse.flatMap({ UInt16($0, radix: 16) }), let mac = c.mac else { return nil }
            let deux = stride(from: 0, to: mac.count, by: 2).map { k -> String in
                let d = mac.index(mac.startIndex, offsetBy: k)
                return String(mac[d..<mac.index(d, offsetBy: 2, limitedBy: mac.endIndex)!])
            }
            return LampeReseau(adresse: ad, mac: deux.joined(separator: ":").uppercased(), nom: c.nom ?? "",
                               code: UInt32(clamping: c.code ?? 0))
        }
        return ApercuReseau(empreinteReseau: r, empreinteApplication: a, lampes: liste)
    }

    /// Memes cles et memes lampes (adresse, MAC, nom, code ; pas les capacites declarees).
    public func memeReseau(que autre: ApercuReseau) -> Bool {
        memesCles(que: autre) && Self.identites(lampes) == Self.identites(autre.lampes)
    }

    public func memesCles(que autre: ApercuReseau) -> Bool {
        empreinteReseau == autre.empreinteReseau && empreinteApplication == autre.empreinteApplication
    }

    static func identites(_ l: [LampeReseau]) -> [String] {
        l.map { "\($0.adresse) \($0.mac.uppercased()) \($0.nom) \($0.code)" }
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

    public var texte: String {
        switch self {
        case .pasDeCopie: "Aucune copie des clés sur ce Mac : « Copier depuis amaran Desktop »."
        case .pontSansCles: "Le pont n'a pas de clés : « Charger le pont »."
        case .pontDifferent: "Le pont n'a pas les clés ou les lampes de la copie : « Charger le pont »."
        case .reseauRecree:
            "amaran Desktop a d'autres clés : réseau recréé ? « Copier depuis amaran Desktop », puis « Charger le pont »."
        case .lampesChangees:
            "amaran Desktop a d'autres lampes : « Copier depuis amaran Desktop », puis « Charger le pont »."
        }
    }
}

public enum ComparaisonCles {
    /// Les ecarts, du plus urgent au moins urgent. `pont` nil : pont sans cles ;
    /// `pontConnu` faux : aucun pont en mode machine (rien a dire de lui).
    public static func ecarts(base: ApercuReseau?, copie: ApercuReseau?, pont: ApercuReseau?,
                              pontConnu: Bool) -> [EcartCles] {
        var e: [EcartCles] = []
        if let base, let copie {
            if !base.memesCles(que: copie) {
                e.append(.reseauRecree)
            } else if !base.memeReseau(que: copie) {
                e.append(.lampesChangees)
            }
        }
        guard let copie else { return [.pasDeCopie] + e }
        if pontConnu {
            if let pont {
                if !pont.memeReseau(que: copie) { e.append(.pontDifferent) }
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
        let quoi = capacite == "cct" ? "la température de couleur" : "la couleur"
        return "Lampe \(lampe) (\(nom), code \(code)) : déclare \(quoi), que le pont ne lui connaît pas : "
            + "marche et intensité seulement, modèle à cataloguer."
    }
}
