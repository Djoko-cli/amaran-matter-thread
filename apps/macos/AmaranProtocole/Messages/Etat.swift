// Messages periodiques du pont amaran (docs/PROTOCOLE-JSON.md 5.2 a 5.5) : config,
// etat, compteurs, reseau. Tout champ est facultatif, sauf le numero d'une lampe.
import Foundation

/// Etat d'une lampe : marche et intensite (0 a 1000, au dixieme de pour cent).
public struct EtatLu: Codable, Sendable, Equatable, Hashable {
    public var marche: Bool?
    public var intensite: Int?

    public init(marche: Bool? = nil, intensite: Int? = nil) {
        self.marche = marche
        self.intensite = intensite
    }

    /// En marche a l'intensite 0 : la lampe n'eclaire pas, Maison la montre eteinte.
    public var noire: Bool { marche == true && intensite == 0 }
}

// MARK: - config (5.2)

/// Un modele du catalogue du firmware.
public struct ModeleCatalogue: Codable, Sendable, Equatable {
    public struct PlageCCT: Codable, Sendable, Equatable {
        public var min: Int?
        public var max: Int?
    }

    /// Code produit Sidus ; absent pour le repli.
    public var code: Int?
    public var nom: String?
    public var capacites: [Capacite]?
    public var type: TypeAppareil?
    public var cctK: PlageCCT?
}

/// `config`, bloc `catalogue`.
public struct ConfigCatalogue: Codable, Sendable, Equatable {
    public var modeles: [ModeleCatalogue]?
    public var repli: ModeleCatalogue?
}

/// `config`, bloc `mesh` : cles en service, adresse, et en-tete de la liste.
public struct ConfigMesh: Codable, Sendable, Equatable {
    public struct Empreintes: Codable, Sendable, Equatable {
        public var reseau: String?
        public var application: String?
    }

    public struct Balayage: Codable, Sendable, Equatable {
        public var fenetreMs: Int?
        public var intervalleMs: Int?
    }

    public var cles: Bool?
    public var empreintes: Empreintes?
    public var adresse: String?
    public var ivNvs: Int?
    public var balayage: Balayage?
    public var lampes: Int?
    public var capacite: Int?
    public var releveMs: Int?
    public var groupe: String?
}

/// `config`, bloc `lampe` : l'identite d'une lampe de la liste.
public struct ConfigLampe: Codable, Sendable, Equatable {
    public var lampe: Int
    public var adresse: String?
    public var mac: String?
    public var nom: String?
    public var code: Int?
    public var modele: String?
    public var catalogue: Bool?
    public var capacites: [Capacite]?
    public var type: TypeAppareil?
}

// MARK: - etat (5.3)

/// `etat`, bloc `pont`.
public struct BlocPont: Codable, Sendable, Equatable {
    public struct Mesh: Codable, Sendable, Equatable {
        public var pret: Bool?
        public var diag: DiagMesh?
    }

    public struct Ordres: Codable, Sendable, Equatable {
        public var total: Int?
        public var confirmes: Int?
        public var abandons: Int?
        public var tenus: Int?
        public var delaiTotalMs: Int?
        public var delaiMaxMs: Int?
        public var lents: Int?

        /// Delai moyen d'un ordre confirme.
        public var delaiMoyenMs: Int? {
            guard let c = confirmes, c > 0, let t = delaiTotalMs else { return nil }
            return t / c
        }
    }

    public var boot: String?
    public var upS: Int?
    public var mesh: Mesh?
    public var ordres: Ordres?
    public var releves: Int?
    public var trames: Int?
}

/// `etat`, bloc `lampe` : une ligne par lampe.
public struct BlocLampe: Codable, Sendable, Equatable {
    public struct Maison: Codable, Sendable, Equatable {
        public var endpoint: Int?
        public var vue: Bool?
        public var masquee: Bool?
    }

    public struct Consigne: Codable, Sendable, Equatable {
        public var marche: Bool?
        public var intensite: Int?
        public var phase: PhaseOrdre?
        public var essai: Int?
    }

    public var lampe: Int
    public var maison: Maison?
    public var entendue: Bool?
    public var lue: EtatLu?
    public var joignable: Bool?
    public var reponseMs: UInt32?
    public var consigne: Consigne?
    public var repondues: Int?
    /// Part des relectures repondues sur 10 min (`part_10min`), en pour cent.
    public var part10Min: Int?
    public var alerte: Bool?
}

/// `etat`, bloc `sante`.
public struct BlocSante: Codable, Sendable, Equatable {
    public struct Led: Codable, Sendable, Equatable {
        public var motif: MotifLed?
        public var test: Bool?
        public var depuisMs: Int?
    }

    public struct Matter: Codable, Sendable, Equatable {
        public var enService: Bool?
        public var thread: Bool?
        public var identifie: Bool?
        public var ble: Bool?
    }

    public struct Systeme: Codable, Sendable, Equatable {
        public var heap: Int?
        public var heapMin: Int?
        public var heapBloc: Int?
        /// Octets de pile jamais utilises, par tache ; nil : tache absente.
        public var piles: [String: Int?]?
        public var jsonPerdus: Int?
        public var jsonTropLongs: Int?
        public var rejets: Int?
    }

    public var boot: String?
    public var upS: Int?
    /// Id de la commande de la console en cours (6.2).
    public var commande: Int?
    public var led: Led?
    public var matter: Matter?
    public var sys: Systeme?
}

// MARK: - compteurs (5.4)

/// `compteurs`, bloc `mesh` : cumulatifs depuis le demarrage.
public struct CompteursMesh: Codable, Sendable, Equatable {
    public struct Balises: Codable, Sendable, Equatable {
        public struct Derniere: Codable, Sendable, Equatable {
            public var iv: Int?
            public var drapeaux: Int?
            public var ms: UInt32?
        }

        public var notres: Int?
        public var autres: Int?
        public var fausses: Int?
        public var derniere: Derniere?
    }

    public var annonces: Int?
    public var nidReconnu: Int?
    public var nidInconnu: Int?
    public var netmicFaux: Int?
    public var accesDechiffres: Int?
    public var etatsLampes: Int?
    public var doublons: Int?
    public var balises: Balises?
    public var emis: Int?
    public var echecsEmission: Int?
    public var filePleine: Int?
    public var iv: Int?
    public var seq: Int?
    public var plancher: Int?
}

// MARK: - reseau (5.5)

/// `reseau`, bloc `matter`.
public struct ReseauMatter: Codable, Sendable, Equatable {
    public struct Abonnements: Codable, Sendable, Equatable {
        public var demandes: Int?
        public var plafonnes: Int?
        public var etablis: Int?
        public var termines: Int?
        public var plafondS: Int?

        /// Abonnements actifs, a peu pres : etablis moins termines.
        public var actifs: Int? {
            guard let e = etablis, let t = termines else { return nil }
            return max(0, e - t)
        }
    }

    public var demarre: Bool?
    public var fabriques: Int?
    public var ble: Bool?
    public var identifie: Bool?
    public var abonnements: Abonnements?
    public var codeManuel: String?
    public var qr: String?
}

/// `reseau`, bloc `thread`.
public struct ReseauThread: Codable, Sendable, Equatable {
    public var role: String?
    public var attache: Bool?
}
